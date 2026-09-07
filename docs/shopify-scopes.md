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

## Current decision (2026-09-08)
- **Installed / enabled for Wave 1:** Phase A + pixel + Phase B `read_orders` + Phase C `write_products` and `write_discounts`
- **OAuth grants verified:** both Wave 1 stores report every configured scope; Shopify also reports the related `read_pixels` and `read_discounts` scopes
- **Order sync:** see [order-sync.md](./order-sync.md)  
- **Live-verified:** reviewed product repair, percentage discount creation, and a bounded autopilot run followed by the kill switch
- **Safety state after smoke:** autopilot stopped and local write gate disabled

## Install checklist (Eng)
1. Set the required scopes on the Partner app.
2. Re-OAuth Outfitters-like + Sapphire-like after any scope change.
3. Confirm OAuth grants, webhook registrations, and web pixel registrations.
4. Keep the stable production URL synchronized across hosting, Partner configuration, and `shopify.app.toml`.
