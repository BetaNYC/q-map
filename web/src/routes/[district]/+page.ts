import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import type { DistrictPayload } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * The district screen's data.
 *
 * Universal load (see the note in src/routes/+page.ts for why that choice is
 * measured rather than stylistic): districts/<slug>.json averages ~4.7 KB, the
 * screen renders nearly all of it, and inlining the response means a
 * client-side navigation from the entry screen needs no round trip.
 *
 * gaps/<slug>.json and the hazard payloads join in at build step 5; the shape
 * of this loader does not change when they do.
 */
export const load: PageLoad = async ({ fetch, params }) => {
  const response = await fetch(dataUrl(`districts/${params.district}.json`));

  // §5: a bad route is an error, a bad parameter degrades. This is a route.
  //
  // entries() in +page.server.ts only ever generates the Queens 14, so this
  // cannot fire during prerender. It fires when a client-side navigation is
  // pushed a slug that has no payload — which would otherwise render a blank
  // district rather than a 404.
  if (response.status === 404) {
    error(404, `No district payload for "${params.district}"`);
  }
  if (!response.ok) {
    throw new Error(`districts/${params.district}.json: ${response.status}`);
  }

  const district: DistrictPayload = await response.json();
  return { district };
};
