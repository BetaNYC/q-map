import type { ExpressionSpecification, LayerSpecification, SourceSpecification } from 'maplibre-gl';
import { dataUrl } from '$lib/data';
import { EVAC, EVAC_OPACITY, FEMA, STORMWATER, SURGE, TIDAL, rampExpression, type Ramp } from './palette';

/**
 * How each toggleable overlay becomes MapLibre sources and layers.
 *
 * Keyed by `layer_id` — the same string that appears in `?layers=`, in a
 * hazard's `map_layers`, and in `data/registry/map_layers.csv`. One vocabulary
 * end to end, so a layer turned on by a shared link is the layer that draws.
 *
 * Only the five with a legend swatch are here, which is the same five
 * `listableLayers()` returns: the available `context` layers with discrete
 * geometry. The three `delivery: inline` choropleths join to cdta.geojson and
 * need a graduated fill and a ramp legend that is not designed; the three
 * `kind: resource` layers are the Resources tab's business.
 *
 * Colours come from $lib/map/palette.ts, which the Layers tab's swatches read
 * too, so the key in the sheet is the colour on the map.
 */

export interface OverlaySpec {
  /** Added to the style under this id, prefixed so nothing collides with the
   *  basemap's own sources. */
  sourceId: string;
  /**
   * Where in the basemap's stack the layers go (Andrew, 2026-11-05).
   *
   *   'under-roads'  below the basemap's roads, buildings and labels, so an
   *                  opaque fill still shows every street on top of it. The
   *                  graded coastal layers.
   *   'top'          above everything in the basemap. Stormwater, which must
   *                  read over the graded layers.
   *
   * Map.svelte resolves 'under-roads' to a basemap layer id (basemap.ts).
   */
  position: 'under-roads' | 'top';
  source: SourceSpecification;
  /** Drawn in order. Ids are prefixed the same way. */
  layers: LayerSpecification[];
}

/**
 * Stormwater: ONE layer since 2026-11-05 (Andrew), its two rain scenarios as
 * the `rain` attribute of stormwater.pmtiles, keyed by the layer's legend.
 * Still drawn as before, told apart by lightness (Andrew, 2026-10-08):
 *
 *   moderate  2.13 in/hr, the heavier storm and the wider extent: blue/600 at
 *             65%, with a 1px off-white outline (STORMWATER in palette.ts)
 *   limited   1.77 in/hr, the thin core inside it: blue/200 at 90%, on top
 *
 * Three style layers on one source, filtered on `rain`, so the order holds
 * whatever the feature order in the tiles: moderate fill, its outline, then
 * the limited fill over both. A casing on LIMITED was tried and dropped on
 * 2026-10-08: at district zoom it swallowed the thin shapes into white
 * speckle.
 *
 * On 'top', above the roads, because it must read over the graded layers.
 */
function stormwater(): OverlaySpec {
  const sourceId = 'overlay-stormwater';
  const rain = (value: 'limited' | 'moderate'): ExpressionSpecification => ['==', ['get', 'rain'], value];
  const base = { source: sourceId, 'source-layer': 'stormwater' } as const;
  return {
    sourceId,
    position: 'top',
    source: {
      type: 'vector',
      // The pmtiles:// prefix is what the registered protocol intercepts.
      // dataUrl() supplies the base path and the cache-busting version.
      url: `pmtiles://${dataUrl('layers/stormwater.pmtiles')}`
    },
    layers: [
      {
        id: `${sourceId}-moderate`,
        type: 'fill',
        ...base,
        filter: rain('moderate'),
        // fill-outline-color transparent: MapLibre's built-in outline is a
        // hairline in the fill's own colour, not the off-white outline below.
        paint: { 'fill-color': STORMWATER.moderate.color, 'fill-opacity': STORMWATER.moderate.opacity, 'fill-outline-color': 'rgba(0, 0, 0, 0)' }
      },
      {
        id: `${sourceId}-moderate-outline`,
        type: 'line',
        ...base,
        filter: rain('moderate'),
        paint: { 'line-color': STORMWATER.outline.color, 'line-width': STORMWATER.outline.width }
      },
      {
        id: `${sourceId}-limited`,
        type: 'fill',
        ...base,
        filter: rain('limited'),
        paint: { 'fill-color': STORMWATER.limited.color, 'fill-opacity': STORMWATER.limited.opacity }
      }
    ]
  };
}

/**
 * The graded layers: one fill coloured by a property, under the roads (surge
 * was the worked example, approved 2026-11-05).
 *
 * Opaque because it sits beneath the basemap's roads and labels, which stay
 * crisp on top of it. At the old 45% translucency, neighbouring classes
 * differed by under 0.04 in lightness, too little to tell five apart; opaque,
 * they keep the ramp's full steps (METHODOLOGY.md). Evacuation zones are the
 * exception, at EVAC_OPACITY.
 *
 * No outline layer: the class colours themselves mark every boundary, and a
 * same-colour line would only thicken them.
 *
 * The cost of opaque: where two graded layers overlap, the upper one hides the
 * lower. Accepted (Andrew, 2026-11-05); the Flooding page opens with one.
 *
 * `tiles` is for FEMA, the one graded layer delivered as PMTiles: at 387 KB
 * of GeoJSON it would have downloaded on every map load, switched on or not.
 */
function graded(
  layerId: 'hurricane_evac_zones' | 'fema_flood_zones' | 'surge_current' | 'tidal_2020s',
  ramp: Ramp,
  { opacity = 1, tiles = false }: { opacity?: number; tiles?: boolean } = {}
): OverlaySpec {
  const sourceId = `overlay-${layerId}`;
  return {
    sourceId,
    position: 'under-roads',
    source: tiles
      ? { type: 'vector', url: `pmtiles://${dataUrl(`layers/${layerId}.pmtiles`)}` }
      : { type: 'geojson', data: dataUrl(`layers/${layerId}.geojson`) },
    layers: [
      {
        id: `${sourceId}-fill`,
        type: 'fill',
        source: sourceId,
        ...(tiles ? { 'source-layer': layerId } : {}),
        paint: {
          'fill-color': rampExpression(ramp),
          'fill-opacity': opacity,
          // Tiles are cut at tile edges; MapLibre's default same-colour
          // hairline would draw those cuts as faint grid lines.
          'fill-outline-color': 'rgba(0, 0, 0, 0)'
        }
      }
    ]
  };
}

/**
 * DRAWING ORDER IS THIS OBJECT'S KEY ORDER, bottom to top (Andrew,
 * 2026-11-05). Map.svelte adds the layers in Object.values() order, and
 * MapLibre draws later layers on top. Every 'under-roads' layer is inserted
 * before the same basemap layer, so they keep this order among themselves.
 *
 *   under the roads   evacuation zones, FEMA, surge, tidal - the broadest
 *                     extent lowest, the smallest (27 tracts) highest
 *   above the roads   stormwater (moderate, its outline, limited)
 *
 * The Layers tab lists them in the reverse of this (registry order, which
 * matches the stacking top first - Andrew, 2026-11-05).
 */
export function overlaySpecs(): Record<string, OverlaySpec> {
  return {
    hurricane_evac_zones: graded('hurricane_evac_zones', EVAC, { opacity: EVAC_OPACITY }),
    fema_flood_zones: graded('fema_flood_zones', FEMA, { tiles: true }),
    surge_current: graded('surge_current', SURGE),
    tidal_2020s: graded('tidal_2020s', TIDAL),
    stormwater: stormwater()
  };
}
