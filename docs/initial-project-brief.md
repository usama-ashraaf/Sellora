Copy and paste this into your new session:

---

We are building **Sellora**, a SaaS for clothing brands, starting with Pakistan and expanding to other markets.

**Start with the marketing website.** The Rails app already exists in this project. Inspect it before making changes. This plan describes the full product direction, but only the marketing website is authorized for the first milestone.

### 1. Product purpose

Sellora helps clothing brands:

- Find mistakes in product information, pricing and promotions.
- Understand product performance using shopping activity, inventory and actual order outcomes.
- Review suggested improvements.
- Eventually automate selected actions within merchant-defined limits.

The buyer is the brand owner or head of ecommerce. Daily users include catalog, merchandising, marketing and ecommerce operations teams.

Our reference market includes brands such as Sapphire, Khaadi, Maria B and Outfitters. **They are potential customer examples, not customers or partners.** Do not imply they use Sellora.

Existing Shopify tools overlap with this idea. Our proposed focus is clothing-specific audits and useful recommendations informed by size availability, stock and final order outcomes. This differentiation needs validation.

### 2. Immediate milestone: marketing website

Build a polished, modern, responsive marketing website for **Sellora**, with scroll animations that explain the product.

The website should attract pilot customers while the application is under development.

**Proposed headline**

> Catch catalog mistakes. Make smarter sales decisions.

**Supporting copy**

> A clearer view of your clothing store—from product information and size availability to the products shoppers actually buy.

**Primary CTA:** Join the pilot  
**Secondary CTA:** See how it works

Use clear language for business owners. Avoid vague AI claims, guaranteed revenue improvements or claims that unfinished integrations already work.

### 3. Visual direction

Aim for a premium editorial design suitable for a fashion technology product:

- Warm ivory backgrounds and near-black typography.
- One vivid accent, initially electric lime.
- Large, confident typography and generous spacing.
- Detailed product interface demonstrations.
- Restrained garment imagery where useful.
- Consistent components, spacing and motion.
- Responsive layouts designed for both desktop and mobile.

Use judgment to make the design feel distinctive. Avoid filling the page with repetitive feature cards or decorative animations that distract from the product.

### 4. Website structure and animation story

**Navigation**

Sellora wordmark, Product, How it works, FAQ and Join the pilot.

**Hero**

Introduce the promise and show an illustrative product interface. Use a short entrance animation for the headline and interface.

**The problem**

Show examples of operational issues:

- Missing size information.
- Conflicting product details.
- An inconsistent sale price.
- A promoted product with poor size availability.

Clearly label examples as demonstrations.

**Catalog audit demonstration**

Use a sticky desktop section where scrolling advances through:

1. A product with an issue.
2. The detected evidence.
3. A suggested correction.
4. A preview of the team’s review step.

Do not imply a real store was audited.

**Sales monitoring demonstration**

Show how Sellora will connect:

Product exposure → product view → cart → checkout → order outcome.

Explain the difference between attention, purchase intent and completed sales. Use illustrative data, clearly labeled.

**Normal days / sale days**

Add an interactive toggle that changes the example priorities:

- Normal days: catalog quality, product discovery and availability.
- Sale days: offer accuracy, stock coverage and promotion performance.

**Team control**

Explain that teams review recommendations. Present autopilot as a later, optional capability.

**Getting started**

Explain the planned Shopify-first pilot:

1. Connect an authorized store.
2. Review catalog findings and available activity data.
3. Evaluate recommendations with the team.

Mark this as the planned workflow until the integration is implemented.

**Pilot request**

A short form for name, work email, store URL and platform.

Do not simulate a successful submission. Inspect existing infrastructure and propose a real storage or delivery mechanism before enabling collection. Add suitable privacy information.

**FAQ and footer**

Address:

- Who Sellora is for.
- Shopify-first support.
- What public audits can inspect.
- What requires an installed integration.
- Whether Sellora changes the store automatically.
- Pilot availability.

Do not fabricate contact details, testimonials or customer logos.

### 5. Animation and accessibility requirements

- Preserve normal browser scrolling.
- Use scroll motion to explain changes in the interface.
- Use simpler vertical transitions on mobile.
- Respect `prefers-reduced-motion`.
- Keep essential content readable without animation.
- Support keyboard navigation and visible focus states.
- Maintain readable contrast.
- Avoid excessive movement, loading delays and layout shifts.

Start with CSS, lightweight JavaScript and Stimulus. Ask before adding animation libraries or other dependencies.

### 6. Rails architecture

Keep the stack simple:

- Ruby on Rails.
- PostgreSQL.
- ERB templates.
- Hotwire and Stimulus.
- Plain CSS initially.
- Puma.
- Active Job and Solid Queue for later background processing.

Inspect installed versions and existing conventions. Do not upgrade dependencies automatically.

Keep the marketing website in this Rails application. Do not introduce React, a separate frontend application, Redis or microservices without a concrete need and approval.

Future application modules should remain inside a modular Rails monolith.

### 7. Future module A: catalog and promotion audits

This is product context, **not part of the immediate website implementation**.

The system will discover the catalog daily and process changes from connected platforms.

Content audits should run when:

- A product is new.
- Relevant product content changes.
- Audit rules change.
- Shared content or campaign changes affect the product.

Store a fingerprint, rule version and last checked time. Unchanged products can skip repeated content checks.

However, stock, prices, links and campaign dates require separate freshness checks even when descriptions remain unchanged.

