<script lang="ts">
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { page } from '$app/state';
  import BottomSheet from '$lib/components/BottomSheet.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import LayerRow from '$lib/components/LayerRow.svelte';
  import Map from '$lib/components/Map.svelte';
  import TabBar from '$lib/components/TabBar.svelte';
  import Popup from '$lib/components/Popup.svelte';
  import ResourceRow from '$lib/components/ResourceRow.svelte';
  import { dataUrl } from '$lib/data';
  import { parseSelection, toggleSelection, withSelection } from '$lib/mapState';
  import { DOCKED_QUERY } from '$lib/mapView';
  import { MediaQuery } from 'svelte/reactivity';
  import { hasDetail } from '$lib/resources';
  import type { Resource } from '$lib/types';

  let { data } = $props();

  /**
   * §5's map state, read from the URL in the browser only.
   *
   * `browser` is not belt-and-braces — accessing page.url.searchParams during
   * prerender throws, because the prerendered page has no query string. On the
   * server this is null, which is exactly the default state; on the client the
   * $derived re-runs against the real URL, so a shared ?categories= link
   * resolves on hydration and on any later client-side navigation.
   *
   * null and [] are different: null is "no parameter, show the default", [] is
   * "a parameter was given and nothing in it was recognised". §5 says absent
   * means default, and that unknown ids are dropped rather than fatal.
   */
  const allCategories = $derived(data.district.resource_categories.map((c) => c.slug));

  /** The categories showing. null -> all of them, the default. Parsing and
   *  writing are shared with the docked desktop map: $lib/mapState.ts. */
  const selected = $derived(
    parseSelection(browser ? page.url.searchParams.get('categories') : null, allCategories)
  );

  function isOn(slug: string): boolean {
    return selected === null || selected.includes(slug);
  }

  /**
   * Toggling writes the selection back into the URL rather than into local
   * state, because the URL IS the state (§5). Two people opening the same link
   * see the same map, and the browser's back button walks the toggles.
   *
   * `replaceState` so twelve taps do not leave twelve history entries to back
   * out of. `noScroll` and `keepFocus` because the row that was tapped must
   * stay where it is and keep focus — a toggle that moves the page or drops
   * focus to the body is unusable with a keyboard or a screen reader.
   *
   * Switching everything back on removes the parameter (the default is all),
   * rather than listing all twelve.
   */
  function toggle(slug: string) {
    const next = toggleSelection(selected ?? allCategories, slug, allCategories);
    const url = withSelection(page.url, 'categories', next, null, allCategories);
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }

  /* ---- Layers ---------------------------------------------------------- */

  /** The switchable layers, from the registry via the root layout's data. */
  const layers = $derived(data.mapLayers);
  const layerIds = $derived(layers.map((l) => l.layer_id));

  /**
   * `?layers=` reads the opposite way round from `?categories=`, and the
   * asymmetry is deliberate.
   *
   * Absent means DEFAULT for both (§5). For categories the sensible default is
   * everything — the resources are the point of the map. For context overlays
   * it is nothing: a bare /q14/map stacking storm surge over two stormwater
   * layers over an evacuation-zone map is unreadable, and §5's worked example
   * has the hazard page supply `?layers=` precisely because the overlays belong
   * to a hazard rather than to the district.
   *
   * §5 says a bare /q14/map "has one fixed default" without naming it. This is
   * a reading, not a quotation — flagged in the handover.
   */
  const selectedLayers = $derived(
    parseSelection(browser ? page.url.searchParams.get('layers') : null, layerIds) ?? []
  );

  function toggleLayer(layerId: string) {
    const next = toggleSelection(selectedLayers, layerId, layerIds);
    // With nothing on, the parameter is dropped rather than written empty:
    // that is this page's default, and the shorter URL is the one to share.
    const url = withSelection(page.url, 'layers', next, [], layerIds);
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }

  /* ---- The popup join -------------------------------------------------- */

  /**
   * resources/<slug>.json, fetched IN THE BROWSER rather than in a load.
   *
   * This is the third data-loading shape in the app, and it exists because of a
   * measurement. A universal load would serialise the whole ~114 KB response
   * into the prerendered HTML — 194 KB once escaped, on each of 14 map pages,
   * for a file the page does not need until someone opens a popup. A server
   * load could slice it, but the map needs the WHOLE list client-side: every
   * feature's popup joins against it (§7.4), so slicing defeats the purpose.
   *
   * So: prerender the page without it, fetch it when the map mounts. The map
   * needs JS regardless — MapLibre is not optional — so this adds no new
   * requirement.
   */
  let resources = $state<Resource[] | null>(null);

  $effect(() => {
    let cancelled = false;

    fetch(dataUrl(`resources/${data.district.slug}.json`))
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((payload) => {
        if (!cancelled) resources = payload.resources;
      })
      .catch(() => {
        // §7.7's governing rule, applied here: degrade to nothing. A failed
        // join means no popup, never a broken page.
        if (!cancelled) resources = [];
      });

    return () => {
      cancelled = true;
    };
  });

  /** ?resource=<resource_id> — the permalink for a FacDB record (§7.4). */
  const requestedResource = $derived(browser ? page.url.searchParams.get('resource') : null);

  const selectedResource = $derived(
    requestedResource && resources
      ? (resources.find((r) => r.resource_id === requestedResource) ?? null)
      : null
  );

  /**
   * The category LABEL. The record carries only a slug, and the labels live in
   * the district payload this page already loaded — the third leg of the join.
   */
  const categoryLabel = $derived(
    selectedResource
      ? (data.district.resource_categories.find((c) => c.slug === selectedResource.category)
          ?.label ?? selectedResource.category)
      : ''
  );

  /** Which sheet tab is showing. Local UI state, not URL state: it is a view
   *  preference rather than something a shared link should pin (§5 lists four
   *  parameters and this is not one of them). */
  let activeTab = $state<'resources' | 'layers'>('resources');

  /** Tapping a point on the map writes `?resource=`, the same permalink §7.4
   *  names — so a map click and a shared link arrive at identical state. */
  function selectResource(resourceId: string) {
    const url = new URL(page.url);
    url.searchParams.set('resource', resourceId);
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }

  /**
   * §5: `?hazard=` exists because the map screen titles itself by hazard and
   * layer ids do not reverse-map to a hazard reliably. Nesting the route
   * instead would have prerendered 112 more pages for a header string.
   *
   * Unknown slugs degrade rather than error — it is a parameter, not a route.
   */
  const hazardParam = $derived(browser ? page.url.searchParams.get('hazard') : null);
  const hazard = $derived(
    hazardParam ? (data.district.hazards.find((h) => h.slug === hazardParam) ?? null) : null
  );

  /* ---- Desktop: forward to the page beside the map -------------------- */

  /**
   * On desktop this page has no job (Andrew, 2026-10-07): the map is beside
   * every page and the toolbar under it does what the sheet does here. A link
   * that lands here, shared from a phone or from a resource page's back link,
   * forwards to the district page, or to the hazard page when `?hazard=` names
   * one, carrying `?layers=`, `?categories=` and `?resource=` so the same map
   * and popup open.
   *
   * One translation: this page's category default is every category, the
   * district page's is none. So an absent `?categories=` is written out as
   * the full list, keeping what the link meant.
   *
   * In the browser only, with `replaceState`, so Back skips this page. The
   * prerendered page shows for a moment first; BottomSheet's static desktop
   * styles keep that moment tidy.
   */
  const docked = new MediaQuery(DOCKED_QUERY, false);

  $effect(() => {
    if (!docked.current) return;
    const params = new URLSearchParams(page.url.search);
    const hazardSlug = params.get('hazard');
    params.delete('hazard');
    if (!params.has('categories')) {
      params.set('categories', data.district.resource_categories.map((c) => c.slug).join(','));
    }
    const toHazard = hazardSlug && data.district.hazards.some((h) => h.slug === hazardSlug);
    const path = toHazard ? `/${data.district.slug}/${hazardSlug}` : `/${data.district.slug}`;
    goto(`${base}${path}?${params}`, { replaceState: true });
  });

  function closePopup() {
    const url = new URL(page.url);
    url.searchParams.delete('resource');
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });

    /**
     * §10: focus "returns to the trigger on close".
     *
     * The trigger is a point on the map, which is not a focusable element —
     * MapLibre's canvas is. Returning there is the closest true statement: it
     * puts the keyboard back where the selection was made, and the canvas is
     * where the arrow keys pan from. Without this, focus falls to <body> and
     * the next Tab starts from the top of the page.
     */
    queueMicrotask(() => {
      document.querySelector<HTMLElement>('.maplibregl-canvas')?.focus();
    });
  }
