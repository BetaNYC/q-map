import { describe, expect, it } from 'vitest';
import { defaultCategories } from './mapView';
import type { ResourceCategory } from './types';

// Synthetic, not the real payloads: web.yml tests a PR against the committed
// data/processed, which gains `default_on` only when the pipeline runs after
// merge. That every real district has at least one default-on category is the
// pipeline's assertion (category_registry_checks), not this file's.
const cat = (slug: string, default_on: boolean): ResourceCategory => ({
  slug,
  label: slug,
  count: 1,
  default_on
});
const district = [
  cat('emergency-services', true),
  cat('health-care', false),
  cat('food-assistance', true),
  cat('older-adults', false)
];

describe('defaultCategories', () => {
  it('returns the default-on categories, in the district’s order', () => {
    expect(defaultCategories(district)).toEqual(['emergency-services', 'food-assistance']);
  });

  it('adds a resource page’s own category, in the district’s order', () => {
    expect(defaultCategories(district, ['health-care'])).toEqual([
      'emergency-services',
      'health-care',
      'food-assistance'
    ]);
  });

  it('ignores an extra slug the district does not hold', () => {
    expect(defaultCategories(district, ['not-a-category'])).toEqual(defaultCategories(district));
  });

  it('does not repeat a category that is already on', () => {
    expect(defaultCategories(district, ['food-assistance'])).toEqual(defaultCategories(district));
  });

  it('is empty when nothing is on, rather than falling back to all', () => {
    expect(defaultCategories([cat('health-care', false)])).toEqual([]);
  });
});
