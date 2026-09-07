# Sellora Shopify API scopes (phased)

Partner app: Sellora · Client ID `7d912d414ddbffe0c1ff644b418efcf9`  
Principle: **least privilege**. Enable only what the current milestone needs. Never put secrets in the repo.

## Milestone map

### Phase A — M3 foundation (dev-store install + catalog sync)
**Enable now for both test stores:**
| Scope | Why |
|-------|-----|
| `read_products` | Catalog, variants, options (sizes), images, status |
| `read_inventory` | Stock / availability freshness |
| `read_locations` | Inventory context per location |

**Webhooks (subscribe when M3 starts; need matching scopes):**
- `products/create`, `products/update`, `products/delete`
- `inventory_levels/update`
- `app/uninstalled`
- `shop/update` (optional)

**Not Admin scopes (separate extensions — M3):**
- Web Pixel Extension (storefront events; consent-aware) — implemented in `extensions/sellora-web-pixel/`; see [web-pixel.md](./web-pixel.md)
- Optional storefront extension later (size select / placement) — not required for first install

### Pixel scopes — Wave 1 enabled (Usama approved 2026-09-06)
**Approved and enabled** in OAuth ceiling (`ShopifyConfig::PIXEL_SCOPES` → `ALLOWED_SCOPES = PHASE_A + PIXEL`):

| Scope | Why |
|-------|-----|
| `write_pixels` | `webPixelCreate` / merchant pixel settings |
| `read_customer_events` | Customer events access for app pixels |

Rails requests these on install and registers the pixel via `Shopify::WebPixelRegistrar` (see [web-pixel.md](./web-pixel.md)). **Partner Dev Dashboard must also list both scopes** (Eng saves via browser separately).

### Phase B — M3 orders (enabled for local Wave 1)
Enabled for M3 order records:
| Scope | Why |
|-------|-----|
| `read_orders` | Orders, line items, financial/fulfillment status (not proof of COD collection) |

Hold until needed:
- `read_discounts` — not needed for the current product-specific discount creation flow
- `read_customers` — **avoid** unless a pilot requires it (minimize PII)
- `read_checkouts` — usually unnecessary if we have pixel + orders
- Advertising APIs — later, pilot-driven

### Phase C — M5 reviewed actions (write, approval-gated)
Add only when applying merchant-approved fixes:
| Scope | Why |
|-------|-----|
| `write_products` | Approved catalog corrections |
| `write_inventory` | Only if we ever adjust stock (default: **omit** unless product requires it) |
| `write_discounts` | Approved promo corrections (verify current scope name) |

All writes also require the server-side `SELLORA_ALLOW_WRITES=true` gate. Bounded autopilot is disabled by default and applies only merchant-selected action types within configured limits.

### Phase D — M6 bounded autopilot
Same write scopes as Phase C; no new scopes expected. Controls are product/ops (evidence floors, cooldowns, caps, kill switch), not extra OAuth scopes.

## Explicitly out of scope (for now)
- `write_orders`, `write_customers`, payment/payout scopes
- Broad `read_all_orders` legacy if avoidable — prefer modern `read_orders` with least data
- Any scope that exposes storefront private credentials into JS (never)

## Current decision (2026-09-06)
- **Installed / enabled for Wave 1:** Phase A + pixel + Phase B `read_orders`  
- **OAuth ceiling:** `ShopifyConfig::ALLOWED_SCOPES` includes reviewed product and discount writes; existing stores must reauthorize before those scopes are granted
- **Order sync:** see [order-sync.md](./order-sync.md)  
- **Implemented but not live-verified:** Phase C reviewed actions and M6 bounded autopilot
- Eng must verify exact scope strings against current Shopify Admin API version before flipping in Partners.

## Install checklist (Eng)
1. Set Wave 1 scopes on Partner app (Phase A + pixel pair)  
2. Install on Outfitters-like + Sapphire-like dev stores (re-OAuth so grants include pixel)  
3. Confirm OAuth grant + webhook + web pixel registration (Rails)  
4. Document store URLs + install status in `docs/dev-stores.md`
