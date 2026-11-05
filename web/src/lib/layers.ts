import { LAYER_SWATCH } from '$lib/map/palette';

/**
 * Map layer vocabulary.
 *
 * `data/registry/map_layers.csv` is the catalogue and the vocabulary for hazard
 * content's `map_layers` (DATA_CONTRACT.md §8). It is NOT in `data/processed/`,
 * so the browser cannot fetch it — `$lib/server/registry.ts` reads it at build
 * time instead and the available rows are serialised into the page.
 *
 * That keeps one copy of the list. Hand-maintaining a second one here is
 * exactly the drift CLAUDE.md warns about.
 */

export interface MapLayer {
  /** Permalink surface — it appears in `?layers=` (§5). */
  layer_id: string;
  label: string;
  /** `context` overlays vs `resource` point layers. */
  kind: 'context' | 'resource';
  /** `inline` means the values ship in the district payload and join to
   *  cdta.geojson by cdta2020 — there is no file to fetch. */
  delivery: string;
  status: string;
}

/**
 * The legend swatch for a layer's row in the Layers tab.
 *
 * Six of them since 2026-11-05: the two stormwater layers in their own colour,
 * and the four graded coastal layers (tidal, surge, FEMA, evacuation zones)
 * by their darkest class - a flat placeholder until Andrew's legend replaces
 * it. The values live in $lib/map/palette.ts beside the map paint they key.
 *
 * The three `delivery: inline` choropleths (hvi_choropleth, chem_businesses,
 * pivi_choropleth) are still not listed: they are graduated fills joined to
 * cdta.geojson with no styling or legend yet. See web/README.md.
 */
export function swatchFor(layer: MapLayer): string | null {
  return LAYER_SWATCH[layer.layer_id] ?? null;
}

/**
 * The layers the Layers tab can currently draw a row for.
 *
 * `kind: resource` is excluded on purpose — cooling_centers, evacuation_centers
 * and `resources` are point layers driven by the Resources tab's categories,
 * not context overlays. Listing them in both tabs would give one thing two
 * switches.
 */
export function listableLayers(layers: MapLayer[]): MapLayer[] {
  return layers.filter((l) => l.kind === 'context' && swatchFor(l) !== null);
}
