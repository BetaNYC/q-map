import type { DistrictIndexEntry } from './types';

/**
 * Which community district a point is in. Shared by "Use my location"
 * (FRONTEND_PLAN.md step 3) and the address field (step 4).
 *
 * No geometry library: point-in-polygon is twenty lines, and turf would add
 * tens of kilobytes to the entry page for one function.
 *
 * WHAT `cdta.geojson` DOES NOT COVER. It holds the 59 CDTAs that correspond to
 * community districts (CDTAType "0"). The 12 Joint Interest Areas — parks and
 * airports: JFK, LaGuardia, Flushing Meadows, Forest Park, Central Park, … —
 * are not in it (METHODOLOGY.md, "CDTAType is a string"). A point there is in
 * NO district, which is a different answer from "outside Queens" and must be
 * worded as one.
 */

type Ring = [number, number][];
type PolygonCoords = Ring[];

export interface CdtaFeature {
  type: 'Feature';
  properties: { cdta2020: string; slug: string };
  geometry:
    | { type: 'Polygon'; coordinates: PolygonCoords }
    | { type: 'MultiPolygon'; coordinates: PolygonCoords[] };
}

/**
 * Even-odd ray casting. A point exactly on an edge may fall either way; at
 * district boundaries that is a metre or two, below GPS and geocoder error.
 */
function inRing([x, y]: [number, number], ring: Ring): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** Inside the outer ring and in none of its holes. */
function inPolygon(point: [number, number], [outer, ...holes]: PolygonCoords): boolean {
  return inRing(point, outer) && !holes.some((h) => inRing(point, h));
}

/** The feature containing [lon, lat], or null. */
export function featureAt(point: [number, number], features: CdtaFeature[]): CdtaFeature | null {
  for (const f of features) {
    const polygons = f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates;
    if (polygons.some((p) => inPolygon(point, p))) return f;
  }
  return null;
}

export type Placement =
  /** A Queens district: navigate to /{slug}. */
  | { kind: 'queens'; district: DistrictIndexEntry }
  /** A community district in another borough - named, so the message can say where. */
  | { kind: 'elsewhere'; district: DistrictIndexEntry }
  /** In no community district: outside NYC, or in a park or airport. */
  | { kind: 'none' };

export function placePoint(
  point: [number, number],
  features: CdtaFeature[],
  districts: DistrictIndexEntry[]
): Placement {
  const f = featureAt(point, features);
  const district = f && districts.find((d) => d.cdta2020 === f.properties.cdta2020);
  if (!district) return { kind: 'none' };
  return district.boro === 'Queens' ? { kind: 'queens', district } : { kind: 'elsewhere', district };
}
