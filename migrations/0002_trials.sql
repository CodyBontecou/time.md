CREATE TABLE IF NOT EXISTS trials (
  id TEXT PRIMARY KEY,
  trial_token TEXT NOT NULL,
  trial_token_hash TEXT NOT NULL UNIQUE,
  trial_token_preview TEXT NOT NULL,
  device_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'trialing',
  started_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  app_version TEXT
);

CREATE INDEX IF NOT EXISTS idx_trials_device_hash ON trials(device_hash);
CREATE INDEX IF NOT EXISTS idx_trials_token_hash ON trials(trial_token_hash);
CREATE INDEX IF NOT EXISTS idx_trials_expires_at ON trials(expires_at);
