# Catalog sync (M3 Phase A)

Pull Shopify products + inventory for installed shops and persist **platform-neutral** catalog rows. Read-only Phase A scopes only:

`read_products`, `read_inventory`, `read_locations`

No write mutations. No orders/customers.

## Tables

| Table | Purpose |
|-------|---------|
| `catalog_products` | `shop_id`, `external_id` (Shopify product GID), `title`, `handle`, `status`, optional `raw_attrs` |
| `catalog_variants` | `catalog_product_id`, `external_id`, `sku`, `title`, `barcode`, `option_summary`, `inventory_item_external_id` |
| `catalog_inventory_levels` | `catalog_variant_id`, `location_external_id`, `available` |

Unique indexes: shop+product external id; product+variant external id; variant+location external id.

## Required ENV

Same as install (see `.env.example` / `docs/shopify-install.md`):

| Variable | Notes |
|----------|--------|
| `SHOPIFY_API_VERSION` | Admin GraphQL version (default `2025-10`) |
| `SHOPIFY_CLIENT_ID` / `SHOPIFY_API_SECRET` | Partner app (OAuth + webhooks) |
| `ACTIVE_RECORD_ENCRYPTION_*` | Decrypt `shops.access_token` for API calls |

Never commit secrets. Load from `/workspace/sellora/secrets/shopify-partner-app.env` locally.

## Smoke — Wave 1 stores

Stores (see `docs/dev-stores.md`):

- `sellora-test-outfitters-like.myshopify.com`
- `sellora-test-sapphire-like.myshopify.com`

Prerequisites: app already installed (encrypted offline token in `shops`), DB migrated.

```sh
bin/rails db:prepare

# One shop
bin/rails "sellora:sync_catalog[sellora-test-outfitters-like.myshopify.com]"
bin/rails "sellora:sync_catalog[sellora-test-sapphire-like.myshopify.com]"

# Every installed shop
bin/rails sellora:sync_catalog_all
```

Inspect:

```sh
bin/rails runner '
  Shop.installed.find_each do |s|
    puts [s.shopify_domain, s.catalog_products.count,
          CatalogVariant.joins(:catalog_product).where(catalog_products: { shop_id: s.id }).count,
          CatalogInventoryLevel.joins(catalog_variant: :catalog_product).where(catalog_products: { shop_id: s.id }).count].inspect
  end
'
```

Or SQL:

```sql
SELECT shop_id, count(*) FROM catalog_products GROUP BY shop_id;
SELECT catalog_product_id, count(*) FROM catalog_variants GROUP BY catalog_product_id;
SELECT catalog_variant_id, location_external_id, available FROM catalog_inventory_levels LIMIT 20;
```

## Job + webhooks

- `Shopify::CatalogSyncJob.perform_later(shop_id)` — Active Job (`:async` in dev; Solid Queue in production).
- Product and inventory webhook stubs enqueue that job after the existing `webhook_events` idempotency claim (duplicates skip enqueue).
- Topics: `products_create`, `products_update`, `products_delete`, `inventory_levels_update`.

## Code map

- `Shopify::AdminClient` — GraphQL pagination (products → variants → inventory levels)
- `Shopify::CatalogSync` — upsert + reconcile removed products/variants/levels
- `Shopify::CatalogSyncJob` — background entrypoint
- `lib/tasks/sellora.rake` — smoke tasks above


## Dual-shop regression (Wave 1)

Outfitters-like and Sapphire-like stores are seeded with **near-identical catalog shapes** for parallel SaaS testing. Sync is always **per-shop** (`shop_id` + stable `external_id` GIDs). The same Shopify GID string may appear in both shops as separate rows — compare shapes across shops without joining on primary keys:

```sh
bin/rails runner '
  domains = %w[
    sellora-test-outfitters-like.myshopify.com
    sellora-test-sapphire-like.myshopify.com
  ]
  domains.each do |d|
    s = Shop.find_by!(shopify_domain: d)
    shape = s.catalog_products.order(:external_id).map { |p|
      {
        external_id: p.external_id, handle: p.handle, status: p.status,
        variants: p.catalog_variants.order(:external_id).map { |v|
          {
            external_id: v.external_id, sku: v.sku, option_summary: v.option_summary,
            levels: v.catalog_inventory_levels.order(:location_external_id).map { |l|
              { location_external_id: l.location_external_id, available: l.available }
            }
          }
        }
      }
    }
    puts d
    puts shape.inspect
  end
'
```

Assert equality of those shape hashes in QA when both stores are fixture-aligned.
