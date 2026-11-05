import { describe, expect, it } from 'vitest';
import { groupCategories } from './categories';
import { overlaySpecs } from './map/overlays';
import { RAMP_KEYS } from './map/palette';
import type { ResourceCategory } from './types';

const cat = (slug: string, group: string, group_label = group): ResourceCategory => ({
  slug, label: slug, count: 1, default_on: false, group, group_label
});

describe('groupCategories', () => {
  it('puts groups in legend order and keeps category order within a group', () => {
    const groups = groupCategories([
      cat('libraries', 'community-and-services', 'Community and services'),
      cat('food', 'basic-needs', 'Basic needs'),
      cat('emergency', 'emergency', 'Emergency'),
      cat('housing', 'basic-needs', 'Basic needs')
    ]);
    expect(groups.map((g) => g.group)).toEqual(['emergency', 'basic-needs', 'community-and-services']);
    expect(groups[1].categories.map((c) => c.slug)).toEqual(['food', 'housing']);
    expect(groups[1]).toMatchObject({ label: 'Basic needs', fill: '#99dd58' });
  });

  it('keeps a category with an unknown group, last and uncoloured', () => {
    const groups = groupCategories([cat('mystery', 'not-a-group'), cat('emergency', 'emergency')]);
    expect(groups.map((g) => [g.group, g.label, g.fill])).toEqual([
      ['emergency', 'emergency', '#f08703'],
      ['', 'Other', null]
    ]);
  });
});

describe('RAMP_KEYS', () => {
  it('keys every overlay, stormwater included since it became one layer', () => {
    expect(Object.keys(RAMP_KEYS).sort()).toEqual(Object.keys(overlaySpecs()).sort());
  });

  it('keys stormwater by scenario, each at its map opacity', () => {
    const k = RAMP_KEYS.stormwater;
    expect(k.ramp.classes.map((c) => [c.value, c.color, c.opacity])).toEqual([
      ['limited', '#cedef0', 0.9],
      ['moderate', '#3f6bb9', 0.65]
    ]);
    expect(k.labels).toEqual({ perClass: ['Limited rain', 'Moderate rain'] });
  });

  it('gives a per-class key one label per class', () => {
    for (const key of Object.values(RAMP_KEYS)) {
      if ('perClass' in key.labels) expect(key.labels.perClass).toHaveLength(key.ramp.classes.length);
    }
  });

  it('draws the evacuation key at the map’s 55%', () => {
    expect(RAMP_KEYS.hurricane_evac_zones.opacity).toBe(0.55);
    expect(RAMP_KEYS.surge_current.opacity).toBe(1);
  });
});
