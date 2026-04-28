const statusEl = document.getElementById('status');
const buttons = Array.from(document.querySelectorAll('button[data-target]'));

const gpuSelectionEl = document.getElementById('gpuSelection');
const contextSizeEl = document.getElementById('contextSize');
const modelSelectEl = document.getElementById('modelSelect');
const fitEstimateEl = document.getElementById('fitEstimate');
const startMainBtn = document.getElementById('startMainBtn');
const gpuLayersSliderEl = document.getElementById('gpuLayersSlider');
const gpuLayersValueEl = document.getElementById('gpuLayersValue');
const gpuLayersHintEl = document.getElementById('gpuLayersHint');
const force999El = document.getElementById('force999');

// ── Monitor panel elements ──
const monitorSection = document.getElementById('monitor-section');
const monitorBadge = document.getElementById('monitorBadge');
const serverDot = document.getElementById('serverDot');
const serverStatusText = document.getElementById('serverStatusText');
const monitorLog = document.getElementById('monitor-log');

let monitorPollId = null;
let monitorLogIndex = 0;
let monitorPhase = 'idle'; // idle | launching | ready | error

const selectedValues = {
  gpu_selection: 'all',
  context: '65536',
  model_path: '',
  gpu_layers: 0,
  max_layers: 0,
  recommended_gpu_layers: 0,
  force_999: false,
};

// ── Monitor helpers ──

function formatTime(ts) {
  const d = new Date(ts * 1000);
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

function addMonitorLog(message, level) {
  const entry = document.createElement('div');
  entry.className = `log-entry ${level}`;
  const now = new Date();
  const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  entry.innerHTML = `<span class="time">${timeStr}</span>${message}`;
  monitorLog.appendChild(entry);
  monitorLog.scrollTop = monitorLog.scrollHeight;
}

function setMonitorPhase(phase) {
  monitorPhase = phase;
  monitorBadge.className = 'monitor-badge ' + phase;
  switch (phase) {
    case 'launching': monitorBadge.textContent = 'Launching...'; break;
    case 'ready': monitorBadge.textContent = 'Server Ready'; break;
    case 'offline': monitorBadge.textContent = 'Idle'; break;
    case 'done': monitorBadge.textContent = 'Done'; break;
    case 'error': monitorBadge.textContent = 'Error'; break;
    default: monitorBadge.textContent = 'Idle';
  }
}

function showMonitor() {
  monitorSection.classList.add('visible');
  monitorLog.innerHTML = '';
  monitorLogIndex = 0;
  addMonitorLog('Initializing launch monitor...', 'info');
  setMonitorPhase('launching');
}

function hideMonitor() {
  clearInterval(monitorPollId);
  monitorPollId = null;
  setMonitorPhase('offline');
  monitorSection.classList.remove('visible');
}

async function checkServerStatus() {
  try {
    const res = await fetch('/server-status');
    const data = await res.json();
    const online = data.online === true;
    serverDot.className = online ? 'online' : 'offline';
    serverStatusText.textContent = online ? 'Online - responding to /v1/models' : 'Offline - not reachable yet';
    return online;
  } catch (err) {
    serverDot.className = 'offline';
    serverStatusText.textContent = 'Cannot check status';
    return false;
  }
}

async function pollLaunchLogs() {
  try {
    const res = await fetch(`/launch-log?since=${monitorLogIndex}`);
    const data = await res.json();
    const logs = data.logs || [];
    monitorLogIndex = data.next_index || monitorLogIndex;

    logs.forEach((entry) => {
      const timeStr = formatTime(entry.timestamp);
      const entryEl = document.createElement('div');
      entryEl.className = `log-entry ${entry.level}`;
      entryEl.innerHTML = `<span class="time">${timeStr}</span>${entry.message}`;
      monitorLog.appendChild(entryEl);
    });

    if (logs.length > 0) {
      monitorLog.scrollTop = monitorLog.scrollHeight;
    }

    // Detect completion from logs
    const lastMsgs = logs.map((l) => l.message);
    if (lastMsgs.some((m) => m.includes('OpenCode launcher dispatched'))) {
      setMonitorPhase('done');
      setTimeout(() => {
        addMonitorLog('--- All done. You can close this monitor. ---', 'success');
        setMonitorPhase('done');
        clearInterval(monitorPollId);
        monitorPollId = null;
        // Still poll server status a bit more
        setTimeout(() => checkServerStatus(), 5000);
      }, 1000);
    }
  } catch (err) {
    // Silently retry on failure
  }
}

async function startMonitoring() {
  showMonitor();
  setMonitorPhase('launching');

  // Initial server check
  checkServerStatus();

  // Poll logs every 1.5 seconds
  if (monitorPollId) clearInterval(monitorPollId);
  monitorPollId = setInterval(pollLaunchLogs, 1500);
  pollLaunchLogs(); // immediate first call

  // Also poll server status every 5 seconds
  setInterval(checkServerStatus, 5000);
}

// ── Original UI functions ──

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
  if (!selectedValues.model_path) return;
  try {
    fitEstimateEl.textContent = 'Calculating VRAM fit estimate...';
    const res = await fetch('/main/estimate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model_path: selectedValues.model_path,
        context: Number(selectedValues.context || '65536'),
        gpu_selection: selectedValues.gpu_selection || 'all'
      })
    });
    const est = await res.json();
    selectedValues.recommended_gpu_layers = Number(est.recommended_gpu_layers || 0);
    selectedValues.max_layers = Number(est.estimated_layer_count || 0);
    selectedValues.gpu_layers = selectedValues.recommended_gpu_layers;
    gpuLayersSliderEl.min = '0';
    gpuLayersSliderEl.max = String(selectedValues.max_layers);
    gpuLayersSliderEl.value = String(selectedValues.gpu_layers);
    gpuLayersValueEl.textContent = String(selectedValues.gpu_layers);
    gpuLayersHintEl.textContent = `Recommended ${selectedValues.recommended_gpu_layers}/${selectedValues.max_layers}. You can override with the slider or check 999.`;
    fitEstimateEl.textContent = `Fit: ${est.estimated_fit} | Recommended GPU layers: ${est.recommended_gpu_layers}/${est.estimated_layer_count} | Selected VRAM: ${est.selected_vram_gb ?? 0} GB | Usable VRAM: ${est.usable_vram_gb ?? 0} GB | KV cache est: ${est.kv_cache_gb ?? 0} GB`;
  } catch (err) {
    fitEstimateEl.textContent = `Could not compute estimate: ${err.message}`;
  }
}

