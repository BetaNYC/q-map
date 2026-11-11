import { CATEGORY_GROUP_FILL } from './map/palette';
import type { ResourceCategory } from './types';

/**
 * The one- or two-letter mark in a resource row's icon box.
 *
 * Mostly the label's first letter, but NOT derivable in every case, because the
 * scheme exists to keep the twelve marks distinct rather than to be mechanical:
 *
 *   Health care          -> "hc"   two letters, not "h"
 *   Housing and shelter  -> "s"    from "shelter", not "housing"
 *   Cooling options      -> "co"   two letters, not "c"
 *
 * The first two fix one collision (plain first letters gave "h" twice); the
 * third keeps "c" for Children and youth.
 *
 * DERIVE-WITH-OVERRIDES rather than a hardcoded table of twelve. §6 is explicit
 * that the category set is derived per district and has already changed twice,
 * so a table would leave a new category with no mark at all; this way it gets
 * its first letter and `assertInitialsDistinct` fails the build if that letter
 * is already taken.
 */
const INITIAL_OVERRIDE: Record<string, string> = {
  'health-care': 'hc',
  'housing-and-shelter': 's',
  'cooling-options': 'co'
};

export function categoryInitial(category: ResourceCategory): string {
  return INITIAL_OVERRIDE[category.slug] ?? category.label.charAt(0).toLowerCase();
}

/**
 * Build-time guard. Two categories sharing a mark is not an error the browser
 * can report — it just draws the same letter twice and looks deliberate, which
 * is how the "h" collision survived into the design in the first place.
 *
 * Called from the map route's entries(), so a category added or renamed
 * upstream fails the build rather than shipping an ambiguous icon.
 */
export function assertInitialsDistinct(categories: ResourceCategory[], context: string): void {
  const seen = new Map<string, string>();

  for (const category of categories) {
    const mark = categoryInitial(category);

    // The icon face ships a-z only (src/fonts.css): any other character
    // would draw in the fallback font, off-centre and in another style.
    if (!/^[a-z]+$/.test(mark)) {
      throw new Error(
        `${context}: category "${category.slug}" renders the mark "${mark}", outside a-z, ` +
          `the only characters the icon font carries. Add an override in src/lib/categories.ts ` +
          `or widen the subset (src/fonts/README-qmap-icon-mono.txt).`
      );
    }

    const previous = seen.get(mark);

    if (previous && previous !== category.slug) {
      throw new Error(
        `${context}: categories "${previous}" and "${category.slug}" both render the mark "${mark}". ` +
          `Add an override in src/lib/categories.ts.`
      );
    }

    seen.set(mark, category.slug);
  }
}

/**
 * The fill of a category's mark: its colour group's ($lib/map/palette.ts). A
 * category with no known group draws on the plain surface, as every mark did
 * before 2026-11-05, rather than in a colour that would claim a group.
 */
export function categoryFill(category: Pick<ResourceCategory, 'group'> | undefined): string | null {
  return (category && CATEGORY_GROUP_FILL[category.group]) ?? null;
}

/** The colour groups in legend order: Emergency, Cooling, Basic needs, Health and care,
 *  Community and services. */
export const CATEGORY_GROUP_ORDER: readonly string[] = Object.keys(CATEGORY_GROUP_FILL);

export interface CategoryGroup<C extends ResourceCategory = ResourceCategory> {
  group: string;
  label: string;
  fill: string | null;
  categories: C[];
}

/**
 * A district's categories under their colour groups (legend option A,
 * 2026-11-05), groups in legend order and categories in the order given
 * (the payload's, which is by count). Only groups the district holds appear.
 * A category whose group is unknown is not dropped: it lands in a trailing
 * group of its own, drawn plain, so it can still be switched on.
 */
export function groupCategories<C extends ResourceCategory>(categories: readonly C[]): CategoryGroup<C>[] {
  const groups = new Map<string, CategoryGroup<C>>();
  for (const c of categories) {
    const known = c.group in CATEGORY_GROUP_FILL;
    const key = known ? c.group : '';
    if (!groups.has(key)) {
      groups.set(key, { group: key, label: known ? c.group_label : 'Other', fill: known ? CATEGORY_GROUP_FILL[key] : null, categories: [] });
    }
    groups.get(key)!.categories.push(c);
  }
  const rank = (g: string) => (g === '' ? Infinity : CATEGORY_GROUP_ORDER.indexOf(g));
  return [...groups.values()].sort((a, b) => rank(a.group) - rank(b.group));
}
