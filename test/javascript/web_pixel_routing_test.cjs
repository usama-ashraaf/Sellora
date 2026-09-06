const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname,
  "../../extensions/sellora-web-pixel/src/index.js"), "utf8")
  .replace(/^import .*;$/gm, "");

function runPixel(settings) {
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
  handlers.product_viewed({ id: "event-1", name: "product_viewed", timestamp: "2026-09-07T12:00:00Z" });
  return requests;
}

const settings = {
  accountID: "1", ingestUrl: "https://sellora.example/web_pixels/events",
  shopDomain: "clothing.myshopify.com", ingestToken: "public-test-capability"
};
const requests = runPixel(settings);
assert.strictEqual(requests.length, 1);
assert.strictEqual(requests[0].body.shop_domain, "clothing.myshopify.com");
assert.strictEqual(requests[0].url, settings.ingestUrl);
assert.strictEqual(requests[0].headers["X-Sellora-Pixel-Token"], settings.ingestToken);
assert.strictEqual(requests[0].credentials, "omit");
assert.strictEqual(runPixel(Object.assign({}, settings, { shopDomain: undefined })).length, 0);
assert.strictEqual(runPixel(Object.assign({}, settings, { ingestToken: undefined })).length, 0);
console.log("web_pixel_routing_test.cjs OK");
