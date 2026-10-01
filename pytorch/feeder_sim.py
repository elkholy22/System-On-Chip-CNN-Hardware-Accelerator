"""Zyklengenaues Modell von Feeder + Array + PE (accumulate mode)."""
import numpy as np


def run_op(weights, acts, N=8, spacing=8, num_banks=2):
    """Eine accumulate-Operation faithful simulieren. Rueckgabe: acc[N] oder None."""
    S = len(weights)
    MIN_SPACING = spacing
    GRID_LAT = N
    PIPE_D = 2 * N

    # ---------------- Array-Register ----------------
    act_delay  = [[0] * N for _ in range(N)]           # [c][stage]
    bank_delay = [[0] * N for _ in range(N)]
    act_v  = [[0] * N for _ in range(N)]
    psum_h = [[0] * N for _ in range(N)]
    bank_v = [[0] * N for _ in range(N)]
    wq = [[[0] * num_banks for _ in range(N)] for _ in range(N)]   # [gr][gc][bank]
    acc = [0] * N
    acc_cnt   = 0
    running   = 0
    tile_pipe = [0] * (PIPE_D + 1)
    space_cnt = MIN_SPACING
    result_valid = 0

    # ---------------- Feeder-Register ----------------
    st = 'IDLE'
    step = 0
    nsteps_q = 0
    a_start = 0; a_wload = 0; a_lbank = 0; a_ubank = 0; a_avalid = 0
    a_arow  = [0] * N
    a_wtile = [[0] * N for _ in range(N)]
    astep = 0

    result_final = None
    done = False

    T = S * spacing + 8 * N + 40
    for cyc in range(T):
        op_start_i = 1 if cyc == 0 else 0

        # ============ KOMBINATORIK (aus aktuellen Registern) ============
        start_i       = a_start
        weight_load_i = a_wload
        load_bank_i   = a_lbank
        use_bank_i    = a_ubank
        act_valid_i   = a_avalid
        act_row_i     = a_arow
        num_steps_i   = nsteps_q

        ready_o = 1 if (running and space_cnt == MIN_SPACING) else 0

        act_skewed  = [act_delay[c][c]  for c in range(N)]
        bank_skewed = [bank_delay[c][c] for c in range(N)]

        n_act_v  = [[0] * N for _ in range(N)]
        n_psum_h = [[0] * N for _ in range(N)]
        n_bank_v = [[0] * N for _ in range(N)]
        for gr in range(N):
            for gc in range(N):
                act_in  = act_skewed[gc]  if gr == 0 else act_v[gr - 1][gc]
                bnk_in  = bank_skewed[gc] if gr == 0 else bank_v[gr - 1][gc]
                psum_in = 0 if gc == 0 else psum_h[gr][gc - 1]
                w   = wq[gr][gc][bnk_in]
                mac = psum_in + act_in * w
                if start_i:
                    n_act_v[gr][gc] = 0; n_psum_h[gr][gc] = 0; n_bank_v[gr][gc] = 0
                else:
                    n_act_v[gr][gc] = act_in; n_psum_h[gr][gc] = mac; n_bank_v[gr][gc] = bnk_in

        right_psum = [psum_h[r][N - 1] for r in range(N)]
        accept  = 1 if (running and act_valid_i and ready_o) else 0
        a_ready_i = ready_o

        # ============ SEQUENTIELLE NEXT-WERTE ============
        # -- Skew --
        n_act_delay  = [act_delay[c][:]  for c in range(N)]
        n_bank_delay = [bank_delay[c][:] for c in range(N)]
        for c in range(N):
            if start_i:
                n_act_delay[c]  = [0] * N
                n_bank_delay[c] = [0] * N
            else:
                for stg in range(N - 1, 0, -1):
                    n_act_delay[c][stg]  = act_delay[c][stg - 1]
                    n_bank_delay[c][stg] = bank_delay[c][stg - 1]
                n_act_delay[c][0]  = act_row_i[c]
                n_bank_delay[c][0] = use_bank_i

        # -- Gewichts-Banks --
        n_wq = [[wq[gr][gc][:] for gc in range(N)] for gr in range(N)]
        if weight_load_i:
            for gr in range(N):
                for gc in range(N):
                    n_wq[gr][gc][load_bank_i] = weights_tile_val(a_wtile, gr, gc)

        # -- tile_pipe / space_cnt / acc --
        n_tile_pipe = [accept] + tile_pipe[0:PIPE_D]
        if accept:
            n_space_cnt = 0
        elif space_cnt != MIN_SPACING:
            n_space_cnt = space_cnt + 1
        else:
            n_space_cnt = space_cnt

        n_running = running
        n_acc = acc[:]
        n_acc_cnt = acc_cnt
        n_result_valid = 0
        if start_i:
            n_acc = [0] * N
            n_acc_cnt = 0
            n_running = 1
            n_tile_pipe = [0] * (PIPE_D + 1)
            n_space_cnt = MIN_SPACING
        elif running:
            for rr in range(N):
                if tile_pipe[GRID_LAT + rr]:
                    n_acc[rr] = n_acc[rr] + right_psum[rr]
            if tile_pipe[PIPE_D] and (acc_cnt + 1 == num_steps_i):
                n_running = 0
                n_result_valid = 1
            if tile_pipe[PIPE_D]:
                n_acc_cnt = acc_cnt + 1

        # -- Feeder-FSM --
        n_st = st; n_step = step; n_nsteps = nsteps_q
        n_a_start = 0; n_a_wload = 0; n_a_avalid = 0
        n_a_lbank = a_lbank; n_a_ubank = a_ubank
        n_a_arow = a_arow[:]; n_a_wtile = [a_wtile[r][:] for r in range(N)]
        n_astep = astep

        if st == 'IDLE':
            if op_start_i:
                n_nsteps  = S
                n_step    = 0
                n_a_start = 1
                n_st      = 'WADDR'
        elif st == 'WADDR':
            n_astep = step
            n_st = 'WLAT'
        elif st == 'WLAT':
            n_st = 'WGET'
        elif st == 'WGET':
            n_a_wtile = [[int(weights[step][gr][gc]) for gc in range(N)] for gr in range(N)]
            n_a_wload = 1
            n_a_lbank = step % num_banks
            n_a_ubank = step % num_banks
            n_st = 'FEED'
        elif st == 'FEED':
            n_astep = step
            n_a_arow = [int(acts[step][c]) for c in range(N)]
            n_a_avalid = 1
            if a_ready_i:
                if step == nsteps_q - 1:
                    n_st = 'WAIT'
                else:
                    n_step = step + 1
                    n_st = 'WADDR'
        elif st == 'WAIT':
            if result_valid:               # a_rvalid_i = result_valid_o
                result_final = (acc[:], cyc)   # a_result_i = result_o = acc_q, + Zyklen
                n_st = 'IDLE'
                done = True

        # ============ COMMIT ============
        act_delay = n_act_delay; bank_delay = n_bank_delay
        act_v = n_act_v; psum_h = n_psum_h; bank_v = n_bank_v
        wq = n_wq
        tile_pipe = n_tile_pipe; space_cnt = n_space_cnt
        running = n_running; acc = n_acc; acc_cnt = n_acc_cnt
        result_valid = n_result_valid
        st = n_st; step = n_step; nsteps_q = n_nsteps
        a_start = n_a_start; a_wload = n_a_wload; a_lbank = n_a_lbank; a_ubank = n_a_ubank
        a_avalid = n_a_avalid; a_arow = n_a_arow; a_wtile = n_a_wtile; astep = n_astep

        if done:
            break

    return result_final


