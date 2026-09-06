# Sellora development stores

## Purpose
Fictional Shopify **development stores** that mimic Pakistani clothing ecommerce patterns for Sellora eng/QA (catalog audits, sizes, promos, stock, later COD/outcomes). **Not** affiliated with real brands — demonstration fixtures only. Never treat Outfitters, Sapphire, or other labels as customers or partners.

## Live stores (Wave 1)

| Store name | Inspired by | Shop domain | Storefront | Admin |
|------------|-------------|-------------|------------|-------|
| Sellora Test - Outfitters-like | outfitters.com.pk (verified Shopify) | `sellora-test-outfitters-like.myshopify.com` | https://sellora-test-outfitters-like.myshopify.com | https://admin.shopify.com/store/sellora-test-outfitters-like |
| Sellora Test - Sapphire-like | Sapphire (style mimic only) | `sellora-test-sapphire-like.myshopify.com` | https://sellora-test-sapphire-like.myshopify.com | https://admin.shopify.com/store/sellora-test-sapphire-like |

- Partner org: **Southville Solutions** (Partners `5165992`, Dev Dashboard `234284567`)
- Partner app: **Sellora** · Client ID `7d912d414ddbffe0c1ff644b418efcf9`
- Owner (stores + fixtures): **Dev Store Agent**
- Partner app install / scopes: **Lead Engineer**

## Status (2026-09-06)
- [x] Partners / Dev Dashboard access
- [x] Both stores created
- [x] Phase A scopes on Partner app: `read_products`, `read_inventory`, `read_locations`
- [x] Custom distribution configured (multi-store for Plus org of Outfitters-like)
- [x] Sellora app **installed** on Outfitters-like
- [x] Sellora app **installed** on Sapphire-like
- [ ] Catalog fixtures fully enriched (Dev Store Agent)
- [ ] Reviewer hardens (token encryption, OAuth HMAC binding, scope assert, webhook ledger)

## Usama test runbook (smoke)

### 1. Open each admin
1. Sign in to Shopify with the Southville Solutions / Partners account.
2. Outfitters-like admin: https://admin.shopify.com/store/sellora-test-outfitters-like
3. Sapphire-like admin: https://admin.shopify.com/store/sellora-test-sapphire-like

### 2. Confirm app install
1. In each admin: **Settings → Apps and sales channels** (or **Apps**).
2. Confirm **Sellora** appears under **Installed apps**.
3. Open Sellora — you should land on the app (embedded or install confirmation). If the Rails app isn’t running locally with OAuth env, the app home may error; install presence in Installed apps is the P0 check.

### 3. Confirm Phase A scopes (optional)
Partner app Dev Dashboard → Sellora → version scopes should list only:
`read_products`, `read_inventory`, `read_locations`.

### 4. Smoke products (when Rails + env are up)
1. Copy secrets from `/workspace/sellora/secrets/shopify-partner-app.env` into local `.env` (never commit).
2. Run Rails (`bin/rails s` on `:3000`).
3. Re-install or open via `/shopify/install?shop=SELLORA-TEST-OUTFITTERS-LIKE.myshopify.com` (and sapphire twin) if testing OAuth session storage.
4. With a stored offline token, GraphQL/REST product read should succeed under Phase A scopes (eng can run a one-off console check).

### 5. Storefront
- Outfitters-like: https://sellora-test-outfitters-like.myshopify.com
- Sapphire-like: https://sellora-test-sapphire-like.myshopify.com  
If password page appears, Dev Store Agent disables storefront password for QA.

## How to re-install / uninstall
1. Admin → Apps → Sellora → Uninstall (tests `app/uninstalled` webhook when Rails is receiving webhooks).
2. Re-install via Custom distribution install link from Partners → Sellora → Distribution, or:
   `https://admin.shopify.com/store/<store-handle>/oauth/install?client_id=7d912d414ddbffe0c1ff644b418efcf9`

## Catalog fixtures
CSV seeds:  
`/workspace/sellora/fixtures/dev-stores/outfitters-like/products.csv`  
`/workspace/sellora/fixtures/dev-stores/sapphire-like/products.csv`

## Notes
- M1 marketing site is separate — do not change it for store work.
- Secrets stay in `/workspace/sellora/secrets/shopify-partner-app.env` (mode 600). Never commit.
- Hold `read_orders` / write scopes until PM enables Phase B/C.
