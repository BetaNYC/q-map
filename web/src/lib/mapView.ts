import type { DistrictIndexEntry } from '$lib/types';

/**
 * WORKED EXAMPLE — the desktop map's contract with the page beside it.
 *
 * On desktop (≥1024px) every page renders into a 390px sidebar, and one map,
 * mounted in the root layout, fills the rest of the window and outlasts
 * navigation. The map belongs to no page, so each page tells it what to show
 * through a `map` field in its load data, which the layout reads from
 * `page.data.map`.
 *
 * WHY LOAD DATA AND NOT A STORE THE PAGE WRITES TO. Andrew's rule
 * (2026-10-07): every page resets the map to its own defaults. Load data does
 * that for nothing, because each navigation replaces `page.data` whole. A
 * store written from a page's $effect would keep the last page's state until
 * the new page's effect ran, and keep it for good on a page that forgot to
 * write. Load data is also known during prerender.
 *
 * A page that is not about one district (entry, alerts, 404, error) declares
 * nothing and gets QUEENS_VIEW. That is still a reset: the fallback is fixed,
 * never the previous page's view.
 *
 * These are DEFAULTS. Any page's URL can carry `?layers=` and `?categories=`,
 * and the layout lays them over this view in the browser ($lib/mapState.ts).
 * Prerender cannot see a query string, so the load states the default and the
 * URL is the state on top of it, exactly as §5 has it for /q{NN}/map. Leaving
 * a page drops its query string, which keeps the reset rule.
 */
export interface MapView {
  /** Slug of the district in focus, outlined and fitted. null: all of Queens. */
  district: string | null;
  /** Overlay `layer_id`s switched on. `[]` is none. */
  layers: string[];
  /**
   * Resource categories shown. `null` is all of them, `[]` is none. With `[]`
   * the district's points file is not fetched at all.
   */
  categories: string[] | null;
}

/** Every Queens district outlined, nothing else on. */
export const QUEENS_VIEW: MapView = { district: null, layers: [], categories: [] };

/** What the map needs to know about a district. A DistrictIndexEntry is one. */
export type MapDistrict = Pick<
  DistrictIndexEntry,
  'cdta2020' | 'slug' | 'display_name' | 'bbox' | 'point_on_surface'
>;

/**
 * The docked-layout breakpoint. At 1024px a 390px sidebar leaves a 634px map;
 * at 768 it would leave 378px, narrower than the sidebar itself, so iPad
 * portrait keeps the phone layout.
 *
 * CSS cannot read a custom property in a media query, so this number is
 * repeated in the @media rules of app.css, +layout.svelte, the entry page, the map page,
 * BottomSheet and PageHeader. Change them together.
 */
export const DOCKED_QUERY = '(min-width: 1024px)';
