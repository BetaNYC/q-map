import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { groupsFor, listingNote, mapsHref, phoneHref, platformOf } from './resourceDetail';
import type { Resource } from './types';

// Real records, from the same files the pages are built from.
const record = (district: string, id: string): Resource => {
  const { resources } = JSON.parse(readFileSync(new URL(`../../static/data/resources/${district}.json`, import.meta.url), 'utf8'));
  const r = resources.find((x: Resource) => x.resource_id === id);
  if (!r) throw new Error(`${id} not in ${district}`);
  return r;
};
const fields = (r: Resource) => Object.fromEntries(groupsFor(r).flatMap((g) => g.fields.map((f) => [f.label, f.lines])));

describe('groupsFor on real records', () => {
  it('a full QNPD record: three groups, in the frame order', () => {
    const groups = groupsFor(record('q01', 'qnpd:ansob-center-for-refugees--1'));
    expect(groups.map((g) => [g.title, g.fields.map((f) => f.label)])).toEqual([
      ['About', ['Mission']],
      ['Contact', ['Address', 'Phone', 'Contact', 'Email', 'Website']],
      ['Access', ['Languages served', 'Fees', 'Accepts referrals']],
    ]);
  });

  it('splits the one two-address email field into two mailto links', () => {
    expect(fields(record('q01', 'qnpd:ansob-center-for-refugees--1')).Email).toEqual([
      { text: 'Imanansob@gmail.com', href: 'mailto:Imanansob@gmail.com' },
      { text: 'Info@Ansob.org', href: 'mailto:Info@Ansob.org' },
    ]);
  });

  it('links a phone extension with a dialling pause', () => {
    expect(fields(record('q01', 'qnpd:jacob-a-riis-neighborhood-settlement--1')).Phone[0].href).toBe('tel:+17187847447,135');
  });

  it('splits two phone numbers into two links', () => {
    expect(fields(record('q08', 'qnpd:samaritan-daytop-village--1')).Phone.map((l: { href?: string }) => l.href)).toEqual([
      'tel:+18553224357',
      'tel:+17186576195',
    ]);
  });

  it('omits a website field that holds a street address', () => {
    expect(fields(record('q13', 'qnpd:service-now-for-adult-persons-inc')).Website).toBeUndefined();
  });

  it('shows referrals whatever the value - "No" and "Yes" alike', () => {
    expect(fields(record('q07', 'qnpd:queens-botanical-garden'))['Accepts referrals']).toEqual([{ text: 'No' }]);
    expect(fields(record('q01', 'qnpd:ansob-center-for-refugees--1'))['Accepts referrals']).toEqual([{ text: 'Yes' }]);
  });

  it('a FRANC record with only a mission: About alone', () => {
    expect(groupsFor(record('q14', 'franc:acqc')).map((g) => g.title)).toEqual(['About']);
  });

  it('a FRANC record with nothing: no groups', () => {
    expect(groupsFor(record('q14', 'franc:101st-precinct'))).toEqual([]);
  });
});

describe('listingNote', () => {
  it('asks people to call only when there is a number', () => {
    expect(listingNote(record('q01', 'qnpd:ansob-center-for-refugees--1'))).toBe('From the Queens Nonprofit Directory. Call to confirm details.');
    expect(listingNote(record('q14', 'franc:acqc'))).toBe('From the FRANC resource map.');
  });
});

describe('phoneHref', () => {
  it.each([
    ['718.278.4303', 'tel:+17182784303'],
    ['718.225.6750 x345', 'tel:+17182256750,345'],
    ['718.978.5777 x 303', 'tel:+17189785777,303'],
    ['1-800-555-0100', 'tel:+18005550100'],
    ['555-0100', null],
  ])('%s -> %s', (v, href) => expect(phoneHref(v)).toBe(href));
});

describe('maps links', () => {
  it('per platform, by coordinates', () => {
    expect(mapsHref('android', 40.7, -73.9, 'A & B')).toBe('geo:40.7,-73.9?q=40.7,-73.9(A%20%26%20B)');
    expect(mapsHref('ios', 40.7, -73.9, 'A & B')).toBe('https://maps.apple.com/?q=A%20%26%20B&ll=40.7,-73.9');
    expect(mapsHref('other', 40.7, -73.9, 'A')).toBe('https://www.google.com/maps/search/?api=1&query=40.7%2C-73.9');
  });

  it.each([
    [{ userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8)', platform: 'Linux armv8l', maxTouchPoints: 5 }, 'android'],
    [{ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)', platform: 'iPhone', maxTouchPoints: 5 }, 'ios'],
    [{ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', platform: 'MacIntel', maxTouchPoints: 5 }, 'ios'], // iPadOS
    [{ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', platform: 'MacIntel', maxTouchPoints: 0 }, 'other'],
  ])('%j -> %s', (nav, expected) => expect(platformOf(nav)).toBe(expected));
});
