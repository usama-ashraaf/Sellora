/**
 * Fail-closed consent helpers for the Sellora web pixel.
 * Missing or non-true flags never allow fire/subscribe side effects.
 */

export function analyticsAllowed(privacy) {
  if (!privacy || typeof privacy !== "object") return false;
  return privacy.analyticsProcessingAllowed === true;
}

export function marketingAllowed(privacy) {
  if (!privacy || typeof privacy !== "object") return false;
  return privacy.marketingAllowed === true;
}

/**
 * @param {object|null|undefined} privacy - init.customerPrivacy / visitorConsentCollected payload
 * @param {{ needsMarketing?: boolean }} [opts]
 * @returns {boolean}
 */
export function mayFire(privacy, opts = {}) {
  const needsMarketing = opts.needsMarketing === true;
  if (!analyticsAllowed(privacy)) return false;
  if (needsMarketing && !marketingAllowed(privacy)) return false;
  return true;
}
