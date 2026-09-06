# Supported Web Pixel (consent-aware) — M3 lean stub

Storefront behavioral events via a Shopify **Web Pixel Extension**, gated on customer privacy consent. Wave 1 OAuth includes Phase A catalog reads **plus** pixel scopes (`write_pixels`, `read_customer_events`). Order/checkout events stay Phase B (`read_orders` parked).

## What landed

| Piece | Location |
|-------|----------|
| Extension stub | `extensions/sellora-web-pixel/` (`shopify.extension.toml` + `src/index.js` + `src/consent.js`) |
| Ingest service | `Activity::WebPixelIngest` → `Activity::Ingest` with `source: "web_pixel"` |
| HTTP endpoint | `POST /web_pixels/events` + `OPTIONS` preflight (`WebPixels::EventsController`) |
| Browser auth | Installation-scoped `ingestToken` → header `X-Sellora-Pixel-Token` (`Activity::PixelToken`) |
| Server/test auth | Optional shared secret header `X-Sellora-Pixel-Secret` = `WEB_PIXEL_INGEST_SECRET` |
| Registrar | `Shopify::WebPixelRegistrar` + rake `sellora:register_web_pixel` / `_all` (after OAuth, best-effort) |
| Limits | Body ≤ 16 KB; ~1200 req/min/IP; ~300 req/min/shop (Rails `rate_limiting` + cache) |

## Consent gate (fail-closed)

1. **Extension TOML** — `[customer_privacy]` requires `analytics = true` and `marketing = true` so Shopify’s pixel manager only loads the pixel when those purposes are allowed.
2. **Pixel JS** — `mayFire()` in `src/consent.js` requires `analyticsProcessingAllowed === true` before subscribe handlers POST. Missing/false → no fire.
3. **Rails ingest** — `Activity::WebPixelIngest` rejects (no row) when consent flags are missing or analytics is not true. Controller returns `403` for consent denial, `401` for bad/missing auth.

Marketing-only events are not subscribed in Wave 1; product/page view and add-to-cart require analytics.

## Allowed event names (Wave 1)

- `page_viewed`
- `product_viewed`
- `product_added_to_cart`

Checkout / purchase / order topics are **out of scope** until Phase B `read_orders`.

## Pixel scopes — approved and enabled (Wave 1)

**Usama approved 2026-09-06.** `write_pixels` and `read_customer_events` are in `ShopifyConfig::PIXEL_SCOPES` / `ALLOWED_SCOPES` and default `SHOPIFY_SCOPES`. Phase B `read_orders` remains parked.

**Partner Dev Dashboard must also list the two pixel scopes** (Eng will save via browser separately). Rails OAuth alone is not enough if the Partner app version omits them.

## Browser auth model

The storefront must not hold Admin API credentials or `WEB_PIXEL_INGEST_SECRET`.

`WebPixelRegistrar` issues a **write-only** `Activity::PixelToken` per installation and stores it in web pixel settings as `ingestToken`. The extension sends that value as `X-Sellora-Pixel-Token`.

- Token claims bind `shop_id` + `installation` timestamp (`shops.updated_at`).
- Reinstall / token wipe (`mark_uninstalled!` / re-OAuth that bumps `updated_at`) invalidates old tokens.
- Resolve requires an installed shop with `account_id`.
- Caller-supplied `account_id` / mismatched `shop_domain` are ignored or rejected; shop comes from the token.
- Capability is event submission only — not reads, orders, billing, or merchant actions.

Optional `X-Sellora-Pixel-Secret` remains for server-side / integration tests only.

## Register / enable on Wave 1

### A. Deploy the extension

1. Ensure Shopify CLI can see this app (Partner app Sellora; root `shopify.app.toml`).
2. From the app root:

```sh
shopify app deploy
# or Partner Dev Dashboard → app versions → release including web pixel extension
```

3. Confirm the extension appears under Partner app → Extensions (name `sellora-web-pixel`).

### B. Activate per Wave 1 store (automatic + rake)

