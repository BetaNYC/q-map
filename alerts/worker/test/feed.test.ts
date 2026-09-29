import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { assessFeed, parseFeed, type FeedItem } from "../src/feed";

const fixture = (name: string) =>
  readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

const item = (author: string, pubDate = "Tue, 29 Sep 2026 12:58:15 GMT"): FeedItem => ({
  guid: "1",
  author,
  title: "",
  link: "",
  pubDate,
});

describe("parseFeed", () => {
  it("reads the real empty feed (2026-09-28) as zero items, not an error", () => {
    expect(parseFeed(fixture("feed-empty-2026-09-28.xml"))).toEqual([]);
  });

  it("reads items, keeping 17-digit guids exact", () => {
    const items = parseFeed(fixture("feed-synthetic-two-languages.xml"));
    expect(items).toHaveLength(2);
    expect(items[0]).toEqual({
      guid: "2655390911272538",
      author: "NYCEM [English]",
      title: "Flood Advisory - Manhattan, The Bronx & Staten Island",
      link: "https://example.invalid/cap/2655390911272538.xml",
      pubDate: "Mon, 03 Aug 2026 14:55:01 GMT",
    });
    // Beyond 2^53: parsed as a number this would round to ...388.
    expect(items[1].guid).toBe("26553909112725389");
  });

  it("returns an array for a single item", () => {
    const one = `<rss version="2.0"><channel><item><guid>1</guid></item></channel></rss>`;
    expect(parseFeed(one)).toHaveLength(1);
  });

  it("rejects a non-RSS body, e.g. an HTML error page served with a 200", () => {
    expect(() => parseFeed("<html><body>blocked</body></html>")).toThrow("not an RSS");
  });
});

describe("assessFeed", () => {
  const LANGUAGES = ["Arabic", "Bengali", "Chinese", "French", "Haitian Creole", "Italian", "Korean",
    "Polish", "Russian", "Spanish", "Urdu", "Yiddish"];

  it("empty feed: quiet, not an outage", () => {
    expect(assessFeed([], new Date())).toMatchObject({ verdict: "quiet", total: 0 });
  });

  // The live feed at 14:57:56 UTC on 2026-09-29: the English police-activity
  // alert (pubDate 12:56:30) had expired at 14:56:30; its 12 translations,
  // published at 12:58:15-12:58:20, had not. Reported as english_missing by
  // the first version of this check.
  it("translations outliving their expired English by minutes: quiet", () => {
    const tail = LANGUAGES.map((l) => item(`NYCEM [${l}]`, "Tue, 29 Sep 2026 12:58:15 GMT"));
    expect(assessFeed(tail, new Date("2026-09-29T14:57:56Z")).verdict).toBe("quiet");
  });

  it("recent translations with no English: the filter string changed", () => {
    const fresh = LANGUAGES.map((l) => item(`NYCEM [${l}]`, "Tue, 29 Sep 2026 12:58:15 GMT"));
    expect(assessFeed(fresh, new Date("2026-09-29T13:00:00Z")).verdict).toBe("english_missing");
  });

  it("the boundary is one hour from the translation's pubDate", () => {
    const one = [item("NYCEM [Spanish]", "Tue, 29 Sep 2026 12:00:00 GMT")];
    expect(assessFeed(one, new Date("2026-09-29T12:59:59Z")).verdict).toBe("english_missing");
    expect(assessFeed(one, new Date("2026-09-29T13:00:00Z")).verdict).toBe("quiet");
  });

  it("an unparseable pubDate counts as recent - the safe error", () => {
    expect(assessFeed([item("NYCEM [Spanish]", "soon")], new Date()).verdict).toBe("english_missing");
  });

  it("English present: on to the CAP tier, carrying only the English items", () => {
    const a = assessFeed([item("NYCEM [English]"), item("NYCEM [Spanish]")], new Date());
    expect(a).toMatchObject({ verdict: "english_present", total: 2 });
    expect(a.english.map((i) => i.author)).toEqual(["NYCEM [English]"]);
  });

  it("matches the author exactly", () => {
    const at = new Date("2026-09-29T13:00:00Z");
    expect(assessFeed([item("NYCEM [English (US)]")], at).verdict).toBe("english_missing");
  });
});
