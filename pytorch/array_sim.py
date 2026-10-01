"""Zyklenmodell von student_systolic_array (accumulate mode) zur Algorithmus-Verifikation."""
import numpy as np

def simulate(weights, acts, N=8, per_wavefront_bank=False, spacing=None):
    """
    weights : list[num_steps] of (N,N) int arrays  (weight_s[r][c])
    acts    : list[num_steps] of (N,) int vectors
    per_wavefront_bank : False = aktuelles Design (globaler use_bank, spacing=2N-1)
                         True  = Optimierung (bank folgt Wellenfront, spacing=N)
    Rueckgabe: (acc[N], zyklen)
    """
    S = len(weights)
    if spacing is None:
        spacing = N if per_wavefront_bank else (2 * N - 1)

    # --- Register ---
    # Skew: pro Spalte c eine Kette der Tiefe N; act_delay[c][st]
    act_delay  = [[0] * N for _ in range(N)]           # Werte
    bank_delay = [[0] * N for _ in range(N)]           # begleitendes Bank-Bit
    # PE-Ausgaenge (registriert): act_v[gr][gc], psum_h[gr][gc]
    act_v  = [[0] * N for _ in range(N)]
    psum_h = [[0] * N for _ in range(N)]
    bank_v = [[0] * N for _ in range(N)]               # Bank, das mit act nach unten haengt
    # Gewichts-Banks pro PE
    wq = [[[0, 0] for _ in range(N)] for _ in range(N)]

    acc = [0] * N
    global_use_bank = 0

    # Feeding-Plan: Schritt s wird zum Zeitpunkt t_accept[s] angenommen.
    t_accept = [s * spacing for s in range(S)]
    # Gewichte fuer Schritt s werden VOR dem Annehmen in bank (s%2 bei opt, s%1..) geladen.
    accept_set = {t: s for s, t in enumerate(t_accept)}

    GRID_LAT = N          # Zeile 0 fertig nach N; Zeile r nach N+r
    T = t_accept[-1] + 4 * N + 10   # grosszuegig: deepster Row-Wavefront + Rand

    # Wellenfront-Tracker: Liste (accept_cycle, step) fuer in-flight Tiles
    # acc[r] += right_psum[r] wenn (cyc - accept_cycle) == GRID_LAT + r
    inflight = []

    for cyc in range(T):
        # ---- 1) Gewichte laden (kombinatorisch vor dem Annehmen bereitstellen) ----
        # Der Feeder laedt Schritt s ein paar Takte vor t_accept[s]; hier setzen wir
        # die Bank direkt beim Annehmen (Modell: Gewichte sind rechtzeitig da).
        pending_bank = None
        if cyc in accept_set:
            s = accept_set[cyc]
            bank = s % 2                   # Doppelpufferung: alternierende Bank je Schritt
            for r in range(N):
                for c in range(N):
                    wq[r][c][bank] = int(weights[s][r][c])
            pending_bank = bank            # global_use_bank REGISTRIERT (erst naechsten Takt)

        # ---- 2) act_row praesentieren (Schritt s beim Annehmen) + Bank-Tag ----
        act_row  = [0] * N
        bank_row = [0] * N
        if cyc in accept_set:
            s = accept_set[cyc]
            for c in range(N):
                act_row[c]  = int(acts[s][c])
                bank_row[c] = s % 2
            inflight.append((cyc, s))

        # ---- 3) act_skewed = act_delay[c][c] (aktuelle Registerwerte) ----
        act_skewed  = [act_delay[c][c]  for c in range(N)]
        bank_skewed = [bank_delay[c][c] for c in range(N)]

        # ---- 4) Grid kombinatorisch (aus aktuellen Registern) ----
        new_act_v  = [[0] * N for _ in range(N)]
        new_psum_h = [[0] * N for _ in range(N)]
        new_bank_v = [[0] * N for _ in range(N)]
        for gr in range(N):
            for gc in range(N):
                act_in  = act_skewed[gc]  if gr == 0 else act_v[gr - 1][gc]
                bnk_in  = bank_skewed[gc] if gr == 0 else bank_v[gr - 1][gc]
                psum_in = 0 if gc == 0 else psum_h[gr][gc - 1]
                use_b   = bnk_in if per_wavefront_bank else global_use_bank
                w       = wq[gr][gc][use_b]
                new_psum_h[gr][gc] = psum_in + act_in * w
                new_act_v[gr][gc]  = act_in
                new_bank_v[gr][gc] = bnk_in

        # ---- 5) Akkumulation: AKTUELLES (registriertes) psum_h, Zeile r bei age N+r+1 ----
        #  RTL: tile_pipe schiebt bei Annahme (A) -> tile_pipe[0]=1 bei A+1;
        #       acc[r] += psum_h[r][N-1] wenn tile_pipe[N+r]=1 (bei A+1+N+r).
        right_psum = [psum_h[r][N - 1] for r in range(N)]   # aktueller Registerwert
        for (acc_cyc, s) in inflight:
            age = cyc - acc_cyc
            for r in range(N):
                if age == N + r + 1:
                    acc[r] += right_psum[r]

        # ---- 6) Register-Update (Takt) ----
        act_v, psum_h, bank_v = new_act_v, new_psum_h, new_bank_v
        for c in range(N):
            for st in range(N - 1, 0, -1):
                act_delay[c][st]  = act_delay[c][st - 1]
                bank_delay[c][st] = bank_delay[c][st - 1]
            act_delay[c][0]  = act_row[c]
            bank_delay[c][0] = bank_row[c]
        # use_bank_q registriert: switcht erst den Takt NACH der Annahme
        if pending_bank is not None:
            global_use_bank = pending_bank

    return acc, T


def reference(weights, acts):
    S = len(weights)
    N = weights[0].shape[0]
    acc = np.zeros(N, dtype=np.int64)
    for s in range(S):
        acc += weights[s].astype(np.int64) @ acts[s].astype(np.int64)
    return acc


if __name__ == "__main__":
    rng = np.random.RandomState(0)
    N = 8
    ok = True
    for trial in range(200):
        S = rng.randint(2, 12)                       # 2..11 Schritte (conv/fc)
        weights = [rng.randint(-8, 8, size=(N, N)) for _ in range(S)]
        acts    = [rng.randint(-8, 8, size=(N,))    for _ in range(S)]
        ref = reference(weights, acts)

        cur, cyc_cur = simulate(weights, acts, N=N, per_wavefront_bank=False)
        opt, cyc_opt = simulate(weights, acts, N=N, per_wavefront_bank=True)

        if not np.array_equal(cur, ref):
            print(f"[trial {trial}] CURRENT != reference: {cur} vs {ref}"); ok = False; break
        if not np.array_equal(opt, ref):
            print(f"[trial {trial}] OPT != reference: {opt} vs {ref}"); ok = False; break

    if ok:
        # Beispiel-Zyklenvergleich fuer S=9 (conv2)
        S = 9
        w = [rng.randint(-8, 8, size=(N, N)) for _ in range(S)]
        a = [rng.randint(-8, 8, size=(N,)) for _ in range(S)]
        _, c_cur = simulate(w, a, N=N, per_wavefront_bank=False)
        _, c_opt = simulate(w, a, N=N, per_wavefront_bank=True)
        print(f"ALL 200 TRIALS PASS: current == opt == reference (bit-identical).")
        print(f"Spacing: current=2N-1={2*N-1}, opt=N={N}  ->  step-time ~{(2*N-1)/N:.2f}x faster")
        print(f"Example S=9 (conv2 op): current~{c_cur} cyc, opt~{c_opt} cyc")
