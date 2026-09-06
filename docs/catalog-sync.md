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

Prerequisites: app already installed **through this Rails app OAuth** (encrypted offline token in `shops` — Partner Custom distribution alone does **not** create `Shop` rows), DB migrated. Local callback: `http://127.0.0.1:3000/auth/shopify/callback` (see `docs/shopify-install.md`).

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

### Coalesce / lock (S3)

Full-catalog sync is **coalesced per shop** via a PostgreSQL advisory lock (`Shopify::CatalogSyncLock`):

- Only one full sync runs for a given `shop_id` at a time.
- Contending jobs **skip** (log `coalesce skip`) rather than run concurrently or wipe mid-flight.
- Transient Admin API failures (`Shopify::AdminClient::TransientError`, timeouts, connection resets) use Active Job `retry_on` with polynomial backoff (5 attempts).

### Fail-closed empty reconcile (S1)

If a full sync sees **zero** products (or an unexpected empty page after products were already seen) while the shop already has local catalog rows, reconcile **aborts** with `Shopify::CatalogSync::EmptySeenError` and **does not** delete existing products/variants/levels. Prefer stale catalog over a wipe from an empty/glitched API response. A genuinely empty shop (zero remote + zero local) is a no-op.

### Nested GraphQL pagination (S2)

Product pages use small first-page sizes to stay under Shopify’s single-query cost limit (~1000):

| Connection | Page size | Pagination |
|------------|-----------|------------|
| `products` | 10 | Cursor pages until `hasNextPage` is false |
| `variants` | 50 | Nested `pageInfo`; remaining pages fetched via `product(id:)` |
| `inventoryLevels` | 10 | Nested `pageInfo`; remaining pages fetched via `inventoryItem(id:)` |

There is **no hard truncate**: nested connections are expanded to completion before upsert/reconcile.

### Uninstall catalog policy (S4)

On `app/uninstalled`, `Shop#mark_uninstalled!` clears the offline token **and purges** that shop’s `catalog_products` (cascading to variants + inventory levels). Catalog rows are **not** retained after uninstall. Re-install starts from an empty local catalog and a fresh sync.

## Code map

- `Shopify::AdminClient` — GraphQL pagination (products → variants → inventory levels, nested to completion)
- `Shopify::CatalogSync` — upsert + fail-closed reconcile
- `Shopify::CatalogSyncLock` — per-shop advisory lock / coalesce
- `Shopify::CatalogSyncJob` — background entrypoint + `retry_on` transients
- `lib/tasks/sellora.rake` — smoke tasks above

## Catalog parity (Wave 1 dual-shop)

After both shops are installed **and** synced, diff counts + SKU sets:

```sh
bin/rails sellora:catalog_parity
# Or explicit domains:
bin/rails "sellora:catalog_parity[sellora-test-outfitters-like.myshopify.com,sellora-test-sapphire-like.myshopify.com]"
```

What it compares:

| Check | Notes |
|-------|--------|
| Counts | `products`, `variants`, `inventory_levels`, non-blank `skus` |
| SKU set | Symmetric difference (`only_a` / `only_b`) |
| Shared SKU shape | Sample mismatches on `option_summary`, `variant_title`, `inventory_sum` (handles may differ by brand flavor) |

Exit: prints `PARITY_OK` or aborts with `PARITY_DIFF`. Implementation: `Sellora::CatalogParity` + `lib/tasks/sellora.rake`.

## Deep shape dump (optional)

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

Prefer `sellora:catalog_parity` for day-to-day Wave 1 regression; use the dump above when debugging a specific shape mismatch.
