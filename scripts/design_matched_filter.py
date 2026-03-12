#!/usr/bin/env python3
"""
design_matched_filter.py
Design a matched filter for a given template signal.

A matched filter is a FIR filter whose coefficients are the TIME-REVERSED
template.  When the input signal matches the template exactly, the filter
output is maximized (equals the signal energy = sum of squares).

For any other input of equal or lower energy, the output is lower.
This makes it the optimal linear detector in the presence of white noise.

Usage:
    python scripts/design_matched_filter.py
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os

# ── Template definition ────────────────────────────────────────────────────────
# This is the signal shape we want to detect.
# Asymmetric so the time-reversal of the MF coefficients is clearly visible.
TEMPLATE    = np.array([0, 50, 150, 250, 100, 0, 0, 0], dtype=np.int64)
SCALE_SHIFT = 8          # output divided by 2^8 = 256
TAPS        = len(TEMPLATE)

# ── Matched filter coefficients = time-reversed template ──────────────────────
MF_COEFFS = TEMPLATE[::-1].copy()   # [0, 0, 0, 100, 250, 150, 50, 0]


def fir_model(coeffs, x):
    """Integer FIR (same arithmetic as fir_filter.vhd)."""
    y       = np.zeros(len(x), dtype=np.int64)
    tap_reg = np.zeros(TAPS, dtype=np.int64)
    for n, xn in enumerate(x):
        tap_vec     = np.empty(TAPS, dtype=np.int64)
        tap_vec[0]  = xn
        tap_vec[1:] = tap_reg[:TAPS - 1]
        tap_reg     = tap_vec.copy()
        y[n]        = int(np.dot(coeffs, tap_vec)) >> SCALE_SHIFT
    return y


def main():
    print("Matched Filter Design")
    print("=" * 50)
    print(f"Template:         {list(TEMPLATE)}")
    print(f"MF coefficients:  {list(MF_COEFFS)}  (time-reversed)")
    print(f"SCALE_SHIFT:      {SCALE_SHIFT}  (divide by {1 << SCALE_SHIFT})")
    print()

    # Theoretical peak output (signal energy)
    energy = int(np.sum(TEMPLATE.astype(np.int64) ** 2))
    peak_theory = energy >> SCALE_SHIFT
    print(f"Signal energy:    sum(T^2) = {energy}")
    print(f"Expected peak:    {energy} >> {SCALE_SHIFT} = {peak_theory}")
    print()

    # ── Build test signals ─────────────────────────────────────────────────────
    N = 32   # total simulation length

    # Signal A: exact template (padded with zeros)
    sig_template = np.zeros(N, dtype=np.int64)
    sig_template[4:4 + TAPS] = TEMPLATE         # template starts at sample 4

    # Signal B: flat rectangular pulse (same duration, height ~150)
    sig_rect = np.zeros(N, dtype=np.int64)
    sig_rect[4:4 + TAPS] = 150                  # same window, constant amplitude

    # Signal C: high-frequency alternating noise
    sig_noise = np.zeros(N, dtype=np.int64)
    sig_noise[4:4 + TAPS] = [100 * (-1)**k for k in range(TAPS)]

    # Signal D: time-reversed template (wrong direction)
    sig_reversed = np.zeros(N, dtype=np.int64)
    sig_reversed[4:4 + TAPS] = TEMPLATE[::-1]

    signals = {
        'Template (correct match)':   sig_template,
        'Flat pulse (wrong shape)':   sig_rect,
        'Alternating noise':          sig_noise,
        'Reversed template':          sig_reversed,
    }

    # ── Run matched filter ─────────────────────────────────────────────────────
    print(f"{'Signal':<30}  {'Peak MF output':>14}  {'vs template':>11}")
    print("-" * 60)
    results = {}
    for name, sig in signals.items():
        out = fir_model(MF_COEFFS, sig)
        peak = int(np.max(np.abs(out)))
        ratio = peak / peak_theory * 100
        print(f"{name:<30}  {peak:>14}  {ratio:>10.1f}%")
        results[name] = (sig, out)
    print()

    # ── VHDL output ───────────────────────────────────────────────────────────
    print("VHDL constant definition:")
    print(f"constant SCALE_SHIFT : integer := {SCALE_SHIFT};")
    print("constant COEFFS : coeff_array_t := (")
    for i, c in enumerate(MF_COEFFS):
        comma = "," if i < TAPS - 1 else " "
        print(f"    to_signed({c:5d}, DATA_BITS){comma}   -- h[{i}]  (template[{TAPS-1-i}])")
    print(");")
    print()
    print(f"-- When input matches template exactly: output peak = {peak_theory}")
    print(f"-- Suggested threshold for peak_detector: {peak_theory // 2}")

    # ── Plot ──────────────────────────────────────────────────────────────────
    cycles = np.arange(N)
    fig, axes = plt.subplots(len(signals), 2, figsize=(13, 10))
    fig.suptitle("Matched Filter: Template Detection vs. Other Signals\n"
                 f"Template = {list(TEMPLATE)}   MF coeffs = {list(MF_COEFFS)}",
                 fontsize=11)

    colors = ['steelblue', 'tomato', 'mediumseagreen', 'darkorange']

    for row, (name, (sig, out)) in enumerate(results.items()):
        peak = int(np.max(np.abs(out)))

        # Input
        ax = axes[row, 0]
        ax.step(cycles, sig, where='post', color=colors[row], lw=1.5)
        ax.axhline(0, color='black', lw=0.5)
        ax.set_ylabel('Amplitude')
        ax.set_title(f'Input: {name}')
        ax.grid(True, alpha=0.3)
        ax.set_xlim(0, N - 1)

        # MF output
        ax = axes[row, 1]
        ax.step(cycles, out, where='post', color=colors[row], lw=1.5)
        ax.axhline(peak_theory // 2, color='gray', ls='--', lw=1,
                   label=f'threshold = {peak_theory // 2}')
        ax.axhline(0, color='black', lw=0.5)
        ax.set_ylabel('MF output')
        ax.set_title(f'MF output — peak = {peak}  ({peak/peak_theory*100:.0f}% of template)')
        ax.legend(fontsize=8, loc='upper right')
        ax.grid(True, alpha=0.3)
        ax.set_xlim(0, N - 1)
        ax.set_ylim(-peak_theory - 20, peak_theory + 20)

    axes[-1, 0].set_xlabel('Clock cycle')
    axes[-1, 1].set_xlabel('Clock cycle')

    plt.tight_layout()
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'results')
    out_path = os.path.join(out_dir, 'matched_filter_response.png')
    plt.savefig(out_path, dpi=150)
    print(f"Plot saved -> {out_path}")


if __name__ == '__main__':
    main()
