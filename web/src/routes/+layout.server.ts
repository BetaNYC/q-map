import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { listableLayers } from '$lib/layers';
import type { MapDistrict } from '$lib/mapView';
import { readAvailableLayers } from '$lib/server/registry';
import type { DistrictIndexEntry } from '$lib/types';
import type { LayoutServerLoad } from './$types';

/**
 * What the docked map needs on every page: the Queens 14, to outline, fit to
 * and click through to, and the bounds of Queens, for the pages that are not
 * about one district.
 *
 * Here rather than in each page's MapView so a page names its district by
 * slug, which every district route already has as a parameter, and no route
 * needs a server load just to read a bbox.
 *
 * Only Queens has pages (§5), so only Queens is clickable. Filtered on
 * districts.json's `boro`, not on a "QN" prefix on cdta2020, so the rule reads
 * the same field the route manifests do and cannot drift from them.
 *
 * Inlined into every prerendered page: 14 entries of four fields, about 1.7 KB.
 * Named `mapDistricts` because the entry page's own load already returns a
 * `queens`, and page data is merged over layout data.
 */
const index: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(process.cwd(), 'static', 'data', 'districts.json'), 'utf8')
);

const mapDistricts: MapDistrict[] = index
  .filter((d) => d.boro === 'Queens')
  .map(({ cdta2020, slug, display_name, bbox }) => ({ cdta2020, slug, display_name, bbox }));

if (mapDistricts.length !== 14) {
  throw new Error(`expected 14 Queens districts in districts.json, found ${mapDistricts.length}`);
}

/** The union of the 14 district bboxes: [xmin, ymin, xmax, ymax]. */
const queensBbox: MapDistrict['bbox'] = [
  Math.min(...mapDistricts.map((d) => d.bbox[0])),
  Math.min(...mapDistricts.map((d) => d.bbox[1])),
  Math.max(...mapDistricts.map((d) => d.bbox[2])),
  Math.max(...mapDistricts.map((d) => d.bbox[3]))
];

/**
 * The layers a reader can switch, in registry order: what `?layers=` is
 * checked against on every page. The registry is a CSV read at build time
 * (data/registry/map_layers.csv) and not shipped, so this is the only way it
 * reaches the browser. Four rows, about 0.5 KB per page.
 */
const mapLayers = listableLayers(readAvailableLayers());

export const load: LayoutServerLoad = () => ({ mapDistricts, queensBbox, mapLayers });
