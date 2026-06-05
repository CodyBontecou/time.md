import { readEnv } from './http.js';

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function parseEmailAddress(value) {
  const trimmed = String(value || '').trim();
  const match = trimmed.match(/^(.+?)\s*<([^>]+)>$/);
  if (match) {
    return {
      name: match[1].trim().replace(/^['"]|['"]$/g, ''),
      address: match[2].trim(),
    };
  }

  return trimmed;
}

export async function sendLicenseEmail(env, { to, activationKey, downloadUrl, sessionId }) {
  const apiToken = readEnv(env, 'CLOUDFLARE_EMAIL_API_TOKEN') || readEnv(env, 'CLOUDFLARE_API_TOKEN');
  const accountId = readEnv(env, 'CLOUDFLARE_ACCOUNT_ID');
  const from = parseEmailAddress(readEnv(env, 'FROM_EMAIL', 'cody@isolated.tech'));
  const supportEmail = readEnv(env, 'SUPPORT_EMAIL', 'cody@isolated.tech');

  if (!apiToken || !accountId) {
    return {
      status: 'skipped',
      provider: 'cloudflare-email',
      reason: 'CLOUDFLARE_EMAIL_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are required for Cloudflare Email Service REST sending.',
    };
  }

  const subject = 'Your time.md desktop license';
  const text = [
    'Thanks for buying time.md.',
    '',
    'Activation key:',
    activationKey,
    '',
    'Open the app and paste this key on first launch to activate this Mac.',
    '',
    'Download:',
    downloadUrl,
    '',
    `Stripe Checkout Session: ${sessionId}`,
    `Support: ${supportEmail}`,
  ].join('\n');

  const html = `
    <div style="font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; color: #141416; line-height: 1.55;">
      <p>Thanks for buying <strong>time.md</strong>.</p>
      <p>Your activation key:</p>
      <pre style="padding: 16px; background: #EBF2FA; border: 1px solid rgba(0,0,0,.14); font-size: 16px; letter-spacing: 1px; white-space: pre-wrap;">${escapeHtml(activationKey)}</pre>
      <p>Open the app and paste this key on first launch to activate this Mac.</p>
      <p><a href="${escapeHtml(downloadUrl)}" style="color: #3885E6; font-weight: 700;">Download time.md for macOS</a></p>
      <p style="color: #5A6168; font-size: 12px;">Stripe Checkout Session: ${escapeHtml(sessionId)}</p>
      <p style="color: #5A6168; font-size: 12px;">Need help? Reply here or email <a href="mailto:${escapeHtml(supportEmail)}">${escapeHtml(supportEmail)}</a>.</p>
    </div>
  `;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/email/sending/send`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${apiToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      to,
      from,
      reply_to: supportEmail,
      subject,
      text,
      html,
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.success === false) {
    const message = payload.errors?.[0]?.message || payload.message || `Cloudflare Email Service returned HTTP ${response.status}.`;
    return {
      status: 'failed',
      provider: 'cloudflare-email',
      reason: message,
    };
  }

  return {
    status: 'sent',
    provider: 'cloudflare-email',
    provider_message_id: payload.result?.message_id || payload.result?.messageId || payload.result?.id || '',
  };
}
