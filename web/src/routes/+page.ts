import { dataUrl } from '$lib/data';
import type { DistrictIndexEntry } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * WORKED EXAMPLE — the universal loader.
 *
 * This is one of the two loader shapes in the app. The choice between them is
 * not stylistic; it was measured, and it is the difference between a 1.6 KB
 * page and a 194 KB one.
 *
 *   +page.ts        (this file)  universal load, runs at prerender AND in the
 *                                browser on client-side navigation. SvelteKit
 *                                serialises the whole fetched RESPONSE into the
 *                                prerendered HTML so hydration does not refetch.
 *
 *   +page.server.ts              server load, runs ONLY at prerender. Only the
 *                                RETURNED VALUE is serialised.
 *
 * Use a universal load when the client genuinely needs the whole payload.
 * Use a server load when the build should slice a large payload down.
 *
 * Measured in the spike, same ~114 KB source file, same one-record return:
 * universal 193,790 bytes of HTML, server 1,595 bytes. Fetching
 * resources/q14.json in a universal load across the 248 resource-detail pages
 * would be ~48 MB of HTML to deliver 248 addresses.
 *
 * Universal is right HERE because districts.json is the picker's data and the
 * lookup table for client-side point-in-polygon after geocoding — the browser
 * needs all 59 entries, so inlining the response saves a round trip rather than
 * wasting one. 13,661 bytes on disk, ~16.8 KB of HTML.
 *
 * `fetch` is SvelteKit's, not the global. During prerender it resolves against
 * static/ with no server running — verified: the spike read the real 59-entry
 * index at build time and got `status=200 n=59 first=bk01`.
 */
export const load: PageLoad = async ({ fetch }) => {
  const response = await fetch(dataUrl('districts.json'));

  // handleHttpError: 'fail' in svelte.config.js catches a missing route, but a
  // data fetch is not a route — a 404 here would parse as nothing and prerender
  // an empty picker. Fail the build instead.
  if (!response.ok) {
    throw new Error(`districts.json: ${response.status} ${response.statusText}`);
  }

  const districts: DistrictIndexEntry[] = await response.json();

  return {
    // districts.json covers all 59 CDTAs citywide; only the Queens 14 have
    // pages. Filter on `boro`, not on a slug prefix — the slug is stored data,
    // and deriving borough from it is the kind of shortcut this project has
    // already paid for elsewhere.
    queens: districts.filter((d) => d.boro === 'Queens'),
    // Kept whole for the geocoder: an address that lands outside Queens needs
    // to be recognised as outside Queens, not as not-found.
    all: districts
  };
};
