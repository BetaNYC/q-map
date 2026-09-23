<script lang="ts">
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { page } from '$app/state';
  import LayerRow from '$lib/components/LayerRow.svelte';
  import Popup from '$lib/components/Popup.svelte';
  import ResourceCard from '$lib/components/ResourceCard.svelte';
  import ResourceRow from '$lib/components/ResourceRow.svelte';
  import { dataUrl } from '$lib/data';
  import { listableLayers } from '$lib/layers';
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
  const requested = $derived(browser ? page.url.searchParams.get('categories') : null);

  const known = $derived(new Set(data.district.resource_categories.map((c) => c.slug)));

  /** The categories showing. null -> all of them, the default. */
  const selected = $derived.by(() => {
    if (requested === null) return null;
    return requested.split(',').filter((slug) => known.has(slug));
  });

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
   * Order-independence (§5) falls out of deriving the parameter from the
   * category list rather than from tap order.
   */
  function toggle(slug: string) {
    const current = selected === null ? data.district.resource_categories.map((c) => c.slug) : selected;

    const next = current.includes(slug)
      ? current.filter((s) => s !== slug)
      : data.district.resource_categories.map((c) => c.slug).filter((s) => current.includes(s) || s === slug);

    const url = new URL(page.url);
    url.searchParams.set('categories', next.join(','));
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }

  /* ---- Layers ---------------------------------------------------------- */

  const layers = $derived(listableLayers(data.layers));

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
  const layersRequested = $derived(browser ? page.url.searchParams.get('layers') : null);

  const knownLayers = $derived(new Set(layers.map((l) => l.layer_id)));

  const selectedLayers = $derived.by(() => {
    if (layersRequested === null) return [];
    // Unknown ids dropped, never fatal (§5) — a link shared before a layer was
    // retired opens the map minus that layer.
    return layersRequested.split(',').filter((id) => knownLayers.has(id));
  });

  function toggleLayer(layerId: string) {
    const next = selectedLayers.includes(layerId)
      ? selectedLayers.filter((id) => id !== layerId)
      : layers.map((l) => l.layer_id).filter((id) => selectedLayers.includes(id) || id === layerId);

    const url = new URL(page.url);
    if (next.length) url.searchParams.set('layers', next.join(','));
    // Drop the parameter rather than writing an empty one: "" would be an
    // explicit empty selection, which happens to render the same as the
    // default but is a different statement, and the shorter URL is the one
    // worth sharing.
    else url.searchParams.delete('layers');

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

  function closePopup() {
    const url = new URL(page.url);
    url.searchParams.delete('resource');
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }
</script>

<!-- SCAFFOLD ONLY. The map itself, the bottom sheet and the popup are steps 8
     and 9. What is real here is the row list and its URL round-trip. -->

<p><a href="{base}/{data.district.slug}">{data.district.display_name}</a></p>

<h1>{data.district.display_name} map</h1>

<!-- All twelve stay listed whatever the selection — §7.3: every category is
     present and toggleable. Filtering the LIST would strand a user who arrived
     from a CategoryRow link with no way to turn anything else on. What the
     ?categories= parameter controls is which are ON, not which exist. -->
<!-- The Resources / Layers tab bar is step 9. Both lists render here for now so
     each component is exercised; they are not meant to sit together. -->

<!-- §5: an unknown ?resource= id opens the map with no popup and no error. That
     falls out of the find() returning undefined rather than needing a branch. -->
{#if selectedResource}
  <Popup
    resource={selectedResource}
    {categoryLabel}
    districtSlug={data.district.slug}
    onClose={closePopup}
  />

  <!-- SCAFFOLD. ResourceCard belongs on the resource detail screen (step 10),
       which needs 248 more prerendered routes. Mounted here so it is exercised
       against real records.

       Guarded by hasDetail: §7.5 is QNPD and FRANC only. A FacDB record has an
       `address` and would otherwise render a one-row card on a page it has no
       detail view for. On the real route this cannot arise — the route only
       exists for the 248 — so the guard belongs at the mount, not inside the
       component. -->
  {#if hasDetail(selectedResource)}
    <ResourceCard resource={selectedResource} />
  {/if}
{/if}

<h2>Resources</h2>
<ul class="rows">
  {#each data.district.resource_categories as category (category.slug)}
    <li>
      <ResourceRow {category} pressed={isOn(category.slug)} onToggle={toggle} />
    </li>
  {/each}
</ul>

<h2>Layers</h2>
<ul class="rows">
  {#each layers as layer (layer.layer_id)}
    <li>
      <LayerRow {layer} pressed={selectedLayers.includes(layer.layer_id)} onToggle={toggleLayer} />
    </li>
  {/each}
</ul>

<style>
  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
  }
</style>
