#!/usr/bin/env python3
"""
plot_results.py
Compare Python FIR reference model against GHDL simulation output.

Reads results/sim.vcd, extracts data_in / data_out at every rising clock
edge, runs the same inputs through a Python integer model, and overlays
both outputs on a plot.  The error (VHDL - Python) should be identically 0.

Usage (from project root):
    python3 scripts/plot_results.py
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import re, os, sys

# ── Filter definition  (must match rtl/fir_filter.vhd) ───────────────────────
COEFFS      = np.array([-1, -6, 25, 110, 110, 25, -6, -1], dtype=np.int64)
TAPS        = len(COEFFS)
SCALE_SHIFT = 8


# ── Python reference model ────────────────────────────────────────────────────
def fir_model(x: np.ndarray) -> np.ndarray:
    """
    Integer FIR model that mirrors fir_filter.vhd exactly:
      - newest sample at tap index 0
      - accumulate 40-bit, arithmetic right-shift by SCALE_SHIFT
      - output is valid every cycle (no valid handshake needed here)
    """
    y       = np.zeros(len(x), dtype=np.int64)
    tap_reg = np.zeros(TAPS,   dtype=np.int64)
    for n, xn in enumerate(x):
        tap_vec     = np.empty(TAPS, dtype=np.int64)
        tap_vec[0]  = xn
        tap_vec[1:] = tap_reg[:TAPS - 1]
        tap_reg     = tap_vec.copy()
        acc         = int(np.dot(COEFFS, tap_vec))
        y[n]        = acc >> SCALE_SHIFT   # arithmetic right-shift (truncate)
    return y


# ── Minimal VCD parser ────────────────────────────────────────────────────────
def parse_vcd(path: str) -> dict:
    """
    Returns {signal_name: [(time, int_value), ...]} for every signal found.
    Handles multi-bit (bus) and single-bit signals.
    Times are in the VCD's native unit (here: femtoseconds).
    """
    id_name: dict[str, str] = {}
    id_bits: dict[str, int] = {}
    events:  dict[str, list] = {}

    with open(path) as f:
        lines = f.readlines()

    t = 0
    for raw in lines:
        line = raw.strip()
        if not line:
            continue

        # Variable declaration
        if '$var' in line:
            m = re.search(r'\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)', line)
            if m:
                w, vid, raw_name = int(m.group(1)), m.group(2), m.group(3)
                name = raw_name.split('[')[0]
                id_name[vid] = name
                id_bits[vid] = w
                events.setdefault(name, [])
            continue

        # Timestamp
        if line.startswith('#'):
            t = int(line[1:])
            continue

        # Multi-bit value  "bBINSTR id"
        if line[0] in 'bB':
            parts = line.split()
            if len(parts) == 2:
                bstr, vid = parts[0][1:], parts[1]
                if vid in id_name:
                    w    = id_bits[vid]
                    bstr = bstr.zfill(w)
                    if any(c not in '01' for c in bstr):
                        continue          # skip U/X/Z (uninitialized)
                    val  = int(bstr, 2)
                    if w > 1 and bstr[0] == '1':
                        val -= (1 << w)          # two's complement
                    events[id_name[vid]].append((t, val))
            continue

        # Single-bit value  "{0|1|x|z}id"
        if line[0] in '01xzXZ' and len(line) >= 2:
            vid = line[1:]
            if vid in id_name:
                events[id_name[vid]].append((t, 1 if line[0] == '1' else 0))

    return events


def build_step(ev_list: list, t_query: int) -> int:
    """Return signal value at time t_query (step function, last value <= t)."""
    val = 0
    for t, v in ev_list:
        if t <= t_query:
            val = v
        else:
            break
    return val


def extract_at_rising_edges(events: dict) -> dict:
    """
    Sample all signals 1 fs after each rising clock edge.
    Returns {name: np.ndarray} for clk, data_in, valid_in, data_out, valid_out.
    """
    clk_ev = events.get('clk', [])
    sigs   = {n: events.get(n, []) for n in
              ('data_in', 'valid_in', 'data_out', 'valid_out')}

    samples  = {n: [] for n in sigs}
    times_ns = []
    prev_clk = 0

    for t, cv in clk_ev:
        if prev_clk == 0 and cv == 1:           # rising edge
            # data_in / valid_in: sample 1 fs BEFORE the edge.
            # The testbench sometimes updates data_in in a delta-cycle
            # AFTER the edge (after resuming from "wait until rising_edge").
            # Sampling pre-edge captures exactly what the DUT latched.
            #
            # data_out / valid_out: sample 1 fs AFTER the edge so the
            # registered output has propagated through delta cycles.
            dt_in  = max(0, t - 1)
            dt_out = t + 1
            times_ns.append(t / 1e6)            # fs → ns
            for name, ev in sigs.items():
                dt = dt_in if name in ('data_in', 'valid_in') else dt_out
                samples[name].append(build_step(ev, dt))
        prev_clk = cv

    return {n: np.array(v, dtype=np.int32) for n, v in samples.items()}, \
           np.array(times_ns)


# ── Plotting ──────────────────────────────────────────────────────────────────
def annotate_phases(ax, times_ns, din, vin):
    """Draw vertical lines and labels between the three test phases."""
    valid_edges = np.where(np.diff(vin.astype(int)) != 0)[0]
    # Find gaps (valid_in goes low between tests)
    gaps = [i for i in valid_edges if vin[i] == 1]   # falling: valid was 1, now 0
    colors = ['#e8f4f8', '#fef9e7', '#f9ebea']
    labels = ['Test 1\nImpulse', 'Test 2\nDC', 'Test 3\nNyquist']
    boundaries = [0] + [times_ns[g] for g in gaps[:2]] + [times_ns[-1]]
    for i, (t0, t1) in enumerate(zip(boundaries, boundaries[1:])):
        ax.axvspan(t0, t1, alpha=0.4, color=colors[i % 3], label=labels[i])


def main():
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    vcd_path    = os.path.join(project_dir, 'results', 'sim.vcd')
    out_path    = os.path.join(project_dir, 'results', 'comparison.png')

    if not os.path.exists(vcd_path):
        sys.exit(f"ERROR: {vcd_path} not found.  Run 'make sim' first.")

    # ── Parse VCD ─────────────────────────────────────────────────────────────
    print("Parsing VCD …")
    events = parse_vcd(vcd_path)
    samples, times_ns = extract_at_rising_edges(events)

    din   = samples['data_in']
    dout  = samples['data_out']
    vin   = samples['valid_in']
    vout  = samples['valid_out']

    # ── Python reference model ─────────────────────────────────────────────────
    # Run on ALL data_in samples (incl. reset phase) so cycle indices align.
    # The VHDL uses a variable (tap_vec) so the output is computed from the
    # current data_in in the SAME clock cycle → no shift needed.
    py_out = fir_model(din)

    # Only compare where valid_out = 1
    mask  = vout == 1
    error = dout[mask].astype(np.int64) - py_out[mask].astype(np.int64)
    max_err = int(np.max(np.abs(error))) if len(error) > 0 else 0

    print(f"Valid output samples : {mask.sum()}")
    print(f"Max |error|          : {max_err}  {'OK PERFECT MATCH' if max_err == 0 else 'MISMATCH'}")
    print()
    print(f"{'Cycle':>6}  {'time_ns':>8}  {'din':>6}  {'dout_vhdl':>10}  {'py_out':>8}  {'err':>6}")
    for idx in np.where(mask)[0]:
        err = int(dout[idx]) - int(py_out[idx])
        print(f"{idx:>6}  {times_ns[idx]:>8.1f}  {din[idx]:>6}  {dout[idx]:>10}  {py_out[idx]:>8}  {err:>6}")

    # ── Plot ──────────────────────────────────────────────────────────────────
    cycles = np.arange(len(times_ns))

    fig, axes = plt.subplots(3, 1, figsize=(13, 9),
                             gridspec_kw={'height_ratios': [2, 2, 1]})
    fig.suptitle('FIR Filter: GHDL Simulation vs. Python Reference Model\n'
                 '8-Tap Low-Pass  |  fc = 0.25·fs  |  Hamming window',
                 fontsize=13)

    # ── Panel 1: Input ────────────────────────────────────────────────────────
    ax = axes[0]
    ax.step(cycles, din, where='post', color='steelblue', lw=1.2, label='data_in')
    ax.step(cycles, vin * 300, where='post',
            color='gray', lw=0.8, ls='--', alpha=0.5, label='valid_in × 300')
    ax.set_ylabel('Sample value')
    ax.set_title('Input')
    ax.legend(loc='upper right', fontsize=8)
    ax.grid(True, alpha=0.3)
    annotate_phases(ax, times_ns, din, vin)

    # ── Panel 2: Output comparison ────────────────────────────────────────────
    ax = axes[1]
    ax.step(cycles, dout,       where='post', color='tomato',    lw=2,
            label='VHDL data_out (simulation)')
    ax.step(cycles, py_out, where='post', color='royalblue', lw=1.2,
            ls='--', label='Python reference model')
    ax.step(cycles, vout * 300, where='post',
            color='gray', lw=0.8, ls=':', alpha=0.4, label='valid_out × 300')
    ax.set_ylabel('Sample value')
    ax.set_title('Output')
    ax.legend(loc='upper right', fontsize=8)
    ax.grid(True, alpha=0.3)
    annotate_phases(ax, times_ns, din, vin)

    # ── Panel 3: Error ────────────────────────────────────────────────────────
    ax = axes[2]
    full_error = dout.astype(np.int64) - py_out.astype(np.int64)
    full_error[~mask] = 0        # zero out invalid samples
    ax.step(cycles, full_error, where='post', color='darkred', lw=1.2)
    ax.axhline(0, color='black', lw=0.8, ls='--')
    ax.set_ylabel('Error')
    ax.set_xlabel('Clock cycle')
    ax.set_title(f'Error (VHDL - Python)   max|err| = {max_err}')
    ax.grid(True, alpha=0.3)
    ax.set_ylim(-2, 2)
    annotate_phases(ax, times_ns, din, vin)

    for ax in axes:
        ax.set_xlim(cycles[0], cycles[-1])

    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    print(f"Plot saved → {out_path}")


if __name__ == '__main__':
    main()
