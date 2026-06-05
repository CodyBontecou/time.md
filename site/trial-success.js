(() => {
  const params = new URLSearchParams(window.location.search);
  const sessionId = params.get('session_id') || '';

  const statusEl = document.querySelector('[data-verification-status]');
  const pulseEl = document.querySelector('[data-status-pulse]');
  const amountEl = document.querySelector('[data-receipt-amount]');
  const emailEl = document.querySelector('[data-receipt-email]');
  const sessionEl = document.querySelector('[data-receipt-session]');
  const trialKeyEl = document.querySelector('[data-receipt-trial-key]');
  const copyTrialKeyButton = document.querySelector('[data-copy-trial-key]');
  const openAppLink = document.querySelector('[data-open-app-link]');
  const downloadLink = document.querySelector('[data-download-link]');
  const shouldOpenApp = params.get('open_app') === '1';
  let trialKey = '';
  let appDeepLink = '';

  const setState = (state, message) => {
    if (statusEl) statusEl.textContent = message;
    if (pulseEl) {
      pulseEl.classList.toggle('is-ready', state === 'ready');
      pulseEl.classList.toggle('is-error', state === 'error');
    }
  };

  const setLinkDisabled = (link, disabled, label) => {
    if (!link) return;
    link.textContent = label;
    link.setAttribute('aria-disabled', disabled ? 'true' : 'false');
    link.classList.toggle('is-ready', !disabled);
  };

  const openApp = () => {
    if (!appDeepLink) return;
    window.location.assign(appDeepLink);
  };

  const shortSession = (value) => {
    if (!value) return '—';
    return value.length > 18 ? `${value.slice(0, 12)}…${value.slice(-6)}` : value;
  };

  const verify = async () => {
    if (sessionEl) sessionEl.textContent = shortSession(sessionId);

    if (!sessionId) {
      setState('error', 'Missing Stripe Checkout session.');
      if (trialKeyEl) trialKeyEl.textContent = 'Not available';
      setLinkDisabled(openAppLink, true, 'TRIAL NOT VERIFIED');
      setLinkDisabled(downloadLink, true, 'DOWNLOAD APP AGAIN');
      return;
    }

    try {
      const response = await fetch(`/api/verify-trial-checkout-session?session_id=${encodeURIComponent(sessionId)}`);
      const payload = await response.json().catch(() => ({}));

      if (!response.ok || !payload.valid) {
        throw new Error(payload.error || 'Trial card setup is not verified yet.');
      }

      trialKey = payload.trial_token || '';
      if (amountEl) amountEl.textContent = payload.amount_display || '$19.99';
      if (emailEl) emailEl.textContent = payload.customer_email || 'See Stripe receipt';
      if (sessionEl) sessionEl.textContent = shortSession(payload.session_id || sessionId);
      if (trialKeyEl) trialKeyEl.textContent = trialKey || payload.trial_token_preview || 'Not available';
      if (copyTrialKeyButton) copyTrialKeyButton.disabled = !trialKey;

      appDeepLink = `timemd://activate-trial?session_id=${encodeURIComponent(payload.session_id || sessionId)}`;
      if (openAppLink) {
        openAppLink.href = appDeepLink;
      }
      if (downloadLink) {
        downloadLink.href = payload.download_url || '/api/download-trial';
        downloadLink.target = '_blank';
        downloadLink.rel = 'noopener';
      }
      setState('ready', shouldOpenApp ? 'Card setup verified. Opening time.md…' : 'Card setup verified. Return to time.md to activate.');
      setLinkDisabled(openAppLink, false, 'OPEN TIME.MD TO ACTIVATE');
      setLinkDisabled(downloadLink, false, 'DOWNLOAD APP AGAIN');
      if (shouldOpenApp) {
        setTimeout(openApp, 500);
      }
    } catch (error) {
      setState('error', error.message);
      if (trialKeyEl) trialKeyEl.textContent = 'Not available';
      setLinkDisabled(openAppLink, true, 'TRIAL NOT VERIFIED');
      setLinkDisabled(downloadLink, true, 'DOWNLOAD APP AGAIN');
    }
  };

  if (openAppLink) {
    openAppLink.addEventListener('click', (event) => {
      event.preventDefault();
      if (!appDeepLink) return;
      openApp();
    });
  }

  if (copyTrialKeyButton) {
    copyTrialKeyButton.addEventListener('click', async () => {
      if (!trialKey) return;
      await navigator.clipboard.writeText(trialKey);
      copyTrialKeyButton.textContent = 'TRIAL KEY COPIED';
      setTimeout(() => { copyTrialKeyButton.textContent = 'COPY TRIAL KEY'; }, 1800);
    });
  }

  verify();
})();
