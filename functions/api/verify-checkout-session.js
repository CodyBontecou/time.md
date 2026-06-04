import { getRequestOrigin, json, jsonError } from '../../cloudflare/lib/http.js';
import { getCheckoutEmail, isPaidCheckoutSession, retrieveCheckoutSession } from '../../cloudflare/lib/stripe.js';
import { fulfillCheckoutSession } from '../../cloudflare/lib/fulfillment.js';

function formatAmount(amount, currency) {
  if (typeof amount !== 'number') return '';

  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency || 'USD',
  }).format(amount / 100);
}

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const sessionId = (url.searchParams.get('session_id') || '').trim();
  if (!sessionId || !sessionId.startsWith('cs_')) {
    return jsonError('Missing or invalid Checkout Session ID.', 400);
  }

  try {
    const session = await retrieveCheckoutSession(env, sessionId);
    const paid = isPaidCheckoutSession(session);

    if (!paid) {
      return json(
        {
          paid: false,
          payment_status: session.payment_status,
          status: session.status,
          error: 'Checkout session has not been paid yet.',
        },
        402,
      );
    }

    const fulfillment = await fulfillCheckoutSession(env, session, {
      includeActivationKey: true,
      sendEmail: true,
      origin: getRequestOrigin(request, env),
    });

    return json({
      paid: true,
      session_id: session.id,
      customer_email: getCheckoutEmail(session),
      amount_total: session.amount_total,
      amount_display: formatAmount(session.amount_total, session.currency),
      currency: session.currency,
      payment_status: session.payment_status,
      activation_key: fulfillment.activationKey,
      activation_key_preview: fulfillment.activationKeyPreview,
      email_status: fulfillment.emailResult.status,
      email_error: fulfillment.emailResult.reason || '',
      download_url: fulfillment.downloadUrl,
    });
  } catch (error) {
    console.error('Cloudflare Stripe Checkout verification error:', error);
    return jsonError(error.message || 'Unable to verify Stripe Checkout session.', error.status || 500);
  }
}

export async function onRequestPost() {
  return jsonError('Method not allowed', 405);
}
