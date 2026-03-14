/* ── app.js — FPGA DSP Demo Visualisation ─────────────────────────────────── */

'use strict';

// ── Plotly theme shared across all charts ─────────────────────────────────
const THEME = {
  bg:      '#1a1d27',
  paper:   '#1a1d27',
  grid:    '#2a2d3a',
  text:    '#8892a4',
  accent:  '#4C9BE8',
  accent2: '#7C5CE8',
  pass:    '#4CE874',
  warn:    '#E8C44C',
  danger:  '#E8624C',
};

const LAYOUT_BASE = {
  paper_bgcolor: THEME.paper,
  plot_bgcolor:  THEME.bg,
  font:          { color: THEME.text, family: 'system-ui, sans-serif', size: 11 },
  margin:        { l: 48, r: 16, t: 28, b: 40 },
  xaxis: {
    gridcolor:   THEME.grid,
    zerolinecolor: THEME.grid,
    tickfont:    { size: 10 },
  },
  yaxis: {
    gridcolor:   THEME.grid,
    zerolinecolor: THEME.grid,
    tickfont:    { size: 10 },
  },
  showlegend: false,
  hovermode: 'x unified',
};

const PLOTLY_CONFIG = { responsive: true, displayModeBar: false };

function layout(overrides = {}) {
  return Object.assign({}, LAYOUT_BASE, overrides);
}

// ── helper: step trace ─────────────────────────────────────────────────────
function stepTrace(x, y, color, name = '', width = 1.5) {
  return {
    x, y, name,
    type: 'scatter', mode: 'lines',
    line: { color, width, shape: 'hv' },
    hovertemplate: `%{x}: %{y}<extra>${name}</extra>`,
  };
}

// ── helper: bar/stem trace ─────────────────────────────────────────────────
function stemTrace(x, y, color, name = '') {
  return {
    x, y, name,
    type: 'bar',
    marker: { color, opacity: 0.85 },
    hovertemplate: `tap %{x}: %{y}<extra>${name}</extra>`,
  };
}

// ── helper: threshold line ─────────────────────────────────────────────────
function threshLine(x0, x1, val, color, dash = 'dash', label = '') {
  return {
    type: 'line', xref: 'x', yref: 'y',
    x0, x1, y0: val, y1: val,
    line: { color, dash, width: 1 },
    label: label ? { text: label, font: { size: 9, color }, yanchor: 'bottom' } : undefined,
  };
}

// ── tab switching ──────────────────────────────────────────────────────────
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(btn.dataset.tab).classList.add('active');
    // trigger resize so Plotly fills the newly visible panel
    window.dispatchEvent(new Event('resize'));
  });
});

// ── load all JSON then initialise ──────────────────────────────────────────
async function loadJSON(path) {
  const r = await fetch(path);
  return r.json();
}

