#!/usr/bin/env python3
"""
export_demo_data.py
Generate JSON data files for the web visualisation demo.

Outputs (all written to docs/data/):
  fir.json          -- FIR filter: coefficients, frequency response, test signals
  matched.json      -- Matched filter: template, coefficients, 4 test signals
  pipeline.json     -- Full pipeline: FIR -> MF -> threshold / peak events
"""

import json
import os
import numpy as np
from scipy.signal import freqz

# ── paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR  = os.path.dirname(__file__)
OUT_DIR     = os.path.join(SCRIPT_DIR, '..', 'docs', 'data')
os.makedirs(OUT_DIR, exist_ok=True)

# ── shared constants ──────────────────────────────────────────────────────────
SCALE_SHIFT  = 8
SCALE        = 1 << SCALE_SHIFT   # 256

# ── FIR coefficients (from design_filter.py) ─────────────────────────────────
FIR_COEFFS = np.array([-1, -6, 25, 110, 110, 25, -6, -1], dtype=np.int64)

# ── Matched filter template and coefficients ──────────────────────────────────
MF_TEMPLATE = np.array([0, 50, 150, 250, 100, 0, 0, 0], dtype=np.int64)
MF_COEFFS   = MF_TEMPLATE[::-1].copy()   # time-reversed
MF_PEAK     = int(np.sum(MF_TEMPLATE.astype(np.int64) ** 2)) >> SCALE_SHIFT  # 380


# ─────────────────────────────────────────────────────────────────────────────
def fir_model(coeffs, x):
    """Integer FIR matching VHDL arithmetic exactly."""
    taps = len(coeffs)
    y        = np.zeros(len(x), dtype=np.int64)
    tap_reg  = np.zeros(taps, dtype=np.int64)
    for n, xn in enumerate(x):
        tap_vec     = np.empty(taps, dtype=np.int64)
        tap_vec[0]  = xn
        tap_vec[1:] = tap_reg[:taps - 1]
        tap_reg     = tap_vec.copy()
        y[n]        = int(np.dot(coeffs, tap_vec)) >> SCALE_SHIFT
    return y


# ─────────────────────────────────────────────────────────────────────────────
# 1. FIR DATA
# ─────────────────────────────────────────────────────────────────────────────
def build_fir_data():
    taps = len(FIR_COEFFS)
    N    = 48

    # Frequency response (float coefficients = int / SCALE)
    h_float = FIR_COEFFS / SCALE
    w, H = freqz(h_float, worN=512)
    freq_norm  = (w / np.pi * 0.5).tolist()   # 0..0.5 (normalised, 0.5 = Nyquist)
    freq_db    = (20 * np.log10(np.maximum(np.abs(H), 1e-10))).tolist()
    freq_phase = np.angle(H).tolist()

    # Impulse response test: input x[0]=256, rest=0
    sig_impulse = np.zeros(N, dtype=np.int64)
    sig_impulse[4] = SCALE
    out_impulse = fir_model(FIR_COEFFS, sig_impulse)

    # DC test: constant 1000
    sig_dc = np.full(N, 1000, dtype=np.int64)
    out_dc = fir_model(FIR_COEFFS, sig_dc)

    # Nyquist test: alternating +-1000
    sig_nyq = np.array([1000 * (-1)**k for k in range(N)], dtype=np.int64)
    out_nyq = fir_model(FIR_COEFFS, sig_nyq)

    return {
        "coeffs":      FIR_COEFFS.tolist(),
        "scale_shift": SCALE_SHIFT,
        "scale":       SCALE,
        "taps":        taps,
        "cutoff_norm": 0.25,
        "freq_response": {
            "freq":  freq_norm,
            "db":    freq_db,
            "phase": freq_phase,
        },
        "tests": {
            "impulse": {
                "label": "Impulse (x[4]=256)",
                "input":  sig_impulse.tolist(),
                "output": out_impulse.tolist(),
            },
            "dc": {
                "label": "DC (constant 1000)",
                "input":  sig_dc.tolist(),
                "output": out_dc.tolist(),
            },
            "nyquist": {
                "label": "Nyquist (alternating +-1000)",
                "input":  sig_nyq.tolist(),
                "output": out_nyq.tolist(),
            },
        },
    }


