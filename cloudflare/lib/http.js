export function readEnv(env, name, fallback = '') {
  const value = env?.[name];
  if (typeof value === 'string') return value.trim();
  return value ?? fallback;
}

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    },
  });
}

export function jsonError(message, status = 500, details = undefined) {
  return json(
    {
      error: message,
      ...(details ? { details } : {}),
    },
    status,
  );
}

export async function readJson(request) {
  const text = await request.text();
  if (!text) return {};

  try {
    return JSON.parse(text);
  } catch (_) {
    return {};
  }
}

export function getRequestOrigin(request, env) {
  const configuredUrl = readEnv(env, 'SITE_URL');
  if (configuredUrl) return configuredUrl.replace(/\/$/, '');

  const url = new URL(request.url);
  return url.origin;
}

export function requireBinding(env, name, label = name) {
  if (!env?.[name]) {
    throw new Error(`${label} binding is not configured.`);
  }

  return env[name];
}

export function isLikelyEmail(value) {
  return typeof value === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}
