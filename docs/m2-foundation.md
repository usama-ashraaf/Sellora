# M2 — Application foundation

Status: implemented on main (this document describes the foundation slice + S2 hardens).

## What shipped

1. **Accounts, memberships, roles**
   - `Account`, `User` (email stub), `Membership` (`owner` / `admin` / `member`)
   - Email-based membership allowed before a `User` is linked
   - **No Devise** — session-free service objects for now (`Accounts::EnsureDemoAccount`)
   - Default account name: **Sellora Demo** (fictional demo workspace only)

2. **Account scoping for stores**
   - `Shop belongs_to :account` (nullable column; historical migration backfilled Wave 1 shops onto Sellora Demo)
   - `Shop.for_account(account)` scope
   - Demo / findings / activity queries use account boundaries
   - **S2:** Shopify OAuth `persist_shop!` always sets `account_id` — creates a dedicated `Account` named `Store <domain>` on first install when missing; preserves existing account on re-install. Never attaches OAuth shops to Sellora Demo.
   - **S2:** `Accounts::EnsureDemoAccount` no longer vacuums `Shop.where(account_id: nil)` onto Demo.

3. **Versioned audit rules engine (clothing)**
   - `AuditRuleSet` (`version`, `name`, `active`, `domain`)
   - `AuditRule` (`rule_key`, `severity`, `config` jsonb)
   - `AuditFinding` evidence rows
   - Seed: `Audit::ClothingRulesSeed` → clothing **v1** (`size_gap`, `compare_at_anomaly`, `missing_size_attr`, plus brief themes)
   - Stub evaluator: `Audit::Runner` against `CatalogProduct` / `CatalogVariant`
   - **S2:** Runner upserts on natural key `(shop_id, audit_rule_id, catalog_product_id, catalog_variant_id)` (`NULLS NOT DISTINCT` unique index) — re-runs do not duplicate findings.

4. **Activity event contract**
   - `ActivityEvent` + `Activity::Ingest`
   - Contract doc: [activity-events.md](./activity-events.md)

5. **Labeled fictional in-app demo**
   - Routes: **`/demo`** and **`/app`**
   - Big **FICTIONAL DEMO / ILLUSTRATIVE DATA** banners
   - Shows account-scoped catalog counts, active rule set version, sample findings
   - Marketing routes (`/`) untouched

6. **Auth gate for `/demo` and `/app` (S2)**
   - HTTP Basic using `DEMO_HTTP_BASIC_USER` and `DEMO_HTTP_BASIC_PASSWORD`
   - If either env var is blank → **503** (fail closed; demo findings/catalog stay hidden)
   - Wrong/missing credentials → **401** with `WWW-Authenticate`
   - Marketing `/` remains public (no gate)
   - Still no Devise / session cookies for merchants — lightweight preview gate only

## Demo HTTP Basic

```bash
# .env (never commit real passwords)
DEMO_HTTP_BASIC_USER=demo
DEMO_HTTP_BASIC_PASSWORD=change-me
```

Browse `/demo` or `/app` with those credentials. Unauthenticated clients cannot see demo findings or catalog counts.

## Seeds

```bash
bin/rails db:seed
```

Ensures Sellora Demo account + owner membership + clothing v1 rules. Does **not** reassign orphan shops.

## Tests

`bin/rails test` covers models, account scoping, OAuth `account_id`, no orphan→Demo vacuum, rule seed, idempotent runner, activity ingest, and HTTP Basic–gated demo pages.
