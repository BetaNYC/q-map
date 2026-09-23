<script lang="ts">
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { page } from '$app/state';
  import LayerRow from '$lib/components/LayerRow.svelte';
  import ResourceRow from '$lib/components/ResourceRow.svelte';
  import { listableLayers } from '$lib/layers';

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
