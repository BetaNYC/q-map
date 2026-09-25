import type { ResourceCategory } from './types';

/**
 * The one- or two-letter mark in a resource row's icon box.
 *
 * Mostly the label's first letter, but NOT derivable in every case, because the
 * scheme exists to keep the twelve marks distinct rather than to be mechanical:
 *
 *   Health care          -> "hc"   two letters, not "h"
 *   Housing and shelter  -> "s"    from "shelter", not "housing"
 *
 * Both are the fix for the same collision — plain first letters gave "h" twice.
 *
 * DERIVE-WITH-OVERRIDES rather than a hardcoded table of twelve. §6 is explicit
 * that the category set is derived per district and has already changed twice,
 * so a table would leave a new category with no mark at all; this way it gets
 * its first letter and `assertInitialsDistinct` fails the build if that letter
 * is already taken.
 */
const INITIAL_OVERRIDE: Record<string, string> = {
  'health-care': 'hc',
  'housing-and-shelter': 's'
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
