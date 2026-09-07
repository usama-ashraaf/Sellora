# Activity event contract (M2)

Append-only ingestion interface for store / account activity signals.

## Model

`ActivityEvent`

| Column | Type | Notes |
|--------|------|--------|
| `account_id` | FK | Required — multi-tenant boundary |
| `shop_id` | FK nullable | Optional store scope |
| `event_name` | string | Stable name, e.g. `catalog.synced`, `product.viewed` |
| `occurred_at` | datetime | When the activity happened (not insert time) |
| `payload` | jsonb | Event-specific attributes; keep PII minimal |
| `source` | string | e.g. `internal`, `shopify_webhook`, `web_pixel`, `demo` |

Rows are **append-only**: do not update `payload` or rename events in place. Correct mistakes by ingesting a compensating event (or ops delete for privacy purge).

## Ingestion interface

Prefer the service object:

```ruby
Activity::Ingest.call(
  account: account,
  shop: shop,                    # optional
  event_name: "catalog.synced",
  occurred_at: Time.current,
  payload: { products: 8 },
  source: "internal"
)
```

Rules:

1. `account` is required.
2. If `shop` is present and already assigned to an account, it must match `account`.
3. `event_name` is required (string).
4. `payload` must be a Hash (default `{}`).
5. Never write secrets (tokens, HMAC keys) into `payload`.

## Web pixel (`source: "web_pixel"`)

Use `Activity::WebPixelIngest` (not raw `Ingest`) for storefront pixel traffic so consent is enforced fail-closed:

```ruby
Activity::WebPixelIngest.call(
  shop_domain: "sellora-test-outfitters-like.myshopify.com",
  event_name: "product_viewed",
  consent: { "analytics_processing_allowed" => true, "marketing_allowed" => true },
  occurred_at: Time.current,
  payload: {
    "id" => "evt-1",
    "product_id" => "gid://shopify/Product/1",
    "variant_id" => "gid://shopify/ProductVariant/2"
  }
)
```

- Missing or non-true analytics consent → `Activity::WebPixelIngest::ConsentDenied` (no row).
- HTTP: `POST /web_pixels/events` with `X-Sellora-Pixel-Token` (browser) or `X-Sellora-Pixel-Secret` (server/test) — see [web-pixel.md](./web-pixel.md).
- Allowed names: `page_viewed`, `product_viewed`, `product_added_to_cart`, `product_removed_from_cart`, `checkout_started`, `payment_info_submitted`, `checkout_completed`.

## Commerce outcome note

Web pixel events use `source: "web_pixel"` via the consent-aware path above. Shopify Admin order sync is authoritative for payment, cancellation, refund, fulfillment and gateway status. COD collection requires courier or ERP evidence and is not inferred from a checkout event or gateway name.

## Privacy

On Shopify uninstall, `Shop#mark_uninstalled!` **deletes** that shop’s `activity_events` (along with catalog and findings). Account-level rows and marketing `pilot_requests` follow [privacy-retention.md](./privacy-retention.md).
