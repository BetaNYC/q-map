import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { displayName, groupResources, listSubtitle, listSummary, resourceCount } from './resourceList';
import type { Resource, ResourceCategory } from './types';

// Real payloads, from the files the map reads. Assertions are about rules, not
// counts, so they hold when CI refreshes the data.
const load = <T>(path: string): T =>
  JSON.parse(readFileSync(new URL(`../../static/data/${path}`, import.meta.url), 'utf8'));
const resources = load<{ resources: Resource[] }>('resources/q14.json').resources;
const categories = load<{ resource_categories: ResourceCategory[] }>('districts/q14.json').resource_categories;

describe('groupResources on q14', () => {
  it('null lists every record once, grouped in the district order', () => {
    const groups = groupResources(resources, categories, null);
    expect(groups.flatMap((g) => g.rows)).toHaveLength(resources.length);
    expect(groups.map((g) => g.category.slug)).toEqual(
      categories.map((c) => c.slug).filter((s) => resources.some((r) => r.category === s))
    );
    for (const g of groups) expect(g.rows.every((r) => r.category === g.category.slug)).toBe(true);
  });

  it('a group count matches the toolbar count for its category', () => {
    for (const g of groupResources(resources, categories, null)) expect(g.rows).toHaveLength(g.category.count);
  });

  it('lists only the categories switched on, and none for []', () => {
    const two = categories.slice(0, 2).map((c) => c.slug);
    expect(groupResources(resources, categories, two).map((g) => g.category.slug)).toEqual(two);
    expect(groupResources(resources, categories, [])).toEqual([]);
    expect(groupResources(resources, categories, ['not-a-category'])).toEqual([]);
  });

  it('sorts rows A-Z by the name as it renders', () => {
    const collator = new Intl.Collator('en', { sensitivity: 'base', numeric: true });
    for (const g of groupResources(resources, categories, null)) {
      const names = g.rows.map((r) => displayName(r.name));
      expect(names).toEqual([...names].sort(collator.compare));
    }
  });

  it('gives each group its category mark', () => {
    const hc = groupResources(resources, categories, ['health-care'])[0];
    expect(hc?.mark).toBe('hc');
  });
});

describe('row text', () => {
  it('collapses the line breaks some FRANC names carry', () => {
    expect(displayName('Battalion Pentecostal Food\nDistribution Center ')).toBe('Battalion Pentecostal Food Distribution Center');
  });

  it('shows an operator only where it adds to the name', () => {
    const base = resources[0];
    expect(listSubtitle({ ...base, name: 'Engine 268/LADDER 137', operator: 'NYC Fire Department' })).toBe('NYC Fire Department');
    expect(listSubtitle({ ...base, name: 'Queens Library at Far Rockaway', operator: 'Queens Library' })).toBeNull();
    expect(listSubtitle({ ...base, operator: undefined })).toBeNull();
  });

  it('never repeats the category: no FRANC or QNPD row has a second line', () => {
    const scraped = resources.filter((r) => r.source !== 'facdb');
    expect(scraped.length).toBeGreaterThan(0);
    expect(scraped.every((r) => listSubtitle(r) === null)).toBe(true);
  });

  it('counts in words', () => {
    expect(resourceCount(1)).toBe('1 resource');
    expect(resourceCount(37)).toBe('37 resources');
    const g = groupResources(resources, categories, null);
    expect(listSummary(g)).toBe(`${resources.length} resources in ${g.length} categories`);
    expect(listSummary(g.slice(0, 1).map((x) => ({ ...x, rows: x.rows.slice(0, 1) })))).toBe('1 resource in 1 category');
  });
});
