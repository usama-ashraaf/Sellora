# Sellora full project and Sapphire-reference E2E sign-off — 2026-09-08 (PKT)

## Verdict

**PASS for the local/Wave 1 M1–M6 definition with the development-store constraints below.** The Sapphire-like Shopify development store contains eight current public Sapphire product references, the storefront and Sellora use PKR, a real Shopify test checkout reached Sellora as paid order `#1004`, the consented pixel journey is product-specific, promotion guidance is consistent with the readiness planner, a reviewed discount was written to Shopify and redeemed at checkout, and bounded autopilot was returned to its stopped state.

This is not a public-launch or Shopify App Store sign-off. The app still uses a temporary Cloudflare quick tunnel (`shopify.app.toml:4-11`), and production hosting, operations, privacy ownership, and external advertising/courier integrations remain separate work (`docs/m1-m3-done-definition.md:39-43`).

## What Sellora offers and what works

| Milestone | Merchant value | Verified implementation |
| --- | --- | --- |
| M1 — Marketing | Explains the clothing-commerce problem and accepts pilot interest | Responsive Rails marketing site and PostgreSQL-backed pilot form are locally complete (`docs/m1-m3-done-definition.md:5-9`). Public publishing and the monitored privacy contact remain open. |
| M2 — Foundation | Keeps each merchant/store isolated and audits clothing catalog quality | Accounts, shops, platform-neutral catalog, versioned clothing rules, immutable activity, labeled fictional demo, and account/shop validation are implemented (`docs/m1-m3-done-definition.md:11-13`). |
| M3 — Shopify | Installs in Shopify, mirrors the catalog and orders, receives source changes, and observes the consented journey | The active Partner version is `sellora-14`. Both Wave 1 stores have catalog, order, webhook, and pixel coverage; the configured OAuth ceiling includes the eight required read/write scopes (`config/initializers/shopify.rb:3-17`). Tokens remain encrypted and pixel submission uses an installation-bound capability (`docs/privacy-retention.md:5-19`). |
| M4 — Merchant intelligence | Finds catalog mistakes and turns demand, orders, stock, size coverage, cost, cancellation, and refund evidence into actions | Daily/on-demand discovery runs catalog and order sync, audits, promotion readiness, and recommendations (`app/services/pilot/discover.rb:15-34`). The embedded dashboard exposes Overview, Promotion Planner, Recommendations, Products, Orders, Activity, and Actions (`app/controllers/shopify/app_controller.rb:10-35`). |
| M5 — Reviewed changes | Shows the exact proposed change, requires approval, detects source drift, writes to Shopify, and records recovery/history | Proposal, approval/rejection, fingerprint conflict detection, apply, failure, and retry are implemented (`app/services/pilot/reviewed_actions.rb:34-127`). Shopify writes require both the granted scope and the protected server gate (`app/services/shopify/action_executor.rb:7-18`). |
| M6 — Bounded autopilot | Executes only selected low-risk action kinds within evidence, stock, size, margin, cooldown, daily-count, and discount-cost limits | Policy, durable runs, recurring runner, merchant controls, and kill switch are implemented (`docs/pilot-ops-m4-m6.md:32-41`). Autopilot does not set prices, alter inventory, or launch social ads (`app/views/shopify/app/_actions.html.erb:37-46`). |

## Sapphire-reference development catalog

