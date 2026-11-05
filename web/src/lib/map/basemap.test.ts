import { describe, expect, it } from 'vitest';
import { fadeInBasemapLayers } from './basemap';

// A stub with Positron's shapes: a layer that snaps on at a fixed opacity, one
// with no opacity set, one Positron already fades by zoom, one that is on from
// the start, a label, and one starting below the app's lowest zoom.
function stubMap() {
  const layers: Array<{ id: string; type: string; minzoom: number; opacity?: unknown; 'source-layer'?: string }> = [
    { id: 'building', type: 'fill', minzoom: 13, 'source-layer': 'buildings' },
    { id: 'road_minor_case', type: 'line', minzoom: 13, opacity: 1, 'source-layer': 'roads' },
    { id: 'road_minor_fill', type: 'line', minzoom: 15, opacity: 1 },
    { id: 'tunnel_rail', type: 'line', minzoom: 13, opacity: 0.5 },
    { id: 'building-top', type: 'fill', minzoom: 13, opacity: { stops: [[13, 0], [16, 1]] }, 'source-layer': 'buildings' },
    { id: 'road_pri_case_ramp', type: 'line', minzoom: 12, opacity: { stops: [[5, 0.5], [7, 1]] } },
    { id: 'water', type: 'fill', minzoom: 0, opacity: 1 },
    { id: 'roadname_minor', type: 'symbol', minzoom: 15 },
    { id: 'road_trunk_case_noramp', type: 'line', minzoom: 5, opacity: 1 }
  ];
  const paint: Record<string, unknown> = {};
  for (const l of layers) {
    if ('opacity' in l) paint[`${l.id}/${l.type}-opacity`] = l.opacity;
  }
  return {
    paint,
    getStyle: () => ({ layers: layers.map(({ id, type, minzoom, ...rest }) => ({ id, type, minzoom, 'source-layer': rest['source-layer'] })) }),
    getPaintProperty: (id: string, name: string) => paint[`${id}/${name}`],
    setPaintProperty: (id: string, name: string, value: unknown) => {
      paint[`${id}/${name}`] = value;
    }
  };
}

describe('fadeInBasemapLayers', () => {
  it('ramps opacity from 0 at the start zoom to its normal value one zoom later', () => {
    const map = stubMap();
    const faded = fadeInBasemapLayers(map, 8.75);
    expect(faded.sort()).toEqual(['building', 'building-top', 'road_minor_case', 'road_minor_fill', 'tunnel_rail']);
    // Streets arrive with their layer, so the fade starts at its minzoom.
    expect(map.paint['road_minor_case/line-opacity']).toEqual(['interpolate', ['linear'], ['zoom'], 13, 0, 14, 1]);
    expect(map.paint['road_minor_fill/line-opacity']).toEqual(['interpolate', ['linear'], ['zoom'], 15, 0, 16, 1]);
    // A layer drawn at half strength fades to half, not to full.
    expect(map.paint['tunnel_rail/line-opacity']).toEqual(['interpolate', ['linear'], ['zoom'], 13, 0, 14, 0.5]);
  });

  it('fades buildings in where the tiles deliver them, not where the layer starts', () => {
    const map = stubMap();
    fadeInBasemapLayers(map, 8.75);
    // Buildings: almost all arrive in z15 tiles. Both building layers, Positron's
    // own 13-16 fade on the tops included.
    expect(map.paint['building/fill-opacity']).toEqual(['interpolate', ['linear'], ['zoom'], 15, 0, 16, 1]);
    expect(map.paint['building-top/fill-opacity']).toEqual(['interpolate', ['linear'], ['zoom'], 15, 0, 16, 1]);
  });

  it("leaves Positron's own zoom styling, labels, and layers already on at the lowest zoom", () => {
    const map = stubMap();
    fadeInBasemapLayers(map, 8.75);
    expect(map.paint['road_pri_case_ramp/line-opacity']).toEqual({ stops: [[5, 0.5], [7, 1]] });
    expect(map.paint['water/fill-opacity']).toBe(1);
    expect(map.paint['road_trunk_case_noramp/line-opacity']).toBe(1);
    expect(map.paint['roadname_minor/symbol-opacity']).toBeUndefined();
  });
});
