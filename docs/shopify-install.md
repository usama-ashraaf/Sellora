# Shopify local install (Phase A / M3 foundation)

Install Sellora on a Partner **development store** with least-privilege Phase A scopes only:

`read_products`, `read_inventory`, `read_locations`

## Prerequisites

- Ruby/Rails app running locally (`bin/rails db:prepare && bin/rails server -b 127.0.0.1 -p 3000`)
- Shopify Partner app **Sellora** (Client ID `7d912d414ddbffe0c1ff644b418efcf9`)
- A public HTTPS tunnel to your machine (ngrok, Cloudflare Tunnel, etc.) so Shopify can reach OAuth callback + webhooks
- Client secret available locally only (e.g. `/workspace/sellora/secrets/shopify-partner-app.env`) — **never commit it**

## Configure Partner app URLs

In Partners → Apps → Sellora → App setup:

| Setting | Value |
|--------|--------|
| App URL | `https://<tunnel-host>/` (or `/shopify/install` if you prefer) |
| Allowed redirection URL(s) | `https://<tunnel-host>/auth/shopify/callback` |

Enable **Phase A** scopes only (see `docs/shopify-scopes.md`). Do not enable Phase B/C scopes yet.

Suggested webhook subscriptions (point at the tunnel host):

| Topic | Endpoint |
|-------|----------|
| `products/create` | `POST https://<tunnel-host>/webhooks/shopify/products_create` |
| `products/update` | `POST https://<tunnel-host>/webhooks/shopify/products_update` |
| `products/delete` | `POST https://<tunnel-host>/webhooks/shopify/products_delete` |
| `inventory_levels/update` | `POST https://<tunnel-host>/webhooks/shopify/inventory_levels_update` |
| `app/uninstalled` | `POST https://<tunnel-host>/webhooks/shopify/app_uninstalled` |

## Local environment

```sh
cp .env.example .env
# Set SHOPIFY_API_SECRET from the Partner app (never commit .env)
# Set SHOPIFY_APP_URL=https://<tunnel-host>
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
4. Confirm a `shops` row exists (`bin/rails runner 'puts Shop.pluck(:shopify_domain, :scope, :uninstalled_at).inspect'`). The access token is stored in ActiveRecord and filtered from logs — do not print it.

## Routes (marketing unchanged)

- Marketing: `/`, `POST /pilot_requests`
- OAuth install: `GET /shopify/install`
- OAuth callback: `GET /auth/shopify/callback`
- Webhooks: `POST /webhooks/shopify/*` (HMAC required)

## Notes

- OAuth uses a session `state` CSRF token and optional query HMAC verification.
- Webhooks verify `X-Shopify-Hmac-Sha256` against the raw body using `SHOPIFY_API_SECRET`.
- `app/uninstalled` clears the stored offline token and sets `uninstalled_at`.
- Product/inventory webhook handlers are stubs in Phase A (acknowledge + log topic/shop only).
