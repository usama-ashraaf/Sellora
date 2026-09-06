# Marketing website review — local milestone

The local implementation covers the marketing website and a real PostgreSQL-backed pilot-interest form. Public launch has not been performed. The original brief is preserved verbatim in `docs/initial-project-brief.md`.

## Requirement review

| Requirement | Implementation and evidence | Limits |
| --- | --- | --- |
| Marketing-only milestone in existing Rails app | `config/routes.rb:2`; `app/views/marketing/show.html.erb:1` | Product modules remain future work. |
| Headline, supporting copy, navigation and both CTAs | `app/views/marketing/show.html.erb:2` | Pilot CTA leads to local collection. |
| Ivory, near-black, lime and responsive editorial design | `app/assets/stylesheets/application.css:11`; `app/views/marketing/_workspace.html.erb:1` | Uses system typography; no downloaded font dependency. |
| Four operational issue examples | `app/views/marketing/_story.html.erb:1` | Explicitly fictional; no real store audited. |
| Four-step sticky desktop catalog narrative | `app/views/marketing/_story.html.erb:13`; `app/javascript/controllers/audit_controller.js:1` | Product concept only. Mobile and reduced-motion branches place evidence beside each narrative step. |
| Exposure → view → cart → checkout → final outcome | `app/views/marketing/_story.html.erb:38` | Fictional seven-day event counts, metric definitions and limitations disclosed. |
| Normal/sale-day priorities | `app/views/marketing/_priorities.html.erb:1`; `app/javascript/controllers/priorities_controller.js:1` | Demonstration; no campaign changes. Without JS both examples remain readable. |
| Team review and future optional autopilot | `app/views/marketing/_priorities.html.erb:19` | No automated store actions implemented. |
| Planned Shopify-first onboarding | `app/views/marketing/_priorities.html.erb:24` | Integration is explicitly in development. |
| Real pilot storage and truthful errors | `app/controllers/pilot_requests_controller.rb:5`; `app/models/pilot_request.rb:3`; `db/migrate/20260906000000_create_pilot_requests.rb:1` | Stores four fields and timestamps; no email delivery or admin interface. |
| Collection privacy | `app/views/marketing/_pilot.html.erb:1`; `config/initializers/filter_parameter_logging.rb:6`; `app/controllers/pilot_requests_controller.rb:10` | Pilot interest framing; fields disclosed (name, work email, store URL, platform); no store connection; retention/deletion stated; temporary placeholder privacy contact (`privacy-placeholder@sellora.example`, not monitored) until production launch. SQL save logging is silenced because development query tags can inline personal values. |
| Keyboard access, focus, reduced motion, normal scrolling | `app/assets/stylesheets/application.css:16`; `app/assets/stylesheets/application.css:97`; `app/javascript/controllers/form_feedback_controller.js:1` | Browser keyboard checks performed; OS reduced-motion preference and screen-reader output were not manually toggled/tested. Reduced-motion controller branch has automated coverage. |
| FAQ, footer, honest status and no invented customers | `app/views/marketing/_faq.html.erb:1`; `app/views/marketing/show.html.erb:26` | No pricing packages, testimonials or customer logos. Privacy contact is an explicitly labeled temporary placeholder, not a production inbox. |
| Existing stack and dependency boundaries | Existing Gemfile, lockfile and import map retained | No new dependencies, React, Redis, remote push, deployment, messages or emails. |

## Verification performed

- `bin/rails test`: **20 tests, 135 assertions, 0 failures, 0 errors**. Includes durable save, normalization, invalid data, escaping, mass assignment, missing CSRF token, rate-limit/reset behavior, database construction/save failure and request/SQL logging checks.
- `node test/javascript/marketing_controllers_test.cjs`: **4 checks passed**. Uses built-in Node assertions only. Covers desktop anchor selection, reduced-motion/mobile placement, resizing and priority state.
- `bin/rubocop`: **32 files inspected, no offenses**.
- `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`: **no warnings or errors**.
- `bin/bundler-audit` and `bin/importmap audit`: **no vulnerabilities reported** by the available audit data. This is not a guarantee against unknown vulnerabilities.
- `bin/rails assets:precompile` and `bin/rails zeitwerk:check`: passed. Generated compiled assets were cleared after verification so local changes continue to load.
- Browser checks at **1440×1000**, **390×844** and **320×740**: no horizontal document overflow; garment images loaded; mobile toggle and keyboard activation worked; FAQ opened using the keyboard with visible focus.
- Browser form check: required-name validation, rejected credential-bearing store URL, retained fields and focused server error; corrected fictional request saved with a focused confirmation. Database query verified one row; the fictional QA row was removed.
- Desktop audit evidence anchor verified after fixing a reading-position boundary issue.
- The final SQL logging fix was verified with an unprepared-statement regression test. The earlier browser QA record was fictional; its pre-fix values appeared in development debug logs and were the evidence that prompted this fix.

## Not checked or not launch-ready

No real Shopify connection, real merchant audit, event tracking, order ingestion, email follow-up, account access, public deployment, domain or trademark verification was performed. Screen-reader behavior, OS-level reduced-motion rendering, 200% text zoom and a cross-browser/device matrix have not been manually verified. No-JS behavior was checked through server-rendered markup and ordinary HTTP form tests, not a JS-disabled browser session.

Before public launch, approve the design and publishing destination, replace the placeholder privacy contact with a monitored production address, assign responsibility for reviewing requests, and verify production HTTPS, database/cache configuration and backups. Public privacy claims must describe the chosen production environment. The current development throttle is per-process memory; production uses the application's configured cache.

## Image provenance

`app/assets/images/linen-kurta.webp` is an original AI-generated garment image, generated once for this project and converted to WebP locally. It represents a fictional example product, not a real merchant catalog item.
