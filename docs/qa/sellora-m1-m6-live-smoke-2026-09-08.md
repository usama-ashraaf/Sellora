# Sellora M1–M6 live smoke — 2026-09-08 (PKT)

Scope: Wave 1 Shopify development stores against Partner app version `sellora-13`. The public endpoint used for this smoke is a temporary Cloudflare quick tunnel and is not a production host.

## Result

PASS for the local/Wave 1 M1–M6 done definition.

## Shopify installation and registrations

- Both stores were reauthorized with `read_products`, `read_inventory`, `read_locations`, `read_orders`, `write_pixels`, `read_customer_events`, `write_products`, and `write_discounts`. A live `currentAppInstallation` query returned all eight plus Shopify's related `read_pixels` and `read_discounts` scopes on each store.
- Both stores expose 8 products and 21 variants after catalog synchronization.
- All seven operational webhook registrations were present on each store: product create/update/delete, inventory update, app uninstall, order create, and order update.
- Web pixels were already registered against the current tunnel: Outfitters-like `gid://shopify/WebPixel/2563834086`; Sapphire-like `gid://shopify/WebPixel/2465464510`.
- Compliance topics are declared in `shopify.app.toml` and were released with `sellora-13`.

## Customer journey and dashboard

- Outfitters-like: a storefront visit to Coastal Crew Tee produced product-view and add-to-cart rows tied to its Shopify product ID.
- Sapphire-like: a storefront visit to Meadow Printed Kurti produced product-view, add-to-cart, and checkout-started rows tied to its Shopify product ID.
- Sapphire-like dashboard showed 8 product views, 4 cart additions, 2 checkout starts, 1 completed checkout, and 2 synchronized orders at the final evidence read.
- Recommendation cards identified an individual product and combined orders/intent with inventory and size coverage. The Meadow candidate showed 148 available units and 100% size coverage.

## Reviewed Shopify writes

- Product repair: cleared the invalid compare-at value for Mist Chiffon Dupatta variant `SF-ODD-OS`. A fresh Shopify catalog synchronization returned `compare_at_price: null` for the exact targeted variant.
- Promotion: created `SELLORA095422`, “Sellora: Meadow Printed Kurti 10% off”. A separate Admin API read returned status `ACTIVE`, starting `2026-09-07T22:03:00Z` and ending `2026-09-14T22:03:00Z`.
- The first discount attempt exposed a Shopify GraphQL input mismatch: `context.all` requires enum value `ALL`. The client and regression test were corrected, then the normal refresh, reapproval, and retry flow succeeded.

## Bounded autopilot

- Enabled a Sapphire-like policy allowing only `social_ad_candidate`, ran it once, and then used the kill switch.
- The run completed with 0 applied and 22 skipped; durable run details recorded `kind_not_allowed: 22`.
- Final policy state is stopped. The local write environment gate is disabled after smoke verification.

## Automated checks

- `bin/rails test`: 195 runs, 793 assertions, 0 failures, 0 errors, 0 skips.
- Marketing JavaScript: 4 checks passed; web-pixel consent/routing suite passed.
- `bin/rubocop`: 157 files inspected, no offenses.
- `bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error`: 0 errors and 0 security warnings. The binstub's online latest-version check was bypassed because it failed before scanning when its release lookup returned no result.
- `bin/rails zeitwerk:check`: all application code eager-loaded successfully.
- Importmap and Bundler audits: no vulnerabilities found.
- `git diff --check`: clean.

## Production work outside this done definition

- Replace the quick tunnel with a stable HTTPS application host and update Shopify URLs.
- Configure production backups, a shared rate-limit cache, monitoring, and alerting.
- Publish a monitored privacy contact and finish the public-launch/App Store review.
- Advertising network campaign execution and courier/ERP proof of COD collection require separate external integrations.