Potential clothing rules include:

- Missing descriptions, images or size information.
- Inconsistent stitched/unstitched details.
- Conflicting piece counts.
- Missing required garment attributes.
- Invalid selling-price and compare-at-price relationships.
- Expired or inconsistent promotion information.

Do not invent fabric, care or garment facts. Suggestions must identify what the team needs to verify.

Each finding should include evidence, severity, affected product or variant, suggested action and resolution history.

Later, supported fixes should offer a before/after preview, approval and source-change checks before applying.

### 8. Future module B: sales and promotion monitoring

Combine:

- Product exposure and placement.
- Product views.
- Cart actions.
- Checkout activity.
- Variant and size availability.
- Orders, payments, cancellations and refunds.
- Delivery and COD collection outcomes where available.

Interpret signals carefully:

- Low traffic alone is not evidence of low demand.
- High views with low cart activity warrant investigation.
- Cart or checkout abandonment does not establish one specific cause.
- A checkout event is not proof of payment.
- Placed COD orders are not collected revenue.
- Revenue is not profit.

Show metric definitions, time windows and data limitations. Profit reporting requires costs and final order outcomes.

Begin with a small number of useful, evidence-backed recommendations. Evaluate whether merchant teams accept them and save time.

### 9. Connector strategy and activity tracking

**Shopify is the first connector.** The internal data model must remain platform-neutral so future connectors can support other clothing brands.

Data sources:

- Public pages: visible catalog information only.
- Commerce API: products, variants, inventory and orders.
- Verified webhooks: source changes, with retries and reconciliation.
- Shopify Web Pixel Extension: supported shopping events.
- Storefront extension: additional semantic interactions such as size selection and visible product position.
- CSV, courier or ERP sources: costs and final COD outcomes.
- Advertising APIs: later, when required by a pilot.

A public audit cannot reveal private traffic or orders.

Browser tracking must honor applicable consent signals. It will remain incomplete because of blockers and network failures.

Never expose private API credentials in storefront JavaScript. Keep public browser collection separate from authenticated server integration endpoints.

Verify current platform scopes, API versions and restrictions when implementing the connector.

### 10. Future data and security foundation

Plan for:

- Accounts, memberships and roles.
- Stores and platform connections.
- Products, variants and inventory.
- Audit runs and findings.
- Activity events.
- Orders and outcomes.
- Campaigns and recommendations.
- Reviewed actions and execution history.

Scope every record and request to the authorized account/store. Do not trust a browser-provided store ID.

Use:

- Encrypted integration credentials.
- Environment variables or approved secret storage.
- Event deduplication.
- Webhook signature validation.
- Durable receipts and retries.
- Periodic source reconciliation.
- Explicit currency handling.
- Retention, deletion and uninstall handling.
- Minimal personal data collection.

### 11. Delivery sequence

**Milestone 1 — marketing website**

Build and verify the responsive website and animation story. Complete a working pilot CTA destination before calling the website launch-ready. Present it for review before publishing.

**Milestone 2 — application foundation**

Account/store boundaries, shared catalog, versioned audit rules, activity contract, tests and a clearly labeled fictional demo.

**Milestone 3 — Shopify development-store integration**

Installation, catalog sync, verified webhooks, supported pixel events, separate order records and uninstall/privacy handling.

**Milestone 4 — read-only merchant pilot**

Daily discovery, change-aware audits, freshness checks, product monitoring, useful recommendations and operational visibility.

**Milestone 5 — reviewed actions**

Before/after previews, explicit approval, source conflict detection, execution history and recovery.

**Milestone 6 — bounded autopilot**

Merchant-selected actions with minimum evidence, cooldowns, spending caps, stock constraints, margin floors where costs are known, monitoring and a kill switch.

Do not start autonomous pricing or advertising in the initial milestones.

### 12. Subscription hypotheses

These prices were discussed as hypotheses and are **not finalized or ready for publication**:

- Audit: approximately PKR 15,000/month.
- Growth: approximately PKR 45,000/month.
- Automation: approximately PKR 100,000+/month.
- Enterprise integrations and onboarding: custom pricing.

Consider per-store plans with clear product and event allowances. Validate willingness to pay and operating costs through pilots before implementing billing.

For the first marketing website, emphasize joining the pilot instead of publishing unvalidated packages.

### 13. Existing work and boundaries

A preliminary Rails foundation was created in another workspace before implementation was paused. It included a fictional catalog dashboard, deterministic audits and a private event endpoint.

Do not assume that code exists here or that it implements Shopify browser tracking. Inspect this project independently. Do not import or overwrite code without reviewing it.

The chosen name is **Sellora**. Domain availability and trademark status have not been verified.

### 14. Working instructions

- Inspect the repository and applicable instructions first.
- Start with the marketing website only.
- Explain the proposed implementation briefly, then proceed within the agreed scope.
- Follow existing conventions.
- Ask before adding dependencies.
- Keep secrets out of source files and logs.
- Do not modify unrelated files.
- Do not purchase domains, deploy publicly or push remotely without explicit approval.
- Do not send emails or messages without authorization.
- Clearly distinguish functioning features from demonstrations and planned capabilities.
- Verify desktop and mobile layouts, keyboard access, reduced motion and form behavior.
- Report what was built, how it was checked and what remains unfinished.

**First action: inspect this Rails project, then build Sellora’s marketing website as a reviewable local implementation.**