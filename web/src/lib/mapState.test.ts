import { describe, expect, it } from 'vitest';
import { parseSelection, toggleSelection, withSelection } from './mapState';

const KNOWN = ['a', 'b', 'c', 'd'];

describe('parseSelection', () => {
  it('returns null for an absent parameter, so the page default applies', () => {
    expect(parseSelection(null, KNOWN)).toBeNull();
  });

  it('reads a present but empty parameter as an explicit empty selection', () => {
    expect(parseSelection('', KNOWN)).toEqual([]);
  });

  it('drops unknown ids rather than failing', () => {
    expect(parseSelection('a,retired,c', KNOWN)).toEqual(['a', 'c']);
  });

  it('returns the order of known, whatever the order given', () => {
    expect(parseSelection('d,a', KNOWN)).toEqual(['a', 'd']);
  });

  it('keeps every non-empty id when there is no known list', () => {
    expect(parseSelection('x,,y', undefined)).toEqual(['x', 'y']);
  });
});

describe('toggleSelection', () => {
  it('adds an id in known order', () => {
    expect(toggleSelection(['c'], 'a', KNOWN)).toEqual(['a', 'c']);
  });

  it('removes an id', () => {
    expect(toggleSelection(['a', 'c'], 'a', KNOWN)).toEqual(['c']);
  });
});

describe('withSelection', () => {
  const url = new URL('https://example.org/q-map/q14/map?resource=x');

  it('writes a selection that differs from the default', () => {
    const out = withSelection(url, 'layers', ['b'], [], KNOWN);
    expect(out.searchParams.get('layers')).toBe('b');
    expect(out.searchParams.get('resource')).toBe('x');
  });

  it('removes the parameter when the selection is the default', () => {
    const on = new URL('https://example.org/q-map/q14/map?layers=b');
    expect(withSelection(on, 'layers', [], [], KNOWN).searchParams.has('layers')).toBe(false);
  });

  it('treats a null default as every known id (the categories default)', () => {
    expect(withSelection(url, 'categories', KNOWN, null, KNOWN).searchParams.has('categories')).toBe(
      false
    );
    expect(withSelection(url, 'categories', ['a'], null, KNOWN).searchParams.get('categories')).toBe('a');
  });

  it('writes an explicit empty selection when the default is not empty', () => {
    // A hazard page whose default layers are on, with both switched off.
    const out = withSelection(url, 'layers', [], ['a', 'b'], KNOWN);
    expect(out.searchParams.get('layers')).toBe('');
  });

  it('ignores default ids the toggles do not know', () => {
    // A hazard default can name a layer with no toggle (pivi_choropleth).
    expect(withSelection(url, 'layers', ['a'], ['a', 'unlisted'], KNOWN).searchParams.has('layers')).toBe(
      false
    );
  });

  it('does not change the URL it was given', () => {
    withSelection(url, 'layers', ['b'], [], KNOWN);
    expect(url.searchParams.has('layers')).toBe(false);
  });
});
