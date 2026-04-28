const statusEl = document.getElementById('status');

async function launch(target) {
  statusEl.textContent = `Starting ${target}...`;
  try {
    const res = await fetch('/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target })
    });

    const data = await res.json();
    statusEl.textContent = data.message || 'Done.';
  } catch (err) {
    statusEl.textContent = `Could not reach launcher API. Double-click entrance.bat and wait 2-3 seconds, then retry. Error: ${err.message}`;
  }
}

document.querySelectorAll('button[data-target]').forEach((btn) => {
  btn.addEventListener('click', () => launch(btn.dataset.target));
});
