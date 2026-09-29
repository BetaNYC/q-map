import { readFileSync } from "node:fs";
import { afterEach, describe, expect, it, vi } from "vitest";
import { parseFeed } from "../src/feed";
import { poll, serve, type Env, type State } from "../src/index";

const fixture = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

// A Map standing in for KV: the calls the Worker makes.
function fakeEnv(initial?: object): Env & { store: Map<string, string>; puts: number } {
  const store = new Map<string, string>();
  if (initial !== undefined) store.set("state", JSON.stringify(initial));
  const env = {
    store,
    puts: 0,
    ALERTS: {
      get: async (key: string, type?: string) => {
        const v = store.get(key) ?? null;
        return v !== null && type === "json" ? JSON.parse(v) : v;
      },
      put: async (key: string, value: string) => {
        env.puts++;
        store.set(key, value);
      },
    } as unknown as KVNamespace,
  };
  return env;
}

const stored = (env: { store: Map<string, string> }) => JSON.parse(env.store.get("state")!) as State;

/**
 * A fetch serving a real archived RSS snapshot, and each CAP link from the
 * real archived CAP file of the same guid. Records which URLs were requested.
 */
function realFeed(rssName: string, overrides: Record<string, () => Response> = {}) {
  const rss = fixture(rssName);
  // CAP link -> guid, read from the snapshot itself with the Worker's parser.
  const links = new Map(
    parseFeed(rss)
      .filter((i) => i.author === "NYCEM [English]")
      .map((i) => [i.link, i.guid]),
  );
  const requested: string[] = [];
  const fetchFn = async (input: RequestInfo | URL) => {
    const url = String(input);
    requested.push(url);
    if (url.includes("/rss/")) return new Response(rss);
    const guid = links.get(url);
    if (guid && overrides[guid]) return overrides[guid]();
    if (guid) return new Response(fixture(`cap/${guid}.xml`));
    return new Response("", { status: 404 });
  };
  return { fetchFn, requested };
}

afterEach(() => vi.unstubAllGlobals());

