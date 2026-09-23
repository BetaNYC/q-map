import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import type { DistrictPayload } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * SCAFFOLD. The hazard screen — guidance sections, four item shapes, phone
 * rows — is build step 7. This loads only enough to prove the 112 routes
 * resolve and that HazardRow's links land somewhere real.
 *
 * It reads the district payload rather than hazards/<slug>.json because the
 * hazard's label and rank are district-scoped; the authored guidance is not,
 * and joins in at step 7.
 */
export const load: PageLoad = async ({ fetch, params }) => {
  const response = await fetch(dataUrl(`districts/${params.district}.json`));
  if (!response.ok) {
    throw new Error(`districts/${params.district}.json: ${response.status}`);
  }

  const district: DistrictPayload = await response.json();
  const hazard = district.hazards.find((h) => h.slug === params.hazard);

  // §5: an unknown hazard slug is a real 404. entries() only ever generates
  // slugs that exist, so this fires on a client-side navigation or a stale
  // shared link, not during prerender.
  if (!hazard) {
    error(404, `"${params.hazard}" is not a hazard in ${params.district}`);
  }

  return { district, hazard };
};
