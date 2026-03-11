#!/usr/bin/env python3
"""
design_filter.py
Design an N-tap FIR low-pass filter, quantize coefficients,
and generate ready-to-paste VHDL output.

Requirements: numpy, scipy, matplotlib
  pip install numpy scipy matplotlib
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')   # non-interactive backend (no display required)
import matplotlib.pyplot as plt
from scipy.signal import firwin, freqz

# ── Parameters ────────────────────────────────────────────────────────────────
N_TAPS      = 8       # number of taps
FC          = 0.25    # normalized cutoff (0 = DC, 0.5 = Nyquist)
WINDOW      = 'hamming'
SCALE_SHIFT = 8       # coefficient scale = 2^SCALE_SHIFT
SCALE       = 1 << SCALE_SHIFT   # = 256
COEFF_BITS  = 16
# ──────────────────────────────────────────────────────────────────────────────

def design_and_quantize(n_taps, fc, window, scale):
    """Return floating-point and integer-quantized coefficients."""
    h_float = firwin(n_taps, fc, window=window, fs=1.0)
    h_norm  = h_float / h_float.sum()          # exact unity DC gain
    h_int   = np.round(h_norm * scale).astype(int)

    # Correct rounding error so sum is exactly 'scale'
    diff = scale - h_int.sum()
    h_int[np.argmax(np.abs(h_int))] += diff

    return h_norm, h_int


def print_vhdl(h_int, coeff_bits, scale_shift):
    print()
    print("-- Paste into fir_filter.vhd:")
    print(f"constant SCALE_SHIFT : integer := {scale_shift};")
    print(f"constant COEFFS : coeff_array_t := (")
    for i, c in enumerate(h_int):
        comma = "," if i < len(h_int) - 1 else " "
        print(f"    to_signed({c:5d}, COEFF_BITS){comma}   -- h[{i}]")
    print(");")
    print(f"-- Sum = {h_int.sum()}  (target: {1 << scale_shift})")


def plot(h_int, scale, fc, out_path):
    w, H = freqz(h_int / scale, worN=8192, fs=1.0)
    H_dB = 20 * np.log10(np.abs(H) + 1e-12)

    fig, axes = plt.subplots(1, 2, figsize=(11, 4))
    fig.suptitle(f"{len(h_int)}-Tap FIR Low-Pass Filter  |  fc={fc}·fs  |  "
                 f"Hamming window  |  {scale}-scaled integer coefficients")

    # Impulse response
    axes[0].stem(range(len(h_int)), h_int, basefmt='C0-')
    axes[0].set_title("Quantized Impulse Response")
    axes[0].set_xlabel("Tap index")
    axes[0].set_ylabel(f"Coefficient (×{scale})")
    axes[0].grid(True)

    # Frequency response
    axes[1].plot(w, H_dB)
    axes[1].axvline(fc, color='r', linestyle='--', label=f'fc = {fc}·fs')
    axes[1].axhline(-3,  color='gray', linestyle=':', label='−3 dB')
    axes[1].set_xlim([0, 0.5])
    axes[1].set_ylim([-80, 5])
    axes[1].set_title("Frequency Response")
    axes[1].set_xlabel("Normalized frequency  (0 = DC,  0.5 = Nyquist)")
    axes[1].set_ylabel("Magnitude (dB)")
    axes[1].legend()
    axes[1].grid(True)

    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    print(f"\nPlot saved → {out_path}")
    plt.show()


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    h_float, h_int = design_and_quantize(N_TAPS, FC, WINDOW, SCALE)

    print(f"FIR design: N={N_TAPS}, fc={FC}·fs, window={WINDOW}, scale=2^{SCALE_SHIFT}={SCALE}")
    print()
    print(f"{'Tap':>4}  {'Float':>10}  {'Integer':>8}")
    print("-" * 28)
    for i, (f, c) in enumerate(zip(h_float, h_int)):
        print(f"{i:>4}  {f:>10.6f}  {c:>8d}")
    print(f"{'Sum':>4}  {h_float.sum():>10.6f}  {h_int.sum():>8d}  (target: {SCALE})")

    print_vhdl(h_int, COEFF_BITS, SCALE_SHIFT)

    import os
    out_dir = os.path.join(os.path.dirname(__file__), "..", "results")
    os.makedirs(out_dir, exist_ok=True)
    plot(h_int, SCALE, FC, os.path.join(out_dir, "filter_frequency_response.png"))