describe("poll, replaying real archived snapshots", () => {
  it("09:48 UTC: the Queens fire is served; the Staten Island flood statement is not", async () => {
    const { fetchFn } = realFeed("feed-2026-09-29T09-48-40Z.xml");
    vi.stubGlobal("fetch", fetchFn);
    const env = fakeEnv();
    const envelope = await poll(env, new Date("2026-09-29T09:48:40Z"));

    expect(envelope.feed_healthy).toBe(true);
    expect(envelope.features).toHaveLength(1);
    expect(envelope.features[0]).toEqual({
      type: "Feature",
      geometry: null,
      properties: {
        id: "2754793634362080",
        guid: "2754793634362080",
        headline: "Notify NYC - Three Alarm Fire - Hillside Avenue (QN)",
        event: "Three Alarm Fire",
        location: "Hillside Avenue",
        scope: "queens",
        category: "Fire",
        body: expect.stringMatching(/^Emergency personnel are on the scene of a three-alarm fire/),
        translations_url: "http://on.nyc.gov/1kdbhe2",
        sent: "2026-09-29T05:17:36-04:00",
        expires: "2026-09-29T07:17:36-04:00",
      },
    });
  });

  it("12:58 UTC: a Queens and a citywide alert, newest first", async () => {
    vi.stubGlobal("fetch", realFeed("feed-2026-09-29T12-58-06Z.xml").fetchFn);
    const envelope = await poll(fakeEnv(), new Date("2026-09-29T12:58:06Z"));
    expect(envelope.features.map((f) => [f.properties.event, f.properties.scope])).toEqual([
      ["Police Activity", "queens"],
      ["Waterbody Advisory", "citywide"],
    ]);
    // The one alert without a translations footer.
    expect(envelope.features[0].properties.translations_url).toBeNull();
  });

  it("drops an alert once the clock passes its expiry, though the feed still lists it", async () => {
    vi.stubGlobal("fetch", realFeed("feed-2026-09-29T12-58-06Z.xml").fetchFn);
    // Waterbody Advisory expires 13:19:11 UTC.
    const envelope = await poll(fakeEnv(), new Date("2026-09-29T13:20:00Z"));
    expect(envelope.features.map((f) => f.properties.event)).toEqual(["Police Activity"]);
  });

  it("downloads each CAP once, then serves it from the cache", async () => {
    const first = realFeed("feed-2026-09-29T12-58-06Z.xml");
    vi.stubGlobal("fetch", first.fetchFn);
    const env = fakeEnv();
    await poll(env, new Date("2026-09-29T12:58:06Z"));
    expect(first.requested.filter((u) => u.includes("/cap/"))).toHaveLength(2);

    const second = realFeed("feed-2026-09-29T12-58-06Z.xml");
    vi.stubGlobal("fetch", second.fetchFn);
    await poll(env, new Date("2026-09-29T13:00:06Z"));
    expect(second.requested.filter((u) => u.includes("/cap/"))).toHaveLength(0);
    expect(env.puts).toBe(2); // one KV write per poll
  });

  it("prunes the cache to what the feed still holds", async () => {
    vi.stubGlobal("fetch", realFeed("feed-2026-09-29T12-58-06Z.xml").fetchFn);
    const env = fakeEnv({ envelope: {}, cap: { "1111": { identifier: "gone" } } });
    await poll(env, new Date("2026-09-29T12:58:06Z"));
    expect(Object.keys(stored(env).cap).sort()).toEqual(["2751666898158459", "2758435766629296"]);
  });

  it("an unreadable CAP makes the whole envelope unavailable, not a partial all-clear", async () => {
    const { fetchFn } = realFeed("feed-2026-09-29T12-58-06Z.xml", {
      "2758435766629296": () => new Response("<html>error</html>"),
    });
    vi.stubGlobal("fetch", fetchFn);
    const env = fakeEnv();
    const envelope = await poll(env, new Date("2026-09-29T12:58:06Z"));
    expect(envelope).toMatchObject({ feed_healthy: false, health_detail: "cap_unreadable", features: [] });
    // The readable one is cached; the unreadable one is retried next poll.
    expect(Object.keys(stored(env).cap)).toEqual(["2751666898158459"]);
  });

  it("stores a healthy empty envelope for an empty feed", async () => {
    vi.stubGlobal("fetch", async () => new Response(fixture("feed-empty-2026-09-28.xml")));
    const env = fakeEnv();
    await poll(env, new Date("2026-09-28T18:00:00Z"));
    expect(stored(env)).toEqual({
      envelope: {
        type: "FeatureCollection",
        generated_at: "2026-09-28T18:00:00.000Z",
        feed_healthy: true,
        health_detail: null,
        features: [],
      },
      cap: {},
    });
  });

  // generated_at must mean "last SUCCESSFUL poll", or the app's staleness
  // rule never fires during an outage.
  it.each([
    ["an HTTP error", () => new Response("", { status: 502 })],
    ["a non-RSS 200", () => new Response("<html>blocked</html>")],
  ])("leaves the previous state untouched on %s", async (_label, respond) => {
    vi.stubGlobal("fetch", async () => respond());
    const env = fakeEnv({ previous: true });
    await expect(poll(env)).rejects.toThrow();
    expect(env.store.get("state")).toBe('{"previous":true}');
  });
});

describe("serve", () => {
  const get = (path = "/", method = "GET") => new Request(`https://example.invalid${path}`, { method });

  it("503s before any poll has completed, with CORS so the app can read it", async () => {
    const res = await serve(get(), fakeEnv());
    expect(res.status).toBe(503);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Cache-Control")).toBe("no-store");
  });

  it("serves the envelope only - never the CAP cache", async () => {
    const res = await serve(get(), fakeEnv({ envelope: { type: "FeatureCollection" }, cap: { x: {} } }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ type: "FeatureCollection" });
    expect(res.headers.get("Content-Type")).toContain("application/geo+json");
  });

  it("404s other paths and 405s other methods", async () => {
    expect((await serve(get("/x"), fakeEnv({}))).status).toBe(404);
    expect((await serve(get("/", "POST"), fakeEnv({}))).status).toBe(405);
  });
});
