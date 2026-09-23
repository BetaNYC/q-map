import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DistrictIndexEntry } from '$lib/types';
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
const index: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(process.cwd(), 'static', 'data', 'districts.json'), 'utf8')
);

export const entries: EntryGenerator = () =>
  index.filter((d) => d.boro === 'Queens').map((d) => ({ district: d.slug }));
