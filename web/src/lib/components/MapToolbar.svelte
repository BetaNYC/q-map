<script lang="ts">
  import CategoryGroupHeader from '$lib/components/CategoryGroupHeader.svelte';
  import LayerRamp from '$lib/components/LayerRamp.svelte';
  import MapToggle from '$lib/components/MapToggle.svelte';
  import { categoryFill, categoryInitial, groupCategories } from '$lib/categories';
  import { RAMP_KEYS } from '$lib/map/palette';
  import { swatchFor, type MapLayer } from '$lib/layers';
  import type { ResourceCategory } from '$lib/types';

  /**
   * The desktop map toolbar: every resource category and every switchable
   * layer, in a band under the docked map. Figma: `MapToolbar`, node 222:514,
   * after d26's LayerToolbar.
   *
   * It is also the map's legend (option A, Andrew, 2026-11-05):
   *
   *   Resources   one column per colour group, headed by the group's swatch
   *               and name (CategoryGroupHeader), so a mark's colour is keyed
   *               where its toggle is. (Briefly one row per group on
   *               2026-11-05; Andrew returned it to columns the same day.)
   *   Layers      each toggle's swatch is the layer's fill; a graded layer
   *               that is on shows its LayerRamp under the toggle. The space
   *               for every graded layer's ramp is held whether the layer is
   *               on or not (Andrew, 2026-11-05), so switching one on never
   *               changes the toolbar's height or moves the map above it.
   *
   * Figma: the "Legend — option A" section, node 299:146.
   *
   * State lives in the URL, not here: the root layout reads `?categories=` and
   * `?layers=` and passes the effective selection down, and a toggle asks the
   * layout to write the next one ($lib/mapState.ts). So a toolbar link can be
   * shared, Back walks the toggles, and the next page resets them.
   *
   * Grid: as many 220px+ columns as fit, 4 at 1440 (Figma's 248px cells) and
   * 2 at 1024. The resource groups take one column each, so at 1024 they wrap
   * two to a row.
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

  const groups = $derived(groupCategories(categories));
</script>

<div class="toolbar">
  <section class="group" aria-labelledby="toolbar-resources">
    <h2 id="toolbar-resources" class="heading">Resources</h2>
    <div class="grid">
      {#each groups as group (group.group)}
        <section class="column" aria-labelledby="toolbar-group-{group.group || 'other'}">
          <CategoryGroupHeader id="toolbar-group-{group.group || 'other'}" label={group.label} fill={group.fill} />
          <ul class="list">
            {#each group.categories as category (category.slug)}
              <li>
                <MapToggle
                  pressed={categoriesOn.includes(category.slug)}
                  label={category.label}
                  mark={categoryInitial(category)}
                  markFill={categoryFill(category)}
                  count={category.count}
                  onToggle={() => onToggleCategory(category.slug)}
                />
              </li>
            {/each}
          </ul>
        </section>
      {/each}
    </div>
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
          {#if RAMP_KEYS[layer.layer_id]}
            <!-- Indented to the label: MapToggle's 16px swatch + 8px gap.
                 Always laid out, hidden while the layer is off: the toolbar
                 is sized for every key up front. visibility (not display)
                 keeps the space and takes it out of the accessibility tree. -->
            <div class="ramp" class:is-off={!layersOn.includes(layer.layer_id)}>
              <LayerRamp layerId={layer.layer_id} />
            </div>
          {/if}
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

  .grid li,
  .column {
    min-width: 0;
  }

  .grid {
    align-items: start;
  }

  .list {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .ramp {
    padding: 0 0 var(--space-100) calc(var(--space-400) + var(--space-200));
  }

  .ramp.is-off {
    visibility: hidden;
  }
</style>
