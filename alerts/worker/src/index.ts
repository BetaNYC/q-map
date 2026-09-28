// q-map alerts service: polls Notify NYC, serves the project's own
// CORS-enabled GeoJSON. The brief is ALERTS_SERVICE.md.
//
//   scheduled (every 2 min)  fetch the feed, assess it, store the envelope
//   GET /                    serve the stored envelope
//
// The poll and the response are decoupled through KV so that a slow or failing
// upstream never delays or breaks a page load.

import { FEED_URL, assessFeed, parseFeed } from "./feed";

export interface Env {
  ALERTS: KVNamespace;
}

// The response. Shape and semantics are specified in ALERTS_SERVICE.md,
// "Envelope" and "Feature properties".
export interface Envelope {
  type: "FeatureCollection";
  /** Last SUCCESSFUL poll. Never advanced by a failed one. */
  generated_at: string;
  feed_healthy: boolean;
  /** Diagnostics only - not part of the app's contract. */
  health_detail: string | null;
  /** Always empty until the CAP layer exists. See feed.ts, assessFeed(). */
  features: never[];
}

const STATE_KEY = "envelope";

const HEADERS = {
  "Content-Type": "application/geo+json; charset=utf-8",
  // Public data, and "*" lets `vite dev` on localhost read it too.
  "Access-Control-Allow-Origin": "*",
  // Polls land every 2 minutes; a minute of edge caching halves origin reads
  // without letting the response lag the store by more than one poll.
  "Cache-Control": "public, max-age=60",
};

export async function poll(env: Env, now: Date = new Date()): Promise<Envelope> {
  const response = await fetch(FEED_URL, {
    headers: { "User-Agent": "q-map-alerts" },
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    throw new Error(`feed returned HTTP ${response.status}`);
  }
  const assessment = assessFeed(parseFeed(await response.text()));

  const envelope: Envelope = {
    type: "FeatureCollection",
    generated_at: now.toISOString(),
    feed_healthy: assessment.healthy,
    health_detail: assessment.detail,
    features: [],
  };
  // One write per successful poll: 720 a day at 2-minute polling, inside the
  // free tier's 1,000. A failed poll writes nothing, so generated_at ages and
  // the app's 15-minute staleness rule takes over.
  await env.ALERTS.put(STATE_KEY, JSON.stringify(envelope));
  console.log(
    `poll ok: ${assessment.total} items, ${assessment.english} English, ` +
      `healthy=${assessment.healthy}${assessment.detail ? ` (${assessment.detail})` : ""}`,
  );
  return envelope;
}

export async function serve(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname !== "/") {
    return new Response("Not found", { status: 404, headers: HEADERS });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { ...HEADERS, "Access-Control-Allow-Methods": "GET, OPTIONS" },
    });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: HEADERS });
  }

  const stored = await env.ALERTS.get(STATE_KEY);
  if (stored === null) {
    // Never polled - a fresh deploy. The app treats any non-2xx as
    // unavailable, which is exactly right: nothing is known yet.
    return new Response(JSON.stringify({ error: "no poll has completed" }), {
      status: 503,
      headers: HEADERS,
    });
  }
  return new Response(stored, { headers: HEADERS });
}

export default {
  async scheduled(_controller, env, ctx) {
    // A thrown poll leaves the previous envelope in place. Logged, and
    // visible in the Worker's dashboard as a failed invocation.
    ctx.waitUntil(poll(env));
  },
  fetch: serve,
} satisfies ExportedHandler<Env>;
