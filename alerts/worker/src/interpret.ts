// Parsed CAP alerts -> the features the endpoint serves.
//
// The eight rules of ALERTS_SERVICE.md, applied to every English alert
// currently in the feed. Stateless: because the feed holds each alert until
// it expires (METHODOLOGY.md, "Five real alerts..."), the current feed is the
// complete set of live alerts and the Update/Cancel messages that supersede
// them - no history needs to be kept to apply the lifecycle.

import { cleanBody } from "./body";
import type { CapAlert } from "./cap";
import { parseHeadline, type Scope } from "./headline";

export interface AlertProperties {
  id: string;
  guid: string;
  headline: string;
  event: string | null;
  location: string | null;
  scope: Exclude<Scope, "other">;
  category: string;
  body: string;
  translations_url: string | null;
  sent: string;
  expires: string;
  hazard_slug: string | null;
  districts: string[];
}

export interface AlertFeature {
  type: "Feature";
  geometry: { type: "MultiPolygon"; coordinates: number[][][][] } | null;
  properties: AlertProperties;
}

// event -> hazard slug. Deliberately empty: the one candidate
// (Coastal Flood Statement -> coastal-storm) is undecided, and a wrong hazard
// page is worse than none. Unmatched events are logged so the table grows
// from real alerts. Keys are exact `event` strings.
const EVENT_HAZARDS: Record<string, string> = {};

export interface Interpretation {
  features: AlertFeature[];
  /** One line per notable decision, for the Worker log. */
  log: string[];
}

export function interpret(
  alerts: { guid: string; cap: CapAlert }[],
  now: Date,
): Interpretation {
  const log: string[] = [];

  // Rule 3. Nothing edits in place: an Update or Cancel names the messages it
  // supersedes, and those must stop showing. Ack and Error are not alerts.
  const superseded = new Set(
    alerts
      .filter(({ cap }) => cap.msgType === "Update" || cap.msgType === "Cancel")
      .flatMap(({ cap }) => cap.references),
  );

  const features: AlertFeature[] = [];
  for (const { guid, cap } of alerts) {
    const label = `${guid} "${cap.headline}"`;

    // Rule 1. A drill rendered as a live emergency is the worst failure available.
    if (cap.status !== "Actual") {
      log.push(`dropped ${label}: status ${cap.status}`);
      continue;
    }
    if (cap.msgType !== "Alert" && cap.msgType !== "Update") {
      if (cap.msgType !== "Cancel") log.push(`dropped ${label}: msgType ${cap.msgType}`);
      continue;
    }
    if (superseded.has(cap.identifier)) {
      log.push(`dropped ${label}: superseded`);
      continue;
    }

    // Rule 4. Unparseable counts as expired: without it there is no
    // authoritative stop-showing time.
    const expires = Date.parse(cap.expires);
    if (Number.isNaN(expires) || expires <= now.getTime()) continue;

    // Rule 7.
    if (cap.certainty === "Unlikely") {
      log.push(`dropped ${label}: certainty Unlikely`);
      continue;
    }

    // Rule 8. The headline tag, never <geocode> (rule 6).
    const headline = parseHeadline(cap.headline);
    if (headline.scope === "other") continue;
    if (headline.scope === "unknown") {
      log.push(`kept ${label}: unrecognised tag ${JSON.stringify(headline.tag)} - add it to headline.ts`);
    }

    // Rule 5. Kept for display. Polygon alerts do not yet resolve to
    // districts (no cdta.geojson intersection), so they are filtered by
    // headline like any other - flagged, because none has been seen and the
    // August sample's polygon headline did not fit the grammar.
    const geometry = toMultiPolygon(cap, log);
    if (geometry) log.push(`polygon alert ${label}: districts not resolved (not built)`);

    const hazard_slug = headline.event ? (EVENT_HAZARDS[headline.event] ?? null) : null;
    if (headline.event && hazard_slug === null) {
      log.push(`no hazard for event ${JSON.stringify(headline.event)}`);
    }

    features.push({
      type: "Feature",
      geometry,
      properties: {
        id: cap.identifier,
        guid,
        headline: cap.headline,
        event: headline.event,
        location: headline.location,
        scope: headline.scope,
        category: cap.category,
        ...cleanBody(cap.description),
        sent: cap.sent,
        expires: cap.expires,
        hazard_slug,
        districts: [],
      },
    });
  }

  // Newest first. The priority triple is constant in the data, so it is not
  // a sort key (rule 7).
  features.sort((a, b) => Date.parse(b.properties.sent) - Date.parse(a.properties.sent));
  return { features, log };
}

/**
 * Rule 5. CAP polygons are "lat,lon" pairs; GeoJSON wants [lon, lat], and a
 * closed ring. A ring that cannot be read is skipped and logged rather than
 * guessed at.
 */
export function toMultiPolygon(cap: CapAlert, log: string[] = []): AlertFeature["geometry"] {
  const polygons: number[][][][] = [];
  for (const raw of cap.areas.flatMap((a) => a.polygons)) {
    const ring = raw.split(/\s+/).map((pair) => {
      const [lat, lon] = pair.split(",").map(Number);
      return [lon, lat];
    });
    if (ring.some(([lon, lat]) => !Number.isFinite(lon) || !Number.isFinite(lat))) {
      log.push(`skipped unreadable polygon on ${cap.identifier}`);
      continue;
    }
    const [first, last] = [ring[0], ring[ring.length - 1]];
    if (first[0] !== last[0] || first[1] !== last[1]) ring.push([...first]);
    // A closed ring needs at least four positions (a triangle plus closure).
    if (ring.length < 4) {
      log.push(`skipped degenerate polygon on ${cap.identifier}`);
      continue;
    }
    polygons.push([ring]);
  }
  return polygons.length ? { type: "MultiPolygon", coordinates: polygons } : null;
}
