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
- Web Pixel Extension (storefront events; consent-aware) — stub in `extensions/sellora-web-pixel/`; see [web-pixel.md](./web-pixel.md)
- Optional storefront extension later (size select / placement) — not required for first install

### Pixel scopes — Wave 1 enabled (Usama approved 2026-09-06)
**Approved and enabled** in OAuth ceiling (`ShopifyConfig::PIXEL_SCOPES` → `ALLOWED_SCOPES = PHASE_A + PIXEL`):

| Scope | Why |
|-------|-----|
| `write_pixels` | `webPixelCreate` / merchant pixel settings |
| `read_customer_events` | Customer events access for app pixels |

Rails requests these on install and registers the pixel via `Shopify::WebPixelRegistrar` (see [web-pixel.md](./web-pixel.md)). **Partner Dev Dashboard must also list both scopes** (Eng saves via browser separately).

### Phase B — M3 orders + M4 monitoring (parked)
Add when building order/outcome + promo monitoring:
| Scope | Why |
|-------|-----|
| `read_orders` | Orders, line items, financial/fulfillment status (not proof of COD collection) |
| `read_discounts` | Promotion / offer accuracy (API name may be `read_discounts` / price rules depending on API version — Eng verify current name) |

Hold until needed:
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

Still no autopilot without M6 controls.

### Phase D — M6 bounded autopilot
Same write scopes as Phase C; no new scopes expected. Controls are product/ops (evidence floors, cooldowns, caps, kill switch), not extra OAuth scopes.

## Explicitly out of scope (for now)
- `write_orders`, `write_customers`, payment/payout scopes
- Broad `read_all_orders` legacy if avoidable — prefer modern `read_orders` with least data
- Any scope that exposes storefront private credentials into JS (never)

## Current decision (2026-09-06)
- **Installed / enabled for Wave 1:** Phase A + pixel (`write_pixels`, `read_customer_events`)  
- **OAuth ceiling:** `ShopifyConfig::ALLOWED_SCOPES` (still rejects `write_products` / `read_orders`)  
- **Parked:** Phase B orders until order path / M4 starts  
- **Approved in principle, not enabled:** Phase C at M5  
- Eng must verify exact scope strings against current Shopify Admin API version before flipping in Partners.

## Install checklist (Eng)
1. Set Wave 1 scopes on Partner app (Phase A + pixel pair)  
2. Install on Outfitters-like + Sapphire-like dev stores (re-OAuth so grants include pixel)  
3. Confirm OAuth grant + webhook + web pixel registration (Rails)  
4. Document store URLs + install status in `docs/dev-stores.md`
