// Headline -> event, location, scope. The only geography Notify NYC gives us.
//
// WORKED EXAMPLE — the first piece of the CAP layer, and the first place this
// project reads meaning out of free text. ALERTS_SERVICE.md, "The headline is
// the location", is the specification; METHODOLOGY.md, "Five real alerts
// overturned the brief's geography", is why it exists at all.
//
// Why a headline and not the CAP fields built for this: in all five archived
// alerts, <geocode> listed all five boroughs and <areaDesc> named all five -
// for a Bronx water main as much as a citywide advisory - and none carried a
// <polygon>. The borough tag at the end of the headline was the only field
// that told them apart.
//
// Three rules it encodes:
//
// 1. PARSE THE TAG AND THE EVENT, NOTHING ELSE. `location` is lifted out for
//    display and never interpreted. Geocoding "Hillside Avenue" would put a
//    guess on a map; ALERTS_SERVICE.md forbids it.
//
// 2. AN UNRECOGNISED TAG IS 'unknown', AND 'unknown' IS KEPT. Five alerts
//    showed two spellings for boroughs in one day ("QN", "Staten Island").
//    The next spelling will arrive unannounced. Dropping a real Queens alert
//    because of it is worse than showing a stray Bronx one, so the filter
//    errs toward inclusion and the service logs the tag for the table.
//
// 3. NEVER THROWS. A headline that does not fit the grammar still produces a
//    result - scope 'unknown', event and location null - so one odd alert
//    cannot take down the poll that carries the others.

export type Scope = "queens" | "citywide" | "other" | "unknown";

export interface ParsedHeadline {
  /** "Three Alarm Fire". Null only when the headline does not fit the grammar. */
  event: string | null;
  /** "Hillside Avenue". Display only. Null when absent or a date ("9/29"). */
  location: string | null;
  /** Drives the Queens filter (rule 8). 'other' is dropped; the rest are kept. */
  scope: Scope;
  /** The raw tag, for the log line when scope is 'unknown'. */
  tag: string | null;
}

// Notify NYC - <event>[ - <location>] (<tag>)
//
// The tag is the LAST parenthesised group, anchored to the end, so a location
// that itself contains parentheses cannot be mistaken for it. The prefix is
// required: a headline without it is not in the observed grammar at all.
const GRAMMAR = /^Notify NYC\s+-\s+(?<body>.+?)\s*\((?<tag>[^()]+)\)\s*$/;

// Segments are separated by " - " with spaces. A bare hyphen is part of a
// name ("Wilkes-Barre", "Hi-Rise"), so it must not split.
const SEPARATOR = /\s+-\s+/;

// "9/29", "9/29/2026", "09-29-2026". The Staten Island coastal flood
// statement used the date as its location segment; it is not a place.
const DATE_LIKE = /^\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?$/;

// Keys are normalised by normaliseTag(). OBSERVED entries are the four tags
// seen in the 2026-09-28/29 archive; the rest are the NYC-standard codes and
// names for each borough - the spellings a new tag is most likely to use.
const TAGS: Record<string, Exclude<Scope, "unknown">> = {
  qn: "queens", // OBSERVED
  queens: "queens",
  nyc: "citywide", // OBSERVED
  citywide: "citywide",
  "all boroughs": "citywide",
  "five boroughs": "citywide",
  bx: "other", // OBSERVED
  bronx: "other",
  "the bronx": "other",
  "staten island": "other", // OBSERVED
  si: "other",
  mn: "other",
  manhattan: "other",
  bk: "other",
  brooklyn: "other",
};

function normaliseTag(tag: string): string {
  return tag.replace(/ /g, " ").replace(/\s+/g, " ").trim().replace(/\.$/, "").toLowerCase();
}

/** A tag, possibly naming several boroughs ("QN & BK"), -> one scope. */
export function scopeOf(tag: string): Scope {
  const whole = TAGS[normaliseTag(tag)];
  if (whole) return whole;

  // Unobserved, but the plausible shape of a two-borough alert. Queens
  // anywhere wins; a citywide part wins next; only a tag whose every part is
  // a known other borough may be dropped.
  const parts = normaliseTag(tag)
    .split(/\s*(?:&|\/|,|\band\b)\s*/)
    .filter(Boolean)
    .map((part) => TAGS[part]);
  if (parts.length < 2) return "unknown";
  if (parts.includes("queens")) return "queens";
  if (parts.includes("citywide")) return "citywide";
  if (parts.every((scope) => scope === "other")) return "other";
  return "unknown";
}

export function parseHeadline(headline: string): ParsedHeadline {
  const match = GRAMMAR.exec(headline.replace(/ /g, " ").trim());
  if (!match?.groups) {
    return { event: null, location: null, scope: "unknown", tag: null };
  }

  const tag = match.groups.tag.trim();
  const [event, ...rest] = match.groups.body.split(SEPARATOR).map((s) => s.trim());
  // Rejoin rather than take rest[0]: a location may itself hold " - ".
  const location = rest.join(" - ") || null;

  return {
    event: event || null,
    location: location && !DATE_LIKE.test(location) ? location : null,
    scope: scopeOf(tag),
    tag,
  };
}
