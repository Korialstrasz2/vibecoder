const statusEl = document.getElementById('status');
const buttons = Array.from(document.querySelectorAll('button[data-target]'));

function setStatus(message) {
  statusEl.textContent = message;
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

async function launch(target) {
  setStatus(`Starting ${target}...`);
  try {
    const res = await fetch('/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target })
    });

    const data = await res.json();
    setStatus(data.message || 'Done.');
  } catch (err) {
    setStatus(`Could not reach launcher API. Double-click entrance.bat and wait 2-3 seconds, then retry. Error: ${err.message}`);
  }
}

buttons.forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});

loadTargetReadiness();
