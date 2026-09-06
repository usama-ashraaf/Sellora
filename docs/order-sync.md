# Order records (Phase B) — M3

Platform-neutral order storage for Shopify development stores. **A placed order is not proof of payment, COD collection, or profit.**

## What landed

| Piece | Location |
|-------|----------|
| Models | `CommerceOrder`, `CommerceOrderLine` |
| Sync | `Shopify::OrderSync` + `Shopify::OrderSyncJob` |
| Webhooks | `ORDERS_CREATE` / `ORDERS_UPDATED` → enqueue order sync |
| Scope | `read_orders` in `ShopifyConfig::PHASE_B_SCOPES` / `ALLOWED_SCOPES` |

## Honesty labels

- `financial_status` / `fulfillment_status` are Shopify display labels.
- No customer PII columns beyond what Shopify returns in order GraphQL (avoid `read_customers`).
- Uninstall purges shop order rows (`Shop#mark_uninstalled!`).

## Register / sync

After OAuth with `read_orders` (Partner Dev Dashboard must list the scope):

```sh
bin/rails sellora:register_webhooks_all
bin/rails runner 'Shop.installed.find_each { |s| Shopify::OrderSyncJob.perform_now(s.id) }'
```

## Related

- [shopify-scopes.md](./shopify-scopes.md)
- [privacy-retention.md](./privacy-retention.md)
- [activity-events.md](./activity-events.md)
