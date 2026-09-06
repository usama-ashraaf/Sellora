/**
 * Sellora Web Pixel — consent-aware storefront event stub (M3 lean).
 *
 * Auth: settings.ingestToken → X-Sellora-Pixel-Token (write-only; no Admin credentials).
 * Shop routing: settings.shopDomain (canonical myshopify.com), not the storefront host.
 * See docs/web-pixel.md for deploy / register / consent blockers.
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
  const shopDomain = settings && settings.shopDomain;
  const ingestToken = settings && settings.ingestToken;

  function postEvent(eventName, event) {
    if (!mayFire(privacy, { needsMarketing: false })) return;
    if (!ingestUrl) return;
    if (!shopDomain) return;
    if (!ingestToken) return;

    const body = {
      shop_domain: shopDomain,
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

    // Public capability: event submission only, scoped to this installation.
    // It grants no access to Admin API credentials or merchant data.
    fetch(ingestUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Sellora-Pixel-Token": ingestToken },
      credentials: "omit",
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
