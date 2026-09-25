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
 * The legend swatch, read off the Figma LayerRow instances.
 *
 * Four of them, and they are exactly the four available `context` layers that
 * have discrete geometry — two PMTiles and two GeoJSON. That is not a
 * coincidence: a single flat swatch is the right key for a polygon layer drawn
 * in one colour.
 *
 * The other three available context layers (hvi_choropleth, chem_businesses,
 * pivi_choropleth) are `delivery: inline` choropleths, drawn as a graduated
 * fill joined to cdta.geojson. A 16px flat swatch is the wrong legend for a
 * ramp, and no ramp legend is designed — so they are not listed yet rather than
 * given an invented colour. See web/README.md.
 */
const LAYER_SWATCH: Record<string, string> = {
  stormwater_limited_1_77: '#9bbde9',
  stormwater_moderate_2_13: '#3f6bb9',
  hurricane_evac_zones: '#ebaa7d',
  surge_current: '#d8b663'
};

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
