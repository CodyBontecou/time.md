ALTER TABLE trials ADD COLUMN stripe_session_id TEXT;
ALTER TABLE trials ADD COLUMN stripe_setup_intent_id TEXT;
ALTER TABLE trials ADD COLUMN stripe_customer_id TEXT;
ALTER TABLE trials ADD COLUMN stripe_payment_method_id TEXT;
ALTER TABLE trials ADD COLUMN customer_email TEXT;
ALTER TABLE trials ADD COLUMN amount_total INTEGER DEFAULT 1999;
ALTER TABLE trials ADD COLUMN currency TEXT DEFAULT 'usd';
ALTER TABLE trials ADD COLUMN charged_at TEXT;
ALTER TABLE trials ADD COLUMN stripe_payment_intent_id TEXT;
ALTER TABLE trials ADD COLUMN charge_error TEXT;
ALTER TABLE trials ADD COLUMN canceled_at TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_trials_stripe_session_id ON trials(stripe_session_id);
CREATE INDEX IF NOT EXISTS idx_trials_stripe_customer_id ON trials(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_trials_status_expires_at ON trials(status, expires_at);
