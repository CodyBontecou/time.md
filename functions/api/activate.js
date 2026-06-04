import { json, jsonError, readJson, requireBinding } from '../../cloudflare/lib/http.js';
import { hashActivationKey, normalizeActivationKey, previewActivationKey, sha256Hex } from '../../cloudflare/lib/license.js';

function nowIso() {
  return new Date().toISOString();
}

export async function onRequestPost({ request, env }) {
  const body = await readJson(request);
  const activationKey = normalizeActivationKey(body.activation_key);

  if (!activationKey) {
    return jsonError('Missing activation key.', 400);
  }

  try {
    const db = requireBinding(env, 'DB', 'D1 DB');
    const keyHash = await hashActivationKey(activationKey);
    const license = await db
      .prepare(
        `SELECT licenses.*, orders.stripe_session_id
         FROM licenses
         JOIN orders ON orders.id = licenses.order_id
         WHERE licenses.activation_key_hash = ?
         LIMIT 1`,
      )
      .bind(keyHash)
      .first();

    if (!license || license.status !== 'active') {
      return json({ valid: false, status: license?.status || 'not_found' }, 404);
    }

    const deviceId = typeof body.device_id === 'string' ? body.device_id.trim() : '';
    const appVersion = typeof body.app_version === 'string' ? body.app_version.slice(0, 40) : '';
    const deviceHash = deviceId ? await sha256Hex(deviceId) : '';
    const timestamp = nowIso();

    if (deviceHash) {
      const existing = await db
        .prepare('SELECT id FROM activations WHERE license_id = ? AND device_hash = ? LIMIT 1')
        .bind(license.id, deviceHash)
        .first();

      if (existing) {
        await db
          .prepare('UPDATE activations SET last_seen_at = ?, app_version = ?, status = ? WHERE id = ?')
          .bind(timestamp, appVersion, 'active', existing.id)
          .run();
      } else {
        await db
          .prepare(
            `INSERT INTO activations (id, license_id, device_hash, app_version, activated_at, last_seen_at, status)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(crypto.randomUUID(), license.id, deviceHash, appVersion, timestamp, timestamp, 'active')
          .run();
      }
    }

    return json({
      valid: true,
      status: 'active',
      license_id: license.id,
      activation_key_preview: previewActivationKey(activationKey),
      stripe_session_id: license.stripe_session_id,
    });
  } catch (error) {
    console.error('Activation error:', error);
    return jsonError(error.message || 'Unable to validate activation key.', 500);
  }
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
