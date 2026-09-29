// q-map alerts service: polls Notify NYC, serves the project's own
// CORS-enabled GeoJSON. The brief is ALERTS_SERVICE.md.
//
//   scheduled (every 2 min)  RSS -> new English CAP files -> interpret -> KV
//   GET /                    serve the stored envelope
//
// The poll and the response are decoupled through KV so that a slow or failing
// upstream never delays or breaks a page load.

import { parseCap, type CapAlert } from "./cap";
import { FEED_URL, assessFeed, parseFeed } from "./feed";
import { interpret, type AlertFeature } from "./interpret";

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
  features: AlertFeature[];
}

/**
 * Everything the Worker keeps, under ONE key so a poll is one KV write: 720 a
 * day at 2-minute polling, inside the free tier's 1,000. Two keys would be
 * 1,440.
 */
export interface State {
  envelope: Envelope;
  /**
   * Parsed CAP by guid, for the English items currently in the feed - the
   * two-tier fetch downloads each CAP file once. Rebuilt every poll from what
   * the feed still holds, so it is bounded by the feed, not by history.
   */
  cap: Record<string, CapAlert>;
}

// "envelope" held the bare envelope before the CAP layer. A new key means the
// first request after that deploy 503s until the first poll, rather than
// misreading the old shape.
const STATE_KEY = "state";

const HEADERS = {
  "Content-Type": "application/geo+json; charset=utf-8",
  // Public data, and "*" lets `vite dev` on localhost read it too.
  "Access-Control-Allow-Origin": "*",
  // Polls land every 2 minutes; a minute of edge caching halves origin reads
  // without letting the response lag the store by more than one poll.
  "Cache-Control": "public, max-age=60",
};

async function fetchText(url: string, timeoutMs: number): Promise<string> {
  const response = await fetch(url, {
    headers: { "User-Agent": "q-map-alerts" },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  return response.text();
}

export async function poll(env: Env, now: Date = new Date()): Promise<Envelope> {
  // A failure here throws: nothing is written, generated_at ages, and the
  // app's 15-minute staleness rule takes over.
  const assessment = assessFeed(parseFeed(await fetchText(FEED_URL, 20_000)));

  const previous = await env.ALERTS.get<State>(STATE_KEY, "json");
  const cache: Record<string, CapAlert> = {};
  const fresh: string[] = [];
  const failed: string[] = [];

  // Two-tier fetch: CAP only for English guids not already parsed. A failure
  // is retried next poll - the item stays in the feed until it expires.
  await Promise.all(
    assessment.english.map(async (item) => {
      const known = previous?.cap?.[item.guid];
      if (known) {
        cache[item.guid] = known;
        return;
      }
      try {
        cache[item.guid] = parseCap(await fetchText(item.link, 10_000));
        fresh.push(item.guid);
      } catch (error) {
        failed.push(`${item.guid}: ${(error as Error).message}`);
      }
    }),
  );

  let envelope: Envelope;
  if (assessment.verdict === "english_missing") {
    envelope = build(now, false, "english_missing", []);
  } else if (failed.length > 0) {
    // An English alert this poll could not read may be the one that matters.
    // Serving the others as the whole picture would be a partial all-clear.
    envelope = build(now, false, "cap_unreadable", []);
    for (const line of failed) console.error(`CAP unreadable: ${line}`);
  } else {
    const { features, log } = interpret(
      Object.entries(cache).map(([guid, cap]) => ({ guid, cap })),
      now,
    );
    envelope = build(now, true, null, features);
    // The interpretation repeats every poll until the feed changes, so log it
    // only then - not 720 times a day.
    if (fresh.length > 0) for (const line of log) console.log(line);
  }

  // One write per successful poll. A failed poll writes nothing.
  const state: State = { envelope, cap: cache };
  await env.ALERTS.put(STATE_KEY, JSON.stringify(state));
  console.log(
    `poll ok: ${assessment.total} items, ${assessment.english.length} English ` +
      `(${fresh.length} new CAP), ${envelope.features.length} served, ` +
      `healthy=${envelope.feed_healthy}${envelope.health_detail ? ` (${envelope.health_detail})` : ""}`,
  );
  return envelope;
}

function build(
  now: Date,
  healthy: boolean,
  detail: string | null,
  features: AlertFeature[],
): Envelope {
  return {
    type: "FeatureCollection",
    generated_at: now.toISOString(),
    feed_healthy: healthy,
    health_detail: detail,
    features,
  };
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

  const state = await env.ALERTS.get<State>(STATE_KEY, "json");
  if (state === null) {
    // Never polled - a fresh deploy. The app treats any non-2xx as
    // unavailable, which is exactly right: nothing is known yet.
    // no-store: a cached 503 would outlive the first successful poll.
    return new Response(JSON.stringify({ error: "no poll has completed" }), {
      status: 503,
      headers: { ...HEADERS, "Cache-Control": "no-store" },
    });
  }
  return new Response(JSON.stringify(state.envelope), { headers: HEADERS });
}

export default {
  async scheduled(_controller, env, ctx) {
    // A thrown poll leaves the previous state in place. Logged, and visible
    // in the Worker's dashboard as a failed invocation.
    ctx.waitUntil(poll(env));
  },
  fetch: serve,
} satisfies ExportedHandler<Env>;
