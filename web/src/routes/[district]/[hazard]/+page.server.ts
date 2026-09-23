import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DistrictIndexEntry, DistrictPayload } from '$lib/types';
import type { EntryGenerator } from './$types';

/**
 * The 112 hazard routes — 14 Queens districts x 8 hazards.
 *
 * Same `entries()` pattern as [district]/+page.server.ts, one level deeper: the
 * parameter space is read from the payloads rather than hand-listed, so a
 * hazard added or renamed upstream changes the route set on the next build
 * instead of silently 404ing.
 *
 * Every district carries all 8, so this is exactly 14 x 8. That is asserted
 * below rather than assumed, because a short payload would otherwise just
 * produce fewer pages and nothing would say so.
 */
const dataDir = join(process.cwd(), 'static', 'data');

/**
 * Static siblings of this route under /[district]/. A hazard slugged the same
 * as one of these would be shadowed by it and its page would silently never be
 * reachable — the prerender would still succeed, which is what makes it worth
 * asserting rather than assuming.
 */
const STATIC_SIBLINGS = ['map', 'resource'];

const index: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(dataDir, 'districts.json'), 'utf8')
);

export const entries: EntryGenerator = () => {
  const queens = index.filter((d) => d.boro === 'Queens');

  const routes = queens.flatMap((d) => {
    const payload: DistrictPayload = JSON.parse(
      readFileSync(join(dataDir, 'districts', `${d.slug}.json`), 'utf8')
    );

    if (payload.hazards.length !== 8) {
      throw new Error(`${d.slug}: expected 8 hazards, got ${payload.hazards.length}`);
    }

    for (const h of payload.hazards) {
      if (STATIC_SIBLINGS.includes(h.slug)) {
        throw new Error(
          `${d.slug}: hazard slug "${h.slug}" collides with the static route /[district]/${h.slug}`
        );
      }
    }

    return payload.hazards.map((h) => ({ district: d.slug, hazard: h.slug }));
  });

  if (routes.length !== queens.length * 8) {
    throw new Error(`expected ${queens.length * 8} hazard routes, built ${routes.length}`);
  }

  return routes;
};
