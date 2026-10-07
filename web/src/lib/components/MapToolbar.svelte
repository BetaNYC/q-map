<script lang="ts">
  import MapToggle from '$lib/components/MapToggle.svelte';
  import { categoryInitial } from '$lib/categories';
  import { swatchFor, type MapLayer } from '$lib/layers';
  import type { ResourceCategory } from '$lib/types';

  /**
   * The desktop map toolbar: every resource category and every switchable
   * layer, in a band under the docked map. Figma: `MapToolbar`, node 222:514,
   * after d26's LayerToolbar.
   *
   * It is also the map's legend: each layer toggle's swatch is the layer's
   * fill. Not yet the resource points', which are all one blue. Styling points
   * by category is decided (Andrew, 2026-10-07) and not yet designed.
   *
   * State lives in the URL, not here: the root layout reads `?categories=` and
   * `?layers=` and passes the effective selection down, and a toggle asks the
   * layout to write the next one ($lib/mapState.ts). So a toolbar link can be
   * shared, Back walks the toggles, and the next page resets them.
   *
   * Grid: as many 220px+ columns as fit. 4 at 1440 (Figma's 248px cells), 2 at
   * 1024.
   */

  interface Props {
    /** The district's categories, in payload order. */
    categories: ResourceCategory[];
    /** Slugs showing on the map. */
    categoriesOn: string[];
    layers: MapLayer[];
    /** layer_ids showing on the map. */
    layersOn: string[];
    onToggleCategory: (slug: string) => void;
    onToggleLayer: (layerId: string) => void;
  }

  let { categories, categoriesOn, layers, layersOn, onToggleCategory, onToggleLayer }: Props =
    $props();
</script>

<div class="toolbar">
  <section class="group" aria-labelledby="toolbar-resources">
    <h2 id="toolbar-resources" class="heading">Resources</h2>
    <ul class="grid">
      {#each categories as category (category.slug)}
        <li>
          <MapToggle
            pressed={categoriesOn.includes(category.slug)}
            label={category.label}
            mark={categoryInitial(category)}
            count={category.count}
            onToggle={() => onToggleCategory(category.slug)}
          />
        </li>
      {/each}
    </ul>
  </section>

  <section class="group" aria-labelledby="toolbar-layers">
    <h2 id="toolbar-layers" class="heading">Layers</h2>
    <ul class="grid">
      {#each layers as layer (layer.layer_id)}
        <li>
          <MapToggle
            pressed={layersOn.includes(layer.layer_id)}
            label={layer.label}
            swatch={swatchFor(layer) ?? 'currentColor'}
            onToggle={() => onToggleLayer(layer.layer_id)}
          />
        </li>
      {/each}
    </ul>
  </section>
</div>

<style>
  .toolbar {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    padding: var(--space-400);
    background: var(--color-surface);
    border-top: 1px solid var(--color-border);
  }

  .group {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  .heading {
    margin: 0;
    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    column-gap: var(--space-200);
    row-gap: var(--space-100);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .grid li {
    min-width: 0;
  }
</style>
