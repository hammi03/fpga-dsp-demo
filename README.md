# FPGA DSP Demo — Fixed-Point FIR Filter in VHDL

A portfolio project for fixed-point digital signal processing on FPGAs.
**Phase 1 (MVP):** 8-tap FIR low-pass filter with full simulation and self-checking testbench.

![Frequency Response](results/filter_frequency_response.png)

---

## Project Structure

```
fpga-dsp-demo/
├── rtl/
│   └── fir_filter.vhd        # Synthesisable FIR filter
├── tb/
│   └── tb_fir_filter.vhd     # Self-checking VHDL testbench
├── scripts/
│   └── design_filter.py      # Python: coefficient design + frequency plot
├── results/
│   └── filter_frequency_response.png
└── README.md
```

---

## Filter Specification

| Parameter         | Value                              |
|-------------------|------------------------------------|
| Architecture      | Direct-form FIR, fully registered  |
| Taps              | 8                                  |
| Data width        | 16-bit signed (Q1.15 range)        |
| Coefficient scale | ×256 (2⁸), sum = 256 → DC gain = 1|
| Cutoff frequency  | ≈ 0.25 · fs                        |
| Window            | Hamming                            |
| Latency           | 1 clock cycle                      |
| Interface         | `valid_in` / `valid_out` handshake |

### Coefficients

```
h = [-2, 10, 44, 76, 76, 44, 10, -2]   (scaled × 256, symmetric)
```

Sum = 256 → unity DC gain.
At Nyquist (fs/2): `Σ h[k]·(−1)^k = 0` → complete rejection.

---

## Architecture

```
          data_in (16-bit signed)
               │
    ┌──────────▼──────────────────────────────────────────┐
    │  tap_reg: shift register (8 × 16 bit)               │ clk
    │  taps[0] = data_in (variable, same cycle)           │──►
    │  taps[1] = tap_reg[0], ..., taps[7] = tap_reg[6]   │
    └──────────┬──────────────────────────────────────────┘
               │  8 taps (16-bit each)
    ┌──────────▼──────────────────────────────────────────┐
    │  MAC:  acc = Σ COEFFS[i] × taps[i]   (40-bit)      │
    └──────────┬──────────────────────────────────────────┘
               │  acc[23:8]  (arithmetic right-shift by 8)
          data_out (16-bit signed)
```

**Key decisions:**

- **Variable for tap vector** — using a VHDL variable to build the current tap state means `data_in` is included in the MAC computation in the *same* clock cycle (no extra latency compared to a two-process design).
- **40-bit accumulator** — worst-case: `76 × 32767 × 8 ≈ 2^33`; 40 bits provides full headroom.
- **Arithmetic right-shift** — `acc[SCALE_SHIFT+15 : SCALE_SHIFT]` is equivalent to dividing by 256 (truncation towards −∞), consistent with two's-complement fixed-point.
- **Standard VHDL** — no vendor-specific libraries; synthesises with GHDL, Xilinx Vivado, Intel Quartus.

---

## Simulation with GHDL

```bash
# Analyse both files
ghdl -a --std=08 rtl/fir_filter.vhd tb/tb_fir_filter.vhd

# Elaborate the testbench
ghdl -e --std=08 tb_fir_filter

# Run and dump waveform
ghdl -r --std=08 tb_fir_filter --vcd=results/sim.vcd --stop-time=3us
```

Open `results/sim.vcd` in **GTKWave** or **Surfer** to inspect waveforms.

### Expected simulation output

```
PASS  Impulse[0]  got=-2
PASS  Impulse[1]  got=10
PASS  Impulse[2]  got=44
PASS  Impulse[3]  got=76
PASS  Impulse[4]  got=76
PASS  Impulse[5]  got=44
PASS  Impulse[6]  got=10
PASS  Impulse[7]  got=-2
PASS  DC steady-state = 1000
PASS  Nyquist rejection (alternating ±1000 → 0)
=== Simulation complete ===
```

---

## Filter Design (Python)

```bash
pip install numpy scipy matplotlib
python scripts/design_filter.py
```

Prints quantized coefficients and saves a frequency-response plot to `results/`.

---

## Planned Extensions (Phase 2+)

- [ ] Generic tap count via VHDL generic
- [ ] Proper Q-format fixed-point scaling
- [ ] Python reference model + simulation-vs-software comparison
- [ ] Threshold detector
- [ ] Peak detection
- [ ] Matched filter / correlator
- [ ] Full signal-processing pipeline
