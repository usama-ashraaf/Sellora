# Supported Web Pixel (consent-aware) — M3 lean stub

Storefront behavioral events via a Shopify **Web Pixel Extension**, gated on customer privacy consent. Phase A catalog/OAuth scopes are unchanged; order/checkout events stay Phase B.

## What landed

| Piece | Location |
|-------|----------|
| Extension stub | `extensions/sellora-web-pixel/` (`shopify.extension.toml` + `src/index.js` + `src/consent.js`) |
| Ingest service | `Activity::WebPixelIngest` → `Activity::Ingest` with `source: "web_pixel"` |
| HTTP stub | `POST /web_pixels/events` (`WebPixels::EventsController`) |
| Auth | Shared secret header `X-Sellora-Pixel-Secret` = `WEB_PIXEL_INGEST_SECRET` |

## Consent gate (fail-closed)

1. **Extension TOML** — `[customer_privacy]` requires `analytics = true` and `marketing = true` so Shopify’s pixel manager only loads the pixel when those purposes are allowed.
2. **Pixel JS** — `mayFire()` in `src/consent.js` requires `analyticsProcessingAllowed === true` before subscribe handlers POST. Missing/false → no fire.
3. **Rails ingest** — `Activity::WebPixelIngest` rejects (no row) when consent flags are missing or analytics is not true. Controller returns `403` for consent denial, `401` for bad/missing secret.

Marketing-only events are not subscribed in Wave 1; product/page view and add-to-cart require analytics.

## Allowed event names (Wave 1)

- `page_viewed`
- `product_viewed`
- `product_added_to_cart`

Checkout / purchase / order topics are **out of scope** until Phase B `read_orders`.

## Register / enable on Wave 1

**Do not** add `write_pixels` / `read_customer_events` to Phase A OAuth yet (milestone decision). Activation therefore is manual / CLI, not a Rails `WebhookRegistrar`-style rake.

### A. Deploy the extension

1. Ensure Shopify CLI can see this app (Partner app Sellora; optional root `shopify.app.toml` when CLI scaffolding is added).
2. From the app root (once CLI is wired):

```sh
shopify app deploy
# or Partner Dev Dashboard → app versions → release including web pixel extension
```

3. Confirm the extension appears under Partner app → Extensions (name `sellora-web-pixel`).

### B. Activate per Wave 1 store (needs pixel scopes)

Shopify requires Admin scopes **`write_pixels`** and **`read_customer_events`** to call `webPixelCreate`. Those are **not** Phase A. Options:

1. **Temporary Partner-only grant** on the custom distribution / Dev Dashboard for the two Wave 1 stores (do not widen production OAuth / `ShopifyConfig::PHASE_A_SCOPES` without a milestone decision), then:

```graphql
mutation {
  webPixelCreate(webPixel: {
    settings: "{\"accountID\":\"<account-or-shop-id>\",\"ingestUrl\":\"https://<public-host>/web_pixels/events\"}"
  }) {
    webPixel { id settings }
    userErrors { field message }
  }
}
```

2. Or activate via **Admin → Settings → Customer events** once the extension is deployed and scopes allow connection.

3. Set `WEB_PIXEL_INGEST_SECRET` on the Rails host. Until app-proxy auth exists, production POSTs from the sandbox need a server-side secret path (see blockers).

### C. Verify

1. Storefront page load with analytics consent granted → network `POST /web_pixels/events`.
2. `ActivityEvent` row with `source: "web_pixel"` and consent snapshot in `payload`.
3. Consent denied / missing → no row (`403` if the request reaches Rails without analytics true).

## Incomplete coverage (blockers)

| Blocker | Impact |
|---------|--------|
| `write_pixels` / `read_customer_events` not in Phase A | No automatic `webPixelCreate` registrar in Rails (intentionally omitted) |
| Shared secret in storefront is unsafe | Extension currently POSTs without the secret; live E2E needs app proxy, signed settings, or a backend relay |
| Public HTTPS App URL / tunnel | Same as embedded app / webhooks — required for real storefront hits |
| Checkout / order pixel events | Deferred with Phase B orders |
| Cookie-banner edge cases | Shopify may not load the pixel at all when required purposes are denied; JS gate is defense-in-depth |

## Example ingest payload

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

Header: `X-Sellora-Pixel-Secret: <WEB_PIXEL_INGEST_SECRET>`

## Related

- [activity-events.md](./activity-events.md)
- [shopify-scopes.md](./shopify-scopes.md)
- [shopify-install.md](./shopify-install.md)