Promise.all([
  loadJSON('data/fir.json'),
  loadJSON('data/matched.json'),
  loadJSON('data/pipeline.json'),
]).then(([firData, matchedData, pipelineData]) => {
  initFIR(firData);
  initMatched(matchedData);
  initPipeline(pipelineData);
}).catch(err => {
  console.error('Failed to load data:', err);
  document.body.insertAdjacentHTML('afterbegin',
    `<div style="background:#E8624C22;border-left:3px solid #E8624C;padding:12px 16px;margin:16px;border-radius:4px;color:#E8624C">
      Failed to load data files. Run <code>python scripts/export_demo_data.py</code> first.
    </div>`
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — FIR FILTER
// ═══════════════════════════════════════════════════════════════════════════
function initFIR(d) {
  // ── 1a: Coefficient bar chart ──────────────────────────────────────────
  Plotly.newPlot('fir-coeffs-plot', [
    stemTrace(
      d.coeffs.map((_, i) => i),
      d.coeffs,
      THEME.accent,
      'Coefficient'
    ),
  ], layout({
    title: { text: 'Impulse Response  h[n]', font: { size: 12, color: THEME.text } },
    xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Tap index', standoff: 4 } },
    yaxis: { ...LAYOUT_BASE.yaxis, title: { text: 'Value (×256 scaled)', standoff: 4 } },
    bargap: 0.3,
    margin: { l: 56, r: 16, t: 36, b: 44 },
  }), PLOTLY_CONFIG);

  // ── 1b: Frequency response ────────────────────────────────────────────
  const fr = d.freq_response;
  Plotly.newPlot('fir-freq-plot', [
    {
      x: fr.freq, y: fr.db,
      type: 'scatter', mode: 'lines',
      line: { color: THEME.accent, width: 2 },
      name: 'Magnitude',
      hovertemplate: 'f/fs = %{x:.3f}<br>%{y:.1f} dB<extra></extra>',
    },
  ], layout({
    title: { text: 'Magnitude Response  |H(f)|', font: { size: 12, color: THEME.text } },
    xaxis: {
      ...LAYOUT_BASE.xaxis,
      title: { text: 'Normalised frequency  (0.5 = Nyquist)', standoff: 4 },
      range: [0, 0.5],
    },
    yaxis: {
      ...LAYOUT_BASE.yaxis,
      title: { text: 'dB', standoff: 4 },
      range: [-80, 5],
    },
    shapes: [
      threshLine(0, 0.5, -3, THEME.muted, 'dot'),
      { type: 'line', xref: 'x', yref: 'paper', x0: 0.25, x1: 0.25,
        y0: 0, y1: 1, line: { color: THEME.warn, dash: 'dash', width: 1 } },
    ],
    annotations: [
      { x: 0.26, y: 0.5, xref: 'x', yref: 'paper', text: 'fc = 0.25',
        showarrow: false, font: { color: THEME.warn, size: 10 }, xanchor: 'left' },
      { x: 0.01, y: -3, xref: 'x', yref: 'y', text: '–3 dB',
        showarrow: false, font: { color: THEME.muted, size: 9 }, xanchor: 'left', yanchor: 'bottom' },
    ],
    margin: { l: 56, r: 16, t: 36, b: 48 },
  }), PLOTLY_CONFIG);

  // ── 1c: Test signal viewer ─────────────────────────────────────────────
  let activeTest = 'impulse';

  function renderFIRTest(key) {
    activeTest = key;
    document.querySelectorAll('#fir-panel .btn[data-test]').forEach(b =>
      b.classList.toggle('active', b.dataset.test === key));

    const t   = d.tests[key];
    const xs  = Array.from({ length: t.input.length }, (_, i) => i);
    const col = { impulse: THEME.accent, dc: THEME.pass, nyquist: THEME.danger };

    Plotly.newPlot('fir-test-input', [
      stepTrace(xs, t.input, col[key], 'Input'),
    ], layout({
      title: { text: 'Input', font: { size: 11, color: THEME.muted } },
      margin: { l: 48, r: 16, t: 28, b: 36 },
      xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Cycle', standoff: 2 } },
    }), PLOTLY_CONFIG);

    Plotly.newPlot('fir-test-output', [
      stepTrace(xs, t.output, col[key], 'FIR output'),
    ], layout({
      title: { text: 'FIR Output', font: { size: 11, color: THEME.muted } },
      margin: { l: 48, r: 16, t: 28, b: 36 },
      xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Cycle', standoff: 2 } },
    }), PLOTLY_CONFIG);
  }

  document.querySelectorAll('#fir-panel .btn[data-test]').forEach(btn => {
    btn.addEventListener('click', () => renderFIRTest(btn.dataset.test));
  });

  renderFIRTest('impulse');

  // ── stats ─────────────────────────────────────────────────────────────
  document.getElementById('fir-stat-taps').textContent  = d.taps;
  document.getElementById('fir-stat-scale').textContent = `2^${d.scale_shift}`;
  document.getElementById('fir-stat-dc').textContent    = '1.0';
  document.getElementById('fir-stat-nyq').textContent   = '0';
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — MATCHED FILTER
// ═══════════════════════════════════════════════════════════════════════════
function initMatched(d) {
  const xs = Array.from({ length: d.n_samples }, (_, i) => i);

  // ── result table ───────────────────────────────────────────────────────
  const tbody = document.getElementById('mf-result-body');
  Object.entries(d.signals).forEach(([key, s]) => {
    const pct = s.pct;
    const cls = pct >= 99 ? 'pass' : pct < 30 ? 'warn' : '';
    tbody.insertAdjacentHTML('beforeend', `
      <tr>
        <td><span style="display:inline-block;width:10px;height:10px;
            border-radius:50%;background:${s.color};margin-right:8px"></span>${s.label}</td>
        <td class="${cls}">${s.peak}</td>
        <td class="${cls}">${pct}%</td>
        <td class="${pct >= 99 ? 'pass' : ''}">${pct >= 99 ? '✓ MATCH' : '–'}</td>
      </tr>`);
  });

  // ── 4-column plots ─────────────────────────────────────────────────────
  const threshold = d.threshold;

  Object.entries(d.signals).forEach(([key, s]) => {
    const inEl  = document.getElementById(`mf-in-${key}`);
    const outEl = document.getElementById(`mf-out-${key}`);
    if (!inEl || !outEl) return;

    Plotly.newPlot(inEl, [
      stepTrace(xs, s.input, s.color, 'Input'),
    ], layout({
      title: { text: s.label, font: { size: 10, color: THEME.muted } },
      margin: { l: 44, r: 8, t: 28, b: 32 },
      xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Cycle', standoff: 2 } },
    }), PLOTLY_CONFIG);

    Plotly.newPlot(outEl, [
      stepTrace(xs, s.output, s.color, 'MF output'),
      {
        x: [xs[0], xs[xs.length - 1]], y: [threshold, threshold],
        type: 'scatter', mode: 'lines',
        line: { color: THEME.muted, dash: 'dash', width: 1 },
        name: `threshold ${threshold}`,
        hoverinfo: 'skip',
      },
    ], layout({
      title: { text: `Peak: ${s.peak}  (${s.pct}%)`, font: { size: 10, color: s.pct >= 99 ? THEME.pass : THEME.muted } },
      margin: { l: 44, r: 8, t: 28, b: 32 },
      xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Cycle', standoff: 2 } },
      yaxis: { ...LAYOUT_BASE.yaxis, range: [-d.peak_theory - 20, d.peak_theory + 40] },
    }), PLOTLY_CONFIG);
  });

  // stats
  document.getElementById('mf-stat-peak').textContent   = d.peak_theory;
  document.getElementById('mf-stat-thresh').textContent = d.threshold;
  document.getElementById('mf-stat-energy').textContent =
    d.peak_theory * (1 << d.scale_shift);
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 — FULL PIPELINE
// ═══════════════════════════════════════════════════════════════════════════
function initPipeline(d) {
  const xs = Array.from({ length: d.n_samples }, (_, i) => i);

  // ── highlight template region ──────────────────────────────────────────
  const tStart = d.template_start;
  const tEnd   = tStart + d.scaled_template.length - 1;
  const templateShape = {
    type: 'rect', xref: 'x', yref: 'paper',
    x0: tStart - 0.5, x1: tEnd + 0.5, y0: 0, y1: 1,
    fillcolor: 'rgba(76,155,232,0.06)', line: { width: 0 },
  };

  // ── raw input ──────────────────────────────────────────────────────────
  Plotly.newPlot('pl-raw', [
    stepTrace(xs, d.raw_in, THEME.accent, 'Raw input'),
  ], layout({
    title: { text: 'Raw Input  (scaled template ×4)', font: { size: 11, color: THEME.muted } },
    shapes: [templateShape],
    margin: { l: 52, r: 16, t: 32, b: 32 },
  }), PLOTLY_CONFIG);

  // ── FIR output ─────────────────────────────────────────────────────────
  Plotly.newPlot('pl-fir', [
    stepTrace(xs, d.fir_out, '#7C9FD8', 'FIR output'),
    {
      x: xs, y: xs.map(i => d.detected[i] ? Math.max(...d.fir_out) * 0.12 : null),
      type: 'scatter', mode: 'markers', name: 'detected',
      marker: { color: THEME.pass, size: 5, symbol: 'triangle-up' },
      hovertemplate: 'detected<extra></extra>',
    },
  ], layout({
    title: { text: 'After FIR Low-Pass  +  Threshold Events', font: { size: 11, color: THEME.muted } },
    shapes: [
      templateShape,
      threshLine(0, d.n_samples - 1, d.threshold_det, THEME.pass, 'dash'),
    ],
    annotations: [{
      x: 1, y: d.threshold_det, xref: 'x', yref: 'y',
      text: `thr ${d.threshold_det}`, showarrow: false,
      font: { color: THEME.pass, size: 9 }, xanchor: 'left', yanchor: 'bottom',
    }],
    margin: { l: 52, r: 16, t: 32, b: 32 },
  }), PLOTLY_CONFIG);

  // ── MF output ──────────────────────────────────────────────────────────
  // mark peak events
  const peakX = d.peak_events.map(e => e.cycle);
  const peakY = d.peak_events.map(e => e.peak_val);

  Plotly.newPlot('pl-mf', [
    stepTrace(xs, d.mf_out, THEME.accent2, 'MF output'),
    {
      x: peakX, y: peakY,
      type: 'scatter', mode: 'markers+text',
      name: 'Peak event',
      marker: { color: THEME.warn, size: 10, symbol: 'star' },
      text: peakX.map((_, i) => `peak=${peakY[i]}`),
      textposition: 'top center',
      textfont: { size: 9, color: THEME.warn },
      hovertemplate: 'Peak: %{y}  pos=%{x}<extra></extra>',
    },
  ], layout({
    title: { text: 'Matched Filter Output  +  Peak Events', font: { size: 11, color: THEME.muted } },
    shapes: [
      templateShape,
      threshLine(0, d.n_samples - 1,  d.threshold_peak, THEME.warn, 'dash'),
      threshLine(0, d.n_samples - 1, -d.threshold_peak, THEME.warn, 'dash'),
    ],
    annotations: [{
      x: 1, y: d.threshold_peak, xref: 'x', yref: 'y',
      text: `thr ±${d.threshold_peak}`, showarrow: false,
      font: { color: THEME.warn, size: 9 }, xanchor: 'left', yanchor: 'bottom',
    }],
    margin: { l: 52, r: 16, t: 32, b: 40 },
    xaxis: { ...LAYOUT_BASE.xaxis, title: { text: 'Clock cycle', standoff: 4 } },
  }), PLOTLY_CONFIG);

  // ── peak event table ───────────────────────────────────────────────────
  const ptbody = document.getElementById('pl-peak-body');
  if (d.peak_events.length === 0) {
    ptbody.insertAdjacentHTML('beforeend',
      '<tr><td colspan="3" style="color:var(--muted);text-align:center">No peaks detected</td></tr>');
  } else {
    d.peak_events.forEach((e, i) => {
      ptbody.insertAdjacentHTML('beforeend', `
        <tr>
          <td>#${i + 1}</td>
          <td class="pass">${e.peak_val}</td>
          <td>${e.cycle}</td>
        </tr>`);
    });
  }

  // ── stats ─────────────────────────────────────────────────────────────
  document.getElementById('pl-stat-peaks').textContent  = d.peak_events.length;
  document.getElementById('pl-stat-tdet').textContent   = d.threshold_det;
  document.getElementById('pl-stat-tpeak').textContent  = d.threshold_peak;
}
