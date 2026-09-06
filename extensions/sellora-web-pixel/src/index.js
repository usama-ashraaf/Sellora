/**
 * Sellora Web Pixel — consent-aware storefront event stub (M3 lean).
 *
 * Incomplete coverage (documented blockers — see docs/web-pixel.md):
 * - Activation uses write_pixels + read_customer_events (Wave 1 OAuth / WebPixelRegistrar).
 * - Ingest uses a shared secret today; app proxy / authenticated channel later.
 * - Checkout / order events deferred to Phase B (no read_orders).
 * - Shopify may not load the pixel at all when required consent is denied.
 */
import { register } from "@shopify/web-pixels-extension";
import { mayFire } from "./consent.js";

// Storefront analytics only — no checkout/order topics in Phase A.
const SUBSCRIPTIONS = [
  { name: "page_viewed", needsMarketing: false },
  { name: "product_viewed", needsMarketing: false },
  { name: "product_added_to_cart", needsMarketing: false }
];

register(({ analytics, settings, init, customerPrivacy }) => {
  let privacy = init && init.customerPrivacy ? init.customerPrivacy : null;

  customerPrivacy.subscribe("visitorConsentCollected", (event) => {
    privacy = event && event.customerPrivacy ? event.customerPrivacy : privacy;
  });

  const ingestUrl = settings && settings.ingestUrl;
  const accountID = settings && settings.accountID;

  function postEvent(eventName, event) {
    if (!mayFire(privacy, { needsMarketing: false })) return;
    if (!ingestUrl) return;

    const body = {
      shop_domain: (init && init.context && init.context.document && init.context.document.location
        && init.context.document.location.host) || undefined,
      event_name: eventName,
      occurred_at: (event && event.timestamp) || new Date().toISOString(),
      account_id: accountID,
      consent: {
        analytics_processing_allowed: !!(privacy && privacy.analyticsProcessingAllowed),
        marketing_allowed: !!(privacy && privacy.marketingAllowed),
        preferences_processing_allowed: !!(privacy && privacy.preferencesProcessingAllowed),
        sale_of_data_allowed: !!(privacy && privacy.saleOfDataAllowed)
      },
      payload: {
        id: event && event.id,
        name: event && event.name
      }
    };

    // Shared secret cannot live in storefront JS safely — Wave 1 uses settings
    // or later app-proxy auth. Endpoint remains fail-closed without server secret.
    fetch(ingestUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      keepalive: true
    }).catch(() => {});
  }

  SUBSCRIPTIONS.forEach(({ name, needsMarketing }) => {
    analytics.subscribe(name, (event) => {
      if (!mayFire(privacy, { needsMarketing })) return;
      postEvent(name, event);
    });
  });
});
