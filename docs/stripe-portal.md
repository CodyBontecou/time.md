# Cloudflare commerce portal

The time.md website is hosted on **Cloudflare Pages** with **Pages Functions**.

The portal offers a free macOS app download. After onboarding, the app paywall starts a **14-day card-backed free trial** through Stripe Checkout Setup mode and returns via a `timemd://` deep link. The portal also sells a one-time **$19.99 USD** macOS desktop license through Stripe Checkout. Trial checkout stores card details in Stripe and issues a trial key; paid checkout creates an activation key, stores fulfillment records in D1, and emails the customer through Cloudflare Email Service.

## Cloudflare resources

Cloudflare is configured to reuse the existing D1 database because this account has reached its D1 database limit. A dedicated R2 bucket was created for trial and paid binaries.

Current bindings:

| Binding | Type | Resource | Required |
| --- | --- | --- | --- |
| `DB` | D1 database | `isolated-tech-store` (`32793cc4-3186-48c0-a2ca-74b071510ce1`) | Yes |
| `RELEASE_BUCKET` | R2 bucket | `time-md-releases` | Yes, for trial and paid binary delivery |
| Cloudflare Email Service REST API | Account API | `cody@isolated.tech` sender | Yes, for license emails |

Apply the schema:

```bash
npm run db:migrate:remote
```

For email sending, enable Cloudflare Email Service / Email Routing for `isolated.tech`, verify `cody@isolated.tech` as the sender address used by `FROM_EMAIL`, and create an API token with Cloudflare Email Service send permission. Store that token in `CLOUDFLARE_EMAIL_API_TOKEN`.

For local development, copy `.dev.vars.example` to `.dev.vars` and run:

```bash
npm run db:migrate:local
npm run dev
```

## Cloudflare Pages settings

Use these Pages settings:

| Setting | Value |
| --- | --- |
| Framework preset | None |
| Build command | leave blank |
| Build output directory | `site` |
| Functions directory | `functions` |

Deploy from CLI:

```bash
npm run deploy
```

## Environment variables

Set these in Cloudflare Pages → Settings → Environment variables. Trim copied secrets so they have no trailing spaces or newlines.

Email delivery uses Cloudflare Email Service's REST API; there is no third-party email provider.

| Variable | Required | Purpose |
| --- | --- | --- |
| `STRIPE_SECRET_KEY` | Yes | Stripe secret key used by Checkout, verification, download, and webhook routes. |
| `STRIPE_WEBHOOK_SECRET` | Yes | Stripe webhook signing secret for `/api/stripe-webhook`. |
| `SITE_URL` | Yes | Canonical site origin, e.g. `https://timemd.isolated.tech`. |
| `CLOUDFLARE_ACCOUNT_ID` | Yes | Cloudflare account ID (`e4265f322e6380ee832b83ad45e3e8c0`). |
| `CLOUDFLARE_EMAIL_API_TOKEN` | Yes | Cloudflare API token with Email Service send permission. |
| `FROM_EMAIL` | Yes | Verified Cloudflare Email sender. Set to `cody@isolated.tech`. |
| `SUPPORT_EMAIL` | Recommended | Support address shown in emails. Defaults to `cody@isolated.tech`. |
| `TIME_MD_TRIAL_DAYS` | Optional | Free trial length in days. Defaults to `14`. |
| `TIME_MD_DOWNLOAD_URL` | Recommended | Preferred public download URL. When set, download endpoints redirect here before checking R2. |
| `TIME_MD_RELEASE_OBJECT_KEY` | Optional | R2 object key for trial/paid release download, e.g. `time.md-latest-macOS.zip`. |
| `STRIPE_PRICE_ID` | Optional | Existing Stripe Price ID. If omitted, the API creates inline price data for `$19.99 USD`. |
| `STRIPE_UNIT_AMOUNT_CENTS` | Optional | Inline price amount in cents. Defaults to `1999`. Ignored when `STRIPE_PRICE_ID` is set. |
| `STRIPE_CURRENCY` | Optional | Inline currency. Defaults to `usd`. Ignored when `STRIPE_PRICE_ID` is set. |
| `STRIPE_AUTOMATIC_TAX` | Optional | Set to `true` to enable Stripe automatic tax if configured in Stripe. |

## Stripe webhook

Create a Stripe webhook endpoint:

```txt
https://timemd.isolated.tech/api/stripe-webhook
```

Subscribe to:

```txt
checkout.session.completed
checkout.session.async_payment_succeeded
```

