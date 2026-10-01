import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { fetchSuggestions, isBareZip, parseSuggestions } from './geosearch';

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8'));

describe('parseSuggestions on real GeoSearch responses', () => {
  it('tidies the label and keeps the coordinates', () => {
    expect(parseSuggestions(fixture('geosearch-46-01-5th-st.json'))).toEqual([
      { id: '-73.95484,40.74707', label: '46-01 5 Street, Long Island City', borough: 'Queens', point: [-73.954843, 40.747074] },
    ]);
  });

  it('merges two spellings of one building, keeping the fuller one, and puts Queens first', () => {
    const s = parseSuggestions(fixture('geosearch-1-broadway.json'));
    expect(s.map((x) => `${x.label} | ${x.borough}`)).toEqual([
      '1 Broadway, Howard Beach | Queens',
      '33-01 Broadway, Astoria | Queens',
      "34-01 B'way, Astoria | Queens",
      '37-01 Broadway, Astoria | Queens',
      '38-01 Broadway, Astoria | Queens',
      '1 Broadway, New York | Manhattan',
    ]);
    expect(new Set(s.map((x) => x.id)).size).toBe(s.length);
  });

  it('survives an empty or malformed response', () => {
    expect(parseSuggestions({})).toEqual([]);
    expect(parseSuggestions({ features: [{ geometry: { coordinates: [NaN, 1] }, properties: { label: 'X' } }] })).toEqual([]);
  });
});

describe('isBareZip', () => {
  it.each([['11691', true], [' 11691 ', true], ['11691-1234', true], ['116-10 Beach Channel Dr', false], ['46-01 5th St', false], ['1169', false]])(
    '%s -> %s',
    (text, expected) => expect(isBareZip(text)).toBe(expected)
  );
});

describe('fetchSuggestions', () => {
  it('encodes the query and throws on an HTTP error', async () => {
    let asked = '';
    const ok = (async (url: string) => { asked = url; return new Response(JSON.stringify(fixture('geosearch-46-01-5th-st.json'))); }) as unknown as typeof fetch;
    await fetchSuggestions(' 46-01 5th St ', { fetchFn: ok });
    expect(asked).toBe('https://geosearch.planninglabs.nyc/v2/autocomplete?text=46-01%205th%20St');
    const bad = (async () => new Response('', { status: 502 })) as unknown as typeof fetch;
    await expect(fetchSuggestions('x', { fetchFn: bad })).rejects.toThrow('GeoSearch 502');
  });
});
