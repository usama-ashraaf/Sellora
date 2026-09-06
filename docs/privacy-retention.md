# Privacy, retention, and uninstall (M3)

This document describes **what Sellora stores today**, what happens on Shopify uninstall, and what remains unfinished before public launch. It is operational truth for Wave 1 development stores — not a public privacy policy.

## Data classes

| Class | Examples | Tenant boundary |
|-------|----------|-----------------|
| Integration secrets | Encrypted `shops.access_token` | Shop |
| Catalog mirror | `catalog_products`, variants, inventory levels | Shop → Account |
| Audit | `audit_rule_sets` / `audit_rules` (global seed), `audit_findings` | Findings: Account + Shop |
| Activity | `activity_events` (incl. `source: web_pixel`) | Account (+ optional Shop) |
| Webhooks ledger | `webhook_events` (idempotency keys) | Shop domain string |
| Marketing pilot | `pilot_requests` (name, work email, store URL, platform) | No Shopify shop FK |
| Demo gate | HTTP Basic env vars only (no passwords in DB) | N/A |

Secrets and tokens never belong in storefront JavaScript, logs, or pixel payloads. Pixel browser auth uses a write-only `Activity::PixelToken` (`docs/web-pixel.md`).

## Shopify `app/uninstalled`

Triggered by verified webhook `POST /webhooks/shopify/app_uninstalled` → `Shop#mark_uninstalled!`.

**Purged for that shop**

- Offline Admin API token (`access_token` set to nil)
- Catalog mirror (products → variants → inventory levels)
- `audit_findings` for the shop
- `activity_events` for the shop

**Retained**

- `shops` row (domain, `uninstalled_at`, scopes snapshot) so re-install and ops can see history
- `accounts` / `memberships` / `users` for the merchant workspace (shop may be one of several)
- Global `audit_rules` seed data
- `webhook_events` ledger rows (delivery idempotency; no catalog/PII payloads)
- Marketing `pilot_requests` (separate interest form; not tied to app install)

Re-install starts with an empty local catalog, a new OAuth token, and a new pixel ingest token (installation timestamp changes).

## Web pixel / consent

- Extension and Rails ingest fail closed without analytics consent (`docs/web-pixel.md`).
- Storefront payloads are allowlisted (`id`, `name`, `product_id`, `variant_id`) plus a consent snapshot.
- Incomplete coverage remains (blockers, network failures); never treat pixel absence as proof of no traffic.

## Marketing pilot form

- Stored in PostgreSQL via `PilotRequest`.
- Logging filters personal fields; see marketing review notes.
- Public page still uses a **placeholder** privacy contact until Usama assigns a monitored address (`docs/marketing-review.md` K-01).
- Deletion of pilot rows is ops/manual until a self-serve or ticketed process exists.

## Retention hypotheses (not automated yet)

| Data | Working hypothesis |
|------|--------------------|
| Catalog / findings / shop activity | Deleted on uninstall (implemented) |
| Webhook idempotency ledger | Keep ≥ 30 days for replay defense; ops may prune older rows |
| Pilot requests | Keep until pilot outreach completes or requester asks deletion; review quarterly |
| Uninstalled `shops` rows | Keep for audit; optional hard-delete after 90 days if domain recycled |

No automated TTL jobs ship in this milestone.

## GDPR / Shopify privacy webhooks

Shopify mandatory compliance webhooks (`customers/data_request`, `customers/redact`, `shop/redact`) are **not registered yet**. Wave 1 stores are fictional Partner development catalogs with minimal customer PII by design. Register and implement these before any production / App Store distribution.

## Public launch blockers (privacy)

1. Replace placeholder privacy contact and publish accurate retention copy.
2. Assign ops owner for pilot request review and deletion requests.
3. Implement Shopify privacy/compliance webhooks before production merchants.
4. Confirm production HTTPS host, backups, and cache (rate limits) configuration.

## Related

- [catalog-sync.md](./catalog-sync.md) — catalog purge on uninstall
- [web-pixel.md](./web-pixel.md) — pixel token + consent
- [activity-events.md](./activity-events.md) — event contract
- [marketing-review.md](./marketing-review.md) — pilot form / K-01
- [shopify-install.md](./shopify-install.md) — webhook paths
