import { getRequestOrigin, json, jsonError, readEnv } from '../../cloudflare/lib/http.js';
import { generateTrialToken, hashTrialToken, previewTrialToken } from '../../cloudflare/lib/license.js';
import { retrieveCheckoutSession, retrieveSetupIntent, trialChargeAmount, trialChargeCurrency } from '../../cloudflare/lib/stripe.js';

function nowIso() {
  return new Date().toISOString();
}

function trialDays(env) {
  const configured = Number.parseInt(readEnv(env, 'TIME_MD_TRIAL_DAYS', '14'), 10);
  return Number.isFinite(configured) && configured > 0 ? configured : 14;
}

function formatAmount(amount, currency) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency || 'USD',
  }).format(amount / 100);
}

function trialResponse(row, origin) {
  return {
    valid: true,
    status: row.status,
    trial_id: row.id,
    trial_token: row.trial_token,
    trial_token_preview: row.trial_token_preview,
    started_at: row.started_at,
    expires_at: row.expires_at,
    customer_email: row.customer_email || '',
    amount_total: row.amount_total || 1999,
    amount_display: formatAmount(row.amount_total || 1999, row.currency || 'usd'),
    currency: row.currency || 'usd',
    session_id: row.stripe_session_id || '',
    download_url: `${origin.replace(/\/$/, '')}/api/download-trial`,
  };
}

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const sessionId = (url.searchParams.get('session_id') || '').trim();
  if (!sessionId || !sessionId.startsWith('cs_')) {
    return jsonError('Missing or invalid Checkout Session ID.', 400);
  }

  try {
    if (!env.DB) throw new Error('D1 DB binding is not configured.');

    const existing = await env.DB.prepare('SELECT * FROM trials WHERE stripe_session_id = ? LIMIT 1').bind(sessionId).first();
    if (existing) {
      return json(trialResponse(existing, getRequestOrigin(request, env)));
    }

    const session = await retrieveCheckoutSession(env, sessionId, { expandLineItems: false });
    if (session.mode !== 'setup' || session.status !== 'complete') {
      return json(
        {
          valid: false,
          status: session.status || 'not_complete',
          error: 'Trial card setup is not complete yet.',
        },
        402,
      );
    }

    const setupIntentId = typeof session.setup_intent === 'string' ? session.setup_intent : session.setup_intent?.id;
    if (!setupIntentId) {
      return jsonError('Trial Checkout Session did not include a SetupIntent.', 422);
    }

    const setupIntent = await retrieveSetupIntent(env, setupIntentId);
    if (setupIntent.status !== 'succeeded') {
      return json(
        {
          valid: false,
          status: setupIntent.status || 'setup_incomplete',
          error: 'Card setup is not complete yet.',
        },
        402,
      );
    }

    const customerId = typeof session.customer === 'string' ? session.customer : setupIntent.customer;
    const paymentMethodId = typeof setupIntent.payment_method === 'string' ? setupIntent.payment_method : setupIntent.payment_method?.id;
    if (!customerId || !paymentMethodId) {
      return jsonError('Stripe did not return a reusable customer/payment method for this trial.', 422);
    }

    const startedAt = new Date();
    const expiresAt = new Date(startedAt.getTime() + trialDays(env) * 24 * 60 * 60 * 1000);
    const trialToken = generateTrialToken();
    const tokenHash = await hashTrialToken(trialToken);
    const trialId = crypto.randomUUID();
    const row = {
      id: trialId,
      trial_token: trialToken,
      trial_token_hash: tokenHash,
      trial_token_preview: previewTrialToken(trialToken),
      device_hash: `pending:${trialId}`,
      status: 'trialing',
      started_at: startedAt.toISOString(),
      expires_at: expiresAt.toISOString(),
      last_seen_at: nowIso(),
      app_version: '',
      stripe_session_id: session.id,
      stripe_setup_intent_id: setupIntent.id,
      stripe_customer_id: customerId,
      stripe_payment_method_id: paymentMethodId,
      customer_email: session.customer_details?.email || session.customer_email || '',
      amount_total: trialChargeAmount(env),
      currency: trialChargeCurrency(env),
    };

    await env.DB
      .prepare(
        `INSERT INTO trials (
          id, trial_token, trial_token_hash, trial_token_preview, device_hash, status,
          started_at, expires_at, last_seen_at, app_version, stripe_session_id,
          stripe_setup_intent_id, stripe_customer_id, stripe_payment_method_id,
          customer_email, amount_total, currency
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        row.id,
        row.trial_token,
        row.trial_token_hash,
        row.trial_token_preview,
        row.device_hash,
        row.status,
        row.started_at,
        row.expires_at,
        row.last_seen_at,
        row.app_version,
        row.stripe_session_id,
        row.stripe_setup_intent_id,
        row.stripe_customer_id,
        row.stripe_payment_method_id,
        row.customer_email,
        row.amount_total,
        row.currency,
      )
      .run();

    return json(trialResponse(row, getRequestOrigin(request, env)), 201);
  } catch (error) {
    console.error('Trial Checkout verification error:', error);
    return jsonError(error.message || 'Unable to verify trial Checkout session.', error.status || 500);
  }
}

export async function onRequestPost() {
  return jsonError('Method not allowed', 405);
}
