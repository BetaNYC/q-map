import { dataUrl } from '$lib/data';
import type { DistrictPayload } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * SCAFFOLD. The map screen — MapLibre, the PMTiles overlays, the bottom sheet,
 * the popup join — is build steps 8 and 9.
 *
 * NOTE WHAT THIS LOAD DOES NOT DO: read the query string.
 *
 * SvelteKit refuses `url.searchParams` in a load on a prerendered page, and it
 * is right to. The page is generated once, at build time, with no query string
 * in existence; whatever the load read would be baked into the HTML that every
 * ?categories= combination then receives. The build fails loudly rather than
 * shipping that:
 *
 *     Error: Cannot access url.searchParams on a page with prerendering enabled
 *
 * So all four of §5's map parameters — categories, layers, hazard, resource —
 * are CLIENT-SIDE state. The prerendered HTML is the default view (§5: "absent
 * means default, not empty"), and the browser applies the URL on top of it.
 * That is the right split for a static site anyway: the shared link still
 * renders a real page without JS, and the state it carries is layered on.
 *
 * The parsing lives in +page.svelte, guarded by `browser`.
 */
export const load: PageLoad = async ({ fetch, params, data }) => {
  const response = await fetch(dataUrl(`districts/${params.district}.json`));
  if (!response.ok) {
    throw new Error(`districts/${params.district}.json: ${response.status}`);
  }

  const district: DistrictPayload = await response.json();

  // `data` is +page.server.ts's return — the layer registry, read from disk at
  // build time. Passed through rather than re-fetched: it is already in the
  // prerendered payload.
  return { district, layers: data.layers };
};
