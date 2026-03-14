/**
 * app.js — FPGA DSP Demo visualisation
 * Tabs: FIR Filter | Matched Filter | Pipeline (interactive + animated)
 */

'use strict';

// ── Plotly theme ──────────────────────────────────────────────────────────────
const C = {
  bg:     '#1a1d27',
  grid:   '#2a2d3a',
  text:   '#8892a4',
  white:  '#e2e8f0',
  blue:   '#4C9BE8',
  purple: '#7C5CE8',
  green:  '#4CE874',
  yellow: '#E8C44C',
  red:    '#E8624C',
};

const BASE_LAYOUT = {
  paper_bgcolor: C.bg,
  plot_bgcolor:  C.bg,
  font:   { color: C.text, family: 'system-ui,sans-serif', size: 11 },
  margin: { l: 52, r: 16, t: 32, b: 40 },
  xaxis:  { gridcolor: C.grid, zerolinecolor: C.grid, tickfont: { size: 10 } },
  yaxis:  { gridcolor: C.grid, zerolinecolor: C.grid, tickfont: { size: 10 } },
  showlegend: false,
  hovermode: 'x unified',
};

const CFG = { responsive: true, displayModeBar: false };

function mkLayout(extra = {}) {
  return Object.assign({}, BASE_LAYOUT,
    extra,
    extra.xaxis ? { xaxis: Object.assign({}, BASE_LAYOUT.xaxis, extra.xaxis) } : {},
    extra.yaxis ? { yaxis: Object.assign({}, BASE_LAYOUT.yaxis, extra.yaxis) } : {},
  );
}

function stepTrace(x, y, color, name = '') {
  return {
    x, y, name, type: 'scatter', mode: 'lines',
    line: { color, width: 2, shape: 'hv' },
    hovertemplate: `%{x}: %{y}<extra>${name}</extra>`,
  };
}

// ── Tab switching ─────────────────────────────────────────────────────────────
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(btn.dataset.tab).classList.add('active');
    window.dispatchEvent(new Event('resize'));
  });
});

// ── Boot immediately — all data computed from dsp.js ─────────────────────────
initFIR();
initMatched();
initPipeline();


// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — FIR FILTER  (fully computed from dsp.js — no JSON needed)
// ═════════════════════════════════════════════════════════════════════════════
function initFIR() {
  const coeffs = DSP.FIR_COEFFS;
  const SCALE  = 1 << DSP.FIR_SCALE;  // 256

  // ── Coefficient bar chart ──────────────────────────────────────────────────
  Plotly.newPlot('fir-coeffs-plot', [{
    x: coeffs.map((_, i) => i), y: coeffs,
    type: 'bar', marker: { color: C.blue, opacity: 0.85 },
    hovertemplate: 'h[%{x}] = %{y}<extra></extra>',
  }], mkLayout({
    title: { text: 'Coefficients  h[n]  (×256 scaled)', font: { size: 12, color: C.white } },
    xaxis: { title: { text: 'Tap index' } },
    yaxis: { title: { text: 'Value' } },
    bargap: 0.3,
  }), CFG);

  // ── Frequency response (DFT computed in JS) ────────────────────────────────
  const nPts = 300;
  const freqX = [], freqDb = [];
  for (let i = 0; i <= nPts; i++) {
    const f = i / (2 * nPts);  // 0 → 0.5 (Nyquist)
    let re = 0, im = 0;
    for (let k = 0; k < coeffs.length; k++) {
      const theta = 2 * Math.PI * f * k;
      re += (coeffs[k] / SCALE) * Math.cos(theta);
      im -= (coeffs[k] / SCALE) * Math.sin(theta);
    }
    freqX.push(f);
    freqDb.push(20 * Math.log10(Math.max(Math.sqrt(re * re + im * im), 1e-10)));
  }

  Plotly.newPlot('fir-freq-plot', [{
    x: freqX, y: freqDb,
    type: 'scatter', mode: 'lines',
    line: { color: C.blue, width: 2 },
    hovertemplate: 'f/fs=%{x:.3f}  %{y:.1f} dB<extra></extra>',
  }], mkLayout({
    title: { text: 'Magnitude Response  |H(f)|', font: { size: 12, color: C.white } },
    xaxis: { title: { text: 'Normalised frequency  (0.5 = Nyquist)' }, range: [0, 0.5] },
    yaxis: { title: { text: 'dB' }, range: [-80, 5] },
    shapes: [
      { type: 'line', xref: 'x', yref: 'paper', x0: 0.25, x1: 0.25, y0: 0, y1: 1,
        line: { color: C.yellow, dash: 'dash', width: 1 } },
      { type: 'line', xref: 'paper', yref: 'y', x0: 0, x1: 1, y0: -3, y1: -3,
        line: { color: C.text, dash: 'dot', width: 1 } },
    ],
    annotations: [
      { x: 0.26, xref: 'x', y: 0.5, yref: 'paper',
        text: 'fc = 0.25', showarrow: false, font: { color: C.yellow, size: 10 }, xanchor: 'left' },
    ],
  }), CFG);

  // ── Test signals (computed with DSP.fir) ───────────────────────────────────
  const N = 48;
  const tests = {
    impulse: {
      label: 'Impulse (x[4]=256)',
      input: Object.assign(new Array(N).fill(0), { 4: SCALE }),
    },
    dc: {
      label: 'DC (constant 1000)',
      input: new Array(N).fill(1000),
    },
    nyquist: {
      label: 'Nyquist (alternating ±1000)',
      input: Array.from({ length: N }, (_, k) => 1000 * (k % 2 === 0 ? 1 : -1)),
    },
  };
  for (const t of Object.values(tests)) {
    // fix: Object.assign on array needs proper array
    if (!Array.isArray(t.input)) t.input = Array.from(t.input);
    t.output = DSP.fir(DSP.FIR_COEFFS, t.input, DSP.FIR_SCALE);
  }
  // fix impulse input — Object.assign doesn't work cleanly above
  tests.impulse.input = new Array(N).fill(0);
  tests.impulse.input[4] = SCALE;
  tests.impulse.output = DSP.fir(DSP.FIR_COEFFS, tests.impulse.input, DSP.FIR_SCALE);

  function renderFIRTest(key) {
    document.querySelectorAll('#fir-panel .btn[data-test]').forEach(b =>
      b.classList.toggle('active', b.dataset.test === key));
    const t   = tests[key];
    const xs  = t.input.map((_, i) => i);
    const col = { impulse: C.blue, dc: C.green, nyquist: C.red };
    Plotly.react('fir-test-input',  [stepTrace(xs, t.input,  col[key], 'Input')],
      mkLayout({ title: { text: 'Input',      font: { size: 11, color: C.text } },
                 margin: { l: 48, r: 12, t: 28, b: 36 } }), CFG);
    Plotly.react('fir-test-output', [stepTrace(xs, t.output, col[key], 'FIR output')],
      mkLayout({ title: { text: 'FIR Output', font: { size: 11, color: C.text } },
                 margin: { l: 48, r: 12, t: 28, b: 36 } }), CFG);
  }

  document.querySelectorAll('#fir-panel .btn[data-test]').forEach(btn =>
    btn.addEventListener('click', () => renderFIRTest(btn.dataset.test)));
  renderFIRTest('impulse');

  document.getElementById('fir-stat-taps').textContent  = coeffs.length;
  document.getElementById('fir-stat-scale').textContent = `2^${DSP.FIR_SCALE}`;
  document.getElementById('fir-stat-dc').textContent    = '1.0';
  document.getElementById('fir-stat-nyq').textContent   = '0';
}


// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — MATCHED FILTER
// ═════════════════════════════════════════════════════════════════════════════
function initMatched() {
  const N         = 40;
  const threshold = DSP.THRESHOLD_PEAK;
  const xs        = Array.from({ length: N }, (_, i) => i);

  const signals = {
    template: { label: 'Template (exact match)',  color: C.blue,
      input: buildSig(N, 4, DSP.MF_TEMPLATE) },
    flat:     { label: 'Flat pulse (wrong shape)', color: C.red,
      input: buildSig(N, 4, new Array(8).fill(150)) },
    noise:    { label: 'Alternating noise',        color: C.green,
      input: buildSig(N, 4, Array.from({length:8}, (_,k) => 100*(k%2===0?1:-1))) },
    reversed: { label: 'Reversed template',        color: C.yellow,
      input: buildSig(N, 4, [...DSP.MF_TEMPLATE].reverse()) },
  };

  function buildSig(n, start, values) {
    const s = new Array(n).fill(0);
    values.forEach((v, i) => { if (start + i < n) s[start + i] = v; });
    return s;
  }

  // Result table
  const tbody = document.getElementById('mf-result-body');
  Object.entries(signals).forEach(([key, s]) => {
    const out  = DSP.fir(DSP.MF_COEFFS, s.input, DSP.MF_SCALE);
    const peak = Math.max(...out.map(Math.abs));
    const pct  = (peak / DSP.MF_PEAK * 100).toFixed(1);
    const cls  = pct >= 99 ? 'pass' : pct < 30 ? 'warn' : '';
    s.out  = out;
    s.peak = peak;
    tbody.insertAdjacentHTML('beforeend', `
      <tr>
        <td><span style="display:inline-block;width:10px;height:10px;
            border-radius:50%;background:${s.color};margin-right:8px"></span>${s.label}</td>
        <td class="${cls}">${peak}</td>
        <td class="${cls}">${pct}%</td>
        <td class="${pct >= 99 ? 'pass' : ''}">${pct >= 99 ? '✓ MATCH' : '–'}</td>
      </tr>`);
  });

  document.getElementById('mf-stat-peak').textContent   = DSP.MF_PEAK;
  document.getElementById('mf-stat-thresh').textContent = threshold;
  document.getElementById('mf-stat-energy').textContent =
    DSP.MF_TEMPLATE.reduce((s, v) => s + v * v, 0);

  // 4 signal plots
  Object.entries(signals).forEach(([key, s]) => {
    const inEl  = document.getElementById(`mf-in-${key}`);
    const outEl = document.getElementById(`mf-out-${key}`);
    if (!inEl || !outEl) return;

    Plotly.newPlot(inEl, [stepTrace(xs, s.input, s.color, 'Input')],
      mkLayout({ title: { text: s.label, font: { size: 10, color: C.text } },
                 margin: { l: 44, r: 8, t: 28, b: 32 } }), CFG);

    Plotly.newPlot(outEl, [
      stepTrace(xs, s.out, s.color, 'MF output'),
      { x: [0, N-1], y: [threshold, threshold], type: 'scatter', mode: 'lines',
        line: { color: C.text, dash: 'dash', width: 1 }, hoverinfo: 'skip' },
    ], mkLayout({
      title: { text: `Peak: ${s.peak}  (${(s.peak/DSP.MF_PEAK*100).toFixed(1)}%)`,
               font: { size: 10, color: s.peak >= DSP.MF_PEAK * 0.99 ? C.green : C.text } },
      margin: { l: 44, r: 8, t: 28, b: 32 },
      yaxis: { range: [-DSP.MF_PEAK - 20, DSP.MF_PEAK + 40] },
    }), CFG);
  });
}


// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — FULL PIPELINE  (interactive + animated)
// ═════════════════════════════════════════════════════════════════════════════
function initPipeline() {
  const N = 64;

  // ── Preset signals ─────────────────────────────────────────────────────────
  const PRESETS = {
    template: {
      label: 'Template ×4',
      fn: () => {
        const s = new Array(N).fill(0);
        DSP.MF_TEMPLATE.forEach((v, i) => { s[8 + i] = v * 4; });
        return s;
      },
    },
    dc: {
      label: 'Strong DC',
      fn: () => new Array(N).fill(0).map((_, i) => (i >= 8 && i < 40) ? 800 : 0),
    },
    nyquist: {
      label: 'Nyquist noise',
      fn: () => new Array(N).fill(0).map((_, i) => (i >= 4 && i < 36) ? (1000*(i%2===0?1:-1)) : 0),
    },
    double: {
      label: 'Two pulses',
      fn: () => {
        const s = new Array(N).fill(0);
        DSP.MF_TEMPLATE.forEach((v, i) => { s[4 + i] = v * 4; });
        DSP.MF_TEMPLATE.forEach((v, i) => { s[32 + i] = v * 3; });
        return s;
      },
    },
    custom: { label: 'Custom', fn: null },
  };

  // ── State ──────────────────────────────────────────────────────────────────
  let currentInput  = PRESETS.template.fn();
  let pipelineResult = DSP.runPipeline(currentInput);
  let animHandle    = null;
  let animStep      = 0;
  let isPlaying     = false;
  let animSpeed     = 80;  // ms per step

  const xs = Array.from({ length: N }, (_, i) => i);

  // ── Initial static render ──────────────────────────────────────────────────
  renderStatic(pipelineResult);

  // ── Preset buttons ──────────────────────────────────────────────────────────
  document.querySelectorAll('.preset-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.preset-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const key = btn.dataset.preset;
      if (key !== 'custom') {
        currentInput   = PRESETS[key].fn();
        pipelineResult = DSP.runPipeline(currentInput);
        stopAnimation();
        renderStatic(pipelineResult);
        document.getElementById('custom-input-area').style.display = 'none';
      } else {
        document.getElementById('custom-input-area').style.display = 'block';
      }
    });
  });

  // ── Custom input ───────────────────────────────────────────────────────────
  document.getElementById('custom-apply').addEventListener('click', () => {
    const raw = document.getElementById('custom-text').value;
    const vals = raw.split(/[\s,;]+/).map(Number).filter(v => !isNaN(v));
    if (vals.length === 0) return;
    currentInput = new Array(N).fill(0);
    vals.slice(0, N).forEach((v, i) => { currentInput[i] = Math.round(v); });
    pipelineResult = DSP.runPipeline(currentInput);
    stopAnimation();
    renderStatic(pipelineResult);
  });

  // ── Speed slider ───────────────────────────────────────────────────────────
  const speedSlider = document.getElementById('anim-speed');
  speedSlider.addEventListener('input', () => {
    animSpeed = 210 - parseInt(speedSlider.value);  // invert: high = fast
    document.getElementById('speed-label').textContent =
      animSpeed < 60 ? 'Fast' : animSpeed < 120 ? 'Medium' : 'Slow';
    if (isPlaying) { stopAnimation(); startAnimation(); }
  });

  // ── Play / Pause ──────────────────────────────────────────────────────────
  document.getElementById('play-btn').addEventListener('click', () => {
    if (isPlaying) {
      stopAnimation();
    } else {
      if (animStep >= N) animStep = 0;
      startAnimation();
    }
  });

  // ── Reset ─────────────────────────────────────────────────────────────────
  document.getElementById('reset-btn').addEventListener('click', () => {
    stopAnimation();
    animStep = 0;
    renderStatic(pipelineResult);
  });

  // ── Animation ─────────────────────────────────────────────────────────────
  function startAnimation() {
    isPlaying = true;
    document.getElementById('play-btn').textContent = '⏸ Pause';
    document.getElementById('play-btn').classList.add('active');
    animHandle = setInterval(() => {
      animStep++;
      if (animStep >= N) {
        stopAnimation();
        renderStatic(pipelineResult);
        return;
      }
      renderAnimFrame(pipelineResult, animStep);
    }, animSpeed);
  }

  function stopAnimation() {
    isPlaying = false;
    clearInterval(animHandle);
    animHandle = null;
    document.getElementById('play-btn').textContent = '▶ Play';
    document.getElementById('play-btn').classList.remove('active');
  }

  // ── Render: full static ────────────────────────────────────────────────────
  function renderStatic(r) {
    animStep = N;
    updatePlots(r, N);
    updatePeakTable(r.peakEvents);
    updateStageStats(r);
  }

  // ── Render: single animation frame ────────────────────────────────────────
  function renderAnimFrame(r, step) {
    updatePlots(r, step);
    // highlight active pipeline stage
    const stage = step < 2 ? 'raw' : step < 4 ? 'fir' : step < 8 ? 'mf' : 'peak';
    document.querySelectorAll('.pipe-block').forEach(el => {
      el.classList.remove('active-stage');
      if (el.dataset.stage === stage) el.classList.add('active-stage');
    });
    document.getElementById('anim-cycle').textContent = `Cycle ${step}`;
  }

  // ── Update all three plots up to `step` samples ────────────────────────────
  function updatePlots(r, step) {
    const s = Math.min(step, N);
    const xSlice  = xs.slice(0, s);
    const cursor  = s < N ? s : null;

    // Cursor (current sample marker)
    const cursorShape = cursor !== null ? [{
      type: 'line', xref: 'x', yref: 'paper',
      x0: cursor, x1: cursor, y0: 0, y1: 1,
      line: { color: C.white, width: 1, dash: 'dot' },
    }] : [];

    // ── Raw input ────────────────────────────────────────────────────────────
    Plotly.react('pl-raw', [
      stepTrace(xSlice, r.rawInput.slice(0, s), C.blue, 'Raw input'),
    ], mkLayout({
      title: { text: 'Raw Input', font: { size: 11, color: C.text } },
      shapes: cursorShape,
      margin: { l: 52, r: 16, t: 30, b: 28 },
      xaxis: { range: [0, N - 1] },
      yaxis: { range: [Math.min(-50, ...r.rawInput) - 20, Math.max(50, ...r.rawInput) + 50] },
    }), CFG);

    // ── FIR output ───────────────────────────────────────────────────────────
    const detMarkers = xSlice
      .map((x, i) => ({ x, y: r.detected[i] }))
      .filter(p => p.y === 1);

    Plotly.react('pl-fir', [
      stepTrace(xSlice, r.firOut.slice(0, s), '#7C9FD8', 'FIR output'),
      {
        x: detMarkers.map(p => p.x),
        y: detMarkers.map(() => DSP.THRESHOLD_DET * 0.15),
        type: 'scatter', mode: 'markers', name: 'detected',
        marker: { color: C.green, size: 7, symbol: 'triangle-up' },
        hovertemplate: 'detected<extra></extra>',
      },
    ], mkLayout({
      title: { text: 'After FIR  +  Threshold Events (▲)', font: { size: 11, color: C.text } },
      shapes: [
        ...cursorShape,
        { type: 'line', xref: 'paper', yref: 'y', x0: 0, x1: 1,
          y0: DSP.THRESHOLD_DET, y1: DSP.THRESHOLD_DET,
          line: { color: C.green, dash: 'dash', width: 1 } },
      ],
      margin: { l: 52, r: 16, t: 30, b: 28 },
      xaxis: { range: [0, N - 1] },
      yaxis: { range: [Math.min(-50, ...r.firOut) - 20, Math.max(600, ...r.firOut) + 80] },
    }), CFG);

    // ── MF output + peak events ───────────────────────────────────────────────
    const visiblePeaks = r.peakEvents.filter(e => e.cycle <= s);
    Plotly.react('pl-mf', [
      stepTrace(xSlice, r.mfOut.slice(0, s), C.purple, 'MF output'),
      {
        x: visiblePeaks.map(e => e.cycle),
        y: visiblePeaks.map(e => e.peak_val),
        type: 'scatter', mode: 'markers+text',
        marker: { color: C.yellow, size: 12, symbol: 'star' },
        text: visiblePeaks.map(e => `${e.peak_val}`),
        textposition: 'top center',
        textfont: { size: 9, color: C.yellow },
        hovertemplate: 'peak_val=%{y}  cycle=%{x}<extra></extra>',
      },
    ], mkLayout({
      title: { text: 'Matched Filter  +  Peak Events (★)', font: { size: 11, color: C.text } },
      shapes: [
        ...cursorShape,
        { type: 'line', xref: 'paper', yref: 'y', x0: 0, x1: 1,
          y0:  DSP.THRESHOLD_PEAK, y1:  DSP.THRESHOLD_PEAK,
          line: { color: C.yellow, dash: 'dash', width: 1 } },
        { type: 'line', xref: 'paper', yref: 'y', x0: 0, x1: 1,
          y0: -DSP.THRESHOLD_PEAK, y1: -DSP.THRESHOLD_PEAK,
          line: { color: C.yellow, dash: 'dash', width: 1 } },
      ],
      margin: { l: 52, r: 16, t: 30, b: 40 },
      xaxis: { range: [0, N - 1], title: { text: 'Clock cycle' } },
      yaxis: { range: [-(DSP.MF_PEAK * 5 + 100), DSP.MF_PEAK * 5 + 200] },
    }), CFG);
  }

  // ── Peak table ─────────────────────────────────────────────────────────────
  function updatePeakTable(events) {
    const tbody = document.getElementById('pl-peak-body');
    tbody.innerHTML = '';
    if (events.length === 0) {
      tbody.insertAdjacentHTML('beforeend',
        '<tr><td colspan="3" style="color:var(--muted);text-align:center;padding:12px">No peaks detected</td></tr>');
    } else {
      events.forEach((e, i) => {
        tbody.insertAdjacentHTML('beforeend', `
          <tr>
            <td>#${i + 1}</td>
            <td class="pass">${e.peak_val}</td>
            <td>${e.cycle}</td>
          </tr>`);
      });
    }
  }

  // ── Stage stats ────────────────────────────────────────────────────────────
  function updateStageStats(r) {
    document.getElementById('pl-stat-peaks').textContent = r.peakEvents.length;
    document.getElementById('pl-stat-tdet').textContent  = DSP.THRESHOLD_DET;
    document.getElementById('pl-stat-tpeak').textContent = DSP.THRESHOLD_PEAK;
    document.getElementById('anim-cycle').textContent = '';
    document.querySelectorAll('.pipe-block').forEach(el => el.classList.remove('active-stage'));
  }
}
