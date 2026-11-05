import { describe, expect, it } from 'vitest';
import { overlaySpecs } from './overlays';
import { EVAC, FEMA, LAYER_SWATCH, SURGE, TIDAL, darkest } from './palette';
import { swatchFor, type MapLayer } from '$lib/layers';

type Paint = Record<string, unknown>;
const layersOf = (id: string) => overlaySpecs()[id].layers as Array<{ id: string; type: string; paint: Paint; 'source-layer'?: string }>;

describe('overlaySpecs', () => {
  it('lists layers in drawing order, bottom to top', () => {
    // Map.svelte adds layers in this order and MapLibre draws later ones on top.
    expect(Object.keys(overlaySpecs())).toEqual([
      'hurricane_evac_zones',
      'fema_flood_zones',
      'surge_current',
      'tidal_2020s',
      'stormwater_moderate_2_13',
      'stormwater_limited_1_77'
    ]);
  });

  it('puts the graded layers under the roads and stormwater above them', () => {
    const position = (id: string) => overlaySpecs()[id].position;
    for (const id of ['hurricane_evac_zones', 'fema_flood_zones', 'surge_current', 'tidal_2020s']) {
      expect(position(id)).toBe('under-roads');
    }
    for (const id of ['stormwater_moderate_2_13', 'stormwater_limited_1_77']) {
      expect(position(id)).toBe('top');
    }
  });
});

describe('stormwater', () => {
  it('styles each layer with one paint, not by Flooding_C', () => {
    for (const id of ['stormwater_moderate_2_13', 'stormwater_limited_1_77']) {
      expect(JSON.stringify(layersOf(id))).not.toContain('Flooding_C');
    }
  });

  it('draws limited rain pale and nearly solid over a darker moderate', () => {
    expect(layersOf('stormwater_moderate_2_13')[0].paint).toEqual({
      'fill-color': '#3f6bb9',
      'fill-opacity': 0.65,
      'fill-outline-color': 'rgba(0, 0, 0, 0)'
    });
    expect(layersOf('stormwater_limited_1_77')[0].paint).toEqual({ 'fill-color': '#cedef0', 'fill-opacity': 0.9 });
  });

  it('outlines moderate in off-white, between its fill and the limited core', () => {
    const [fill, outline] = layersOf('stormwater_moderate_2_13');
    expect(fill.type).toBe('fill');
    expect(outline).toMatchObject({
      type: 'line',
      'source-layer': 'stormwater_moderate_2_13',
      paint: { 'line-color': '#fefcfa', 'line-width': 1 }
    });
    // Limited has no outline: a casing there swallowed the thin shapes (2026-10-08).
    expect(layersOf('stormwater_limited_1_77')).toHaveLength(1);
  });
});

describe('graded layers', () => {
  const cases = [
    ['surge_current', SURGE, 'ss_cur', [1, '#dda8c5', 2, '#c77aa6', 3, '#b55e91', 4, '#a1497f', 5, '#8c386c']],
    ['tidal_2020s', TIDAL, 'tid_20s', [1, '#80c9c9', 2, '#16acac', 3, '#0c9293', 4, '#077d7d', 5, '#00696a']],
    ['fema_flood_zones', FEMA, 'zone', ['0.2PCT', '#c1b0e3', 'AE', '#8c6cc1', 'VE', '#684798']],
    ['hurricane_evac_zones', EVAC, 'zone', [6, '#d7dce4', 5, '#b6bbc2', 4, '#91979f', 3, '#7a818a', 2, '#686e76', 1, '#575c62']]
  ] as const;

  it.each(cases)('%s colours each class exactly, and nothing else', (id, _ramp, property, pairs) => {
    const [fill] = layersOf(id);
    expect(fill.paint['fill-color']).toEqual(['match', ['get', property], ...pairs, 'rgba(0, 0, 0, 0)']);
  });

  it.each(cases)("%s is one fill, keyed in the Layers tab by its darkest class", (id, ramp) => {
    expect(layersOf(id)).toHaveLength(1);
    expect(swatchFor({ layer_id: id } as MapLayer)).toBe(darkest(ramp));
  });

  it('is opaque, except evacuation zones at 55%', () => {
    for (const id of ['fema_flood_zones', 'surge_current', 'tidal_2020s']) {
      expect(layersOf(id)[0].paint['fill-opacity']).toBe(1);
    }
    expect(layersOf('hurricane_evac_zones')[0].paint['fill-opacity']).toBe(0.55);
  });

  it('reads FEMA from its PMTiles, by source-layer', () => {
    const spec = overlaySpecs().fema_flood_zones;
    expect(spec.source.type).toBe('vector');
    expect((spec.source as { url: string }).url).toMatch(/^pmtiles:\/\/.*fema_flood_zones\.pmtiles/);
    expect(layersOf('fema_flood_zones')[0]['source-layer']).toBe('fema_flood_zones');
  });
});

describe('the Layers tab key', () => {
  it('has a swatch for exactly the layers the map can draw', () => {
    expect(Object.keys(LAYER_SWATCH).sort()).toEqual(Object.keys(overlaySpecs()).sort());
  });
});
