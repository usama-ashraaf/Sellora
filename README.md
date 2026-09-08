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

Open http://127.0.0.1:3000. The pilot interest form collects name, work email, store URL and platform only. Valid submissions are stored in `pilot_requests`; nothing is emailed and submitting does not connect a store. Requests are deleted after 365 days or earlier after a verified deletion request. A monitored privacy contact is still required before production launch. Operators can inspect requests through the Rails console; there is no public listing endpoint. Do not copy request records or unfiltered query output into logs or shared reports.

## Checks

```sh
bin/rails test
node test/javascript/marketing_controllers_test.cjs
node test/javascript/web_pixel_consent_test.cjs
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

The JavaScript checks use built-in Node functionality and need no npm dependencies. If you precompile assets in development, run `bin/rails assets:clobber` afterward to restore live asset updates.

Pre-production marketing plus a live Shopify development-store pilot. Catalog, order, pixel, recommendation, promotion-readiness, reviewed-action, compliance, retention and bounded-autopilot flows are implemented. Promotion readiness uses demand by variant to recommend Promote, Limit, or Block and to estimate safe order and campaign-spend capacity. Stable hosting, production operations, App Store review, and a monitored privacy contact must be finalized before public launch. See the [2026-09-08 live smoke report](docs/qa/sellora-m1-m6-live-smoke-2026-09-08.md).
