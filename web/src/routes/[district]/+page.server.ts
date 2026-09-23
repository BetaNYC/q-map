import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DistrictIndexEntry } from '$lib/types';
import type { EntryGenerator } from './$types';

/**
 * WORKED EXAMPLE — the prerender manifest for a parameterised route.
 *
 * §5 requires 389 real URLs with no hand-maintained list. `entries()` is how a
 * route declares its own parameter space; SvelteKit calls it at build time and
 * prerenders one HTML file per returned object. Every parameterised route in
 * the app follows this shape:
 *
 *   /q{NN}                          <- this file, from districts.json
 *   /q{NN}/{hazard-slug}            from the district payload's hazards[]
 *   /q{NN}/map                      from districts.json
 *   /q{NN}/resource/{source}/{slug} from resources/q*.json, source !== 'facdb'
 *
 * Why this lives in +page.server.ts and not +page.ts:
 *
 *   A +page.ts is bundled for the browser, so it cannot import node:fs. A
 *   +page.server.ts never reaches the client, so it can. This route's actual
 *   data loading still happens in +page.ts (universal); this file exports
 *   `entries` and nothing else.
 *
 * Why fs and not fetch:
 *
 *   `entries()` runs before the prerenderer starts and is given no `fetch`.
 *   Reading the file directly is the only option, and it was verified in the
 *   spike — a cwd-relative read of static/data/ resolved through the symlink at
 *   build time. cwd is web/ for both `vite dev` and `vite build`.
 */
const districts: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(process.cwd(), 'static', 'data', 'districts.json'), 'utf8')
);

export const entries: EntryGenerator = () => {
  // Queens only. §5: a non-Queens CDTA such as /bk01 is a real 404, because
  // only Queens has pages — so those slugs must not be prerendered at all.
  return districts.filter((d) => d.boro === 'Queens').map((d) => ({ district: d.slug }));
};
