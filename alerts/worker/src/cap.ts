// The data tier: one CAP 1.2 document -> the fields the service reads.
//
// Parsing only. No rule is applied here - status, lifecycle, expiry and the
// Queens filter live in interpret.ts - so the parsed form can be cached in KV
// and re-interpreted after a deploy changes the rules.

import { XMLParser } from "fast-xml-parser";

export interface CapArea {
  areaDesc: string;
  /** Raw CAP polygon strings, "lat,lon lat,lon ...". None seen in the archive yet. */
  polygons: string[];
}

export interface CapAlert {
  identifier: string;
  sent: string;
  status: string;
  msgType: string;
  /** Identifiers from <references>, which holds "sender,identifier,sent" triples. */
  references: string[];
  language: string;
  category: string;
  certainty: string;
  expires: string;
  headline: string;
  description: string;
  areas: CapArea[];
}

const parser = new XMLParser({
  // Same reason as feed.ts: identifiers are 16-digit numbers.
  parseTagValue: false,
  // Some producers write <cap:alert>; Everbridge uses a default namespace.
  removeNSPrefix: true,
  // Every repeatable CAP element, forced to an array so one and many parse
  // to the same shape.
  isArray: (name) => ["info", "area", "polygon", "category"].includes(name),
});

/** CAP XML -> CapAlert. Throws on anything that is not a CAP <alert>. */
export function parseCap(xml: string): CapAlert {
  const alert = parser.parse(xml)?.alert;
  if (!alert || typeof alert !== "object") {
    throw new Error("not a CAP <alert>");
  }

  // CAP allows one <info> per language in a single alert. Everbridge sends
  // one alert per language instead, each with a single <info>, but take the
  // English block explicitly rather than trusting position.
  const infos: Record<string, unknown>[] = alert.info ?? [];
  const info = infos.find((i) => text(i.language).toLowerCase().startsWith("en")) ?? infos[0];
  if (!info) {
    throw new Error(`CAP ${text(alert.identifier)} has no <info>`);
  }

  const areas = ((info.area as Record<string, unknown>[] | undefined) ?? []).map((area) => ({
    areaDesc: text(area.areaDesc),
    polygons: ((area.polygon as unknown[] | undefined) ?? []).map(text).filter(Boolean),
  }));

  return {
    identifier: text(alert.identifier),
    sent: text(alert.sent),
    status: text(alert.status),
    msgType: text(alert.msgType),
    references: text(alert.references)
      .split(/\s+/)
      .filter(Boolean)
      .map((triple) => triple.split(",")[1] ?? "")
      .filter(Boolean),
    language: text(info.language),
    category: text((info.category as unknown[] | undefined)?.[0]),
    certainty: text(info.certainty),
    expires: text(info.expires),
    headline: text(info.headline),
    description: text(info.description),
    areas,
  };
}

function text(value: unknown): string {
  if (value && typeof value === "object" && "#text" in value) {
    return String((value as { "#text": unknown })["#text"]).trim();
  }
  return value == null ? "" : String(value).trim();
}
