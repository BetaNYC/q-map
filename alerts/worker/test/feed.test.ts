import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { assessFeed, parseFeed, type FeedItem } from "../src/feed";

const fixture = (name: string) =>
  readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

const item = (author: string): FeedItem => ({ guid: "1", author, title: "", link: "" });

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
  it("empty feed: a quiet period, not an outage", () => {
    expect(assessFeed([])).toMatchObject({ verdict: "empty", total: 0 });
  });

  it("other languages but no English: the filter string changed", () => {
    expect(assessFeed([item("NYCEM [Spanish]")]).verdict).toBe("english_missing");
  });

  it("English present: on to the CAP tier, carrying only the English items", () => {
    const a = assessFeed([item("NYCEM [English]"), item("NYCEM [Spanish]")]);
    expect(a).toMatchObject({ verdict: "english_present", total: 2 });
    expect(a.english.map((i) => i.author)).toEqual(["NYCEM [English]"]);
  });

  it("matches the author exactly", () => {
    expect(assessFeed([item("NYCEM [English (US)]")]).verdict).toBe("english_missing");
  });
});
