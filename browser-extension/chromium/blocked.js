const params = new URLSearchParams(location.search);
const domain = params.get('domain') || 'This site';
let remaining = Number(params.get('remaining') || '0');

const domainEl = document.getElementById('domain');
const timerEl = document.getElementById('timer');
domainEl.textContent = domain;

defaultRender();
const interval = setInterval(() => {
  remaining = Math.max(0, remaining - 1);
  defaultRender();
  if (remaining <= 0) clearInterval(interval);
}, 1000);

function defaultRender() {
  if (remaining <= 0) {
    timerEl.textContent = 'Unlocked — refresh the original tab to continue.';
    return;
  }
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  timerEl.textContent = `${minutes}:${String(seconds).padStart(2, '0')} remaining`;
}
