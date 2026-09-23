import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import { hasDetail } from '$lib/resources';
import type { DistrictIndexEntry, DistrictPayload, Resource } from '$lib/types';
import type { EntryGenerator, PageServerLoad } from './$types';

/**
 * The 248 resource-detail routes — the last of §5's 389.
 *
 * `/q{NN}/resource/{source}/{slug}`, from `resource_id` split on its one
 * colon: `qnpd:her-care-inc` -> `/q14/resource/qnpd/her-care-inc`.
 *
 * FACDB RECORDS GET NO ROUTE, BY DESIGN. 3,547 of the 3,795 resources are
 * FacDB and are popup-only; their permalink is
 * `/q{NN}/map?resource=facdb:<hash>` (§7.4). Because this generator never
 * emits them, `/q14/resource/facdb/<hash>` is simply a path that was never
 * built, which is exactly §5's "a FacDB id on a /resource/ path is a 404".
 * No explicit rejection is needed and none is written — the absence IS the
 * behaviour.
 */
const dataDir = join(process.cwd(), 'static', 'data');

/** §5: `[a-z]+:[a-z0-9-]+`. A colon-free or oddly-cased id would silently
 *  produce a route that cannot be reached, so it fails the build instead. */
const RESOURCE_ID = /^[a-z]+:[a-z0-9-]+$/;

/** §5 asserts a max slug length of 60. Longer would still route, but it is a
 *  stated fact about the data and a change upstream should surface here. */
const MAX_SLUG = 60;

const index: DistrictIndexEntry[] = JSON.parse(
  readFileSync(join(dataDir, 'districts.json'), 'utf8')
);

export const entries: EntryGenerator = () => {
  const queens = index.filter((d) => d.boro === 'Queens');
  const seen = new Set<string>();

  const routes = queens.flatMap((d) => {
    const payload: { resources: Resource[] } = JSON.parse(
      readFileSync(join(dataDir, 'resources', `${d.slug}.json`), 'utf8')
    );

    return payload.resources
      .filter((r) => r.source !== 'facdb')
      .map((r) => {
        if (!RESOURCE_ID.test(r.resource_id)) {
          throw new Error(`${d.slug}: resource_id "${r.resource_id}" is not [a-z]+:[a-z0-9-]+`);
        }

        const separator = r.resource_id.indexOf(':');
        const source = r.resource_id.slice(0, separator);
        const slug = r.resource_id.slice(separator + 1);

        if (slug.length > MAX_SLUG) {
          throw new Error(`${d.slug}: slug "${slug}" is ${slug.length} chars, over the stated max of ${MAX_SLUG}`);
        }

        // A collision would mean two resources sharing a URL, and the second
        // would overwrite the first's page with no error anywhere.
        const path = `${d.slug}/${source}/${slug}`;
        if (seen.has(path)) throw new Error(`duplicate resource route: ${path}`);
        seen.add(path);

        return { district: d.slug, source, slug };
      });
  });

  // §5 states 248. Asserted rather than trusted: a short payload would just
  // build fewer pages, and the popup's detail links would 404 in production
  // with nothing having failed.
  if (routes.length !== 248) {
    throw new Error(`expected 248 resource routes, built ${routes.length}`);
  }

  return routes;
};

/**
 * One resource's detail page.
 *
 * A SERVER load, and it has to be. These 248 pages each need ONE record out of
 * a `resources/q*.json` that runs to 114 KB — and q12's to rather more. A
 * universal load would serialise the whole fetched response into every page:
 * measured at up to 306 KB of HTML each and 44 MB across the build, against
 * 12 MB of actual data.
 *
 * A server load serialises only what it returns, so each page carries the one
 * record it renders. This is the case the note in src/routes/+page.ts
 * describes, and the reason that note exists.
 *
 * The map screen is the opposite case and keeps its universal load: it genuinely
 * needs the whole list client-side for the popup join.
 */
export const load: PageServerLoad = async ({ fetch, params }) => {
  const resourceId = `${params.source}:${params.slug}`;

  const [resourceResponse, districtResponse] = await Promise.all([
    fetch(dataUrl(`resources/${params.district}.json`)),
    fetch(dataUrl(`districts/${params.district}.json`))
  ]);

  if (!resourceResponse.ok) {
    throw new Error(`resources/${params.district}.json: ${resourceResponse.status}`);
  }
  if (!districtResponse.ok) {
    throw new Error(`districts/${params.district}.json: ${districtResponse.status}`);
  }

  const { resources }: { resources: Resource[] } = await resourceResponse.json();
  const district: DistrictPayload = await districtResponse.json();

  const resource = resources.find((r) => r.resource_id === resourceId);

  // §5: a bad route is an error. entries() only ever generates the 248, so
  // neither branch fires during prerender.
  if (!resource) {
    error(404, `No resource "${resourceId}" in ${params.district}`);
  }

  // A FacDB id reaching a /resource/ path. It has no page by design (§5).
  if (!hasDetail(resource)) {
    error(404, `"${resourceId}" is a FacDB record and has no detail page`);
  }

  const categoryLabel =
    district.resource_categories.find((c) => c.slug === resource.category)?.label ??
    resource.category;

  // Only these three values are serialised — not the 114 KB they came from.
  return {
    resource,
    categoryLabel,
    district: { slug: district.slug, display_name: district.display_name }
  };
};
