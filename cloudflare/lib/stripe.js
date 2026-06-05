import { readEnv } from './http.js';

const STRIPE_API_BASE = 'https://api.stripe.com/v1';
const encoder = new TextEncoder();

function toFormBody(params = {}) {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === '') continue;
    body.append(key, String(value));
  }
  return body;
}

function bytesToHex(bytes) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;

  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export async function stripeRequest(env, method, path, params = {}) {
  const secretKey = readEnv(env, 'STRIPE_SECRET_KEY');
  if (!secretKey) throw new Error('STRIPE_SECRET_KEY is not configured.');

  const upperMethod = method.toUpperCase();
  let url = `${STRIPE_API_BASE}${path}`;
  const init = {
    method: upperMethod,
    headers: {
      authorization: `Bearer ${secretKey}`,
    },
  };

  const formBody = toFormBody(params);
  if (upperMethod === 'GET') {
    const query = formBody.toString();
    if (query) url = `${url}?${query}`;
  } else {
    init.headers['content-type'] = 'application/x-www-form-urlencoded';
    init.body = formBody.toString();
  }

  const response = await fetch(url, init);
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};

  if (!response.ok) {
    const error = new Error(payload?.error?.message || `Stripe returned HTTP ${response.status}.`);
    error.status = response.status;
    error.stripe = payload?.error;
    throw error;
  }

  return payload;
}

function buildLineItemParams(env) {
  const priceId = readEnv(env, 'STRIPE_PRICE_ID');
  if (priceId) {
    return {
      'line_items[0][price]': priceId,
      'line_items[0][quantity]': 1,
    };
  }

  const amount = Number.parseInt(readEnv(env, 'STRIPE_UNIT_AMOUNT_CENTS', '1999'), 10);
  return {
    'line_items[0][price_data][currency]': readEnv(env, 'STRIPE_CURRENCY', 'usd') || 'usd',
    'line_items[0][price_data][unit_amount]': Number.isFinite(amount) && amount > 0 ? amount : 1999,
    'line_items[0][price_data][product_data][name]': readEnv(env, 'STRIPE_PRODUCT_NAME', 'time.md macOS Desktop License'),
    'line_items[0][price_data][product_data][description]': readEnv(
      env,
      'STRIPE_PRODUCT_DESCRIPTION',
      'One-time license for the local-only time.md macOS desktop application.',
    ),
    'line_items[0][price_data][product_data][metadata][app]': 'time.md',
    'line_items[0][price_data][product_data][metadata][platform]': 'macOS',
    'line_items[0][quantity]': 1,
  };
}

export async function createCheckoutSession(env, { origin, customerEmail, source = 'marketing-site' }) {
  return stripeRequest(env, 'POST', '/checkout/sessions', {
    mode: 'payment',
    success_url: `${origin}/success.html?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/cancel.html`,
    allow_promotion_codes: true,
    billing_address_collection: 'auto',
    customer_creation: 'always',
    customer_email: customerEmail,
    'automatic_tax[enabled]': readEnv(env, 'STRIPE_AUTOMATIC_TAX') === 'true',
    'metadata[app]': 'time.md',
    'metadata[product]': 'desktop-license',
    'metadata[source]': String(source).slice(0, 80),
    'payment_intent_data[metadata][app]': 'time.md',
    'payment_intent_data[metadata][product]': 'desktop-license',
    'custom_text[submit][message]': 'After payment, return to time.md to verify your order, receive your activation key, and download the macOS app.',
    ...buildLineItemParams(env),
  });
}

export function trialChargeAmount(env) {
  const amount = Number.parseInt(readEnv(env, 'STRIPE_UNIT_AMOUNT_CENTS', '1999'), 10);
  return Number.isFinite(amount) && amount > 0 ? amount : 1999;
}

export function trialChargeCurrency(env) {
  return readEnv(env, 'STRIPE_CURRENCY', 'usd') || 'usd';
}

export async function createTrialCheckoutSession(env, { origin, customerEmail, source = 'trial-portal', returnToApp = false }) {
  const trialDays = Number.parseInt(readEnv(env, 'TIME_MD_TRIAL_DAYS', '14'), 10) || 14;
  const amount = trialChargeAmount(env);
  const currency = trialChargeCurrency(env);
  const amountDisplay = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
  }).format(amount / 100);
  const successUrl = returnToApp
    ? `${origin}/trial-success.html?open_app=1&session_id={CHECKOUT_SESSION_ID}`
    : `${origin}/trial-success.html?session_id={CHECKOUT_SESSION_ID}`;

  return stripeRequest(env, 'POST', '/checkout/sessions', {
    mode: 'setup',
    currency,
    success_url: successUrl,
    cancel_url: `${origin}/cancel.html`,
    billing_address_collection: 'auto',
    customer_creation: 'always',
    customer_email: customerEmail,
    'metadata[app]': 'time.md',
    'metadata[product]': 'desktop-trial',
    'metadata[source]': String(source).slice(0, 80),
    'metadata[return_to_app]': returnToApp ? 'true' : 'false',
    'metadata[trial_days]': trialDays,
    'metadata[amount_total]': amount,
    'metadata[currency]': currency,
    'setup_intent_data[metadata][app]': 'time.md',
    'setup_intent_data[metadata][product]': 'desktop-trial',
    'setup_intent_data[metadata][trial_days]': trialDays,
    'setup_intent_data[metadata][amount_total]': amount,
    'setup_intent_data[metadata][currency]': currency,
    'custom_text[submit][message]': `Your card is stored securely by Stripe to activate the ${trialDays}-day time.md trial. You will not be charged today. Buy the ${amountDisplay} license if you want to keep using time.md after the trial.`,
  });
}

export async function retrieveCheckoutSession(env, sessionId, { expandLineItems = true } = {}) {
  return stripeRequest(
    env,
    'GET',
    `/checkout/sessions/${encodeURIComponent(sessionId)}`,
    expandLineItems ? { 'expand[]': 'line_items.data.price.product' } : {},
  );
}

export async function retrieveSetupIntent(env, setupIntentId) {
  return stripeRequest(env, 'GET', `/setup_intents/${encodeURIComponent(setupIntentId)}`);
}

export function isPaidCheckoutSession(session) {
  return session?.payment_status === 'paid' || session?.status === 'complete';
}

export function getCheckoutEmail(session) {
  return session?.customer_details?.email || session?.customer_email || '';
}

export async function verifyStripeWebhookSignature(rawBody, signatureHeader, webhookSecret, toleranceSeconds = 300) {
  if (!signatureHeader) return false;

  const parts = Object.fromEntries(
    signatureHeader.split(',').map((part) => {
      const [key, value] = part.split('=');
      return [key, value];
    }),
  );
  const timestamp = parts.t;
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (Number.isFinite(age) && age > toleranceSeconds) return false;

  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(webhookSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signedPayload = `${timestamp}.${rawBody}`;
  const digest = await crypto.subtle.sign('HMAC', key, encoder.encode(signedPayload));
  const expected = bytesToHex(new Uint8Array(digest));

  return timingSafeEqual(expected, signature);
}
