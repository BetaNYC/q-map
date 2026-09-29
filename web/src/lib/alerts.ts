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

/**
 * ALERTS_SERVICE.md, "Feature properties" - revised against the first five
 * real alerts. Examples below are from those alerts.
 */
export interface AlertProperties {
  id: string;
  guid: string;
  /** Verbatim: "Notify NYC - Three Alarm Fire - Hillside Avenue (QN)". 37-62 chars observed. */
  headline: string;
  /** "Three Alarm Fire" - the type label. Null only if the headline was malformed. */
  event: string | null;
  /** "Hillside Avenue". Display verbatim; often null. Never a map position. */
  location: string | null;
  /**
   * Branch the WORDING on this: "in Queens" or "citywide". 'unknown' means the
   * borough tag was unrecognised - the alert is kept rather than risk hiding a
   * Queens one, so word it neutrally.
   */
  scope: 'queens' | 'citywide' | 'unknown';
  /** CAP category: "Fire", "Safety", "Infra", "Geo" observed. The only structured field that varies. */
  category: string;
  /**
   * Plain text. Paragraphs split on blank lines; single newlines are
   * meaningful (NWS "What:/Where:" lines, "- " bullets). Links and phone
   * numbers arrive as bare text - linkify here. 300-1,000 chars observed.
   */
  body: string;
  /** Notify NYC's page with this alert in ASL and 12 languages. 4 of 5 observed. */
  translations_url: string | null;
  /** ISO 8601 with offset. */
  sent: string;
  /** ISO 8601 with offset. Always sent + 2 h observed. Re-checked here; see isExpired(). */
  expires: string;
  /** One of the 8 hazard slugs, or null. Null is the common case - link nowhere hazard-specific. */
  hazard_slug: string | null;
  /** Queens district slugs, for polygon alerts only. Empty for every alert observed. */
  districts: string[];
}

export interface AlertFeature {
  type: 'Feature';
  /** Null unless the alert carried a CAP polygon - none of the five observed did. */
  geometry: GeoJSON.MultiPolygon | null;
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
