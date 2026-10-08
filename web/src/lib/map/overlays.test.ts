import { describe, expect, it } from 'vitest';
import { overlaySpecs } from './overlays';

describe('overlaySpecs', () => {
  it('lists layers in drawing order, bottom to top', () => {
    // Map.svelte adds layers in this order and MapLibre draws later ones on top.
    expect(Object.keys(overlaySpecs())).toEqual([
      'hurricane_evac_zones',
      'surge_current',
      'stormwater_moderate_2_13',
      'stormwater_limited_1_77'
    ]);
  });

  it('styles each stormwater layer with one paint, not by Flooding_C', () => {
    for (const id of ['stormwater_moderate_2_13', 'stormwater_limited_1_77']) {
      const [fill] = overlaySpecs()[id].layers;
      expect(JSON.stringify(fill)).not.toContain('Flooding_C');
    }
  });

  it('draws limited rain pale and nearly solid over a darker moderate', () => {
    const paint = (id: string) => (overlaySpecs()[id].layers[0] as { paint: Record<string, unknown> }).paint;
    expect(paint('stormwater_moderate_2_13')).toEqual({
      'fill-color': '#3f6bb9',
      'fill-opacity': 0.65,
      'fill-outline-color': 'rgba(0, 0, 0, 0)'
    });
    expect(paint('stormwater_limited_1_77')).toEqual({ 'fill-color': '#cedef0', 'fill-opacity': 0.9 });
  });
});
