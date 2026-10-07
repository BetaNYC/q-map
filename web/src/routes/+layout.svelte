<script lang="ts">
  import '../app.css';
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { page } from '$app/state';
  import { MediaQuery } from 'svelte/reactivity';
  import { provideAlerts } from '$lib/alertsContext';
  import MapToolbar from '$lib/components/MapToolbar.svelte';
  import Popup from '$lib/components/Popup.svelte';
  import SiteHeader from '$lib/components/SiteHeader.svelte';
  import { dataUrl } from '$lib/data';
  import { parseSelection, toggleSelection, withSelection } from '$lib/mapState';
  import { DOCKED_QUERY, QUEENS_VIEW, type MapView } from '$lib/mapView';
  import type { DistrictPayload, Resource, ResourceCategory } from '$lib/types';

  let { children, data } = $props();

  // One alerts poller for the visit - see $lib/alertsContext.ts. start() only
  // runs in the browser ($effect never runs during prerender) and returns its
  // own cleanup.
  const alerts = provideAlerts();
  $effect(() => alerts.start());

  /**
   * WORKED EXAMPLE — the docked desktop layout.
   *
   * At ≥1024px every page renders into a 390px sidebar, and one map fills the
   * rest of the window and stays mounted across navigation. What it shows
   * comes from the page (see $lib/mapView.ts). Below 1024px nothing here
   * changes the page at all.
   *
   * TWO SWITCHES, ON PURPOSE.
   *
   *   @media: CSS. The grid is in the prerendered HTML, so on desktop the
   *   sidebar is in place at first paint and does not jump when JS arrives.
   *   Only the map pane is empty until then.
   *
   *   `docked.current`: JS. Decides whether to load MapLibre. The chunk is
   *   1,012 KB (274 KB gzipped), and a phone reading a district page has never
   *   downloaded it. The dynamic import() below keeps it that way: no import
   *   statement in this file names the map, so it is not in the layout's
   *   bundle. The fallback `false` is what prerender sees, so the server
   *   never renders a map.
   *
   * Crossing 1024px in a live window mounts or unmounts the map. That loses
   * the user's pan and zoom, which is fine: the page resets the map anyway.
   */
  const docked = new MediaQuery(DOCKED_QUERY, false);

  const knownLayers = $derived(data.mapLayers.map((l) => l.layer_id));

  /** The page's own defaults, before the URL is applied. */
  const declared = $derived((page.data.map as MapView | undefined) ?? QUEENS_VIEW);

  /**
   * The district's categories, for the toolbar's rows and for checking
   * `?categories=`. Fetched in the browser, on desktop only: inlining all 14
   * districts' lists into every page would add about 1.65 MB across the build
   * for phones that never show a toolbar (measured, METHODOLOGY.md). The file
   * is about 4.7 KB and usually already in the HTTP cache from the page's own
   * load. Kept per slug for the visit.
   */
  let categoriesBySlug = $state<Record<string, ResourceCategory[]>>({});

  $effect(() => {
    const slug = declared.district;
    if (!docked.current || !slug || categoriesBySlug[slug]) return;
    let cancelled = false;
    fetch(dataUrl(`districts/${slug}.json`))
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((payload: DistrictPayload) => {
        if (!cancelled) categoriesBySlug[slug] = payload.resource_categories;
      })
      .catch(() => {
        // Degrade to no resource rows, never a broken page (§7.7's rule).
        if (!cancelled) categoriesBySlug[slug] = [];
      });
    return () => {
      cancelled = true;
    };
  });

  const categories = $derived(declared.district ? (categoriesBySlug[declared.district] ?? null) : null);
  const knownCategories = $derived(categories?.map((c) => c.slug));

  /**
   * The page's MapView with the URL's selection laid over it.
   *
   * `?layers=` and `?categories=` are read here, for whatever page is open,
   * not by the pages. The page's load supplies the defaults (absent means
   * default, §5), and the URL is the state on top of them, so any page's link
   * carries its toggles. The reset rule holds: a link to another page has no
   * query string, so the next page opens on its own defaults.
   *
   * In the browser only. A prerendered page has no query string, and reading
   * `page.url.searchParams` during prerender throws.
   *
   * Categories are checked against the district's list once it has loaded.
   * Before that every slug is kept: an unknown one simply matches no point.
   */
  const view = $derived.by((): MapView => {
    if (!browser) return declared;

    const params = page.url.searchParams;
    return {
      ...declared,
      layers: parseSelection(params.get('layers'), knownLayers) ?? declared.layers,
      // Points are per district, so the Queens overview has none to filter.
      categories: declared.district
        ? (parseSelection(params.get('categories'), knownCategories) ?? declared.categories)
        : declared.categories
    };
  });

  /* ---- The toolbar ---------------------------------------------------- */

  /** What the toolbar shows as on: `null` (all) spelled out. */
  const categoriesOn = $derived(view.categories ?? knownCategories ?? []);
  const layersOn = $derived(view.layers.filter((id) => knownLayers.includes(id)));

  /**
   * A toggle writes the next selection into this page's URL, and the map
   * follows the URL. `replaceState` so sixteen clicks are not sixteen history
   * entries; `noScroll` and `keepFocus` so the sidebar stays put and focus
   * stays on the toggle. A selection equal to the page's default is written as
   * no parameter ($lib/mapState.ts).
   */
  function writeSelection(url: URL) {
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }

  function toggleCategory(slug: string) {
    const known = knownCategories ?? [];
    const next = toggleSelection(categoriesOn, slug, known);
    writeSelection(withSelection(page.url, 'categories', next, declared.categories, known));
  }

  function toggleLayer(layerId: string) {
    const next = toggleSelection(layersOn, layerId, knownLayers);
    const defaults = declared.layers.filter((id) => knownLayers.includes(id));
    writeSelection(withSelection(page.url, 'layers', next, defaults, knownLayers));
  }

  /* ---- The popup ------------------------------------------------------ */

  /**
   * `?resource=` opens a point's popup, on any page with a district: the
   * toolbar can switch points on anywhere, so a click on one has to work
   * anywhere. The join is the map page's: resources/<slug>.json, fetched in
   * the browser, here only once a popup is actually asked for.
   */
  const resourceParam = $derived(browser ? page.url.searchParams.get('resource') : null);
  let resourcesBySlug = $state<Record<string, Resource[]>>({});

  $effect(() => {
    const slug = declared.district;
    if (!docked.current || !slug || !resourceParam || resourcesBySlug[slug]) return;
    let cancelled = false;
    fetch(dataUrl(`resources/${slug}.json`))
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((payload: { resources: Resource[] }) => {
        if (!cancelled) resourcesBySlug[slug] = payload.resources;
      })
      .catch(() => {
        if (!cancelled) resourcesBySlug[slug] = [];
      });
    return () => {
      cancelled = true;
    };
  });

  const selectedResource = $derived(
    resourceParam && declared.district
      ? (resourcesBySlug[declared.district]?.find((r) => r.resource_id === resourceParam) ?? null)
      : null
  );

  const popupCategoryLabel = $derived(
    selectedResource
      ? (categories?.find((c) => c.slug === selectedResource.category)?.label ?? selectedResource.category)
      : ''
  );

  function closePopup() {
    const url = new URL(page.url);
    url.searchParams.delete('resource');
    writeSelection(url);
    // §10: focus returns to the trigger. A point is not focusable; the canvas,
    // where the arrow keys pan from, is the closest true statement.
    queueMicrotask(() => document.querySelector<HTMLElement>('.map-pane .maplibregl-canvas')?.focus());
  }

  /** null when the view is all of Queens, or names a slug with no page. */
  const district = $derived(
    view.district ? (data.mapDistricts.find((d) => d.slug === view.district) ?? null) : null
  );

  const queensIds = $derived(data.mapDistricts.map((d) => d.cdta2020));

  /** Clicking a district on the docked map goes to its page. */
  function selectDistrict(slug: string) {
    goto(`${base}/${slug}`);
  }

  /**
   * Clicking a resource point writes `?resource=`, the permalink §7.4 names,
   * on whatever page is open; the popup above reads it.
   */
  function selectResource(resourceId: string) {
    const url = new URL(page.url);
    url.searchParams.set('resource', resourceId);
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }
</script>

