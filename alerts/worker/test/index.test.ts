import { readFileSync } from "node:fs";
import { afterEach, describe, expect, it, vi } from "vitest";
import { poll, serve, type Env } from "../src/index";

// A Map standing in for KV: the two methods the Worker uses.
function fakeEnv(initial?: string): Env & { store: Map<string, string> } {
  const store = new Map<string, string>();
  if (initial !== undefined) store.set("envelope", initial);
  const ALERTS = {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => void store.set(key, value),
  } as unknown as KVNamespace;
  return { ALERTS, store };
}

const emptyFeed = readFileSync(
  new URL("./fixtures/feed-empty-2026-09-28.xml", import.meta.url),
  "utf8",
);

afterEach(() => vi.unstubAllGlobals());

describe("poll", () => {
  it("stores a healthy empty envelope for an empty feed", async () => {
    vi.stubGlobal("fetch", async () => new Response(emptyFeed));
    const env = fakeEnv();
    await poll(env, new Date("2026-09-28T18:00:00Z"));
    expect(JSON.parse(env.store.get("envelope")!)).toEqual({
      type: "FeatureCollection",
      generated_at: "2026-09-28T18:00:00.000Z",
      feed_healthy: true,
      health_detail: null,
      features: [],
    });
  });

  // generated_at must mean "last SUCCESSFUL poll", or the app's staleness
  // rule never fires during an outage.
  it.each([
    ["an HTTP error", () => new Response("", { status: 502 })],
    ["a non-RSS 200", () => new Response("<html>blocked</html>")],
  ])("leaves the previous envelope untouched on %s", async (_label, respond) => {
    vi.stubGlobal("fetch", async () => respond());
    const env = fakeEnv('{"previous":true}');
    await expect(poll(env)).rejects.toThrow();
    expect(env.store.get("envelope")).toBe('{"previous":true}');
  });
});

describe("serve", () => {
  const get = (path = "/", method = "GET") =>
    new Request(`https://example.invalid${path}`, { method });

  it("503s before any poll has completed, with CORS so the app can read it", async () => {
    const res = await serve(get(), fakeEnv());
    expect(res.status).toBe(503);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Cache-Control")).toBe("no-store");
  });

  it("serves the stored envelope verbatim", async () => {
    const res = await serve(get(), fakeEnv('{"type":"FeatureCollection"}'));
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('{"type":"FeatureCollection"}');
    expect(res.headers.get("Content-Type")).toContain("application/geo+json");
  });

  it("404s other paths and 405s other methods", async () => {
    expect((await serve(get("/x"), fakeEnv("{}"))).status).toBe(404);
    expect((await serve(get("/", "POST"), fakeEnv("{}"))).status).toBe(405);
  });
});
