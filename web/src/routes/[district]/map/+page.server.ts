import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertInitialsDistinct } from '$lib/categories';
import type { DistrictIndexEntry, DistrictPayload } from '$lib/types';
import type { EntryGenerator } from './$types';

/**
 * The 14 map routes.
 *
 * Note what is NOT here: the query parameters. `?categories=`, `?layers=`,
 * `?hazard=` and `?resource=` are map STATE, not route identity (§5) — one
 * prerendered page per district serves every combination, and the parameters
 * are read in the browser. Prerendering them would be 14 pages times the power
 * set of twelve categories.
 *
 * This route sorts before [hazard] in SvelteKit's specificity order because a
 * static segment beats a dynamic one, so /q14/map cannot be swallowed by
 * /q14/[hazard]. The reverse — a hazard slugged "map" being shadowed by this
 * route — is the direction that would fail silently, so [hazard]'s own
 * entries() asserts no hazard slug collides with a static sibling.
 */
const dataDir = join(process.cwd(), 'static', 'data');

const index: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(dataDir, 'districts.json'), 'utf8')
);

export const entries: EntryGenerator = () => {
  const queens = index.filter((d) => d.boro === 'Queens');

  // The category marks are per-district data, so the check is per district:
  // §6 warns the set is derived and has already changed twice, and a district
  // carrying a different twelve could collide where q14 does not. Two
  // categories drawing the same letter is invisible at runtime — it just looks
  // deliberate — so it has to fail here.
  for (const d of queens) {
    const payload: DistrictPayload = JSON.parse(
      readFileSync(join(dataDir, 'districts', `${d.slug}.json`), 'utf8')
    );
    assertInitialsDistinct(payload.resource_categories, d.slug);
  }

  return queens.map((d) => ({ district: d.slug }));
};
