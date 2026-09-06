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
- [ ] Live ops: Partner URL/scopes, CLI pixel deploy, re-OAuth, storefront smoke (manual)

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
- [x] `AutopilotPolicy` (allowlist, severity, cooldown, daily cap, stock gate)
- [x] Kill switch (`kill_switch!` / enabled default false)
- [x] `Pilot::Autopilot` runner
- Out of scope: autonomous pricing / advertising

## Still unfinished (honest)
- Live Wave 1 pixel deploy + E2E (needs your CLI auth)
- Concrete Admin `productUpdate` payloads per action kind (patch stub only)
- Shopify compliance webhooks (customers/redact etc.) before production
- Public marketing launch
