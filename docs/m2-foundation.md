# M2 — Application foundation

Status: implemented on main (this document describes the foundation slice).

## What shipped

1. **Accounts, memberships, roles**
   - `Account`, `User` (email stub), `Membership` (`owner` / `admin` / `member`)
   - Email-based membership allowed before a `User` is linked
   - **No Devise** — session-free service objects for now (`Accounts::EnsureDemoAccount`)
   - Default account name: **Sellora Demo**

2. **Account scoping for stores**
   - `Shop belongs_to :account` (nullable column; migration backfills existing shops onto Sellora Demo)
   - `Shop.for_account(account)` scope
   - Demo / findings / activity queries use account boundaries

3. **Versioned audit rules engine (clothing)**
   - `AuditRuleSet` (`version`, `name`, `active`, `domain`)
   - `AuditRule` (`rule_key`, `severity`, `config` jsonb)
   - `AuditFinding` evidence rows
   - Seed: `Audit::ClothingRulesSeed` → clothing **v1** (`size_gap`, `compare_at_anomaly`, `missing_size_attr`, plus brief themes)
   - Stub evaluator: `Audit::Runner` against `CatalogProduct` / `CatalogVariant`

4. **Activity event contract**
   - `ActivityEvent` + `Activity::Ingest`
   - Contract doc: [activity-events.md](./activity-events.md)

5. **Labeled fictional in-app demo**
   - Open routes: **`/demo`** and **`/app`**
   - Big **FICTIONAL DEMO / ILLUSTRATIVE DATA** banners
   - Shows account-scoped catalog counts, active rule set version, sample findings
   - Marketing routes (`/`) untouched

6. **Auth stub (documented)**
   - M2 deliberately has no session cookies / passwords
   - `/demo` is open for local and review use
   - Real authentication lands in a later milestone

## Seeds

```bash
bin/rails db:seed
```

Ensures Sellora Demo account + owner membership + clothing v1 rules.

## Tests

`bin/rails test` covers models, account scoping, rule seed, runner stub, activity ingest, and the demo page.