Public facts were captured from [Sapphire Pakistan](https://pk.sapphireonline.pk/) on 8 September 2026. The source site describes these public sections as trending/best-selling, but it does not expose private order counts, inventory, costs, refunds, or ad performance. Sellora therefore treats the copied records as public catalog references, not proof of Sapphire sales.

| Product | Public SKU | Public price | Public reference |
| --- | --- | ---: | --- |
| Printed Lawn Shirt | `PRW26CWMV96S_999` | PKR 4,990 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PRW26CWMV96S_999.html) |
| 2 Piece - Printed Seersucker Suit | `PW26CASTV823_999` | PKR 9,990 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PW26CASTV823_999.html) |
| Printed Seersucker Shirt | `PRW26CTV703S_999` | PKR 5,590 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PRW26CTV703S_999.html) |
| 2 Piece - Solid Textured Cotton Suit | `PBWSCWMRV808_999` | PKR 8,590 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PBWSCWMRV808_999.html) |
| 2 Piece - Solid Cotton Linen Suit | `PEW26CAWMV95_999` | PKR 8,990 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PEW26CAWMV95_999.html) |
| 2 Piece - Embroidered Cotton Linen Suit | `PR26SCSTV816_999` | PKR 10,990 | [Source](https://pk.sapphireonline.pk/collections/ready-to-wear/products/PR26SCSTV816_999.html) |
| 3 Piece - Embroidered Lawn Suit | `3PESGS26V763` | PKR 7,590 | [Source](https://pk.sapphireonline.pk/collections/unstitched/products/3PESGS26V763.html) |
| Textured Maxi Dress | `WTOPV0826009_999` | PKR 7,990 | [Source](https://pk.sapphireonline.pk/collections/western-wear/products/WTOPV0826009_999.html) |

No images were copied. Titles, public SKUs, prices, descriptions, garment facts, product types, tags, handles, and the available public size labels were loaded into the existing eight-product/21-variant QA shape. Variant inventory remains synthetic so low-stock and stock-out cases stay testable. Unit cost is a disclosed synthetic QA assumption of 55% of public price because public cost data does not exist. Every product description names the capture date, public source, lack of affiliation/endorsement, omitted images, and synthetic stock/cost assumptions.

The Shopify store currency was changed from USD to PKR after preserving the earlier test history. Current storefront pages display `Rs.7,590.00` for the lawn suit. Sellora now stores Shopify's current `shop.currencyCode` during catalog sync (`app/services/shopify/admin_client.rb:16-71`, `app/services/shopify/catalog_sync.rb:87-96`) and uses it before historical order/event currency (`app/services/pilot/promotion_readiness.rb:287-297`). Orders `#1001`–`#1003` correctly retain their original USD history; new order `#1004` is PKR.

## Live customer and merchant test

### Customer journey

1. Opened the public-reference product page and verified title, public SKU, labeled garment facts, one-size option, disclosure, omitted image, and PKR 7,590 price.
2. Added and removed products to verify product/variant-specific `product_added_to_cart` and `product_removed_from_cart` events.
3. Entered checkout with clearly fictional QA customer data. The pixel emitted `checkout_started`, `payment_info_submitted`, and `checkout_completed`, including the Shopify product/variant IDs and line item. The extension subscribes to all seven supported events and maps product, variant, SKU, quantity, order, value, and currency fields (`extensions/sellora-web-pixel/src/index.js:1-69`).
4. Completed Shopify test order `#1004` with confirmation `WX5TWC0KQ`. Shopify and Sellora both report paid, PKR 9,051.72 total, PKR 759 discount, one `3PESGS26V763-OS` unit, and the exact product/variant IDs.
5. Cleared the cart after the smoke flow.

### Dashboard and intelligence

- Final synchronized state: 8 products, 21 variants, 4 orders, 0 open audit findings.
- The latest pixel sequence shows product view → cart add → checkout start → payment step → completed checkout in PKR. The Activity view presents journey stage, explanation, product, SKU, variant, quantity, value, consent, and time (`app/views/shopify/app/_activity.html.erb:1-42`).
- The lawn suit is **Promote, 100/100, medium confidence**, with 2 paid orders, 2 units, 12 safe additional orders, and a PKR 30,360 spend ceiling. The decision engine weights variant-level view, cart, checkout, completion, and paid-unit demand and blocks hard stock/economics constraints (`app/services/pilot/promotion_readiness.rb:4-12`, `app/services/pilot/promotion_readiness.rb:63-103`, `app/services/pilot/promotion_readiness.rb:191-213`).
- Recommendations now use the same current promotion decisions. Only products marked Promote can become featured/social candidates, while restock advice is tied to safe-order or size-coverage constraints (`app/services/pilot/recommendations.rb:69-103`). Applied/rejected reviewed actions stay closed during later refreshes, preventing duplicate discount proposals (`app/services/pilot/recommendations.rb:211-217`).
- Final open recommendation: **Feature on storefront: 3 Piece - Embroidered Lawn Suit**. The already applied social recommendation remains dismissed.

### Reviewed action and storefront result

- Prepared the social recommendation as an exact product-specific 10% discount proposal.
- Confirmed the server write gate blocked the first apply while disabled.
- Enabled the gate only for this approved development-store test, used the normal refresh/reapproval path, and applied the action.
- Shopify Admin GraphQL read-back returned discount ID `gid://shopify/DiscountCodeNode/2363792359614`, code `SELLORA292030`, status `ACTIVE`, 10%, one-use-per-customer, the exact lawn-suit product ID, and the configured 8–15 September window.
- A customer checkout applied the code automatically: PKR 7,590 became PKR 6,831, saving PKR 759. The final paid order also added PKR 2,220.72 development-store shipping.
- The local Shopify write gate was disabled again after verification.

### Bounded autopilot

- Saved an enabled policy allowing only `social_ad_candidate`, with inventory/size protection and the existing evidence, cooldown, daily action, discount, and cost limits.
- Ran it after the social action had already been applied. It applied nothing and recorded one skip because the remaining featured recommendation kind was not allowed.
- Used the kill switch. Final policy state is stopped.

## Bugs found and corrected during sign-off

1. Resolved catalog issues remained open after Shopify data was corrected. `Audit::Runner` now resolves findings not emitted by the rules evaluated in that pass and reopens a resolved finding if the issue returns (`app/services/audit/runner.rb:50-70`, `app/services/audit/runner.rb:220-249`).
2. Real Shopify descriptions did not populate the structured garment facts expected by the clothing rules. Catalog sync now extracts only explicit `Fit`, `Fabric`, `Piece count`, `Care`, and `Stitched` labels; it does not infer missing facts (`app/services/shopify/catalog_sync.rb:162-180`).
3. Fixed inventory thresholds could contradict Promotion Planner margin and safe-capacity decisions. Recommendation selection now consumes the planner's current product decision (`app/services/pilot/recommendations.rb:13-20`, `app/services/pilot/recommendations.rb:83-103`, `app/jobs/shopify/order_sync_job.rb:11-18`).
4. A completed action could be offered again after recommendation refresh. Applied/rejected recommendation/action pairs now stay closed (`app/services/pilot/recommendations.rb:211-217`).
5. The planner could label a current PKR catalog using a historical USD order. Catalog sync now records Shopify's authoritative current currency and the planner prefers it (`app/services/shopify/admin_client.rb:16-71`, `app/services/pilot/promotion_readiness.rb:287-297`).
6. The overview metric was labeled “Actions to review” while counting open recommendations. It now says “Open recommendations” (`app/views/shopify/app/_overview.html.erb:2-7`).

## Automated verification

- `bin/rails test`: 215 runs, 899 assertions, 0 failures, 0 errors, 0 skips.
- Marketing JavaScript: 4 checks passed.
- Web pixel consent and routing suites: passed.
- `bin/rubocop`: 166 files inspected, no offenses.
- `bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error`: 0 errors, 0 warnings. The repository binstub's latest-version lookup failed before scanning, so the bundled scanner was used directly.
- Bundler audit: no vulnerabilities.
- Importmap audit: no vulnerable packages.
- `bin/rails zeitwerk:check`: all application code eager-loaded successfully.

## Remaining outside local/Wave 1 sign-off

- Stable production HTTPS hosting, production Shopify URLs, backups, a shared rate-limit cache, monitoring, and alerting.
- A monitored privacy contact, production privacy-policy review, pilot operating owner, and public marketing publish decision.
- Shopify App Store submission and production-merchant compliance delivery verification.
- Billing/subscriptions. The prices in the original brief remain unvalidated hypotheses and are not implemented plans.
- Direct Meta/TikTok/Google ad-platform execution. Sellora identifies candidates and prepares Shopify actions; it does not launch campaigns.
- A storefront/theme extension that automatically changes featured placement. The current feature recommendation opens Shopify customization for the merchant.
- Courier/ERP feeds for delivery, returns, and COD cash collection. Shopify order/fulfillment/gateway status is retained as a labeled proxy only (`docs/promotion-readiness.md:43-45`).
- Production data quality: merchant-provided unit cost, shipping, acquisition-cost, ROAS, COD-failure, and final outcome inputs must replace QA assumptions.