</script>

<!-- SCAFFOLD ONLY. The map itself, the bottom sheet and the popup are steps 8
     and 9. What is real here is the row list and its URL round-trip. -->

<svelte:head>
  <!-- The hazard name when the link carried one, the district otherwise. The
       prerendered title is the district form, because `?hazard=` is read in
       the browser (§5) — it updates on hydration. -->
  <title>{hazard ? `${hazard.label} in ${data.district.display_name}` : `${data.district.display_name} map`} | Queens Resource Map</title>
</svelte:head>

<!-- §3: the map screen is a stage with a bottom sheet — the map fills the
     body, and the header sits above it. A flex column of exactly one viewport
     so the stage cannot push itself below the fold. -->
<div class="screen">
  <!-- The heading is the district's name alone (Andrew, 2026-10-07): with
       SiteHeader above it, "The Rockaways map" said "map" twice over. The
       document <title> keeps "map", so this tab is still told apart from the
       district page's. -->
  <div class="chrome">
    <PageHeader
      title={hazard ? hazard.label : data.district.display_name}
      back={{
        href: `/${data.district.slug}`,
        // With the district's name already the heading, the back link would
        // repeat it (Andrew, 2026-10-07). Under a hazard heading the name still
        // says where the link goes, so it stays.
        label: hazard ? data.district.display_name : 'Back to District page'
      }}
    />
  </div>

