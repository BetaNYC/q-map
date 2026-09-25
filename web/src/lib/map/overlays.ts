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
  stormwater_limited_1_77: '#9bbde9',
  stormwater_moderate_2_13: '#3f6bb9',
  hurricane_evac_zones: '#ebaa7d',
  surge_current: '#d8b663'
} as const;

/** Polygons are translucent so overlapping layers stay legible and the
 *  basemap's streets read through — the whole reason for a street basemap. */
const FILL_OPACITY = 0.45;
const LINE_OPACITY = 0.9;

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
        paint: {
          'fill-color': FILL[layerId],
          // Flooding_C is the styling attribute and takes two values: 1 is
          // nuisance flooding (>= 4in, < 1ft), 2 is deep and contiguous
          // (>= 1ft). Deep water reads more strongly.
          'fill-opacity': [
            'case',
            ['==', ['get', 'Flooding_C'], 2],
            FILL_OPACITY + 0.2,
            FILL_OPACITY
          ]
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

export function overlaySpecs(): Record<string, OverlaySpec> {
  return {
    stormwater_limited_1_77: stormwater('stormwater_limited_1_77'),
    stormwater_moderate_2_13: stormwater('stormwater_moderate_2_13'),
    hurricane_evac_zones: polygonGeojson('hurricane_evac_zones'),
    surge_current: polygonGeojson('surge_current')
  };
}
