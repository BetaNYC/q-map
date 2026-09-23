import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import type { DistrictPayload, HazardContent } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * SCAFFOLD. The hazard screen's chrome — header, section ordering, the
 * current-conditions block — is build step 7. This loads enough to render the
 * authored guidance so the four item shapes are exercised against real
 * content.
 *
 * Two fetches, both small: the district payload for the hazard's label and
 * rank, and hazards/<slug>.json for the citywide guidance. The district
 * payload's `hazard_overrides` names which hazards have a district-specific
 * file; step 7 adds that third fetch, which REPLACES whole top-level keys
 * rather than deep-merging.
 */
export const load: PageLoad = async ({ fetch, params }) => {
  const districtResponse = await fetch(dataUrl(`districts/${params.district}.json`));
  if (!districtResponse.ok) {
    throw new Error(`districts/${params.district}.json: ${districtResponse.status}`);
  }

  const district: DistrictPayload = await districtResponse.json();
  const hazard = district.hazards.find((h) => h.slug === params.hazard);

  // §5: an unknown hazard slug is a real 404. entries() only ever generates
  // slugs that exist, so this fires on a client-side navigation or a stale
  // shared link, not during prerender.
  if (!hazard) {
    error(404, `"${params.hazard}" is not a hazard in ${params.district}`);
  }

  const contentResponse = await fetch(dataUrl(`hazards/${params.hazard}.json`));
  if (!contentResponse.ok) {
    throw new Error(`hazards/${params.hazard}.json: ${contentResponse.status}`);
  }

  const content: HazardContent = await contentResponse.json();

  return { district, hazard, content };
};
