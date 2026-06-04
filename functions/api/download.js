import { jsonError, readEnv } from '../../cloudflare/lib/http.js';
import { isPaidCheckoutSession, retrieveCheckoutSession } from '../../cloudflare/lib/stripe.js';

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const sessionId = (url.searchParams.get('session_id') || '').trim();
  if (!sessionId || !sessionId.startsWith('cs_')) {
    return jsonError('Missing or invalid Checkout Session ID.', 400);
  }

  try {
    const session = await retrieveCheckoutSession(env, sessionId);
    if (!isPaidCheckoutSession(session)) {
      return jsonError('Payment is not verified.', 402);
    }

    const objectKey = readEnv(env, 'TIME_MD_RELEASE_OBJECT_KEY');
    if (env.RELEASE_BUCKET && objectKey) {
      const object = await env.RELEASE_BUCKET.get(objectKey);
      if (!object) return jsonError('Release object was not found in R2.', 404);

      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('etag', object.httpEtag);
      headers.set('content-type', headers.get('content-type') || 'application/zip');
      headers.set('content-disposition', `attachment; filename="${objectKey.split('/').pop()}"`);
      return new Response(object.body, { headers });
    }

    const fallbackUrl = readEnv(env, 'TIME_MD_DOWNLOAD_URL', 'https://github.com/codybontecou/time.md/releases/latest');
    return Response.redirect(fallbackUrl, 302);
  } catch (error) {
    console.error('Paid download error:', error);
    return jsonError(error.message || 'Unable to prepare download.', error.status || 500);
  }
}

export async function onRequestPost() {
  return jsonError('Method not allowed', 405);
}
