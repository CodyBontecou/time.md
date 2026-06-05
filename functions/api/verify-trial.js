import { json, jsonError, readJson, requireBinding } from '../../cloudflare/lib/http.js';
import { hashTrialToken, normalizeTrialToken, sha256Hex } from '../../cloudflare/lib/license.js';

function nowIso() {
  return new Date().toISOString();
}

function isExpired(row, now = new Date()) {
  return new Date(row.expires_at).getTime() <= now.getTime();
}

function trialResponse(row, valid = true, status = row.status) {
  return {
    valid,
    status,
    trial_id: row.id,
    trial_token_preview: row.trial_token_preview,
    started_at: row.started_at,
    expires_at: row.expires_at,
  };
}

export async function onRequestPost({ request, env }) {
  const body = await readJson(request);
  const trialToken = normalizeTrialToken(body.trial_token);
  const deviceId = typeof body.device_id === 'string' ? body.device_id.trim() : '';
  const appVersion = typeof body.app_version === 'string' ? body.app_version.slice(0, 40) : '';

  if (!trialToken) {
    return jsonError('Missing trial token.', 400);
  }

  if (!deviceId) {
    return jsonError('Missing device ID.', 400);
  }

  try {
    const db = requireBinding(env, 'DB', 'D1 DB');
    const tokenHash = await hashTrialToken(trialToken);
    const deviceHash = await sha256Hex(deviceId);
    const trial = await db.prepare('SELECT * FROM trials WHERE trial_token_hash = ? LIMIT 1').bind(tokenHash).first();

    if (!trial) {
      return json({ valid: false, status: 'not_found' }, 404);
    }

    const timestamp = nowIso();
    if (String(trial.device_hash || '').startsWith('pending:')) {
      const existingDeviceTrial = await db
        .prepare('SELECT id, status FROM trials WHERE device_hash = ? AND id != ? LIMIT 1')
        .bind(deviceHash, trial.id)
        .first();

      if (existingDeviceTrial) {
        return json(trialResponse(trial, false, 'device_already_trialed'), 403);
      }

      await db
        .prepare('UPDATE trials SET device_hash = ?, last_seen_at = ?, app_version = ? WHERE id = ?')
        .bind(deviceHash, timestamp, appVersion, trial.id)
        .run();
      trial.device_hash = deviceHash;
    }

    if (trial.device_hash !== deviceHash) {
      return json(trialResponse(trial, false, 'device_mismatch'), 403);
    }

    if (trial.status === 'converted' || trial.status === 'active') {
      await db
        .prepare('UPDATE trials SET last_seen_at = ?, app_version = ? WHERE id = ?')
        .bind(timestamp, appVersion, trial.id)
        .run();
      return json(trialResponse({ ...trial, last_seen_at: timestamp, app_version: appVersion }, true, trial.status));
    }

    if (trial.status !== 'trialing') {
      await db
        .prepare('UPDATE trials SET last_seen_at = ?, app_version = ? WHERE id = ?')
        .bind(timestamp, appVersion, trial.id)
        .run();
      return json(trialResponse({ ...trial, last_seen_at: timestamp, app_version: appVersion }, false, trial.status), trial.status === 'expired' ? 410 : 403);
    }

    if (isExpired(trial)) {
      await db
        .prepare('UPDATE trials SET status = ?, last_seen_at = ?, app_version = ? WHERE id = ?')
        .bind('expired', timestamp, appVersion, trial.id)
        .run();
      return json(trialResponse({ ...trial, status: 'expired', last_seen_at: timestamp, app_version: appVersion }, false, 'expired'), 410);
    }

    await db
      .prepare('UPDATE trials SET last_seen_at = ?, app_version = ? WHERE id = ?')
      .bind(timestamp, appVersion, trial.id)
      .run();

    return json(trialResponse({ ...trial, last_seen_at: timestamp, app_version: appVersion }));
  } catch (error) {
    console.error('Verify trial error:', error);
    return jsonError(error.message || 'Unable to verify trial.', 500);
  }
}

export async function onRequestGet() {
  return jsonError('Method not allowed', 405);
}
