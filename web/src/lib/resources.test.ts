import { describe, expect, it } from 'vitest';
import { mapReturnPath, mapStateQuery, sourceLabel } from './resources';
import { parseSelection } from './mapState';
import type { Resource } from './types';

const acqc = { resource_id: 'franc:acqc', category: 'health-care' } as Resource;
const back = (path: string) => new URL(path, 'https://x.test').searchParams;

describe('the map state a popup link carries', () => {
  it('writes the effective selection out in full, empty included', () => {
    const q = mapStateQuery({ categories: ['health-care', 'food-assistance'], layers: [], hazard: null });
    const p = new URLSearchParams(q);
    expect(parseSelection(p.get('categories'))).toEqual(['health-care', 'food-assistance']);
    // Present but empty means none - not the page's default.
    expect(parseSelection(p.get('layers'))).toEqual([]);
    expect(p.has('hazard')).toBe(false);
  });

  it('keeps the hazard the map was titled by', () => {
    expect(new URLSearchParams(mapStateQuery({ categories: [], layers: ['surge_current'], hazard: 'coastal-storm' })).get('hazard')).toBe(
      'coastal-storm'
    );
  });
});

describe('mapReturnPath', () => {
  it('without carried state, derives from the record as before', () => {
    expect(mapReturnPath(acqc, 'q14')).toBe('/q14/map?categories=health-care&resource=franc%3Aacqc');
    expect(mapReturnPath(acqc, 'q14', new URLSearchParams())).toBe('/q14/map?categories=health-care&resource=franc%3Aacqc');
  });

  it('with carried state, returns it and adds the resource', () => {
    const carried = new URLSearchParams(mapStateQuery({ categories: ['emergency-services', 'health-care'], layers: ['surge_current'], hazard: 'coastal-storm' }));
    const p = back(mapReturnPath(acqc, 'q14', carried));
    expect(p.get('categories')).toBe('emergency-services,health-care');
    expect(p.get('layers')).toBe('surge_current');
    expect(p.get('hazard')).toBe('coastal-storm');
    expect(p.get('resource')).toBe('franc:acqc');
  });

  it('ignores anything else in the query string', () => {
    const p = back(mapReturnPath(acqc, 'q14', new URLSearchParams('layers=&utm_source=x')));
    expect([...p.keys()]).toEqual(['layers', 'resource']);
  });
});

describe('sourceLabel', () => {
  it.each([
    ['facdb', 'DCP Facilities Database'],
    ['qnpd', 'Queens Nonprofit Directory'],
    ['franc', 'FRANC Resource Map'],
    ['manual', null],
    ['something-new', null]
  ])('%s -> %s', (source, label) => expect(sourceLabel({ source })).toBe(label));
});
