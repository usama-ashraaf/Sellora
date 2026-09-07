# Supported Web Pixel and commerce signals (consent-aware)

Storefront behavioral events flow through a Shopify **Web Pixel Extension**, gated on customer privacy consent. Shopify Admin order sync and order webhooks supply server-side payment, cancellation, refund, fulfillment and payment-gateway outcomes.

## What landed

| Piece | Location |
|-------|----------|
| Pixel extension | `extensions/sellora-web-pixel/` (`shopify.extension.toml` + `src/index.js` + `src/consent.js`) |
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

All subscribed events require analytics consent. The pixel deliberately omits customer contact, address and payment details.

## Allowed event names

- `page_viewed`
- `product_viewed`
- `product_added_to_cart`
- `product_removed_from_cart`
- `checkout_started`
- `payment_info_submitted`
- `checkout_completed`

Product and cart payloads include Shopify product and variant GIDs. Checkout payloads contain only a checkout token, optional order GID, total money, and up to 25 sanitized product lines. Payment, cancellation, refund, fulfillment and COD gateway outcomes come from `Shopify::OrderSync`, not from browser claims.

## Pixel scopes — approved and enabled (Wave 1)

**Usama approved 2026-09-06.** `write_pixels` and `read_customer_events` are in `ShopifyConfig::PIXEL_SCOPES` / `ALLOWED_SCOPES` and default `SHOPIFY_SCOPES`. Phase B `read_orders` is also implemented; existing installations must reauthorize whenever their granted scope snapshot is missing required scopes.

**Partner Dev Dashboard must also list the two pixel scopes** (Eng will save via browser separately). Rails OAuth alone is not enough if the Partner app version omits them.

## Browser auth model

The storefront must not hold Admin API credentials or `WEB_PIXEL_INGEST_SECRET`.

`WebPixelRegistrar` issues a **write-only** `Activity::PixelToken` per installation and stores it in web pixel settings as `ingestToken`. The extension sends that value as `X-Sellora-Pixel-Token`.

- Token claims bind `shop_id` + `installation` timestamp (`shops.updated_at`).
- Reinstall / token wipe (`mark_uninstalled!` / re-OAuth that bumps `updated_at`) invalidates old tokens.
- Resolve requires an installed shop with `account_id`.
- Caller-supplied account identifiers are not accepted. A mismatched `shop_domain` is rejected; the account and shop come from the signed token.
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
    settings: "{\"shopDomain\":\"<canonical-shop>.myshopify.com\",\"ingestToken\":\"<token>\",\"ingestUrl\":\"https://<public-host>/web_pixels/events\"}"
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

## Operational requirements and limits

| Blocker | Impact |
|---------|--------|
| Partner Dev Dashboard scopes out of sync | OAuth may not grant pixel pair until Eng saves scopes in browser |
| Extension not deployed (`shopify app deploy`) | `webPixelCreate` fails: “No web pixel was found for this app” |
| Public HTTPS App URL / tunnel | Required for real storefront hits and Admin embed |
| Cookie-banner edge cases | Shopify may not load the pixel at all when required purposes are denied; JS gate is defense-in-depth |
| COD collection | A COD gateway label is not proof of delivery or cash remittance; connect courier or ERP data for that claim |

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
  "payload": {
    "id": "evt-1",
    "name": "product_viewed",
    "product_id": "gid://shopify/Product/1",
    "variant_id": "gid://shopify/ProductVariant/2",
    "sku": "SF-KURTA-M",
    "amount": "2490.00",
    "currency": "PKR"
  }
}
```

Header: `X-Sellora-Pixel-Token: <ingestToken from web pixel settings>`

Payload keys are allowlisted. Checkout line items retain only product ID, variant ID, SKU and quantity. Personal data and unrecognized nested values are dropped.

## Related

- [activity-events.md](./activity-events.md)
- [shopify-scopes.md](./shopify-scopes.md)
- [shopify-install.md](./shopify-install.md)
