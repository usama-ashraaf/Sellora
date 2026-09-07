const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname,
  "../../extensions/sellora-web-pixel/src/index.js"), "utf8")
  .replace(/^import .*;$/gm, "");

function runPixel(settings, eventName = "product_viewed", event = null) {
  const requests = [];
  const handlers = {};
  vm.runInNewContext(source, {
    register(callback) {
      callback({
        settings,
        init: {
          customerPrivacy: { analyticsProcessingAllowed: true },
          context: { document: { location: { host: "custom-clothing.example" } } }
        },
        analytics: { subscribe(name, handler) { handlers[name] = handler; } },
        customerPrivacy: { subscribe() {} }
      });
    },
    mayFire: function (privacy) {
      return !!(privacy && privacy.analyticsProcessingAllowed === true);
    },
    fetch(url, options) {
      requests.push({ url, headers: options.headers, body: JSON.parse(options.body), credentials: options.credentials });
      return Promise.resolve({ ok: true });
    }
  });
  const defaultEvent = { id: "event-1", name: eventName, timestamp: "2026-09-07T12:00:00Z" };
  handlers[eventName](event || defaultEvent);
  return { requests, subscriptions: Object.keys(handlers) };
}

const settings = {
  ingestUrl: "https://sellora.example/web_pixels/events",
  shopDomain: "clothing.myshopify.com", ingestToken: "public-test-capability"
};
const result = runPixel(settings, "product_viewed", {
  id: "event-1", name: "product_viewed", timestamp: "2026-09-07T12:00:00Z",
  data: { productVariant: { id: "gid://shopify/ProductVariant/2", sku: "KURTA-M",
    product: { id: "gid://shopify/Product/1" }, price: { amount: "2490.00", currencyCode: "PKR" } } }
});
const requests = result.requests;
assert.strictEqual(requests.length, 1);
assert.strictEqual(requests[0].body.shop_domain, "clothing.myshopify.com");
assert.strictEqual(requests[0].url, settings.ingestUrl);
assert.strictEqual(requests[0].headers["X-Sellora-Pixel-Token"], settings.ingestToken);
assert.strictEqual(requests[0].credentials, "omit");
assert.strictEqual(requests[0].body.payload.product_id, "gid://shopify/Product/1");
assert.strictEqual(requests[0].body.payload.variant_id, "gid://shopify/ProductVariant/2");
assert.strictEqual(requests[0].body.payload.sku, "KURTA-M");
assert.strictEqual(requests[0].body.payload.amount, "2490.00");
assert.strictEqual(requests[0].body.account_id, undefined);
assert.deepStrictEqual(Array.from(result.subscriptions), [
  "page_viewed", "product_viewed", "product_added_to_cart", "product_removed_from_cart",
  "checkout_started", "payment_info_submitted", "checkout_completed"
]);

const checkout = runPixel(settings, "checkout_completed", {
  id: "event-2", name: "checkout_completed", timestamp: "2026-09-07T12:05:00Z",
  data: { checkout: { token: "checkout-token", order: { id: "gid://shopify/Order/3" },
    totalPrice: { amount: "4980.00", currencyCode: "PKR" }, lineItems: [
      { quantity: 2, variant: { id: "gid://shopify/ProductVariant/2", sku: "KURTA-M",
        product: { id: "gid://shopify/Product/1" } } }
    ], email: "must-not-leave-browser@example.com" } }
}).requests[0].body.payload;
assert.strictEqual(checkout.checkout_token, "checkout-token");
assert.strictEqual(checkout.order_id, "gid://shopify/Order/3");
assert.strictEqual(checkout.line_items[0].product_id, "gid://shopify/Product/1");
assert.strictEqual(checkout.line_items[0].quantity, 2);
assert.strictEqual(checkout.email, undefined);

assert.strictEqual(runPixel(Object.assign({}, settings, { shopDomain: undefined })).requests.length, 0);
assert.strictEqual(runPixel(Object.assign({}, settings, { ingestToken: undefined })).requests.length, 0);
console.log("web_pixel_routing_test.cjs OK");