<!-- The map is the stage; the sheet floats over it (§3). Both are client-only:
     MapLibre needs a DOM and a WebGL context, and a prerendered page has
     neither. -->
<div class="stage">
  {#if browser}
    {#if !docked.current}
      <Map
        district={data.entry}
        visibleLayers={selectedLayers}
        visibleCategories={selected}
        onSelectResource={selectResource}
      />
    {/if}

    {#if selectedResource && !docked.current}
      <!-- §5: an unknown ?resource= id opens the map with no popup and no
           error — that falls out of find() returning undefined. On desktop
           the layout draws the popup, on the page this one forwards to. -->
      <div class="popup-layer">
        <Popup
          resource={selectedResource}
          {categoryLabel}
          districtSlug={data.district.slug}
          onClose={closePopup}
        />
      </div>
    {/if}

    <BottomSheet label="Resources and layers for {data.district.display_name}">
      {#snippet header()}
        <TabBar
          idBase="mapsheet"
          tabs={[
            { id: 'resources', label: 'Resources' },
            { id: 'layers', label: 'Layers' }
          ]}
          active={activeTab}
          onSelect={(id) => (activeTab = id as 'resources' | 'layers')}
        />
      {/snippet}

      {#snippet children()}
        <div id="mapsheet-panel" role="tabpanel" aria-labelledby="mapsheet-tab-{activeTab}">
          {#if activeTab === 'resources'}
            <!-- All twelve stay listed whatever the selection (§7.3) —
                 filtering the LIST would strand someone who arrived from a
                 CategoryRow link with no way to turn anything else on. -->
            <ul class="rows">
              {#each data.district.resource_categories as category (category.slug)}
                <li>
                  <ResourceRow {category} pressed={isOn(category.slug)} onToggle={toggle} />
                </li>
              {/each}
            </ul>
          {:else}
            <ul class="rows">
              {#each layers as layer (layer.layer_id)}
                <li>
                  <LayerRow
                    {layer}
                    pressed={selectedLayers.includes(layer.layer_id)}
                    onToggle={toggleLayer}
                  />
                </li>
              {/each}
            </ul>
          {/if}
        </div>
      {/snippet}
    </BottomSheet>
  {/if}
  </div>
</div>

<style>
  /* Exactly one viewport tall, never more: the stage is positioned against
     this, and a stage that starts below a header while still being 100svh
     pushes the sheet off the bottom of the screen. */
  .screen {
    display: flex;
    flex-direction: column;
    /* SiteHeader sits above this page in the root layout. */
    height: calc(100svh - var(--site-header-height));
    overflow: hidden;
  }

  .chrome {
    flex-shrink: 0;
    padding-inline: var(--gutter);
    /* 24, as on every other screen (was 12: the header audit, 2026-10-07). */
    padding-top: var(--space-600);
  }

  /* The map screen opts out of the other screens' centred column — the map
     fills whatever the header leaves, and the sheet is positioned against
     this element rather than the viewport. */
  .stage {
    position: relative;
    flex: 1 1 auto;
    min-height: 0;
    width: 100%;
    overflow: hidden;
  }

  .popup-layer {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    /* Above the sheet's peek height so a popup is never hidden behind it. */
    bottom: calc(var(--sheet-height, 123px) + var(--space-300));
    z-index: 3;
  }

  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  /* Desktop: a page in the sidebar like any other. No viewport-tall stage;
     the sheet is static (see BottomSheet), and the popup floats over the
     docked map, centred in the space right of the 390px sidebar.
     DOCKED_QUERY, $lib/mapView.ts. */
  @media (min-width: 1024px) {
    .screen {
      height: auto;
      overflow: visible;
    }

    .stage {
      position: static;
      overflow: visible;
    }

    .popup-layer {
      position: fixed;
      left: calc(50vw + 195px);
      bottom: var(--space-600);
    }
  }
</style>
