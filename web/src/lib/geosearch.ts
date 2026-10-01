/**
 * NYC GeoSearch (NYC City Planning), for the entry page's address field.
 *
 * Verified 2026-09-30: `Access-Control-Allow-Origin: *`, no key, an
 * autocomplete endpoint. The site's third runtime dependency, after the CARTO
 * basemap and the alerts Worker — so everything here may fail, and the caller
 * degrades to the district list when it does.
 *
 * Shapes from real responses (src/lib/fixtures/geosearch-*.json):
 *   - labels arrive upper-case with a ", NY, USA" tail:
 *     "46-01 5 STREET, Long Island City, NY, USA"
 *   - one building can arrive twice under two spellings at one point:
 *     "1 BROADWAY" and "1 B'WAY", both Howard Beach, both [-73.830522, 40.658433]
 *   - results span all five boroughs
 */

export const AUTOCOMPLETE_URL = 'https://geosearch.planninglabs.nyc/v2/autocomplete';

/** Shown at most; the list sits above two panels on a phone. */
export const MAX_SUGGESTIONS = 6;

export interface Suggestion {
  /** Stable key: the rounded coordinates. */
  id: string;
  /** "46-01 5 Street, Long Island City" */
  label: string;
  borough: string;
  point: [number, number];
}

/**
 * A bare ZIP code is never sent (decision 3, 2026-09-30). Measured: "11691"
 * (Far Rockaway, QN14) geocodes to a house on Springfield Blvd in Cambria
 * Heights (QN13) - a confident wrong answer.
 */
export function isBareZip(text: string): boolean {
  return /^\s*\d{5}(-\d{4})?\s*$/.test(text);
}

/** "46-01 5 STREET" -> "46-01 5 Street"; "B'WAY" -> "B'way". */
function titleCase(s: string): string {
  return s.toLowerCase().replace(/(^|[\s-])([a-z])/g, (_m, sep: string, c: string) => sep + c.toUpperCase());
}

/** GeoSearch's label -> street and place, without the ", NY, USA" tail. */
function displayLabel(raw: string): string {
  const [street, place] = raw.split(', ');
  return place ? `${titleCase(street)}, ${place}` : titleCase(street);
}

interface GeoSearchFeature {
  geometry: { coordinates: [number, number] };
  properties: { label?: string; borough?: string };
}

/**
 * Response -> suggestions. One per location: where two spellings share a
 * point, the longer label wins ("Broadway" over "B'way"). Queens first, in
 * GeoSearch's order otherwise - this map covers Queens, and a Queens address
 * is almost always the one meant.
 */
export function parseSuggestions(json: { features?: GeoSearchFeature[] }): Suggestion[] {
  const byPoint = new Map<string, Suggestion>();
  for (const f of json.features ?? []) {
    const raw = f.properties.label;
    const [lon, lat] = f.geometry?.coordinates ?? [];
    if (!raw || !Number.isFinite(lon) || !Number.isFinite(lat)) continue;
    const id = `${lon.toFixed(5)},${lat.toFixed(5)}`;
    const s: Suggestion = { id, label: displayLabel(raw), borough: f.properties.borough ?? '', point: [lon, lat] };
    const seen = byPoint.get(id);
    if (!seen || s.label.length > seen.label.length) byPoint.set(id, s);
  }
  const all = [...byPoint.values()];
  return [...all.filter((s) => s.borough === 'Queens'), ...all.filter((s) => s.borough !== 'Queens')].slice(0, MAX_SUGGESTIONS);
}

/** Throws on network or HTTP failure; the caller decides what to say. */
export async function fetchSuggestions(
  text: string,
  { fetchFn = fetch, signal }: { fetchFn?: typeof fetch; signal?: AbortSignal } = {}
): Promise<Suggestion[]> {
  const url = `${AUTOCOMPLETE_URL}?text=${encodeURIComponent(text.trim())}`;
  const response = await fetchFn(url, { signal });
  if (!response.ok) throw new Error(`GeoSearch ${response.status}`);
  return parseSuggestions(await response.json());
}