<!-- WHY THE WINDOW SCROLLS, NOT THE SIDEBAR. The map pane is sticky in the
     right column, so the page's own content scrolls the window as it does on a
     phone. That keeps SvelteKit's scroll handling: top of the page on every
     navigation, the old position restored on Back. A sidebar with its own
     scroll would keep the last page's scroll position across a click-through
     unless reset by hand, and on a classic-scrollbar system its 15px bar
     would take width from the 390px column and rewrap every component drawn at
     358px. -->
<div class="shell">
  <div class="page">
    <!-- On every page, above the page itself: full width on a phone, the top of
         the sidebar on desktop. -->
    <SiteHeader isHome={page.route.id === '/'} />

    <!-- <main> is what keeps each page's own <header> from being a second
         banner landmark beside SiteHeader's. -->
    <main>
      {@render children()}
    </main>
  </div>

  <!-- A named region, so the docked map and its controls are a landmark a
       screen reader can jump to, beside the banner and <main>. Not "Map":
       MapLibre already labels its canvas container role="region" "Map", and two
       landmarks with one name cannot be told apart (axe landmark-unique).
       Hidden (display: none) on phones, which also removes it from the
       accessibility tree there. -->
  <section class="map-pane" aria-label="Map and map controls">
    {#if docked.current}
      <div class="map-stage">
        {#await import('$lib/components/Map.svelte') then { default: Map }}
          <Map
            {district}
            overviewBbox={data.queensBbox}
            visibleLayers={view.layers}
            visibleCategories={view.categories}
            selectableDistricts={queensIds}
            onSelectDistrict={selectDistrict}
            onSelectResource={selectResource}
          />
        {/await}

        {#if selectedResource && declared.district}
          <div class="popup-layer">
            <Popup
              resource={selectedResource}
              categoryLabel={popupCategoryLabel}
              districtSlug={declared.district}
              onClose={closePopup}
            />
          </div>
        {/if}
      </div>

      <!-- Pages about one district only (Figma frames 02, 03, 05): entry,
           alerts and 404 show all of Queens, where there are no points. -->
      {#if declared.district && categories}
        <MapToolbar
          {categories}
          {categoriesOn}
          layers={data.mapLayers}
          {layersOn}
          onToggleCategory={toggleCategory}
          onToggleLayer={toggleLayer}
        />
      {/if}
    {/if}
  </section>
</div>

<style>
  /* Below the breakpoint the shell is inert: a plain block, and the map pane
     is never shown. */
  .map-pane {
    display: none;
  }

  /* 1024px is DOCKED_QUERY in $lib/mapView.ts. A custom property cannot be
     used in a media query, so the number is repeated; change both. */
  @media (min-width: 1024px) {
    .shell {
      display: grid;
      /* 390px: the mobile frame exactly, so every component keeps its 358px
         measure and each page's own `.screen` column fills it unchanged. */
      grid-template-columns: 390px minmax(0, 1fr);
      align-items: start;
    }

    .map-pane {
      display: flex;
      flex-direction: column;
      position: sticky;
      top: 0;
      height: 100svh;
      /* What shows before MapLibre paints, and if it never does. */
      background: var(--color-surface-sunken);
    }

    /* The map takes what the toolbar leaves. A grid so the map's
       `height: 100%` has a definite box to fill. */
    .map-stage {
      position: relative;
      display: grid;
      flex: 1 1 auto;
      min-height: 0;
    }

    .popup-layer {
      position: absolute;
      left: 50%;
      bottom: var(--space-600);
      transform: translateX(-50%);
      z-index: 3;
    }
  }
</style>
