# Sellora

A Rails marketing website for Sellora, a clothing-brand catalog and sales operations product in development. The first milestone contains illustrative product demos and a real local pilot-interest form.

- [Original project brief](docs/initial-project-brief.md)
- [Implementation review, checks and remaining launch work](docs/marketing-review.md)
- [Shopify local install (M3 Phase A)](docs/shopify-install.md)
- [Shopify API scopes](docs/shopify-scopes.md)

## Run locally

The existing stack uses Ruby 3.3.10, Rails 8.1.3.1, PostgreSQL, ERB, Hotwire/Stimulus, plain CSS and Puma. Dependencies were not changed for this milestone.

With the existing bundle installed and PostgreSQL running:

```sh
bin/rails db:prepare
bin/rails server -b 127.0.0.1 -p 3000
```

Open http://127.0.0.1:3000. The pilot interest form collects name, work email, store URL and platform only. Valid submissions are stored in `pilot_requests`; nothing is emailed and submitting does not connect a store. Retention is for pilot evaluation (delete on request / when the pilot ends). The listed privacy contact is a temporary placeholder until production launch. Operators can inspect requests through the Rails console; there is no public listing endpoint. Do not copy request records or unfiltered query output into logs or shared reports.

## Checks

```sh
bin/rails test
node test/javascript/marketing_controllers_test.cjs
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

The JavaScript checks use built-in Node functionality and need no npm dependencies. If you precompile assets in development, run `bin/rails assets:clobber` afterward to restore live asset updates.

Pre-production marketing + pilot interest collection. Privacy copy uses a temporary placeholder contact (`privacy-placeholder@sellora.example`, not monitored) until a production contact and hosting ownership are finalized. Shopify OAuth + webhook scaffolding (M3 Phase A) is documented in docs/shopify-install.md; later sync/order milestones remain future work.
