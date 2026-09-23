import { base } from '$app/paths';

/**
 * The single place that knows how a path in DATA_CONTRACT.md §1 becomes a URL.
 *
 * WORKED EXAMPLE — this is the pattern every data read in the app follows.
 * Nothing else should build a data URL by hand.
 *
 *   dataUrl('districts.json')            -> /q-map/data/districts.json
 *   dataUrl('districts/q14.json')        -> /q-map/data/districts/q14.json
 *   dataUrl('layers/resources/q14.geojson')
 *                                        -> /q-map/data/layers/resources/q14.geojson
 *
 * Three things it is buying:
 *
 * 1. ONE PATH VOCABULARY. `base` comes from svelte.config.js, so the URL is
 *    identical in `vite dev`, in `vite preview` and on Pages. The path passed
 *    in is the path DATA_CONTRACT.md §1 names, unmodified — if the contract
 *    says `gaps/q14.json`, that is the argument.
 *
 * 2. ABSOLUTE, NOT RELATIVE. SvelteKit emits its own asset hrefs relative to
 *    each page, which is correct for assets it manages. A hand-written
 *    './data/…' is not managed, and would resolve differently on /q-map/q14/
 *    than on /q-map/q14/resource/qnpd/her-care-inc/. `${base}/…` cannot drift
 *    with route depth.
 *
 * 3. CACHE BUSTING IN ONE PLACE. The pipeline overwrites data/processed/ at
 *    the same URLs on every refresh, and Pages serves with an ETag plus a
 *    short max-age. CI sets VITE_DATA_VERSION to the deploy SHA, which changes
 *    whenever the deployed data changes.
 *
 *    NOT the DATA_VERSION file (`data-v4`). That is the tag of the Tier-2
 *    *input* mirror release that pipeline.yml downloads; it does not change
 *    when the outputs change, so busting a cache with it would be a no-op
 *    exactly when it mattered.
 *
 *    Unset in dev, so local URLs stay clean and match what the spike measured.
 */
const version = import.meta.env.VITE_DATA_VERSION as string | undefined;

export function dataUrl(path: string): string {
  const url = `${base}/data/${path}`;
  return version ? `${url}?v=${version}` : url;
}
