import { jsonError } from '../../cloudflare/lib/http.js';

export async function onRequestPost() {
  return jsonError('Card-backed trials must be started through Stripe Checkout from the time.md app paywall.', 402);
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
