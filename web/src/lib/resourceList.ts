import { categoryInitial } from './categories';
import { isSameOrganisation } from './resources';
import type { Resource, ResourceCategory } from './types';

/**
 * The map's resource list: which rows show, in what order, and what each says.
 * Figma: ResourceListItem 265:162, ResourceListGroupHeader 265:163.
 *
 * Shared by the desktop pane over the docked map and the phone sheet's List
 * tab, so the two always list the same thing the map is showing.
 */

export interface ListGroup {
  category: ResourceCategory;
  /** The category's mark, the same letter as its points on the map. */
  mark: string;
  rows: Resource[];
}

/**
 * Group `resources` by category, one group per category switched on.
 *
 * Groups follow the district's `resource_categories` order (largest first),
 * which is the toolbar's and the Categories tab's order too. Rows are A-Z by
 * name, ignoring case: a list you scan for a name, unlike the map.
 *
 * `visible` is `?categories=` already parsed: null is every category, [] none.
 * A category with no records is dropped rather than shown with an empty group.
 */
export function groupResources(
  resources: readonly Resource[],
  categories: readonly ResourceCategory[],
  visible: readonly string[] | null
): ListGroup[] {
  const on = visible === null ? null : new Set(visible);
  const byCategory = new Map<string, Resource[]>();
  for (const r of resources) {
    if (on && !on.has(r.category)) continue;
    const rows = byCategory.get(r.category);
    if (rows) rows.push(r);
    else byCategory.set(r.category, [r]);
  }

  const collator = new Intl.Collator('en', { sensitivity: 'base', numeric: true });
  return categories.flatMap((category) => {
    const rows = byCategory.get(category.slug);
    if (!rows) return [];
    rows.sort((a, b) => collator.compare(displayName(a.name), displayName(b.name)));
    return [{ category, mark: categoryInitial(category), rows }];
  });
}

/**
 * A name as it renders. 23 of 79 FRANC names carry line breaks or stray spaces
 * ("Far Rockaway - LIRR\n"); HTML collapses them, so sorting must too or
 * "Battalion Pentecostal Food\nDistribution" sorts apart from its neighbours.
 */
export function displayName(name: string): string {
  return name.replace(/\s+/g, ' ').trim();
}

/**
 * A row's second line: the operator where it says something the name does not.
 *
 * NOT subtitleFor(). The popup falls back to the category label so its second
 * line is never empty; in the list the row sits under its category's heading,
 * so that fallback would only repeat it. Every FRANC and QNPD row has no
 * operator and shows no second line.
 */
export function listSubtitle(resource: Resource): string | null {
  const { operator, name } = resource;
  return operator && !isSameOrganisation(operator, name) ? operator : null;
}

/** "37 resources", "1 resource". */
export function resourceCount(n: number): string {
  return `${n} ${n === 1 ? 'resource' : 'resources'}`;
}

/** The phone sheet's summary line: "97 resources in 10 categories". */
export function listSummary(groups: readonly ListGroup[]): string {
  const n = groups.reduce((sum, g) => sum + g.rows.length, 0);
  const c = groups.length;
  return `${resourceCount(n)} in ${c} ${c === 1 ? 'category' : 'categories'}`;
}
