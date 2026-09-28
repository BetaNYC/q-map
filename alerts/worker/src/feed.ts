// The discovery tier: the Notify NYC RSS feed, parsed and assessed.
//
// Nothing here reads CAP. Status, msgType, expiry, geometry - rules 1-8 in
// ALERTS_SERVICE.md - arrive with the CAP layer, which is deliberately not
// built until data/archive/alerts/ holds real CAP files to test it against.

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
  healthy: boolean;
  /** Diagnostics only. The app branches on `healthy`, never on this string. */
  detail: string | null;
  english: number;
  total: number;
}

export function assessFeed(items: FeedItem[]): Assessment {
  const english = items.filter((i) => i.author === ENGLISH_AUTHOR).length;
  const total = items.length;

  // An empty feed is a quiet hour, not an outage - observed 2026-09-28 17:04
  // UTC. The one state in which this phase can truthfully say "no alerts".
  if (total === 0) {
    return { healthy: true, detail: null, english, total };
  }

  // English missing while other languages are present: the filter string has
  // changed, not the weather.
  if (english === 0) {
    return { healthy: false, detail: "english_missing", english, total };
  }

  // Alerts exist, and this phase cannot interpret them - it has no CAP layer
  // to apply rules 1-8. Serving an empty list here would be a false all-clear
  // during a real alert. Unavailable is the honest answer until the CAP layer
  // lands; the app already renders it as "no banner".
  return { healthy: false, detail: "alerts_uninterpreted", english, total };
}