After a successful OAuth persist (shop has pixel scopes), Rails calls `Shopify::WebPixelRegistrar` best-effort (same pattern as webhooks). Re-run anytime:

```sh
bin/rails "sellora:register_web_pixel[sellora-test-outfitters-like.myshopify.com]"
bin/rails sellora:register_web_pixel_all
```

The registrar is **idempotent**: queries `webPixel`, creates via `webPixelCreate` when missing, or `webPixelUpdate` when settings drifted. Settings JSON:

```json
{
  "accountID": "<account_id or shop_id>",
  "shopDomain": "<canonical-shop>.myshopify.com",
  "ingestToken": "<Activity::PixelToken for this installation>",
  "ingestUrl": "https://<SHOPIFY_APP_URL>/web_pixels/events"
}
```

The pixel uses `shopDomain` from registration instead of the storefront hostname, so custom storefront domains map to the saved shop. Missing `shopDomain` / `ingestToken` / `ingestUrl` fail closed in the extension. Re-register existing pixels after deploying this settings schema.

Rake output prints `shop_domain` and `ingest_url` only — never the token.

Manual GraphQL (if needed):

```graphql
mutation {
  webPixelCreate(webPixel: {
    settings: "{\"accountID\":\"<account-or-shop-id>\",\"shopDomain\":\"<canonical-shop>.myshopify.com\",\"ingestToken\":\"<token>\",\"ingestUrl\":\"https://<public-host>/web_pixels/events\"}"
  }) {
    webPixel { id settings }
    userErrors { field message }
  }
}
```

Set a public HTTPS `SHOPIFY_APP_URL`. Optional: set `WEB_PIXEL_INGEST_SECRET` for non-browser test clients.

### C. Verify

1. Storefront page load with analytics consent granted → network `POST /web_pixels/events` with `X-Sellora-Pixel-Token`.
2. `ActivityEvent` row with `source: "web_pixel"` and consent snapshot in `payload`.
3. Consent denied / missing → no row (`403` if the request reaches Rails without analytics true).
4. Tampered / stale token → `401`; cross-shop `shop_domain` → `403`.

### D. Re-OAuth Wave 1 stores

Existing installs granted Phase-A-only scopes must re-OAuth so the offline token includes `write_pixels` + `read_customer_events`:

1. Confirm Partner Dev Dashboard lists all five Wave 1 scopes.
2. Kick install: `https://<tunnel-host>/shopify/install?shop=sellora-test-outfitters-like.myshopify.com` (and sapphire twin).
3. Approve the consent screen (pixel scopes appear).
4. Confirm `shops.scope` includes the pixel pair; then `sellora:register_web_pixel_all` if OAuth-time registration was skipped/failed.

## Incomplete coverage (blockers)

| Blocker | Impact |
|---------|--------|
| Partner Dev Dashboard scopes out of sync | OAuth may not grant pixel pair until Eng saves scopes in browser |
| Extension not deployed (`shopify app deploy`) | `webPixelCreate` fails: “No web pixel was found for this app” |
| Public HTTPS App URL / tunnel | Required for real storefront hits and Admin embed |
| Checkout / order pixel events | Deferred with Phase B orders |
| Cookie-banner edge cases | Shopify may not load the pixel at all when required purposes are denied; JS gate is defense-in-depth |

## Example ingest payload (browser)

```json
{
  "shop_domain": "sellora-test-outfitters-like.myshopify.com",
  "event_name": "product_viewed",
  "occurred_at": "2026-09-06T12:00:00Z",
  "consent": {
    "analytics_processing_allowed": true,
    "marketing_allowed": true
  },
  "payload": { "id": "evt-1", "name": "product_viewed" }
}
```

Header: `X-Sellora-Pixel-Token: <ingestToken from web pixel settings>`

Payload keys are allowlisted (`id`, `name`, `product_id`, `variant_id`); personal data and nested secrets are dropped.

## Related

- [activity-events.md](./activity-events.md)
- [shopify-scopes.md](./shopify-scopes.md)
- [shopify-install.md](./shopify-install.md)
