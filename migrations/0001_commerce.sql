CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  stripe_session_id TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT,
  customer_email TEXT NOT NULL,
  amount_total INTEGER NOT NULL,
  currency TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS licenses (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  activation_key TEXT NOT NULL,
  activation_key_hash TEXT NOT NULL UNIQUE,
  activation_key_preview TEXT NOT NULL,
  customer_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  issued_at TEXT NOT NULL,
  revoked_at TEXT,
  FOREIGN KEY(order_id) REFERENCES orders(id)
);

CREATE TABLE IF NOT EXISTS activations (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL,
  device_hash TEXT NOT NULL,
  app_version TEXT,
  activated_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  FOREIGN KEY(license_id) REFERENCES licenses(id),
  UNIQUE(license_id, device_hash)
);

CREATE TABLE IF NOT EXISTS email_events (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_message_id TEXT,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  detail TEXT,
  sent_at TEXT NOT NULL,
  FOREIGN KEY(order_id) REFERENCES orders(id)
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_email ON orders(customer_email);
CREATE INDEX IF NOT EXISTS idx_licenses_order_id ON licenses(order_id);
CREATE INDEX IF NOT EXISTS idx_licenses_customer_email ON licenses(customer_email);
CREATE INDEX IF NOT EXISTS idx_activations_license_id ON activations(license_id);
CREATE INDEX IF NOT EXISTS idx_email_events_order_id ON email_events(order_id);
