// The discovery tier: the Notify NYC RSS feed, parsed and assessed.
//
// Nothing here reads CAP. It decides only what the RSS alone can: whether the
// feed is quiet, broken, or holding English alerts for cap.ts to read.

import { XMLParser } from "fast-xml-parser";

export const FEED_URL =
  "https://feeds.everbridge.net/feeds/453003085617722/rss/rss.xml";

// The exact literal. Everbridge encodes the language in a human-readable label
// rather than a CAP field - see "The monitoring rule" in ALERTS_SERVICE.md.
export const ENGLISH_AUTHOR = "NYCEM [English]";

export interface FeedItem {
  guid: string;
  author: string;
  title: string;
  link: string;
}

const parser = new XMLParser({
  // guids are 16-digit numbers. With value parsing on, "2655390911272538"
  // becomes a JS number - exact today, but one digit longer and it silently
  // rounds, and the persistence key stops matching. Keep every value a string.
  parseTagValue: false,
  // One <item> parses as an object, several as an array. Force the array so
  // the one-alert case is not a different shape from the five-alert case.
  isArray: (name) => name === "item",
});

/** RSS text -> items. Throws on anything that is not an RSS 2.0 document. */
export function parseFeed(xml: string): FeedItem[] {
  const doc = parser.parse(xml);
  const channel = doc?.rss?.channel;
  // An empty <channel> parses to "", which is falsy but valid. Test for the
  // key, not the value: a quiet feed must not be mistaken for a broken one.
  if (!doc?.rss || !("channel" in doc.rss)) {
    throw new Error("not an RSS document");
  }
  const items: unknown[] = channel?.item ?? [];
  return items.map((raw) => {
    const item = raw as Record<string, unknown>;
    return {
      guid: text(item.guid),
      author: text(item.author),
      title: text(item.title),
      link: text(item.link),
    };
  });
}

// <guid isPermaLink="false"> would parse to an object with a #text key.
function text(value: unknown): string {
  if (value && typeof value === "object" && "#text" in value) {
    return String((value as { "#text": unknown })["#text"]).trim();
  }
  return value == null ? "" : String(value).trim();
}

export interface Assessment {
  /**
   * What the RSS tier alone can conclude:
   *   empty            no items at all - a quiet feed, healthy
   *   english_missing  items, none English - the filter string changed
   *   english_present  go on to the CAP tier
   */
  verdict: "empty" | "english_missing" | "english_present";
  english: FeedItem[];
  total: number;
}

export function assessFeed(items: FeedItem[]): Assessment {
  const english = items.filter((i) => i.author === ENGLISH_AUTHOR);
  const total = items.length;

  // An empty feed is a quiet period, not an outage - observed 2026-09-28
  // 17:04 UTC.
  if (total === 0) return { verdict: "empty", english, total };

  // English missing while other languages are present: the filter string has
  // changed, not the weather.
  if (english.length === 0) return { verdict: "english_missing", english, total };

  return { verdict: "english_present", english, total };
}
