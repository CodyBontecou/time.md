(() => {
  const params = new URLSearchParams(window.location.search);
  const sessionId = params.get('session_id') || '';

  const statusEl = document.querySelector('[data-verification-status]');
  const pulseEl = document.querySelector('[data-status-pulse]');
  const amountEl = document.querySelector('[data-receipt-amount]');
  const emailEl = document.querySelector('[data-receipt-email]');
  const sessionEl = document.querySelector('[data-receipt-session]');
  const licenseEl = document.querySelector('[data-receipt-license]');
  const copyLicenseButton = document.querySelector('[data-copy-license]');
  const downloadLink = document.querySelector('[data-download-link]');
  let activationKey = '';

  const setState = (state, message) => {
    if (statusEl) statusEl.textContent = message;
    if (pulseEl) {
      pulseEl.classList.toggle('is-ready', state === 'ready');
      pulseEl.classList.toggle('is-error', state === 'error');
    }
  };

  const setDownloadDisabled = (disabled, label) => {
    if (!downloadLink) return;
    downloadLink.textContent = label;
    downloadLink.setAttribute('aria-disabled', disabled ? 'true' : 'false');
    downloadLink.classList.toggle('is-ready', !disabled);
  };

  const shortSession = (value) => {
    if (!value) return '—';
    return value.length > 18 ? `${value.slice(0, 12)}…${value.slice(-6)}` : value;
  };

  const verify = async () => {
    if (sessionEl) sessionEl.textContent = shortSession(sessionId);

    if (!sessionId) {
      setState('error', 'Missing Stripe Checkout session.');
      if (licenseEl) licenseEl.textContent = 'Not available';
      setDownloadDisabled(true, 'PAYMENT NOT VERIFIED');
      return;
    }

    try {
      const response = await fetch(`/api/verify-checkout-session?session_id=${encodeURIComponent(sessionId)}`);
      const payload = await response.json().catch(() => ({}));

      if (!response.ok || !payload.paid) {
        throw new Error(payload.error || 'Payment is not verified yet.');
      }

      activationKey = payload.activation_key || '';
      if (amountEl) amountEl.textContent = payload.amount_display || '$19.99';
      if (emailEl) emailEl.textContent = payload.customer_email || 'See Stripe receipt';
      if (sessionEl) sessionEl.textContent = shortSession(payload.session_id || sessionId);
      if (licenseEl) licenseEl.textContent = activationKey || payload.activation_key_preview || 'Sent by email';
      if (copyLicenseButton) copyLicenseButton.disabled = !activationKey;

      if (downloadLink) {
        downloadLink.href = payload.download_url;
        downloadLink.target = '_blank';
        downloadLink.rel = 'noopener';
      }
      const emailNote = payload.email_status === 'sent' ? ' License email sent.' : '';
      setState('ready', `Payment verified. Download unlocked.${emailNote}`);
      setDownloadDisabled(false, 'DOWNLOAD TIME.MD FOR macOS');
    } catch (error) {
      setState('error', error.message);
      if (licenseEl) licenseEl.textContent = 'Not available';
      setDownloadDisabled(true, 'PAYMENT NOT VERIFIED');
    }
  };

  if (copyLicenseButton) {
    copyLicenseButton.addEventListener('click', async () => {
      if (!activationKey) return;
      await navigator.clipboard.writeText(activationKey);
      copyLicenseButton.textContent = 'ACTIVATION KEY COPIED';
      setTimeout(() => { copyLicenseButton.textContent = 'COPY ACTIVATION KEY'; }, 1800);
    });
  }

  verify();
})();
