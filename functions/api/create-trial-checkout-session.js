import { getRequestOrigin, isLikelyEmail, json, jsonError, readJson } from '../../cloudflare/lib/http.js';
import { createTrialCheckoutSession } from '../../cloudflare/lib/stripe.js';

export async function onRequestPost({ request, env }) {
  try {
    const body = await readJson(request);
    const origin = getRequestOrigin(request, env);
    const customerEmail = isLikelyEmail(body.email) ? body.email.trim() : undefined;
    const session = await createTrialCheckoutSession(env, {
      origin,
      customerEmail,
      source: typeof body.source === 'string' ? body.source : 'time.md trial portal',
      returnToApp: body.return_to_app === true,
    });

    return json({ url: session.url, id: session.id });
  } catch (error) {
    console.error('Cloudflare Stripe trial Checkout session error:', error);
    return jsonError(error.message || 'Unable to create trial Checkout session.', error.status || 500);
  }
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
