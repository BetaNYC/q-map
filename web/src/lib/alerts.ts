/**
 * The app's one runtime dependency: the Notify NYC alerts Worker.
 *
 * WORKED EXAMPLE — the pattern for anything live. Every other read in the app
 * goes through dataUrl() and is baked in at prerender; this one must NOT be.
 *
 * Three rules it encodes:
 *
 * 1. BROWSER ONLY, NEVER AT PRERENDER. A +page.ts load runs at build time and
 *    SvelteKit inlines the response into the HTML. An alert fetched then would
 *    ship frozen into a static page and be shown as live until the next
 *    deploy - a days-old flood warning presented as current. So this is a
 *    plain function, not a loader, and it takes no SvelteKit `fetch`. Call it
 *    from an $effect or onMount, neither of which runs on the server.
 *
 * 2. IT NEVER THROWS. ALERTS_SERVICE.md: the app must degrade to nothing when
 *    the service is down, and it must never be able to break a page. Every
 *    failure - unset URL, network, timeout, non-2xx, malformed JSON, a stale
 *    or unhealthy envelope - resolves to { status: 'unavailable' }.
 *
 * 3. THREE STATES, NOT TWO. 'none' is a claim that Queens has no active
 *    alerts; 'unavailable' is the absence of any claim. The banner renders
 *    nothing for either. The alerts page must word them differently, because
 *    it can be reached from a bookmark, where silence reads as all-clear.
 *
 * The response shape is specified in ALERTS_SERVICE.md ("Envelope", "Feature
 * properties"). If this file and the brief disagree, the brief is right.
 */

/** Set at build time. Unset (local dev, PR builds) means 'unavailable'. */
const ALERTS_URL = import.meta.env.VITE_ALERTS_URL as string | undefined;

/** Three missed polls at the brief's 5-minute polling ceiling. */
export const STALE_AFTER_MS = 15 * 60 * 1000;

/** A banner that appears 8 s late is fine; a page that waits on it is not. */
const TIMEOUT_MS = 8000;

export type Severity = 'Extreme' | 'Severe' | 'Moderate' | 'Minor' | 'Unknown';
export type Urgency = 'Immediate' | 'Expected' | 'Future' | 'Past' | 'Unknown';
/** `Unlikely` is filtered by the service and never arrives. */
export type Certainty = 'Observed' | 'Likely' | 'Possible' | 'Unknown';

/**
 * ALERTS_SERVICE.md, "Feature properties". The Worker does not emit features
 * yet (no CAP layer), so nothing here has been observed in a real response.
 */
export interface AlertProperties {
  id: string;
  guid: string;
  headline: string;
  description: string;
  /** Unverified whether NYCEM populates it. Design for null. */
  instruction: string | null;
  /** Display-only. Not a label for a polygon alert - see `counties`. */
  area_desc: string;
  /** ISO 8601 with offset. */
  sent: string;
  /** ISO 8601 with offset. Re-checked here; see isExpired(). */
  expires: string;
  severity: Severity;
  urgency: Urgency;
  certainty: Certainty;
  /**
   * Branch the WORDING on this, never on districts.length. 'county' means the
   * source said "Queens" and nothing more precise.
   */
  area_precision: 'polygon' | 'county';
  /** Queens district slugs. All 14 when area_precision is 'county'. */
  districts: string[];
  /** One of the 8 hazard slugs, or null - null routes to the district page. */
  hazard_slug: string | null;
  /** SAME-derived county FIPS. Never a label for a polygon alert. */
  counties: string[];
}

export interface AlertFeature {
  type: 'Feature';
  geometry: GeoJSON.MultiPolygon;
  properties: AlertProperties;
}

export type AlertsState =
  /** No claim either way. `reason` is for the console, not for copy. */
  | { status: 'unavailable'; reason: string }
  /** The service vouches that nothing is active, as of `asOf`. */
  | { status: 'none'; asOf: Date }
  /** In the Worker's order: severity, then urgency, then newest. Never empty. */
  | { status: 'active'; asOf: Date; alerts: AlertFeature[] };

const unavailable = (reason: string): AlertsState => ({ status: 'unavailable', reason });

/**
 * Seams for tests: a network, a clock, a URL and a timeout. Callers pass
 * nothing - `fetchAlerts()`.
 */
export interface FetchAlertsOptions {
  fetchFn?: typeof fetch;
  now?: Date;
  url?: string;
  timeoutMs?: number;
}

/** Fetch and interpret the alerts envelope. Resolves; never rejects. */
export async function fetchAlerts({
  fetchFn = fetch,
  now = new Date(),
  // Omitted in tests, VITE_ALERTS_URL is unset, which is how the test suite
  // exercises 'not_configured' - and why no test can reach the live Worker.
  url = ALERTS_URL,
  timeoutMs = TIMEOUT_MS
}: FetchAlertsOptions = {}): Promise<AlertsState> {
  if (!url) return unavailable('not_configured');

  let body: unknown;
  try {
    const response = await fetchFn(url, { signal: AbortSignal.timeout(timeoutMs) });
    // 503 is the Worker's "no poll has completed yet" - unavailable, correctly.
    if (!response.ok) return unavailable(`http_${response.status}`);
    body = await response.json();
  } catch {
    // Network error, CORS failure, timeout, or a body that is not JSON.
    return unavailable('fetch_failed');
  }

  if (!isEnvelope(body)) return unavailable('malformed');

  // The Worker cannot interpret what it is seeing - an English-filter break,
  // or alerts it has no CAP layer to vet. Not a claim of calm.
  if (!body.feed_healthy) return unavailable('unhealthy');

  // generated_at is the last SUCCESSFUL poll. If the poller has died, the
  // store keeps serving its final answer; age is the only sign.
  //
  // Measured against the viewer's clock, so a device more than 15 minutes
  // fast sees 'unavailable' - the safe direction to be wrong in.
  const asOf = new Date(body.generated_at);
  if (now.getTime() - asOf.getTime() > STALE_AFTER_MS) return unavailable('stale');

  // The service drops expired alerts, but a snapshot up to 15 minutes old can
  // still hold one that has since expired.
  const alerts = body.features.filter((f) => !isExpired(f, now));
  return alerts.length === 0 ? { status: 'none', asOf } : { status: 'active', asOf, alerts };
}

function isExpired(feature: AlertFeature, now: Date): boolean {
  const expires = Date.parse(feature.properties.expires);
  // An unparseable expiry is treated as expired: without it there is no
  // authoritative stop-showing time, and showing an alert forever is worse.
  return Number.isNaN(expires) || expires <= now.getTime();
}

/**
 * Checks the envelope, not every feature property: the features array is the
 * Worker's own output, validated there. This guards against the response not
 * being the Worker's at all - a proxy error page, a misconfigured URL.
 */
function isEnvelope(value: unknown): value is {
  type: 'FeatureCollection';
  generated_at: string;
  feed_healthy: boolean;
  features: AlertFeature[];
} {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    v.type === 'FeatureCollection' &&
    typeof v.generated_at === 'string' &&
    !Number.isNaN(Date.parse(v.generated_at)) &&
    typeof v.feed_healthy === 'boolean' &&
    Array.isArray(v.features)
  );
}
