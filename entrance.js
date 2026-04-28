const statusEl = document.getElementById('status');
const buttons = Array.from(document.querySelectorAll('button[data-target]'));

const gpuSelectionEl = document.getElementById('gpuSelection');
const contextSizeEl = document.getElementById('contextSize');
const modelSelectEl = document.getElementById('modelSelect');
const fitEstimateEl = document.getElementById('fitEstimate');
const startMainBtn = document.getElementById('startMainBtn');

function setStatus(message) {
  statusEl.textContent = message;
}

function formatModelLabel(model) {
  const paramText = model.param_tag === 'unknown'
    ? 'params: unknown'
    : model.model_type === 'moe'
      ? `${model.param_tag} (active ${model.active_params_b}B / total ${model.total_params_b}B)`
      : `${model.param_tag} dense`;
  return `${model.name} | ${model.size_gb} GB | ${paramText} | ${model.architecture} | ~${model.estimated_layers} layers`;
}

async function loadTargetReadiness() {
  try {
    const res = await fetch('/targets');
    const data = await res.json();
    const targets = data.targets || {};

    buttons.forEach((btn) => {
      const target = btn.dataset.target;
      const ready = Boolean(targets[target]?.ready);
      btn.disabled = !ready;
      btn.title = ready ? '' : `Missing files: ${(targets[target]?.missing || []).join(', ')}`;
    });

    const notReadyTargets = Object.entries(targets).filter(([, info]) => !info.ready);
    if (notReadyTargets.length > 0) {
      setStatus(`Some launch targets are not ready (${notReadyTargets.length} issue(s)). Hover a disabled button for details.`);
      return;
    }

    setStatus('Ready.');
  } catch (err) {
    setStatus(`Could not read launch target status: ${err.message}`);
  }
}

async function updateEstimate() {
  if (!modelSelectEl.value) return;
  try {
    fitEstimateEl.textContent = 'Calculating VRAM fit estimate...';
    const res = await fetch('/main/estimate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model_path: modelSelectEl.value,
        context: Number(contextSizeEl.value || '65536'),
        gpu_selection: gpuSelectionEl.value || 'all'
      })
    });
    const est = await res.json();
    fitEstimateEl.textContent = `Fit: ${est.estimated_fit} | Recommended GPU layers: ${est.recommended_gpu_layers}/${est.estimated_layer_count} | Selected VRAM: ${est.selected_vram_gb ?? 0} GB | Usable VRAM: ${est.usable_vram_gb ?? 0} GB | KV cache est: ${est.kv_cache_gb ?? 0} GB`;
  } catch (err) {
    fitEstimateEl.textContent = `Could not compute estimate: ${err.message}`;
  }
}

async function loadMainOptions() {
  try {
    const res = await fetch('/main/options');
    const data = await res.json();

    gpuSelectionEl.innerHTML = '';
    (data.gpu_choices || []).forEach((entry) => {
      const option = document.createElement('option');
      option.value = entry.value;
      option.textContent = entry.label;
      gpuSelectionEl.appendChild(option);
    });

    contextSizeEl.innerHTML = '';
    (data.contexts || []).forEach((ctx) => {
      const option = document.createElement('option');
      option.value = String(ctx);
      option.textContent = `${Math.floor(ctx / 1024)}k`;
      contextSizeEl.appendChild(option);
    });

    modelSelectEl.innerHTML = '';
    (data.models || []).forEach((model) => {
      const option = document.createElement('option');
      option.value = model.path;
      option.textContent = formatModelLabel(model);
      modelSelectEl.appendChild(option);
    });

    const defaults = data.defaults || {};
    if (defaults.gpu_selection) gpuSelectionEl.value = defaults.gpu_selection;
    if (defaults.context) contextSizeEl.value = String(defaults.context);
    if (defaults.model_path) modelSelectEl.value = defaults.model_path;

    if (modelSelectEl.options.length === 0) {
      startMainBtn.disabled = true;
      setStatus('No GGUF models found in MAIN_DATA/models. Add models first.');
      fitEstimateEl.textContent = 'No model available for estimation.';
      return;
    }

    await updateEstimate();
  } catch (err) {
    setStatus(`Could not load profile options: ${err.message}`);
  }
}

async function launch(target) {
  setStatus(`Starting ${target}...`);
  try {
    const payload = { target };

    if (target === 'main_plus_opencode') {
      payload.profile = {
        model_path: modelSelectEl.value,
        context: Number(contextSizeEl.value || '65536'),
        gpu_selection: gpuSelectionEl.value || 'all',
      };
    }

    const res = await fetch('/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    setStatus(data.message || 'Done.');
  } catch (err) {
    setStatus(`Could not reach launcher API. Double-click entrance.bat and wait 2-3 seconds, then retry. Error: ${err.message}`);
  }
}

[gpuSelectionEl, contextSizeEl, modelSelectEl].forEach((el) => {
  el?.addEventListener('change', updateEstimate);
});

buttons.forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});

loadTargetReadiness();
loadMainOptions();
