# M4–M6 pilot ops (local)

Lean read-only pilot → reviewed actions → bounded autopilot on the existing Rails monolith.

## M4 — Read-only merchant pilot

| Piece | Location |
|-------|----------|
| Change-aware audits | `Audit::Fingerprint`, `Audit::Runner` (skip unchanged content; freshness always) |
| Discovery | `Pilot::Discover`, `Pilot::DiscoverShopJob`, `Pilot::DailyDiscoveryJob` |
| Recommendations | `Pilot::Recommendations` over findings + traffic/intent signal |
| Schedule | `config/recurring.yml` → daily discovery |
| Ops UI | Embedded `Shopify::AppController#show` |
| Rake | `sellora:discover[shop]` / `sellora:discover_all` |

After catalog sync, `Shopify::CatalogSyncJob` also runs audit + recommendations.

Honesty: recommendations tell the team what to **verify**. No invented garment facts. Pixel traffic signals are incomplete.

## M5 — Reviewed actions

| Piece | Location |
|-------|----------|
| Model | `ReviewedAction` (before/after snapshots, statuses) |
| Workflow | `Pilot::ReviewedActions` propose → approve/reject → apply |
| Conflict | Fingerprint mismatch → `conflict` status |
| Writes | Local apply by default; Shopify write only if `write_products` **and** `SELLORA_ALLOW_WRITES=true` |
| Patch stub | `Shopify::ProductPatch` (no autonomous pricing) |

Rake: `sellora:propose_action[id]`, `sellora:apply_action[id]`

## M6 — Bounded autopilot

| Piece | Location |
|-------|----------|
| Policy | `AutopilotPolicy` (enabled default **false**, kinds allowlist, severity floor, cooldown, daily cap, require_in_stock, kill switch) |
| Runner | `Pilot::Autopilot` / `Pilot::AutopilotShopJob` |
| Rake | `sellora:autopilot[shop]`, `sellora:autopilot_kill[shop]` |

No autonomous pricing or advertising.

## Uninstall

Shop uninstall also purges recommendations, reviewed actions, and autopilot policy.

## Related

- [privacy-retention.md](./privacy-retention.md)
- [shopify-scopes.md](./shopify-scopes.md)
- [order-sync.md](./order-sync.md)