The webhook verifies the Stripe signature, retrieves the Checkout Session, creates the order/license in D1, and sends the activation email through Cloudflare Email Service.

## Runtime flow

1. Website trial buttons download the macOS app for free through `GET /api/download-trial`.
2. The app shows onboarding before collectors start, then presents the paywall.
3. The app paywall calls `POST /api/create-trial-checkout-session` with `return_to_app: true`.
4. The Cloudflare Function creates a Stripe Checkout Session in `setup` mode so Stripe collects/stores the card. time.md never sees card numbers.
5. Stripe returns trial users to `/trial-success.html?open_app=1&session_id={CHECKOUT_SESSION_ID}`.
6. The success page verifies the session, then opens `timemd://activate-trial?session_id=...`.
7. The app handles the deep link, calls `/api/verify-trial-checkout-session`, receives the trial key, then calls `POST /api/verify-trial` to bind the trial to the app's random device ID and cache the trial token in Keychain.
8. Later app launches call `POST /api/verify-trial` in the background to refresh trial status until expiration.
9. Buy buttons call `POST /api/create-checkout-session`.
10. The Cloudflare Function creates a Stripe Checkout Session for the one-time paid license.
11. Stripe returns paid customers to `/success.html?session_id={CHECKOUT_SESSION_ID}` or `/cancel.html`.
12. `/api/verify-checkout-session` retrieves the Stripe session, creates/reuses the activation key, sends email if needed, and returns the paid download URL.
13. Stripe webhook performs the same paid fulfillment asynchronously for reliability.
14. `/api/download?session_id=...` verifies payment and redirects to `TIME_MD_DOWNLOAD_URL` when set, otherwise streams from R2 when configured.

## Trial endpoints

Trials require Stripe Checkout card setup from the app paywall before the app receives a trial key. The server stores the SHA-256 device hash after first app activation, a trial token/token hash, Stripe session/setup/customer/payment-method IDs, start and expiration dates, status, app version, and last-seen timestamp. Trial duration is controlled by `TIME_MD_TRIAL_DAYS` and defaults to 14 days.

Create a card-backed trial Checkout Session:

```txt
POST /api/create-trial-checkout-session
```

Optional body from the macOS app:

```json
{
  "source": "time.md macOS app paywall",
  "return_to_app": true
}
```

Response:

```json
{
  "id": "cs_...",
  "url": "https://checkout.stripe.com/..."
}
```

Verify the completed trial Checkout Session:

```txt
GET /api/verify-trial-checkout-session?session_id=cs_...
```

Response:

```json
{
  "valid": true,
  "status": "trialing",
  "trial_id": "...",
  "trial_token": "TMDTRIAL-...",
  "trial_token_preview": "TMDTRIAL…ABCD",
  "started_at": "2026-06-04T00:00:00.000Z",
  "expires_at": "2026-06-18T00:00:00.000Z",
  "download_url": "https://timemd.isolated.tech/api/download-trial"
}
```

Verify a saved trial:

```txt
POST /api/verify-trial
```

Body:

```json
{
  "trial_token": "TMDTRIAL-...",
  "device_id": "random-stable-device-id",
  "app_version": "2.5.0"
}
```

Expired trials return `410` with `valid: false` and `status: "expired"`.

## Activation keys

Activation keys are generated by Cloudflare Functions and stored in D1 with a SHA-256 hash and preview value. The current endpoint for app-side paid-license validation is:

```txt
POST /api/activate
```

Body:

```json
{
  "activation_key": "TMD-XXXX-XXXX-XXXX-XXXX-XXXX",
  "device_id": "optional-stable-device-id",
  "app_version": "2.5.0"
}
```

Response:

```json
{
  "valid": true,
  "status": "active",
  "license_id": "...",
  "activation_key_preview": "TMD-ABCD…WXYZ"
}
```

The macOS desktop app allows onboarding before entitlement, but keeps local collectors and the main app locked behind either an active trial or this paid activation endpoint. After onboarding, users can open the card-backed Stripe trial checkout, return through the `timemd://activate-trial` deep link, paste a fallback trial key, or paste the paid activation key from the success page/license email. The app sends only entitlement data, app version, and a random locally generated device ID; the endpoint stores only the device hash in D1. A successful paid activation is cached locally in Keychain/UserDefaults so the app can continue working if later launches are offline, while background reverification can revoke invalid keys.

## Sending license emails again

Support can trigger another send with a paid Checkout Session ID:

```bash
curl -X POST https://timemd.isolated.tech/api/send-license-email \
  -H 'content-type: application/json' \
  -d '{"session_id":"cs_live_..."}'
```
