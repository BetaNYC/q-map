import { dataUrl } from './data';
import type { CdtaFeature } from './geo';

/**
 * cdta.geojson, fetched once per visit on first use and shared by "Use my
 * location" and the address field. 126 KB, and only fetched when someone asks
 * where they are - the picker map loads its own copy through MapLibre.
 *
 * A failure is not cached, so the next attempt retries.
 */
let boundaries: Promise<CdtaFeature[]> | undefined;

export function loadBoundaries(): Promise<CdtaFeature[]> {
  boundaries ??= fetch(dataUrl('cdta.geojson')).then(async (r) => {
    if (!r.ok) throw new Error(`cdta.geojson: ${r.status}`);
    return (await r.json()).features as CdtaFeature[];
  });
  boundaries.catch(() => (boundaries = undefined));
  return boundaries;
}