def weights_tile_val(a_wtile, gr, gc):
    return a_wtile[gr][gc]


def reference(weights, acts):
    N = weights[0].shape[0]
    acc = np.zeros(N, dtype=np.int64)
    for s in range(len(weights)):
        acc += weights[s].astype(np.int64) @ acts[s].astype(np.int64)
    return acc


if __name__ == "__main__":
    rng = np.random.RandomState(1)
    N = 8

    def sweep(spacing, num_banks, trials=300):
        fails = 0
        first_fail = None
        for t in range(trials):
            S = rng.randint(2, 12)
            w = [rng.randint(-8, 8, size=(N, N)) for _ in range(S)]
            a = [rng.randint(-8, 8, size=(N,))    for _ in range(S)]
            ref = reference(w, a)
            got = run_op(w, a, N=N, spacing=spacing, num_banks=num_banks)
            acc = None if got is None else got[0]
            if acc is None or not np.array_equal(acc, ref):
                fails += 1
                if first_fail is None:
                    first_fail = (S, acc, list(ref))
        return fails, first_fail

    print("Faithful RTL-level feeder+array+PE model (accumulate mode)")
    print("Findet die MINIMAL SICHERE spacing pro Bank-Anzahl K.")
    print("Feeder-Floor = 4 Takte/Schritt (S_WADDR->WLAT->WGET->FEED), also bringt")
    print("spacing < 4 nichts; effektive spacing = max(min_safe, 4).\n")

    baseline_spacing = 2 * N - 1   # 15
    print(f"{'K banks':>8} | {'min-safe spacing':>16} | {'eff. spacing':>12} | "
          f"{'spacing-frac speedup':>20}")
    print("-" * 68)
    for K in [2, 3, 4, 5, 6, 8]:
        min_safe = None
        for sp in range(4, 2 * N):          # try 4..15
            fails, _ = sweep(sp, K, trials=400)
            if fails == 0:
                min_safe = sp
                break
        if min_safe is None:
            print(f"{K:>8} | {'none <=15':>16} | {'-':>12} | {'-':>20}")
            continue
        eff = max(min_safe, 4)
        gain = baseline_spacing / eff
        print(f"{K:>8} | {min_safe:>16} | {eff:>12} | {gain:>18.2f}x")
    print()
    print(f"Baseline (K=2, spacing={baseline_spacing}) is the current working design (1.00x).")

    # ---- Gemessene End-to-End-Zyklen pro Op (inkl. Drain), CHOSEN vs Baseline ----
    print("\nGemessene Op-Zyklen (echte accept-to-result, inkl. 2N-Drain):")
    print(f"{'layer (S steps)':>18} | {'baseline K2/s15':>16} | {'K8/s4':>8} | {'per-op speedup':>14}")
    print("-" * 66)
    layers = [("conv1  S=2", 2), ("fc2    S=8", 8), ("conv2  S=9", 9), ("fc1    S=50", 50)]
    rng2 = np.random.RandomState(7)
    for name, S in layers:
        w = [rng2.randint(-8, 8, size=(N, N)) for _ in range(S)]
        a = [rng2.randint(-8, 8, size=(N,))    for _ in range(S)]
        ref = reference(w, a)
        base = run_op(w, a, N=N, spacing=2 * N - 1, num_banks=2)
        opt  = run_op(w, a, N=N, spacing=4,         num_banks=8)
        assert np.array_equal(base[0], ref) and np.array_equal(opt[0], ref), \
            f"{name}: correctness broke!"
        sp = base[1] / opt[1]
        print(f"{name:>18} | {base[1]:>16} | {opt[1]:>8} | {sp:>12.2f}x")
