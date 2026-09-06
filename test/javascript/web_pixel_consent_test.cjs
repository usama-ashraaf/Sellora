/**
 * Node smoke for extensions/sellora-web-pixel/src/consent.js (fail-closed).
 * Uses dynamic import of the ESM module.
 */
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");

async function main() {
  const modPath = path.join(
    __dirname,
    "..",
    "..",
    "extensions",
    "sellora-web-pixel",
    "src",
    "consent.js"
  );
  const { analyticsAllowed, marketingAllowed, mayFire } = await import(pathToFileURL(modPath).href);

  assert.strictEqual(analyticsAllowed(null), false);
  assert.strictEqual(analyticsAllowed({}), false);
  assert.strictEqual(analyticsAllowed({ analyticsProcessingAllowed: false }), false);
  assert.strictEqual(analyticsAllowed({ analyticsProcessingAllowed: true }), true);

  assert.strictEqual(marketingAllowed({ marketingAllowed: true }), true);
  assert.strictEqual(marketingAllowed({ marketingAllowed: false }), false);

  assert.strictEqual(mayFire(null), false);
  assert.strictEqual(mayFire({ analyticsProcessingAllowed: true }), true);
  assert.strictEqual(
    mayFire({ analyticsProcessingAllowed: true, marketingAllowed: false }, { needsMarketing: true }),
    false
  );
  assert.strictEqual(
    mayFire({ analyticsProcessingAllowed: true, marketingAllowed: true }, { needsMarketing: true }),
    true
  );

  console.log("web_pixel_consent_test.cjs OK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