# ─────────────────────────────────────────────────────────────────────────────
# 2. MATCHED FILTER DATA
# ─────────────────────────────────────────────────────────────────────────────
def build_matched_data():
    N = 40

    def make_signal(values, start=4):
        s = np.zeros(N, dtype=np.int64)
        s[start:start + len(values)] = values
        return s

    taps = len(MF_COEFFS)

    signals = {
        "template": {
            "label": "Template (exact match)",
            "color": "#4C9BE8",
            "input": make_signal(MF_TEMPLATE),
        },
        "flat": {
            "label": "Flat pulse (wrong shape)",
            "color": "#E8624C",
            "input": make_signal(np.full(taps, 150, dtype=np.int64)),
        },
        "noise": {
            "label": "Alternating noise",
            "color": "#4CE874",
            "input": make_signal(np.array([100 * (-1)**k for k in range(taps)], dtype=np.int64)),
        },
        "reversed": {
            "label": "Reversed template",
            "color": "#E8C44C",
            "input": make_signal(MF_TEMPLATE[::-1]),
        },
    }

    results = {}
    for key, info in signals.items():
        out  = fir_model(MF_COEFFS, info["input"])
        peak = int(np.max(np.abs(out)))
        results[key] = {
            "label":  info["label"],
            "color":  info["color"],
            "input":  info["input"].tolist(),
            "output": out.tolist(),
            "peak":   peak,
            "pct":    round(peak / MF_PEAK * 100, 1),
        }

    return {
        "template":     MF_TEMPLATE.tolist(),
        "coeffs":       MF_COEFFS.tolist(),
        "scale_shift":  SCALE_SHIFT,
        "peak_theory":  MF_PEAK,
        "threshold":    MF_PEAK // 2,
        "signals":      results,
        "n_samples":    N,
    }


# ─────────────────────────────────────────────────────────────────────────────
# 3. FULL PIPELINE DATA
# ─────────────────────────────────────────────────────────────────────────────
def build_pipeline_data():
    """
    Simulate the full pipeline:
      raw_in -> [FIR LP] -> fir_out -> [Threshold det] -> detected
                                    -> [Matched Filter] -> mf_out -> [Peak det]
    Uses the same scenario as the testbench: scaled template x4.
    """
    THRESHOLD_DET  = 500
    THRESHOLD_PEAK = MF_PEAK // 2   # 190
    N = 80

    # ── Input: scaled template (x4) embedded in noise context ─────────────────
    raw = np.zeros(N, dtype=np.int64)
    scaled_template = MF_TEMPLATE * 4   # [0, 200, 600, 1000, 400, 0, 0, 0]
    raw[8:8 + len(scaled_template)] = scaled_template

    # ── Stage 1: FIR low-pass filter ──────────────────────────────────────────
    fir_out = fir_model(FIR_COEFFS, raw)

    # ── Stage 2a: Threshold detector ──────────────────────────────────────────
    detected = (np.abs(fir_out) > THRESHOLD_DET).astype(int).tolist()

    # ── Stage 2b: Matched filter ───────────────────────────────────────────────
    mf_out = fir_model(MF_COEFFS, fir_out)

    # ── Stage 3: Peak detector (Python model) ─────────────────────────────────
    peak_events = []
    state = 'IDLE'
    max_val, max_abs, max_pos, pos_cnt = 0, 0, 0, 0
    for i, v in enumerate(mf_out):
        abs_v = abs(v)
        if state == 'IDLE':
            if abs_v > THRESHOLD_PEAK:
                max_val, max_abs, max_pos = v, abs_v, 0
                pos_cnt = 1
                state = 'TRACKING'
        elif state == 'TRACKING':
            if abs_v > THRESHOLD_PEAK:
                if abs_v > max_abs:
                    max_val, max_abs, max_pos = v, abs_v, pos_cnt
                pos_cnt += 1
            else:
                peak_events.append({
                    "cycle":    i,
                    "peak_val": int(max_val),
                    "peak_pos": int(max_pos),
                })
                state = 'IDLE'

    return {
        "n_samples":       N,
        "threshold_det":   THRESHOLD_DET,
        "threshold_peak":  THRESHOLD_PEAK,
        "raw_in":          raw.tolist(),
        "fir_out":         fir_out.tolist(),
        "detected":        detected,
        "mf_out":          mf_out.tolist(),
        "peak_events":     peak_events,
        "scaled_template": scaled_template.tolist(),
        "template_start":  8,
    }


# ─────────────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────────────
def write_json(name, data):
    path = os.path.join(OUT_DIR, name)
    with open(path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    size = os.path.getsize(path)
    print(f"  {name:<25}  {size:>7} bytes")


if __name__ == '__main__':
    print("Exporting demo data...")
    write_json('fir.json',     build_fir_data())
    write_json('matched.json', build_matched_data())
    write_json('pipeline.json', build_pipeline_data())
    print("Done -> docs/data/")
