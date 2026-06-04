import { json, jsonError, readEnv } from '../../cloudflare/lib/http.js';
import { fulfillCheckoutSession } from '../../cloudflare/lib/fulfillment.js';
import { retrieveCheckoutSession, verifyStripeWebhookSignature } from '../../cloudflare/lib/stripe.js';

const FULFILLMENT_EVENTS = new Set([
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
]);

export async function onRequestPost({ request, env }) {
  const rawBody = await request.text();
  const webhookSecret = readEnv(env, 'STRIPE_WEBHOOK_SECRET');
  const allowUnverified = readEnv(env, 'ALLOW_UNVERIFIED_STRIPE_WEBHOOKS') === 'true';

  if (!webhookSecret && !allowUnverified) {
    return jsonError('STRIPE_WEBHOOK_SECRET is not configured.', 500);
  }

  if (webhookSecret) {
    const signatureHeader = request.headers.get('stripe-signature') || '';
    const valid = await verifyStripeWebhookSignature(rawBody, signatureHeader, webhookSecret);
    if (!valid) return jsonError('Invalid Stripe webhook signature.', 400);
  }

  let event;
  try {
    event = JSON.parse(rawBody);
  } catch (_) {
    return jsonError('Invalid Stripe webhook payload.', 400);
  }

  try {
    if (FULFILLMENT_EVENTS.has(event.type)) {
      const sessionId = event.data?.object?.id;
      if (!sessionId) return jsonError('Missing Checkout Session ID in webhook.', 400);

      const session = await retrieveCheckoutSession(env, sessionId);
      const fulfillment = await fulfillCheckoutSession(env, session, {
        includeActivationKey: false,
        sendEmail: true,
      });

      return json({
        received: true,
        fulfilled: true,
        session_id: sessionId,
        activation_key_preview: fulfillment.activationKeyPreview,
        email_status: fulfillment.emailResult.status,
      });
    }

    return json({ received: true, ignored: true, type: event.type });
  } catch (error) {
    console.error('Stripe webhook fulfillment error:', error);
    return jsonError(error.message || 'Unable to fulfill Stripe webhook.', error.status || 500);
  }
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
