const statusEl = document.getElementById('status');
const buttons = Array.from(document.querySelectorAll('button[data-target]'));

const gpuModeEl = document.getElementById('gpuMode');
const gpuIndexEl = document.getElementById('gpuIndex');
const contextSizeEl = document.getElementById('contextSize');
const modelSelectEl = document.getElementById('modelSelect');
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
  return `${model.name} | ${model.size_gb} GB | ${paramText} | ${model.architecture}`;
}

function updateGpuSelectionLock() {
  gpuIndexEl.disabled = gpuModeEl.value !== 'single';
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

async function loadMainOptions() {
  try {
    const res = await fetch('/main/options');
    const data = await res.json();

    gpuIndexEl.innerHTML = '';
    (data.gpus || []).forEach((gpu) => {
      const option = document.createElement('option');
      option.value = gpu.index;
      option.textContent = `${gpu.index} - ${gpu.name} (${gpu.vram_gb} GB)`;
      gpuIndexEl.appendChild(option);
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
    if (defaults.gpu_mode) gpuModeEl.value = defaults.gpu_mode;
    if (defaults.gpu_index) gpuIndexEl.value = defaults.gpu_index;
    if (defaults.context) contextSizeEl.value = String(defaults.context);
    if (defaults.model_path) modelSelectEl.value = defaults.model_path;

    if (modelSelectEl.options.length === 0) {
      startMainBtn.disabled = true;
      setStatus('No GGUF models found in MAIN_DATA/models. Add models first.');
    }

    updateGpuSelectionLock();
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
        gpu_mode: gpuModeEl.value,
        gpu_index: gpuIndexEl.value || null,
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

gpuModeEl?.addEventListener('change', updateGpuSelectionLock);
buttons.forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});

loadTargetReadiness();
loadMainOptions();
