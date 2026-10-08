import type { LayerSpecification, SourceSpecification } from 'maplibre-gl';
import { dataUrl } from '$lib/data';

/**
 * How each toggleable overlay becomes MapLibre sources and layers.
 *
 * Keyed by `layer_id` — the same string that appears in `?layers=`, in a
 * hazard's `map_layers`, and in `data/registry/map_layers.csv`. One vocabulary
 * end to end, so a layer turned on by a shared link is the layer that draws.
 *
 * Only the four with a legend swatch are here, which is the same four
 * `listableLayers()` returns: the available `context` layers with discrete
 * geometry. The three `delivery: inline` choropleths join to cdta.geojson and
 * need a graduated fill and a ramp legend that is not designed; the three
 * `kind: resource` layers are the Resources tab's business.
 *
 * Colours come from the LayerRow swatches (Figma node 14:1142's siblings) so
 * the key in the sheet is the colour on the map. Hardcoded here rather than
 * read from a token, because MapLibre paint properties are evaluated in a
 * canvas and cannot resolve a CSS custom property.
 */

export interface OverlaySpec {
  /** Added to the style under this id, prefixed so nothing collides with the
   *  basemap's own sources. */
  sourceId: string;
  source: SourceSpecification;
  /** Drawn in order. Ids are prefixed the same way. */
  layers: LayerSpecification[];
}

/** The four swatch colours, repeated from $lib/layers for MapLibre's benefit. */
const FILL = {
  stormwater_limited_1_77: '#cedef0',
  stormwater_moderate_2_13: '#3f6bb9',
  hurricane_evac_zones: '#ebaa7d',
  surge_current: '#d8b663'
} as const;

/** Polygons are translucent so overlapping layers stay legible and the
 *  basemap's streets read through — the whole reason for a street basemap. */
const FILL_OPACITY = 0.45;
const LINE_OPACITY = 0.9;

/**
 * The two stormwater layers, told apart by lightness (Andrew, 2026-10-08).
 *
 * Moderate rain is the heavier storm and the wider extent: dark (blue/600) and
 * fairly solid, drawn first. Limited rain, a lighter storm, floods a thin core
 * inside it: pale (blue/200) and nearly opaque, drawn on top. Darker reads as
 * more severe, which is the heavier storm.
 *
 * At the old 45% each, the dark one over the grey basemap and the pale one
 * came out within 1.1:1 of each other: one colour. These settings composite to
 * about 1.9:1 between the core and its surround, at every zoom. A casing on
 * the limited layer was tried and dropped: at district zoom it swallowed the
 * thin shapes into white speckle.
 */
const STORMWATER_OPACITY = {
  stormwater_moderate_2_13: 0.65,
  stormwater_limited_1_77: 0.9
} as const;

function stormwater(layerId: 'stormwater_limited_1_77' | 'stormwater_moderate_2_13'): OverlaySpec {
  return {
    sourceId: `overlay-${layerId}`,
    source: {
      type: 'vector',
      // The pmtiles:// prefix is what the registered protocol intercepts.
      // dataUrl() supplies the base path and the cache-busting version, so the
      // archive resolves the same way every other payload does.
      url: `pmtiles://${dataUrl(`layers/${layerId}.pmtiles`)}`
    },
    layers: [
      {
        id: `overlay-${layerId}-fill`,
        type: 'fill',
        source: `overlay-${layerId}`,
        // DATA_CONTRACT §8: the source-layer name matches the file name.
        'source-layer': layerId,
        // One style for the whole layer (Andrew, 2026-10-08). The source's
        // Flooding_C attribute separates nuisance flooding (1: >= 4in, < 1ft)
        // from deep and contiguous (2: >= 1ft); that was drawn 20% stronger,
        // and is no longer distinguished. The attribute stays in the tiles.
        paint: {
          'fill-color': FILL[layerId],
          'fill-opacity': STORMWATER_OPACITY[layerId],
          // No stroke on moderate (Andrew, 2026-10-08). MapLibre outlines
          // every fill polygon in its own colour by default, drawn over the
          // translucent fill, so at 65% the edges read as a darker stroke, and
          // the seams between the many adjacent polygons in these tiles as
          // lines inside the shapes. Transparent removes both. Limited, pale
          // and at 90%, shows no visible outline and keeps the default.
          ...(layerId === 'stormwater_moderate_2_13' ? { 'fill-outline-color': 'rgba(0, 0, 0, 0)' } : {})
        }
      }
    ]
  };
}

function polygonGeojson(layerId: 'hurricane_evac_zones' | 'surge_current'): OverlaySpec {
  return {
    sourceId: `overlay-${layerId}`,
    source: { type: 'geojson', data: dataUrl(`layers/${layerId}.geojson`) },
    layers: [
      {
        id: `overlay-${layerId}-fill`,
        type: 'fill',
        source: `overlay-${layerId}`,
        paint: { 'fill-color': FILL[layerId], 'fill-opacity': FILL_OPACITY }
      },
      {
        // An outline as well as a fill: at 45% opacity over a grey basemap the
        // boundary of a translucent polygon is hard to place, and both of these
        // are layers where the EDGE is the information — which zone you are in,
        // where the surge stops.
        id: `overlay-${layerId}-line`,
        type: 'line',
        source: `overlay-${layerId}`,
        paint: { 'line-color': FILL[layerId], 'line-width': 1, 'line-opacity': LINE_OPACITY }
      }
    ]
  };
}

/**
 * DRAWING ORDER IS THIS OBJECT'S KEY ORDER, bottom to top (Andrew,
 * 2026-10-08): hurricane evacuation zones, storm surge, stormwater (moderate),
 * stormwater (limited). Map.svelte adds the layers in Object.values() order,
 * and MapLibre draws later layers on top. The broad coastal zones sit
 * underneath; the stormwater extents, smaller and street-scale, sit on top,
 * with the limited-rain extent (the more frequent flooding) uppermost.
 *
 * This is the map's order only. The toolbar lists layers in registry order.
 */
export function overlaySpecs(): Record<string, OverlaySpec> {
  return {
    hurricane_evac_zones: polygonGeojson('hurricane_evac_zones'),
    surge_current: polygonGeojson('surge_current'),
    stormwater_moderate_2_13: stormwater('stormwater_moderate_2_13'),
    stormwater_limited_1_77: stormwater('stormwater_limited_1_77')
  };
}
