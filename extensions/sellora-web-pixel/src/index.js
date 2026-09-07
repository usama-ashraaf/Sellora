/**
 * Sellora Web Pixel — consent-aware storefront event collector.
 *
 * Auth: settings.ingestToken → X-Sellora-Pixel-Token (write-only; no Admin credentials).
 * Shop routing: settings.shopDomain (canonical myshopify.com), not the storefront host.
 * See docs/web-pixel.md for deploy / register / consent blockers.
 */
import { register } from "@shopify/web-pixels-extension";
import { mayFire } from "./consent.js";

const SUBSCRIPTIONS = [
  { name: "page_viewed", needsMarketing: false },
  { name: "product_viewed", needsMarketing: false },
  { name: "product_added_to_cart", needsMarketing: false },
  { name: "product_removed_from_cart", needsMarketing: false },
  { name: "checkout_started", needsMarketing: false },
  { name: "payment_info_submitted", needsMarketing: false },
  { name: "checkout_completed", needsMarketing: false }
];

function money(value) {
  if (!value) return {};
  return { amount: value.amount, currency: value.currencyCode };
}

function variantPayload(variant) {
  if (!variant) return {};
  return {
    product_id: variant.product && variant.product.id,
    variant_id: variant.id,
    sku: variant.sku
  };
}

function eventPayload(eventName, event) {
  const data = event && event.data ? event.data : {};
  const base = { id: event && event.id, name: event && event.name };

  if (eventName === "product_viewed") {
    const variant = data.productVariant;
    return { ...base, ...variantPayload(variant), ...money(variant && variant.price) };
  }

  if (eventName === "product_added_to_cart" || eventName === "product_removed_from_cart") {
    const line = data.cartLine;
    return {
      ...base,
      ...variantPayload(line && line.merchandise),
      quantity: line && line.quantity,
      ...money(line && line.cost && line.cost.totalAmount)
    };
  }

  if (eventName.startsWith("checkout_") || eventName === "payment_info_submitted") {
    const checkout = data.checkout || {};
    return {
      ...base,
      checkout_token: checkout.token,
      order_id: checkout.order && checkout.order.id,
      ...money(checkout.totalPrice),
      line_items: (checkout.lineItems || []).slice(0, 25).map((line) => ({
        ...variantPayload(line.variant),
        quantity: line.quantity
      }))
    };
  }

  return base;
}

register(({ analytics, settings, init, customerPrivacy }) => {
  let privacy = init && init.customerPrivacy ? init.customerPrivacy : null;

  customerPrivacy.subscribe("visitorConsentCollected", (event) => {
    privacy = event && event.customerPrivacy ? event.customerPrivacy : privacy;
  });

  const ingestUrl = settings && settings.ingestUrl;
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
      consent: {
        analytics_processing_allowed: !!(privacy && privacy.analyticsProcessingAllowed),
        marketing_allowed: !!(privacy && privacy.marketingAllowed),
        preferences_processing_allowed: !!(privacy && privacy.preferencesProcessingAllowed),
        sale_of_data_allowed: !!(privacy && privacy.saleOfDataAllowed)
      },
      payload: eventPayload(eventName, event)
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
