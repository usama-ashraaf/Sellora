# Sellora week handoff — 2026-09-06 (PKT)

**Pause:** Usama stood down Eng/QA/Reviewer/Dev Store until next week.  
**Repo tip:** `origin/main` @ `d9d138b` (pushed).  
**Partner app:** Sellora · Client ID `7d912d414ddbffe0c1ff644b418efcf9` · org Southville Solutions (`5165992`)  
**Wave 1 stores:** `sellora-test-outfitters-like` · `sellora-test-sapphire-like`  
**Active Partner app version (embed):** sellora-6 · App URL was Cloudflare quick tunnel (ephemeral)

Overall M1–M3 toward done-def: **~70–75%**. Goal next week: finish M1–M3 to 100%.

---

## Done (shipped / verified)

### M1 Marketing
- Rails marketing site + pilot form (DB)
- QA F-01 / K-03 / K-04 cleared
- K-01 dummy privacy placeholder on main (`7189d85`) — not public-launch ready

### M2 Foundation
- Foundation on main (`03af6bf`)
- S2 hardens Reviewer PASS (`8695640`): OAuth `account_id` per shop (never Demo), no orphan→Demo vacuum, `/demo`+`/app` HTTP Basic, finding dedupe

### M3 Shopify
- Phase A install both Wave 1 stores
- Catalog sync + hardens + `PARITY_OK` (8 products / 21 variants / 21 SKUs, SF-*)
- ST-03 embed PASS (tunnel + sellora-6); QA report `docs/qa/` on PM box
- Webhooks register + Shopify→app delivery PASS (`c738ab5` + QA smoke)
- Web Pixel lean stub Reviewer PASS (`91e320f`)
- Pixel scopes + `WebPixelRegistrar` on main (`d9d138b`) — Usama approved `write_pixels` + `read_customer_events`

### Wave 1 stores
- Clothing fixtures frozen; QA clothing smoke PASS

### Reviews / QA docs (PM box `/workspace/sellora/docs/`)
- `reviews/m2-s2-hardens-8695640.md`
- `reviews/m3-webhook-registration-c738ab5.md`
- `reviews/m3-web-pixel-91e320f.md`
- `qa/st03-embed-retest-2026-09-06.md`
- `qa/m3-webhooks-smoke-2026-09-06.md`
- `qa/clothing-fixture-smoke-2026-09-06.md`

---

## Blocked / mid-flight when paused

1. **`shopify app deploy` of `extensions/sellora-web-pixel`** — needs Shopify CLI device auth (session did not stick; last attempted code `QNMW-PVQV`). Without deploy, `webPixelCreate` fails: “No web pixel was found for this app”.
2. Wave 1 **live pixel register** after deploy + any OAuth re-consent for pixel scopes.
3. Ephemeral Cloudflare tunnel URL in `shopify.app.toml` — replace when resuming.

---

## Remaining for M1–M3 100%

1. CLI deploy web pixel extension → register on both Wave 1 stores  
2. Pixel E2E S3: app-proxy/auth for ingest secret, rate limit, shop_domain mapping → QA storefront smoke  
3. Phase B: `read_orders` + order records sync  
4. Uninstall/privacy retention docs complete  
5. M2: clothing audit rules engine + activity producers + labeled fictional demo honesty + tests  
6. M2 S3 residuals (optional): Runner `Account.demo!` fallback, nullable `shops.account_id`, finding↔shop account validation  
7. M1: Usama publish/review; real privacy contact when ready  

**Parked:** M4–M6

---

## Resume checklist (next week)

1. Fresh Cloudflare tunnel (or stable HTTPS host); set Partner App URL + `SHOPIFY_APP_URL` + update `shopify.app.toml`  
2. `shopify auth login` / `shopify app deploy` with Usama device auth; keep CLI process alive until session writes  
3. Re-OAuth Wave 1 if pixel scopes not yet on install; `sellora:register_web_pixel` / `_all`  
4. Pixel E2E hardens → QA → Phase B → M2 gaps → M1 publish call  