function renderChoiceButtons(container, entries, selectedValue, onSelect) {
  container.innerHTML = '';
  entries.forEach((entry) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'choice-btn';
    button.textContent = entry.label;
    button.dataset.value = entry.value;
    button.setAttribute('role', 'radio');
    button.setAttribute('aria-checked', String(entry.value === selectedValue));
    if (entry.value === selectedValue) {
      button.classList.add('active');
    }
    button.addEventListener('click', () => onSelect(entry.value));
    container.appendChild(button);
  });
}

async function loadMainOptions() {
  try {
    const res = await fetch('/main/options');
    const data = await res.json();
    if (data.generated_profiles) {
      setStatus(`Ready. Generated ${data.generated_profiles} startup profile .bat files in MAIN_DATA/startup_bat_profiles.`);
    }

    const defaults = data.defaults || {};
    selectedValues.gpu_selection = defaults.gpu_selection || data.gpu_choices?.[0]?.value || 'all';
    selectedValues.context = String(defaults.context || data.contexts?.[0] || 65536);
    selectedValues.model_path = defaults.model_path || data.models?.[0]?.path || '';

    if ((data.models || []).length === 0) {
      startMainBtn.disabled = true;
      setStatus('No GGUF models found in MAIN_DATA/models. Add models first.');
      fitEstimateEl.textContent = 'No model available for estimation.';
      return;
    }

    const renderAllChoices = () => {
      renderChoiceButtons(
        gpuSelectionEl,
        (data.gpu_choices || []).map((entry) => ({ value: entry.value, label: entry.label })),
        selectedValues.gpu_selection,
        async (value) => {
          selectedValues.gpu_selection = value;
          renderAllChoices();
          await updateEstimate();
        }
      );
      renderChoiceButtons(
        contextSizeEl,
        (data.contexts || []).map((ctx) => ({ value: String(ctx), label: `${Math.floor(ctx / 1024)}k` })),
        selectedValues.context,
        async (value) => {
          selectedValues.context = value;
          renderAllChoices();
          await updateEstimate();
        }
      );
      renderChoiceButtons(
        modelSelectEl,
        (data.models || []).map((model) => ({ value: model.path, label: formatModelLabel(model) })),
        selectedValues.model_path,
        async (value) => {
          selectedValues.model_path = value;
          renderAllChoices();
          await updateEstimate();
        }
      );
    };

    renderAllChoices();
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
        model_path: selectedValues.model_path,
        context: Number(selectedValues.context || '65536'),
        gpu_selection: selectedValues.gpu_selection || 'all',
        gpu_layers: Number(selectedValues.gpu_layers || 0),
        force_999: Boolean(selectedValues.force_999),
      };
    }

    const res = await fetch('/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    setStatus(data.message || 'Done.');

    // ── If this was main_plus_opencode, start the monitor ──
    if (target === 'main_plus_opencode' && data.status === 'launching') {
      startMonitoring();
      addMonitorLog(data.message, 'info');
      addMonitorLog(`Profile: ${data.profile || 'unknown'}`, 'info');
      addMonitorLog(`GPU layers: ${data.gpu_layers || '0'}`, 'info');
      addMonitorLog('', 'info'); // spacer
    }
  } catch (err) {
    setStatus(`Could not reach launcher API. Double-click entrance.bat and wait 2-3 seconds, then retry. Error: ${err.message}`);
    if (monitorPollId) {
      addMonitorLog(`ERROR: ${err.message}`, 'error');
      setMonitorPhase('error');
      clearInterval(monitorPollId);
      monitorPollId = null;
    }
  }
}

// ── Wire up buttons ──

buttons.forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});

gpuLayersSliderEl.addEventListener('input', () => {
  selectedValues.gpu_layers = Number(gpuLayersSliderEl.value || '0');
  gpuLayersValueEl.textContent = String(selectedValues.gpu_layers);
});

force999El.addEventListener('change', () => {
  selectedValues.force_999 = force999El.checked;
  gpuLayersSliderEl.disabled = selectedValues.force_999;
});

// ── Startup ──

loadTargetReadiness();
loadMainOptions();

// Show monitor section but collapsed
monitorSection.classList.remove('visible');
