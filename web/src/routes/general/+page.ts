import { error } from '@sveltejs/kit';
import { dataUrl } from '$lib/data';
import type { PageContent } from '$lib/types';
import type { PageLoad } from './$types';

/**
 * General Resources: content/pages/general.yml, published by the pipeline as
 * pages/general.json (R/content.R, validate_page_content).
 *
 * Universal load, as the hazard pages: a few KB, all of it rendered, and a
 * client-side navigation from the entry page then needs no round trip.
 *
 * No `map` in the returned data: on desktop the docked map shows all of
 * Queens, as it does for the entry and alerts pages ($lib/mapView.ts).
 */
export const load: PageLoad = async ({ fetch }) => {
  const response = await fetch(dataUrl('pages/general.json'));
  if (response.status === 404) error(404, 'No General Resources content published');
  if (!response.ok) throw new Error(`pages/general.json: ${response.status}`);

  const content: PageContent = await response.json();
  return { content };
};
