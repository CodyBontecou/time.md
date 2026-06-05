import { jsonError, readEnv } from '../../cloudflare/lib/http.js';

export async function onRequestGet({ env }) {
  try {
    const configuredDownloadUrl = readEnv(env, 'TIME_MD_DOWNLOAD_URL');
    if (configuredDownloadUrl) {
      return Response.redirect(configuredDownloadUrl, 302);
    }

    const objectKey = readEnv(env, 'TIME_MD_RELEASE_OBJECT_KEY', 'time.md-latest-macOS.zip');
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
    console.error('Trial download error:', error);
    return jsonError(error.message || 'Unable to prepare trial download.', error.status || 500);
  }
}

export async function onRequestPost() {
  return jsonError('Method not allowed', 405);
}
