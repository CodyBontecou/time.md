import { readEnv, requireBinding } from './http.js';
import { getCheckoutEmail, isPaidCheckoutSession } from './stripe.js';
import { generateActivationKey, hashActivationKey, previewActivationKey } from './license.js';
import { sendLicenseEmail } from './email.js';

function nowIso() {
  return new Date().toISOString();
}

export function buildDownloadUrl(env, sessionId, origin = '') {
  const baseUrl = (origin || readEnv(env, 'SITE_URL')).replace(/\/$/, '');
  if (baseUrl && sessionId) {
    return `${baseUrl}/api/download?session_id=${encodeURIComponent(sessionId)}`;
  }

  return readEnv(env, 'TIME_MD_DOWNLOAD_URL', 'https://github.com/codybontecou/time.md/releases/latest');
}

async function upsertOrder(db, session) {
  const existing = await db
    .prepare('SELECT * FROM orders WHERE stripe_session_id = ? LIMIT 1')
    .bind(session.id)
    .first();

  const email = getCheckoutEmail(session);
  const updatedAt = nowIso();
  const order = {
    id: existing?.id || crypto.randomUUID(),
    stripe_session_id: session.id,
    stripe_payment_intent_id: typeof session.payment_intent === 'string' ? session.payment_intent : '',
    customer_email: email,
    amount_total: session.amount_total || 0,
    currency: session.currency || 'usd',
    status: session.payment_status || session.status || 'unknown',
    created_at: existing?.created_at || updatedAt,
    updated_at: updatedAt,
  };

  if (existing) {
    await db
      .prepare(
        `UPDATE orders
         SET stripe_payment_intent_id = ?, customer_email = ?, amount_total = ?, currency = ?, status = ?, updated_at = ?
         WHERE id = ?`,
      )
      .bind(
        order.stripe_payment_intent_id,
        order.customer_email,
        order.amount_total,
        order.currency,
        order.status,
        order.updated_at,
        order.id,
      )
      .run();
  } else {
    await db
      .prepare(
        `INSERT INTO orders (id, stripe_session_id, stripe_payment_intent_id, customer_email, amount_total, currency, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        order.id,
        order.stripe_session_id,
        order.stripe_payment_intent_id,
        order.customer_email,
        order.amount_total,
        order.currency,
        order.status,
        order.created_at,
        order.updated_at,
      )
      .run();
  }

  return order;
}

async function getOrCreateLicense(db, order) {
  const existing = await db
    .prepare("SELECT * FROM licenses WHERE order_id = ? AND status = 'active' ORDER BY issued_at DESC LIMIT 1")
    .bind(order.id)
    .first();

  if (existing) {
    return { license: existing, activationKey: existing.activation_key, newlyIssued: false };
  }

  const activationKey = generateActivationKey();
  const hash = await hashActivationKey(activationKey);
  const issuedAt = nowIso();
  const license = {
    id: crypto.randomUUID(),
    order_id: order.id,
    activation_key: activationKey,
    activation_key_hash: hash,
    activation_key_preview: previewActivationKey(activationKey),
    customer_email: order.customer_email,
    status: 'active',
    issued_at: issuedAt,
    revoked_at: null,
  };

  await db
    .prepare(
      `INSERT INTO licenses (id, order_id, activation_key, activation_key_hash, activation_key_preview, customer_email, status, issued_at, revoked_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      license.id,
      license.order_id,
      license.activation_key,
      license.activation_key_hash,
      license.activation_key_preview,
      license.customer_email,
      license.status,
      license.issued_at,
      license.revoked_at,
    )
    .run();

  return { license, activationKey, newlyIssued: true };
}

async function hasSentLicenseEmail(db, orderId) {
  const row = await db
    .prepare("SELECT id FROM email_events WHERE order_id = ? AND type = 'license' AND status = 'sent' LIMIT 1")
    .bind(orderId)
    .first();
  return Boolean(row);
}

async function recordEmailEvent(db, orderId, emailResult) {
  await db
    .prepare(
      `INSERT INTO email_events (id, order_id, provider, provider_message_id, type, status, detail, sent_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      crypto.randomUUID(),
      orderId,
      emailResult.provider || 'cloudflare-email',
      emailResult.provider_message_id || '',
      'license',
      emailResult.status || 'unknown',
      emailResult.reason || '',
      nowIso(),
    )
    .run();
}

export async function fulfillCheckoutSession(env, session, options = {}) {
  if (!isPaidCheckoutSession(session)) {
    throw new Error('Checkout session has not been paid yet.');
  }

  const db = requireBinding(env, 'DB', 'D1 DB');
  const order = await upsertOrder(db, session);
  const { license, activationKey, newlyIssued } = await getOrCreateLicense(db, order);

  const priorSent = await hasSentLicenseEmail(db, order.id);
  const shouldSendEmail = options.sendEmail !== false && (newlyIssued || options.forceEmail || !priorSent);
  let emailResult = { status: 'not_sent', provider: 'cloudflare-email' };

  if (shouldSendEmail && order.customer_email) {
    emailResult = await sendLicenseEmail(env, {
      to: order.customer_email,
      activationKey,
      downloadUrl: buildDownloadUrl(env, session.id, options.origin),
      sessionId: session.id,
    });
    await recordEmailEvent(db, order.id, emailResult);
  }

  return {
    order,
    license,
    activationKey: options.includeActivationKey ? activationKey : undefined,
    activationKeyPreview: license.activation_key_preview,
    newlyIssued,
    emailResult,
    downloadUrl: buildDownloadUrl(env, session.id, options.origin),
  };
}
