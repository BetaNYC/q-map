import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import type { Conditions, DistrictPayload, HazardContent } from '$lib/types';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params }) => {
  const districtResponse = await fetch(dataUrl(`districts/${params.district}.json`));
  if (!districtResponse.ok) {
    throw new Error(`districts/${params.district}.json: ${districtResponse.status}`);
  }

  const district: DistrictPayload = await districtResponse.json();
  const hazard = district.hazards.find((h) => h.slug === params.hazard);

  // §5: an unknown hazard slug is a real 404. entries() only generates slugs
  // that exist, so this catches a client-side navigation or a stale link.
  if (!hazard) {
    error(404, `"${params.hazard}" is not a hazard in ${params.district}`);
  }

  /**
   * THE OVERRIDE IS FETCHED INSTEAD OF THE BASE, NOT IN ADDITION TO IT.
   *
   * `hazard_overrides` on the district payload names which hazards have a
   * district-specific file, and §3 says to fetch it only for those — one
   * district, one hazard, today: q14 / coastal-storm.
   *
   * The contract describes the override as replacing whole top-level keys
   * rather than deep-merging, which reads like the frontend has a merge to
   * perform. It does not: the emitted file is already self-contained. Verified
   * against the real file — its `slug`, `label`, `jra_category` and `summary`
   * are byte-identical to the base's, and `meta.overridden` lists only
   * `sections` and `map_layers` as replaced. The pipeline does the merge.
   *
   * So there is one fetch either way, and no client-side merge to get wrong.
   */
  const isOverridden = district.hazard_overrides?.includes(params.hazard) ?? false;

  const contentPath = isOverridden
    ? `districts/${params.district}/hazards/${params.hazard}.json`
    : `hazards/${params.hazard}.json`;

  const contentResponse = await fetch(dataUrl(contentPath));
  if (!contentResponse.ok) {
    throw new Error(`${contentPath}: ${contentResponse.status}`);
  }

  const content: HazardContent = await contentResponse.json();

  /**
   * `conditions.json` is fetched only where a section declares it — one
   * hazard, infectious-disease. It is 2 KB, but fetching it on all 112 hazard
   * pages would inline it into 112 prerendered pages for the 14 that use it.
   */
  const wantsConditions = content.sections.some((s) => s.id === 'current-conditions');

  let conditions: Conditions | null = null;
  if (wantsConditions) {
    const response = await fetch(dataUrl('conditions.json'));
    if (!response.ok) throw new Error(`conditions.json: ${response.status}`);
    conditions = await response.json();
  }

  return { district, hazard, content, conditions, isOverridden };
};
