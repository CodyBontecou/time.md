const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const encoder = new TextEncoder();

function bytesToHex(bytes) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomGroup(length = 4) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => ALPHABET[byte % ALPHABET.length]).join('');
}

export function generateActivationKey() {
  return ['TMD', randomGroup(), randomGroup(), randomGroup(), randomGroup(), randomGroup()].join('-');
}

export function generateTrialToken() {
  return ['TMDTRIAL', randomGroup(6), randomGroup(6), randomGroup(6), randomGroup(6)].join('-');
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export async function hashActivationKey(activationKey) {
  return sha256Hex(activationKey.trim().toUpperCase());
}

export async function hashTrialToken(trialToken) {
  return sha256Hex(trialToken.trim().toUpperCase());
}

export function normalizeActivationKey(activationKey) {
  return String(activationKey || '').trim().toUpperCase();
}

export function normalizeTrialToken(trialToken) {
  return String(trialToken || '').trim().toUpperCase();
}

export function previewActivationKey(activationKey) {
  const normalized = normalizeActivationKey(activationKey);
  if (normalized.length <= 14) return normalized;
  return `${normalized.slice(0, 8)}…${normalized.slice(-4)}`;
}

export function previewTrialToken(trialToken) {
  const normalized = normalizeTrialToken(trialToken);
  if (normalized.length <= 14) return normalized;
  return `${normalized.slice(0, 8)}…${normalized.slice(-4)}`;
}
