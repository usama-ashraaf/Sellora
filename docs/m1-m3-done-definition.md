# M1–M3 “100% done” definition (Usama 2026-09-06)

Focus: complete first three milestones fully; M4–M6 later. Wave 1 stores must be good enough to test the SaaS.

## M1 — Marketing website (100%)
- [x] Responsive marketing site + story sections + Stimulus demos
- [x] Pilot form with real DB storage (local)
- [x] QA/Reviewer eng gates (F-01 etc.)
- [ ] Public-ready privacy copy + retention/ops owner (K-01) — **needed for “launch-ready 100%”**
- [ ] Present for review / publish decision by Usama
- Local-complete vs public-launch: call out clearly

## M2 — Application foundation (100%)
- [x] Accounts, memberships, roles
- [x] Stores / platform connections (Shop model + OAuth) — extend to account scoping
- [x] Shared catalog tables (products/variants/inventory) — flesh demo
- [x] Versioned audit rules engine (clothing rules from brief)
- [x] Activity event contract (schema + ingestion interface)
- [x] Tests covering foundation
- [x] Clearly labeled fictional in-app demo (not just marketing)

See also: [m2-foundation.md](./m2-foundation.md), [activity-events.md](./activity-events.md).

## M3 — Shopify development-store integration (100%)
- [x] Partner app + Phase A scopes
- [x] Install on both Wave 1 stores
- [x] Catalog sync + hardens + parity task
- [x] Webhook HMAC + idempotency stubs
- [ ] Embedded app home working in Shopify admin (**needs public HTTPS App URL**)
- [x] Webhooks registered via GraphQL (`WebhookRegistrar` + rake); E2E verify against Wave 1 when tunnel live
- [x] Supported Web Pixel events (consent-aware) — lean stub + ingest + docs; see [web-pixel.md](./web-pixel.md) (activation scopes / app-proxy still blockers for live E2E)
- [ ] Separate order records (Phase B `read_orders` when implementing this slice)
- [ ] Uninstall/privacy handling complete (token+catalog purge done; document retention)

## Wave 1 stores (required for SaaS testing)
- [x] Two near-identical fictional shops
- [ ] Prices, compare-at, inventory, SF-* variant SKUs correct on both
- [ ] QA fixture-fidelity PASS
- [ ] Eng sync shows non-blank SKUs + PARITY_OK
- No scraping of real brand sites
