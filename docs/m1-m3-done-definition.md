# M1–M6 done definition (local)

Focus: local / Wave 1 development-store completion. Public launch and App Store compliance remain separate.

## M1 — Marketing website
- [x] Responsive marketing site + story + Stimulus demos
- [x] Pilot form with DB storage
- [x] Local-complete privacy framing
- [ ] Optional: Usama publish/review; monitored privacy contact for public launch

## M2 — Application foundation
- [x] Accounts, shops, catalog, clothing rules, activity, labeled demo, tests
- [x] S3 residuals (no Demo fallback, shop account required, finding↔shop validation)

## M3 — Shopify integration
- [x] Install, catalog sync, webhooks, pixel ingest/token, orders Phase B, uninstall purge
- [x] Wave 1 live ops: CLI deploy, re-OAuth, webhooks, pixel registration, storefront funnel smoke, order sync, and reviewed writes
- [ ] Production ops: replace the temporary Cloudflare URL with a stable HTTPS host

## M4 — Read-only merchant pilot
- [x] Daily discovery job + `Pilot::Discover`
- [x] Change-aware audits (fingerprint + rule version)
- [x] Remaining clothing content rules + recommendations
- [x] Ops visibility on embedded app home
- See [pilot-ops-m4-m6.md](./pilot-ops-m4-m6.md)

## M5 — Reviewed actions
- [x] Propose / approve / reject / apply with before/after snapshots
- [x] Source conflict detection via fingerprint
- [x] Execution history on `ReviewedAction`
- [x] Shopify writes gated (`write_products` + `SELLORA_ALLOW_WRITES`) — no autonomous pricing

## M6 — Bounded autopilot
- [x] `AutopilotPolicy` (allowlist, evidence, severity, cooldown, daily action/discount caps, stock/size/margin gates)
- [x] Kill switch (`kill_switch!` / enabled default false)
- [x] `Pilot::Autopilot` runner, recurring schedule, merchant controls, and durable run history
- Out of scope: autonomous pricing / advertising

## Still unfinished (honest)
- Stable production hosting, backups, shared rate-limit cache, and production Shopify URLs
- Monitored privacy contact, operating owner, and public marketing launch review
- Shopify App Store submission and production-merchant compliance verification
- External advertising and courier/ERP connectors, which remain future integrations rather than M1–M6 requirements

Wave 1 live evidence is recorded in [sellora-m1-m6-live-smoke-2026-09-08.md](./qa/sellora-m1-m6-live-smoke-2026-09-08.md).
