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

## Phase A note

Shopify Phase A scopes only. Order / checkout payloads are out of scope until Phase B `read_orders`. Web pixel events will use the same contract with `source: "web_pixel"` when M3 completes that slice.

## Privacy

Account / shop uninstall flows may delete or nullify related events per retention policy (document in M3 privacy hardening). Until then, treat events as merchant-scoped operational data.
