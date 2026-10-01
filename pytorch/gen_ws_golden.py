"""Erzeugt Golden-Vektoren fuer die weight-stationary Kern-Testbench."""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from conv_ws_sim import route_stream, reference_conv2, reference_conv1, ws_conv1_N16

N   = 16
IN  = 5                      # 5x5 input feature map
P_H = IN - 2                 # 3
P_W = IN - 2                 # 3
P   = P_H * P_W              # 9 Positionen


def build():
    rng = np.random.RandomState(3)
    X = rng.randint(-8, 8, size=(IN, IN, 8))
    W = rng.randint(-8, 8, size=(16, 8, 3, 3))
    ref = reference_conv2(X, W)                       # (3,3,16)

    positions = [(oh, ow) for oh in range(P_H) for ow in range(P_W)]
    taps = [(kh, kw) for kh in range(3) for kw in range(3)]        # 9
    tap_tiles = [taps[i:i + 2] for i in range(0, 9, 2)]           # 5 (letztes: 1 Tap)
    NTILE = len(tap_tiles)

    W_tiles = []   # [NTILE][16][16]
    A_tiles = []   # [NTILE][P][16]
    for tile in tap_tiles:
        Wt = np.zeros((16, 16), dtype=np.int64)
        At = np.zeros((P, 16), dtype=np.int64)
        for slot, (kh, kw) in enumerate(tile):
            base = slot * 8
            for r in range(16):
                for c in range(8):
                    Wt[r][base + c] = int(W[r, c, kh, kw])
            for p, (oh, ow) in enumerate(positions):
                for c in range(8):
                    At[p][base + c] = int(X[oh + kh, ow + kw, c])
        W_tiles.append(Wt)
        A_tiles.append(At)

    # --- Self-Check bei REALER Kadenz spacing=2: extern akkumulierte Erfassung == Referenz ---
    acc = np.zeros((P, 16), dtype=np.int64)
    for t in range(NTILE):
        cap = route_stream(W_tiles[t], [A_tiles[t][p] for p in range(P)], N=16, spacing=2)
        for p in range(P):
            for r in range(16):
                acc[p][r] += cap[p][r]
    Y = np.zeros((P, 16), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        Y[p] = ref[oh, ow]
    assert np.array_equal(acc, Y), "GOLDEN self-check FAILED (route_stream != reference)"
    return NTILE, W_tiles, A_tiles, Y


def h8(v):    # signed 8-bit -> 2 hex nibbles
    return f"{int(v) & 0xFF:02x}"

def h32(v):   # signed 32-bit -> 8 hex nibbles
    return f"{int(v) & 0xFFFFFFFF:08x}"

def h64(v):   # 64-bit act word (8 int8 channels) -> 16 hex nibbles
    return f"{int(v) & 0xFFFFFFFFFFFFFFFF:016x}"

def h72(v):   # 72-bit pbuf patch word (9 int8 taps) -> 18 hex nibbles
    return f"{int(v) & ((1 << 72) - 1):018x}"


# ===========================================================================
#  ENGINE-Golden: ECHTE conv2 (13x13x8 -> 11x11x16, P=121, N=16, 5 Tap-Tiles,
#  spacing=2) mit den REPACKTEN Gewichten aus conv2_ws_tiles.mem (genau die
#  Bytes, die die Engine-Weight-BRAM per $readmemh laedt). Fuer die Engine-TB,
#  die student_ws_conv2 als Ganzes prueft: Aktivierungsbild vorladen, laufen
#  lassen, acc_o[p][r] == eng_y[p][r] vergleichen.
#
#  Der Self-Check ist STARK: die Referenz-Gewichte kommen UNABHAENGIG aus dem
#  Modell (natuerlicher (kh,kw)-Index), die WS-Route benutzt die mem-Bytes ->
#  ein Fehler in Kachel-Byteorder / Tap-zu-Tile / Slot-Spalten / spacing
#  wuerde die beiden auseinanderlaufen lassen.
# ===========================================================================
def _tap_tiles():
    taps = [(kh, kw) for kh in range(3) for kw in range(3)]      # 9, row-major
    return [taps[i:i + 2] for i in range(0, 9, 2)]               # 5 (letztes: 1 Tap)


def _read_mem_tiles(path):
    """Read conv2_ws_tiles.mem EXACTLY as student_(ws_)weight_bram reads it (signed)."""
    from pack_conv2_ws_tiles import line_to_tile
    tiles = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s:
                tiles.append(line_to_tile(s))
    return tiles


def _reconstruct_W(W_tiles):
    """Invert the tap-tiling: (16,8,3,3) from the 5 stationary 16x16 tiles."""
    W = np.zeros((16, 8, 3, 3), dtype=np.int64)
    for t, tile in enumerate(_tap_tiles()):
        for slot, (kh, kw) in enumerate(tile):
            base = slot * 8
            for r in range(16):
                for c in range(8):
                    W[r, c, kh, kw] = int(W_tiles[t][r][base + c])
    return W


def build_engine():
    IMW, OH, OW = 13, 11, 11
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    Pn = len(positions)
    tap_tiles = _tap_tiles()
    NTILE = len(tap_tiles)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mem_path = os.path.join(root, "src", "rtl", "student", "conv2_ws_tiles.mem")

    # (1) UNABHAENGIGE Referenz-Gewichte direkt aus dem Modell (natuerlicher Index).
    W_ref = None
    try:
        from pack_conv2_ws_tiles import load_quantized_model
        m = load_quantized_model()
        W_ref = m.conv2.weight().int_repr().numpy().astype(np.int64)   # (16,8,3,3)
        assert W_ref.shape == (16, 8, 3, 3), W_ref.shape
    except Exception as e:                                             # noqa: BLE001
        print(f"[engine] Modell-Load fehlgeschlagen ({e}); Referenz aus mem rekonstruiert.")

    # (2) Die ECHTEN repackten Gewichte, die die HW-BRAM laedt.
    if os.path.exists(mem_path):
        W_tiles = _read_mem_tiles(mem_path)
        assert len(W_tiles) == NTILE, f"{mem_path}: erwarte {NTILE} Kacheln, habe {len(W_tiles)}"
    else:
        print(f"[engine] {mem_path} fehlt -- erst pack_conv2_ws_tiles.py laufen lassen; "
              f"baue Kacheln aus dem Modell.")
        assert W_ref is not None, "weder mem noch Modell -- kann Engine-Golden nicht bauen."
        from pack_conv2_ws_tiles import build_tiles
        W_tiles = build_tiles(W_ref)

    if W_ref is None:
        W_ref = _reconstruct_W(W_tiles)
    else:
        # on-disk mem MUSS zum aktuellen Modell passen (sonst packer neu laufen lassen)
        from pack_conv2_ws_tiles import build_tiles
        W_tiles_model = build_tiles(W_ref)
        for t in range(NTILE):
            assert np.array_equal(np.asarray(W_tiles[t]), np.asarray(W_tiles_model[t])), (
                f"conv2_ws_tiles.mem Kachel {t} != aktuelles Modell -- pack_conv2_ws_tiles.py neu laufen lassen")

    # (3) Deterministisches Aktivierungsbild (13x13x8, voller signed-int8-Bereich).
    rng = np.random.RandomState(21)
    X = rng.randint(-128, 128, size=(IMW, IMW, 8)).astype(np.int64)
    ref = reference_conv2(X, W_ref)                                   # (11,11,16)

    # (4) Self-Check bei REALER Kadenz spacing=2: WS-Route (mem-Bytes) == Referenz.
    acc = np.zeros((Pn, 16), dtype=np.int64)
    for t, tile in enumerate(tap_tiles):
        acts = [np.zeros(16, dtype=np.int64) for _ in range(Pn)]
        for slot, (kh, kw) in enumerate(tile):
            base = slot * 8
            for p, (oh, ow) in enumerate(positions):
                for c in range(8):
                    acts[p][base + c] = int(X[oh + kh, ow + kw, c])
        cap = route_stream(W_tiles[t], acts, N=16, spacing=2)
        for p in range(Pn):
            for r in range(16):
                acc[p][r] += cap[p][r]
    Y = np.zeros((Pn, 16), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        Y[p] = ref[oh, ow]
    assert np.array_equal(acc, Y), "ENGINE-Golden Self-Check FEHLGESCHLAGEN (WS-Route != reference_conv2)"

    return NTILE, IMW, OH, OW, Pn, W_tiles, X, Y


def emit_engine():
    NTILE, IMW, OH, OW, Pn, W_tiles, X, Y = build_engine()
    DEPTH = IMW * IMW                                                 # 169

    L = []
    L.append("// AUTOGENERIERT von pytorch/gen_ws_golden.py -- NICHT von Hand editieren.")
    L.append("// WS-ENGINE-Golden: ECHTE conv2 (13x13x8 -> 11x11x16), N=16, 5 Tap-Tiles, P=121.")
    L.append("// eng_w  == conv2_ws_tiles.mem (die Bytes, die die Engine-Weight-BRAM laedt).")
    L.append("// eng_act: 64b-Woerter (8 int8-Kanaele, Kanal c in Bits [c*8+:8]); Adresse = row*EIMW+col")
    L.append("//          -> genau die act_buffer-Ablage (rp_word[k*8+:8]=rp_act[k], Raster row*13+col).")
    L.append("// eng_y[p][r]: erwarteter roher 32b-MAC, p=oh*EOW+ow, r=Ausgabekanal 0..15 (== u_acc.acc_o).")
    L.append("localparam int EN        = 16;")
    L.append(f"localparam int ENTILE    = {NTILE};")
    L.append(f"localparam int EP        = {Pn};")
    L.append("localparam int ESPACING  = 2;")
    L.append(f"localparam int EIMW      = {IMW};")
    L.append(f"localparam int EOH       = {OH};")
    L.append(f"localparam int EOW       = {OW};")
    L.append(f"localparam int EACT_DEPTH= {DEPTH};")
    L.append("")
    L.append("logic signed [7:0]  eng_w   [ENTILE][EN][EN];")
    L.append("logic        [63:0] eng_act [0:EACT_DEPTH-1];")
    L.append("logic signed [31:0] eng_y   [EP][EN];")
    L.append("")
    L.append("task automatic load_engine_golden();")
    for t in range(NTILE):
        for r in range(16):
            for c in range(16):
                L.append(f"  eng_w[{t}][{r}][{c}] = 8'sh{h8(W_tiles[t][r][c])};")
    for row in range(IMW):
        for col in range(IMW):
            addr = row * IMW + col
            word = 0
            for c in range(8):
                word |= (int(X[row, col, c]) & 0xFF) << (c * 8)
            L.append(f"  eng_act[{addr}] = 64'h{h64(word)};")
    for p in range(Pn):
        for r in range(16):
            L.append(f"  eng_y[{p}][{r}] = 32'sh{h32(Y[p][r])};")
    L.append("endtask")
    L.append("")

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "src", "tb", "ws_engine_gold.svh")
    with open(path, "w") as f:
        f.write("\n".join(L))
    print(f"ENGINE-Golden Self-Check PASS. Wrote src/tb/ws_engine_gold.svh  "
          f"(NTILE={NTILE}, P={Pn}, act_depth={DEPTH}; "
          f"{NTILE*16*16} weights + {DEPTH} act-words + {Pn*16} expected).")


# ===========================================================================
#  ENGINE-conv1-Golden: ECHTE conv1 (28x28x1 -> 26x26x8, GP=676, N=16, 1 Tap-
#  Tile, spacing=1) mit den EXAKTEN Gewichten aus conv1_ws_tile.mem (genau die
#  Bytes, die die geteilte Engine-Weight-BRAM in Slot CONV1_BASE=5 per
#  $readmemh laedt). Fuer student_ws_conv1_engine_tb, die student_ws_conv als
#  Ganzes in conv1-Modus (mode_i=0) prueft: pbuf vorladen, laufen lassen, den
#  Readout-Stream (rvalid_o -> result_o[0..7]) je Position gegen die Referenz
#  vergleichen.
#
#  Der Self-Check ist STARK: die Referenz-Gewichte kommen UNABHAENGIG aus dem
#  Modell (natuerlicher (kh,kw)-Index -> reference_conv1); die WS-Route benutzt
#  die mem-Bytes (ws_conv1_N16). Ein Fehler in Tile-Byteorder / Tap-Spalten /
#  spacing wuerde die beiden auseinanderlaufen lassen.
# ===========================================================================
def _read_conv1_mem_tile(path):
    """Read conv1_ws_tile.mem EXACTLY as student_ws_weight_bram reads it (signed 16x16)."""
    from pack_conv2_ws_tiles import line_to_tile
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s:
                return line_to_tile(s)
    raise RuntimeError(f"{path}: keine Tile-Zeile gefunden")


def _reconstruct_W1(Wt):
    """(8,1,3,3) aus dem 16x16 conv1-Tile: Zeile oc=Out-Kanal(0..7), Spalte tap=kh*3+kw."""
    W1 = np.zeros((8, 1, 3, 3), dtype=np.int64)
    for oc in range(8):
        for tap in range(9):
            W1[oc, 0, tap // 3, tap % 3] = int(Wt[oc][tap])
    return W1


def build_engine_conv1():
    IMW, OH, OW = 28, 26, 26                                          # echtes conv1: 28x28 -> 26x26
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    Pn = len(positions)                                              # 676

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mem_path = os.path.join(root, "src", "rtl", "student", "conv1_ws_tile.mem")

    # (1) UNABHAENGIGE Referenz-Gewichte direkt aus dem Modell (natuerlicher Index).
    W_ref = None
    try:
        from pack_conv2_ws_tiles import load_quantized_model
        m = load_quantized_model()
        W_ref = m.conv1.weight().int_repr().numpy().astype(np.int64)  # (8,1,3,3)
        assert W_ref.shape == (8, 1, 3, 3), W_ref.shape
    except Exception as e:                                            # noqa: BLE001
        print(f"[engine-conv1] Modell-Load fehlgeschlagen ({e}); Referenz aus mem rekonstruiert.")

    # (2) Das ECHTE gepackte Tile, das die HW-BRAM in Slot 5 laedt.
    if os.path.exists(mem_path):
        Wt = _read_conv1_mem_tile(mem_path)                          # (16,16) signed
    else:
        print(f"[engine-conv1] {mem_path} fehlt -- erst pack_conv1_ws_tile.py laufen lassen; "
              f"baue Tile aus dem Modell.")
        assert W_ref is not None, "weder mem noch Modell -- kann conv1-Golden nicht bauen."
        from pack_conv1_ws_tile import build_conv1_tile
        Wt = np.asarray(build_conv1_tile(W_ref))

    if W_ref is None:
        W_ref = _reconstruct_W1(Wt)
    else:
        # on-disk mem MUSS zum aktuellen Modell passen (sonst packer neu laufen lassen)
        from pack_conv1_ws_tile import build_conv1_tile
        Wt_model = np.asarray(build_conv1_tile(W_ref))
        assert np.array_equal(np.asarray(Wt), Wt_model), (
            "conv1_ws_tile.mem != aktuelles Modell -- pack_conv1_ws_tile.py neu laufen lassen")

    # Gewichte, die die HW effektiv multipliziert (aus den mem-Bytes rekonstruiert).
    W_hw = _reconstruct_W1(Wt)

    # (3) Deterministisches Eingabebild (28x28x1, voller signed-int8-Bereich).
    #     Die Engine interpretiert pbuf-Bytes als signed int8 -> Referenz ebenso.
    rng = np.random.RandomState(41)
    X = rng.randint(-128, 128, size=(IMW, IMW, 1)).astype(np.int64)
    ref = reference_conv1(X, W_ref)                                  # (26,26,8)

    # (4) Self-Check: WS-conv1-Route (mem-Bytes, spacing=1) == Referenz-conv1.
    y_ws, _ = ws_conv1_N16(X, W_hw)
    assert np.array_equal(y_ws, ref), (
        "ENGINE-conv1-Golden Self-Check FEHLGESCHLAGEN (ws_conv1_N16(mem) != reference_conv1)")

    Y = np.zeros((Pn, 8), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        Y[p] = ref[oh, ow]
    return IMW, OH, OW, Pn, Wt, X, Y


def emit_engine_conv1():
    IMW, OH, OW, Pn, Wt, X, Y = build_engine_conv1()
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]

    L = []
    L.append("// AUTOGENERIERT von pytorch/gen_ws_golden.py -- NICHT von Hand editieren.")
    L.append("// WS-ENGINE-conv1-Golden: ECHTE conv1 (28x28x1 -> 26x26x8), N=16, 1 Tap-Tile, GP=676.")
    L.append("// Gewichte == conv1_ws_tile.mem (Slot 5, via CONV1_WS_MEM_FILE in die Engine-Weight-BRAM).")
    L.append("// c1_pbuf[p]: 72b Patch-Wort, Byte t (Bits [t*8+:8]) = Tap t = X[oh+kh,ow+kw] mit tap=kh*3+kw")
    L.append("//            (byte0=(kh0,kw0) .. byte8=(kh2,kw2)); p = oh*C1_OW+ow (lineare pbuf-Adresse=ic).")
    L.append("// c1_exp[p][r]: erwarteter roher 32b-MAC = reference_conv1[oh,ow,r], r=Out-Kanal 0..7 (== ac_acc[r]).")
    L.append(f"localparam int C1_GP    = {Pn};")
    L.append(f"localparam int C1_IMW   = {IMW};")
    L.append(f"localparam int C1_OH    = {OH};")
    L.append(f"localparam int C1_OW    = {OW};")
    L.append(f"localparam int C1_DEPTH = {Pn};   // pbuf-Woerter (= GP, lineare Rasteradresse)")
    L.append("")
    L.append("logic [71:0]        c1_pbuf [0:C1_GP-1];")
    L.append("logic signed [31:0] c1_exp  [0:C1_GP-1][0:7];")
    L.append("")
    L.append("task automatic load_conv1_golden();")
    for p, (oh, ow) in enumerate(positions):
        word = 0
        for tap in range(9):
            kh, kw = tap // 3, tap % 3
            word |= (int(X[oh + kh, ow + kw, 0]) & 0xFF) << (tap * 8)
        L.append(f"  c1_pbuf[{p}] = 72'h{h72(word)};")
    for p in range(Pn):
        for r in range(8):
            L.append(f"  c1_exp[{p}][{r}] = 32'sh{h32(Y[p][r])};")
    L.append("endtask")
    L.append("")

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "src", "tb", "ws_conv1_gold.svh")
    with open(path, "w") as f:
        f.write("\n".join(L))
    print(f"ENGINE-conv1-Golden Self-Check PASS. Wrote src/tb/ws_conv1_gold.svh  "
          f"(GP={Pn}, pbuf_depth={Pn}; {Pn} pbuf-words + {Pn*8} expected).")


def main():
    NTILE, W_tiles, A_tiles, Y = build()
    L = []
    L.append("// AUTOGENERIERT von pytorch/gen_ws_golden.py -- NICHT von Hand editieren.")
    L.append("// WS-Kern-Golden: conv2 5x5x8 -> 3x3x16, N=16, 5 Tap-Tiles, P=9.")
    L.append(f"localparam int GN       = {N};")
    L.append(f"localparam int GNTILE   = {NTILE};")
    L.append(f"localparam int GP       = {P};")
    L.append(f"localparam int GSPACING = 2;   // reale act_buffer-Kadenz (2 Woerter/Position)")
    L.append("")
    L.append("logic signed [7:0]  gold_w [GNTILE][GN][GN];")
    L.append("logic signed [7:0]  gold_a [GNTILE][GP][GN];")
    L.append("logic signed [31:0] gold_y [GP][GN];")
    L.append("")
    L.append("task automatic load_golden();")
    for t in range(NTILE):
        for r in range(N):
            for c in range(N):
                L.append(f"  gold_w[{t}][{r}][{c}] = 8'sh{h8(W_tiles[t][r][c])};")
    for t in range(NTILE):
        for p in range(P):
            for c in range(N):
                L.append(f"  gold_a[{t}][{p}][{c}] = 8'sh{h8(A_tiles[t][p][c])};")
    for p in range(P):
        for r in range(N):
            L.append(f"  gold_y[{p}][{r}] = 32'sh{h32(Y[p][r])};")
    L.append("endtask")
    L.append("")

    out = "src/tb/ws_gold.svh"
    import os
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, out)
    with open(path, "w") as f:
        f.write("\n".join(L))
    print(f"GOLDEN self-check PASS. Wrote {out}  "
          f"(N={N}, NTILE={NTILE}, P={P}, "
          f"{NTILE*N*N} weights + {NTILE*P*N} acts + {P*N} expected).")

    # Engine-Golden (volle conv2, echte repackte Gewichte) zusaetzlich erzeugen.
    emit_engine()

    # conv1-Engine-Golden (volle conv1, echtes conv1_ws_tile.mem) zusaetzlich erzeugen.
    emit_engine_conv1()


if __name__ == "__main__":
    main()
