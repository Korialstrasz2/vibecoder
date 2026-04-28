const statusEl = document.getElementById('status');

async function launch(target) {
  statusEl.textContent = `Starting ${target}...`;
  try {
    const res = await fetch('http://127.0.0.1:8765/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target })
    });

    const data = await res.json();
    statusEl.textContent = data.message || 'Done.';
  } catch (err) {
    statusEl.textContent = `Could not reach launcher.py (${err.message}). Start it first: python launcher.py`;
  }
}

document.querySelectorAll('button[data-target]').forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});
