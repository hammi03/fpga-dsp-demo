/**
 * dsp.js — integer DSP models matching the VHDL implementation exactly.
 * All arithmetic uses integer math with arithmetic right-shift (>> operator).
 */

'use strict';

const DSP = (() => {

  // ── FIR low-pass filter coefficients (from design_filter.py) ─────────────
  const FIR_COEFFS   = [-1, -6, 25, 110, 110, 25, -6, -1];
  const FIR_SCALE    = 8;   // divide by 256

  // ── Matched filter coefficients = time-reversed template ─────────────────
  const MF_TEMPLATE  = [0, 50, 150, 250, 100, 0, 0, 0];
  const MF_COEFFS    = [...MF_TEMPLATE].reverse();  // [0,0,0,100,250,150,50,0]
  const MF_SCALE     = 8;
  const MF_PEAK      = MF_TEMPLATE.reduce((s, v) => s + v * v, 0) >> MF_SCALE; // 380

  // ── Thresholds ─────────────────────────────────────────────────────────────
  const THRESHOLD_DET  = 500;
  const THRESHOLD_PEAK = Math.floor(MF_PEAK / 2);  // 190

  /**
   * Integer FIR filter — identical arithmetic to fir_filter.vhd / matched_filter.vhd
   * @param {number[]} coeffs
   * @param {number[]} input
   * @param {number}   scaleShift
   * @returns {number[]}
   */
  function fir(coeffs, input, scaleShift) {
    const taps   = coeffs.length;
    const output = new Array(input.length).fill(0);
    const reg    = new Array(taps).fill(0);   // shift register

    for (let n = 0; n < input.length; n++) {
      // Build tap vector: newest sample first
      const tap = [input[n], ...reg.slice(0, taps - 1)];
      // Update shift register
      for (let i = 0; i < taps; i++) reg[i] = tap[i];
      // MAC
      let acc = 0;
      for (let i = 0; i < taps; i++) acc += coeffs[i] * tap[i];
      // Arithmetic right-shift (truncation towards -inf for negatives)
      output[n] = acc >> scaleShift;
    }
    return output;
  }

  /**
   * Threshold detector — matches threshold_detector.vhd
   * Returns array of 0/1: 1 when |sample| > threshold
   */
  function thresholdDetector(signal, threshold) {
    return signal.map(v => Math.abs(v) > threshold ? 1 : 0);
  }

  /**
   * Peak detector — matches peak_detector.vhd state machine (IDLE / TRACKING)
   * @returns {{ cycle: number, peak_val: number, peak_pos: number }[]}
   */
  function peakDetector(signal, threshold) {
    const events = [];
    let state = 'IDLE';
    let maxVal = 0, maxAbs = 0, maxPos = 0, posCnt = 0;

    for (let i = 0; i < signal.length; i++) {
      const v    = signal[i];
      const absV = Math.abs(v);

      if (state === 'IDLE') {
        if (absV > threshold) {
          maxVal = v; maxAbs = absV; maxPos = 0;
          posCnt = 1;
          state = 'TRACKING';
        }
      } else {  // TRACKING
        if (absV > threshold) {
          if (absV > maxAbs) { maxVal = v; maxAbs = absV; maxPos = posCnt; }
          posCnt++;
        } else {
          events.push({ cycle: i, peak_val: maxVal, peak_pos: maxPos });
          state = 'IDLE';
        }
      }
    }
    return events;
  }

  /**
   * Run the full pipeline on a raw input array.
   * Returns all intermediate signals and detection events.
   */
  function runPipeline(rawInput) {
    const firOut      = fir(FIR_COEFFS, rawInput, FIR_SCALE);
    const detected    = thresholdDetector(firOut, THRESHOLD_DET);
    const mfOut       = fir(MF_COEFFS, firOut, MF_SCALE);
    const peakEvents  = peakDetector(mfOut, THRESHOLD_PEAK);
    return { rawInput, firOut, detected, mfOut, peakEvents };
  }

  return {
    FIR_COEFFS, FIR_SCALE,
    MF_TEMPLATE, MF_COEFFS, MF_SCALE, MF_PEAK,
    THRESHOLD_DET, THRESHOLD_PEAK,
    fir, thresholdDetector, peakDetector, runPipeline,
  };
})();
