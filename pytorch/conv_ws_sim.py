"""Zyklenmodell der weight-stationary conv-Umstellung (route mode + Anti-Diagonal-Erfassung), parametrisiert ueber N."""
import numpy as np


# ---------------------------------------------------------------------------
#  Zyklengenaues route-mode-Array mit anti-diagonaler Erfassung
# ---------------------------------------------------------------------------
def route_stream(W_tile, acts, N, spacing=1):
    """
    W_tile  : (N,N) int   -- stationaere Gewichte (bereits geladen), W_tile[r][c]
    acts    : list[P] of (N,) int -- je Position ein Aktivierungs-Vektor (Spalte c)
    spacing : Injektions-Kadenz. spacing=1 (1 Pos/Takt, wenn act_buffer 1 Vektor/Takt
              liefern kann) oder spacing=2 (N=16 conv2: 2 Tap-Woerter/Position aus dem
              64b-Single-Port-act_buffer -> 1 Position alle 2 Takte).
    Injektion: Position p bei Zyklus p*spacing (route mode, ready=1).
    Rueckgabe: cap[P][N]  mit cap[p][r] = Zeile r des Ergebnisses fuer Position p,
               so wie es die anti-diagonale Erfassung am rechten Rand einsammelt.

    Modelliert die Register exakt wie student_systolic_array:
      Skew:  act_delay[c][st], act_skewed[c] = act_delay[c][c]
      Grid:  act_v[gr][gc] (nach unten), psum_h[gr][gc] (nach rechts), left=0
      Exit:  Position p, Zeile r verlaesst rechts bei Zyklus p*spacing + N + r + 1.
    """
    P = len(acts)
    act_delay = [[0] * N for _ in range(N)]      # [c][stage]
    act_v  = [[0] * N for _ in range(N)]
    psum_h = [[0] * N for _ in range(N)]
    cap = [[None] * N for _ in range(P)]

    T = P * spacing + 2 * N + 2
    for cyc in range(T):
        # --- act_row praesentieren: Position p bei Zyklus p*spacing ---
        act_row = [0] * N
        if cyc % spacing == 0 and 0 <= cyc // spacing < P:
            p_inj = cyc // spacing
            for c in range(N):
                act_row[c] = int(acts[p_inj][c])

        # --- kombinatorisch aus aktuellen Registern ---
        act_skewed = [act_delay[c][c] for c in range(N)]
        n_act_v  = [[0] * N for _ in range(N)]
        n_psum_h = [[0] * N for _ in range(N)]
        for gr in range(N):
            for gc in range(N):
                a_in = act_skewed[gc] if gr == 0 else act_v[gr - 1][gc]
                p_in = 0 if gc == 0 else psum_h[gr][gc - 1]
                n_psum_h[gr][gc] = p_in + a_in * int(W_tile[gr][gc])
                n_act_v[gr][gc]  = a_in

        # --- rechter Rand DIESES Takts (registrierter Wert) einsammeln ---
        # Zeile r gehoert zu Position p mit p*spacing + N + r + 1 == cyc.
        for r in range(N):
            praw = cyc - N - r - 1
            if praw >= 0 and (praw % spacing == 0):
                p = praw // spacing
                if 0 <= p < P:
                    cap[p][r] = psum_h[r][N - 1]

        # --- Takt: Register updaten ---
        act_v, psum_h = n_act_v, n_psum_h
        for c in range(N):
            for st in range(N - 1, 0, -1):
                act_delay[c][st] = act_delay[c][st - 1]
            act_delay[c][0] = act_row[c]

    return cap


# ---------------------------------------------------------------------------
#  Referenz-conv2 (Standard-Faltung, 8 in / 16 out, 3x3, kein Pad)
# ---------------------------------------------------------------------------
def reference_conv1(X, W):
    """X:(H,Wd,1) int, W:(8,1,3,3) int -> Y:(H-2,Wd-2,8) int64. conv1: 1 in-ch, 3x3."""
    H, Wd = X.shape[0], X.shape[1]
    OH, OW = H - 2, Wd - 2
    Y = np.zeros((OH, OW, 8), dtype=np.int64)
    for oh in range(OH):
        for ow in range(OW):
            for oc in range(8):
                s = 0
                for kh in range(3):
                    for kw in range(3):
                        s += int(X[oh + kh, ow + kw, 0]) * int(W[oc, 0, kh, kw])
                Y[oh, ow, oc] = s
    return Y


