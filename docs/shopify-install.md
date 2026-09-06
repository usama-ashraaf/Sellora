# Shopify local install (Phase A / M3 foundation)

Install Sellora on a Partner **development store** with least-privilege Phase A scopes only:

`read_products`, `read_inventory`, `read_locations`

## Prerequisites

- Ruby/Rails app running locally (`bin/rails db:prepare && bin/rails server -b 127.0.0.1 -p 3000`)
- Shopify Partner app **Sellora** (Client ID `7d912d414ddbffe0c1ff644b418efcf9`)
- A public HTTPS tunnel to your machine (ngrok, Cloudflare Tunnel, etc.) so Shopify can reach OAuth callback + webhooks
- Client secret available locally only (e.g. `/workspace/sellora/secrets/shopify-partner-app.env`) — **never commit it**
- Active Record encryption keys for `shops.access_token` (see `.env.example`; generate with `bin/rails db:encryption:init`)

## Configure Partner app URLs

In Partners → Apps → Sellora → App setup (required):

| Setting | Value |
|--------|--------|
| **App URL** | `https://<tunnel-host>/` (or `https://<tunnel-host>/shopify/install`) |
| **Allowed redirection URL(s)** | `https://<tunnel-host>/auth/shopify/callback` |

The Allowed redirection URL **must** end with `/auth/shopify/callback` (Rails route `shopify_callback`). A mismatch here is a common cause of OAuth token-exchange failures.

Enable **Phase A** scopes only (see `docs/shopify-scopes.md`). Do not enable Phase B/C scopes yet.

### Webhook paths

Suggested webhook subscriptions (point at the tunnel host):

| Topic | Endpoint |
|-------|----------|
| `products/create` | `POST https://<tunnel-host>/webhooks/shopify/products_create` |
| `products/update` | `POST https://<tunnel-host>/webhooks/shopify/products_update` |
| `products/delete` | `POST https://<tunnel-host>/webhooks/shopify/products_delete` |
| `inventory_levels/update` | `POST https://<tunnel-host>/webhooks/shopify/inventory_levels_update` |
| `app/uninstalled` | `POST https://<tunnel-host>/webhooks/shopify/app_uninstalled` |

### Usama testing — live Wave 1 stores

Install / re-install against these Partner development stores (see `docs/dev-stores.md`):

| Store | Shop domain | Install kick URL |
|-------|-------------|------------------|
| Outfitters-like | `sellora-test-outfitters-like.myshopify.com` | `https://<tunnel-host>/shopify/install?shop=sellora-test-outfitters-like.myshopify.com` |
| Sapphire-like | `sellora-test-sapphire-like.myshopify.com` | `https://<tunnel-host>/shopify/install?shop=sellora-test-sapphire-like.myshopify.com` |

## Local environment

```sh
cp .env.example .env
# Set SHOPIFY_API_SECRET from the Partner app (never commit .env)
# Set SHOPIFY_APP_URL=https://<tunnel-host>
# Set ACTIVE_RECORD_ENCRYPTION_* from `bin/rails db:encryption:init` (never commit)
export $(grep -v '^#' .env | xargs)   # or use your preferred env loader
bin/rails db:prepare
bin/rails server -b 127.0.0.1 -p 3000
```

Rails does not load `.env` automatically in this app; export variables in your shell or process manager.

## Install on a dev store

1. Open:
   `https://<tunnel-host>/shopify/install?shop=<your-store>.myshopify.com`
2. Approve the OAuth consent screen (Phase A scopes).
3. You should land on `/auth/shopify/callback` and see an install confirmation.
4. Confirm a `shops` row exists (`bin/rails runner 'puts Shop.pluck(:shopify_domain, :scope, :uninstalled_at).inspect'`). The access token is **encrypted at rest** and filtered from logs — do not print it.

## Routes (marketing unchanged)

- Marketing: `/`, `POST /pilot_requests`
- OAuth install: `GET /shopify/install`
- OAuth callback: `GET /auth/shopify/callback`
- Webhooks: `POST /webhooks/shopify/*` (HMAC required)

## Security notes (Reviewer hardens)

- OAuth uses a session `state` CSRF token.
- When `SHOPIFY_API_SECRET` is set, callback **requires** query HMAC verification (no optional skip).
- Callback `shop` must match the shop stored in session at install start.
- Granted OAuth scopes must be a subset of Phase A; broader grants are rejected.
- `shops.access_token` is encrypted with Active Record encryption (keys via ENV only).
- `support_unencrypted_data` is **temporary**: it lets pre-encryption plaintext tokens remain readable until each row is re-saved (which re-encrypts). **Follow-up:** once every `shops.access_token` is known encrypted, set `support_unencrypted_data` to `false` in `config/initializers/active_record_encryption.rb` and drop the plaintext fallback.
- Webhooks verify `X-Shopify-Hmac-Sha256` and record an idempotency ledger (`webhook_events`) keyed by `X-Shopify-Webhook-Id` (or a body/HMAC fingerprint fallback). Duplicates are acknowledged with `200` and skip business logic.
- `app/uninstalled` clears the stored offline token and sets `uninstalled_at`.
- Product/inventory webhooks enqueue `Shopify::CatalogSyncJob` after the idempotency ledger claim (see `docs/catalog-sync.md`).

## Rate limiting (ops)

Shopify retries webhooks aggressively; the ledger prevents duplicate side effects. For public install URLs, put an edge rate limit (e.g. Cloudflare / reverse-proxy) on:

- `GET /shopify/install` — low QPS per IP (browser install kicks)
- `POST /webhooks/shopify/*` — allow Shopify’s retry bursts but cap anonymous abuse

A Rack-level throttle can be added later (e.g. `rack-attack`) if edge limits are unavailable.


## Catalog sync (Phase A)

After install, pull products + inventory into platform-neutral tables:

```sh
bin/rails "sellora:sync_catalog[sellora-test-outfitters-like.myshopify.com]"
bin/rails sellora:sync_catalog_all
```

Details, tables, and Wave 1 smoke steps: **`docs/catalog-sync.md`**.
