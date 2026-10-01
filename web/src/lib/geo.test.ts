import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { featureAt, placePoint, type CdtaFeature } from './geo';
import type { DistrictIndexEntry } from './types';

// The real files - the same ones the app fetches.
const data = (f: string) => JSON.parse(readFileSync(new URL(`../../static/data/${f}`, import.meta.url), 'utf8'));
const features: CdtaFeature[] = data('cdta.geojson').features;
const districts: DistrictIndexEntry[] = data('districts.json');
const where = (lon: number, lat: number) => {
  const p = placePoint([lon, lat], features, districts);
  return p.kind === 'none' ? 'none' : `${p.kind}:${p.district.cdta2020}`;
};

describe('placePoint on the real boundaries', () => {
  it("every district's own point_on_surface lands in that district - all 59", () => {
    const misses = districts.filter((d) => featureAt(d.point_on_surface, features)?.properties.cdta2020 !== d.cdta2020);
    expect(misses.map((d) => d.cdta2020)).toEqual([]);
  });

  it.each([
    // 46-01 5th St, Long Island City - the coordinates NYC GeoSearch returned.
    ['46-01 5th St, Long Island City', -73.954843, 40.747074, 'queens:QN02'],
    ['Beach 116th St, Rockaway Park', -73.836, 40.5794, 'queens:QN14'],
    ['Main St, Flushing', -73.8303, 40.7593, 'queens:QN07'],
    ['Brooklyn Borough Hall', -73.9903, 40.6928, 'elsewhere:BK02'],
    ['JFK airport - a Joint Interest Area, in no district', -73.7781, 40.6413, 'none'],
    ['Jersey City - outside NYC', -74.0776, 40.7282, 'none'],
  ])('%s', (_label, lon, lat, expected) => {
    expect(where(lon, lat)).toBe(expected);
  });
});

describe('featureAt geometry', () => {
  // A 10x10 square with a 2x2 hole in the middle.
  const square: CdtaFeature = {
    type: 'Feature',
    properties: { cdta2020: 'XX01', slug: 'x01' },
    geometry: {
      type: 'Polygon',
      coordinates: [
        [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
        [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
      ],
    },
  };

  it('is inside the outer ring but not inside a hole', () => {
    expect(featureAt([2, 2], [square])).toBe(square);
    expect(featureAt([5, 5], [square])).toBeNull();
    expect(featureAt([11, 5], [square])).toBeNull();
  });

  it('finds a point in any part of a MultiPolygon', () => {
    const multi: CdtaFeature = {
      type: 'Feature',
      properties: { cdta2020: 'XX02', slug: 'x02' },
      geometry: { type: 'MultiPolygon', coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]], [[[20, 20], [30, 20], [30, 30], [20, 30], [20, 20]]]] },
    };
    expect(featureAt([25, 25], [multi])).toBe(multi);
  });
});