# ---------------------------------------------------------------------------
#  WS-conv1 bei N=16: EIN Tap-Tile (9 Taps x 1 Kanal in Spalten 0..8, 8 out in
#  Zeilen 0..7), spacing=1 -- der 9-Pixel-Patch ist EIN Wort (pbuf 72b). 676 Pos.
# ---------------------------------------------------------------------------
def ws_conv1_N16(X, W):
    OH, OW = X.shape[0] - 2, X.shape[1] - 2
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    P = len(positions)
    # 1 Tile: Zeile oc = Out-Kanal (0..7), Spalte tap = kh*3+kw (0..8), Rest 0.
    W_tile = np.zeros((16, 16), dtype=np.int64)
    for oc in range(8):
        for tap in range(9):
            W_tile[oc][tap] = int(W[oc, 0, tap // 3, tap % 3])
    acts = []
    for (oh, ow) in positions:
        v = np.zeros(16, dtype=np.int64)
        for tap in range(9):
            v[tap] = int(X[oh + tap // 3, ow + tap % 3, 0])
        acts.append(v)
    cap = route_stream(W_tile, acts, N=16, spacing=1)
    Y = np.zeros((OH, OW, 8), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        for r in range(8):
            Y[oh, ow, r] = cap[p][r]
    return Y, P * 1 + 2 * 16


def reference_conv2(X, W):
    """X:(H,Wd,8) int, W:(16,8,3,3) int -> Y:(H-2,Wd-2,16) int64"""
    H, Wd, C = X.shape
    OH, OW = H - 2, Wd - 2
    Y = np.zeros((OH, OW, 16), dtype=np.int64)
    for oh in range(OH):
        for ow in range(OW):
            for oc in range(16):
                s = 0
                for kh in range(3):
                    for kw in range(3):
                        for ic in range(8):
                            s += int(X[oh + kh, ow + kw, ic]) * int(W[oc, ic, kh, kw])
                Y[oh, ow, oc] = s
    return Y


# ---------------------------------------------------------------------------
#  WS-conv2 bei N=8:  2 Gruppen x 9 Tap-Tiles, extern akkumuliert
# ---------------------------------------------------------------------------
def ws_conv2_N8(X, W):
    OH, OW = X.shape[0] - 2, X.shape[1] - 2
    P = OH * OW
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    Y = np.zeros((OH, OW, 16), dtype=np.int64)
    cycles = 0

    for grp in range(2):                       # 16 out-ch = 2 Gruppen a 8
        acc = [[0] * 8 for _ in range(P)]
        for kh in range(3):
            for kw in range(3):                # 9 Taps
                # Gewichts-Tile[r][c] = W[grp*8+r][c][kh][kw]  (8 out x 8 in)
                W_tile = np.array([[int(W[grp * 8 + r, c, kh, kw]) for c in range(8)]
                                   for r in range(8)], dtype=np.int64)
                # Aktivierungen: je Position das 8-Kanal-Fenster-Wort X[oh+kh][ow+kw]
                acts = [np.array([int(X[oh + kh, ow + kw, c]) for c in range(8)],
                                 dtype=np.int64) for (oh, ow) in positions]
                cap = route_stream(W_tile, acts, N=8)
                for p in range(P):
                    for r in range(8):
                        acc[p][r] += cap[p][r]
                cycles += P + 2 * 8            # Stream + Fill/Drain je Tap-Tile
        for p, (oh, ow) in enumerate(positions):
            for r in range(8):
                Y[oh, ow, grp * 8 + r] = acc[p][r]
    return Y, cycles


# ---------------------------------------------------------------------------
#  WS-conv2 bei N=16:  1 Gruppe (16 out), 2 Taps je 16er-Tile -> 5 Tiles
# ---------------------------------------------------------------------------
def ws_conv2_N16(X, W, spacing=2):
    OH, OW = X.shape[0] - 2, X.shape[1] - 2
    P = OH * OW
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    Y = np.zeros((OH, OW, 16), dtype=np.int64)
    cycles = 0

    taps = [(kh, kw) for kh in range(3) for kw in range(3)]   # 9 Taps
    # Zu 16er-Spalten packen: je Tile 2 Taps (16 in = 2 x 8 Kanaele); Tap 9 allein.
    tap_tiles = [taps[i:i + 2] for i in range(0, 9, 2)]        # 5 Tiles (letztes: 1 Tap)

    acc = [[0] * 16 for _ in range(P)]
    for tile in tap_tiles:
        # Gewichts-Tile[r=0..15 out][c=0..15 in] : c<8 -> Tap tile[0], c>=8 -> Tap tile[1]
        W_tile = np.zeros((16, 16), dtype=np.int64)
        acts = [np.zeros(16, dtype=np.int64) for _ in range(P)]
        for slot, (kh, kw) in enumerate(tile):                # slot 0 -> Spalten 0..7, slot 1 -> 8..15
            base = slot * 8
            for r in range(16):
                for c in range(8):
                    W_tile[r][base + c] = int(W[r, c, kh, kw])
            for p, (oh, ow) in enumerate(positions):
                for c in range(8):
                    acts[p][base + c] = int(X[oh + kh, ow + kw, c])
        cap = route_stream(W_tile, acts, N=16, spacing=spacing)
        for p in range(P):
            for r in range(16):
                acc[p][r] += cap[p][r]
        cycles += P * spacing + 2 * 16
    for p, (oh, ow) in enumerate(positions):
        for r in range(16):
            Y[oh, ow, r] = acc[p][r]
    return Y, cycles


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    rng = np.random.RandomState(0)
    # kleines, aber echtes conv2-Format: 13x13 x 8 -> 11x11 x 16 (wie im RTL)
    X = rng.randint(-8, 8, size=(13, 13, 8))
    W = rng.randint(-8, 8, size=(16, 8, 3, 3))

    ref = reference_conv2(X, W)

    # -- Schritt 1: route-mode-Erfassung == naive Matmul, spacing 1 UND 2 --
    P = 6
    Wt = rng.randint(-4, 4, size=(8, 8))
    acts = [rng.randint(-4, 4, size=(8,)) for _ in range(P)]
    cap1 = route_stream(Wt, acts, N=8, spacing=1)
    cap2 = route_stream(Wt, acts, N=8, spacing=2)
    ok_cap1 = all(cap1[p][r] == int(Wt[r] @ acts[p]) for p in range(P) for r in range(8))
    ok_cap2 = all(cap2[p][r] == int(Wt[r] @ acts[p]) for p in range(P) for r in range(8))
    print(f"[1a] route capture == matmul, spacing 1 : {'PASS' if ok_cap1 else 'FAIL'}")
    print(f"[1b] route capture == matmul, spacing 2 : {'PASS' if ok_cap2 else 'FAIL'}")

    # -- Schritt 2: WS N=8 == Referenz --
    y8, c8 = ws_conv2_N8(X, W)
    ok8 = np.array_equal(y8, ref)
    print(f"[2]  WS conv2 (N=8,  2 grp x 9 taps)  == reference : {'PASS' if ok8 else 'FAIL'}")

    # -- Schritt 3: WS N=16 bei REALER Kadenz spacing=2 == Referenz --
    y16, c16 = ws_conv2_N16(X, W, spacing=2)
    ok16 = np.array_equal(y16, ref)
    print(f"[3]  WS conv2 (N=16, 5 tiles, spacing=2) == reference : {'PASS' if ok16 else 'FAIL'}")

    # -- Schritt 4: WS conv1 (N=16, 1 Tile, spacing=1) == Referenz --
    Xc1 = rng.randint(-8, 8, size=(8, 8, 1))
    Wc1 = rng.randint(-8, 8, size=(8, 1, 3, 3))
    ref1 = reference_conv1(Xc1, Wc1)
    y1, c1 = ws_conv1_N16(Xc1, Wc1)
    ok1 = np.array_equal(y1, ref1)
    print(f"[4]  WS conv1 (N=16, 1 tile,  spacing=1) == reference : {'PASS' if ok1 else 'FAIL'}")

    print()
    print(f"conv2 stream cycles (nur Array, Fill/Drain inkl.):")
    print(f"   WS N=8  (spacing 1): {c8:5d}   (121 Pos x 18 Tap-Streams)")
    print(f"   WS N=16 (spacing 2): {c16:5d}   (121 Pos x 5 Tap-Streams, 2 Woerter/Pos)")
    base_accum = 242 * 63       # aktueller banked-accumulate conv2 (242 ops x 63 cyc)
    print(f"   banked-accumulate conv2 (ist): ~{base_accum}")
    if ok16:
        print(f"   -> WS N=16 spacing2 vs banked conv2: ~{base_accum / max(c16,1):.2f}x auf conv2 (nur Array)")
    print()
    ok_all = ok_cap1 and ok_cap2 and ok8 and ok16 and ok1
    print("ALLE BIT-IDENTISCH." if ok_all else "!!! FEHLER -- nicht bit-identisch.")
