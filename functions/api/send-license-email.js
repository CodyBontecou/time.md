import { getRequestOrigin, json, jsonError, readJson } from '../../cloudflare/lib/http.js';
import { retrieveCheckoutSession } from '../../cloudflare/lib/stripe.js';
import { fulfillCheckoutSession } from '../../cloudflare/lib/fulfillment.js';

export async function onRequestPost({ request, env }) {
  const body = await readJson(request);
  const sessionId = String(body.session_id || '').trim();
  if (!sessionId || !sessionId.startsWith('cs_')) {
    return jsonError('Missing or invalid Checkout Session ID.', 400);
  }

  try {
    const session = await retrieveCheckoutSession(env, sessionId);
    const fulfillment = await fulfillCheckoutSession(env, session, {
      includeActivationKey: false,
      sendEmail: true,
      forceEmail: true,
      origin: getRequestOrigin(request, env),
    });

    return json({
      sent: fulfillment.emailResult.status === 'sent',
      email_status: fulfillment.emailResult.status,
      email_error: fulfillment.emailResult.reason || '',
      activation_key_preview: fulfillment.activationKeyPreview,
    });
  } catch (error) {
    console.error('License email send error:', error);
    return jsonError(error.message || 'Unable to send license email again.', error.status || 500);
  }
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
