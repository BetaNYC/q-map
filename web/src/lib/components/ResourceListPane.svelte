<script lang="ts">
  import ResourceList from '$lib/components/ResourceList.svelte';
  import { resourceCount, type ListGroup } from '$lib/resourceList';

  /**
   * The resource list over the docked desktop map, pinned to its top-left
   * corner. Figma: the ResourceList frames in "07 Resource List - Desktop",
   * header ResourceListHeader 265:180.
   *
   * HEIGHT. At most 389px (Andrew, 2026-10-20: taller and it outweighs the
   * map), and never past the map's own height less 16 above and below. The
   * caller passes the result as `maxHeight`, because it also has to keep the
   * pane clear of the Popup, which only the layout knows the size of.
   *
   * COLLAPSING is local state in the layout, not a URL parameter: like the
   * sheet's tab, it is a view preference, not something a shared link should
   * pin. Collapsed, the pane is its header alone, as a pill in the Popup's
   * surface.
   */

  interface Props {
    groups: ListGroup[];
    selectedId: string | null;
    onSelect: (resourceId: string, row: HTMLElement) => void;
    collapsed: boolean;
    onToggle: () => void;
    /** px. See HEIGHT above. */
    maxHeight: number;
  }

  let { groups, selectedId, onSelect, collapsed, onToggle, maxHeight }: Props = $props();

  const total = $derived(groups.reduce((n, g) => n + g.rows.length, 0));
</script>

<section
  class="pane"
  class:is-collapsed={collapsed}
  aria-labelledby="resource-pane-heading"
  style="--pane-max: {maxHeight}px"
>
  <div class="header">
    <h2 class="title" id="resource-pane-heading">
      {groups.length > 0 ? resourceCount(total) : 'No resources shown'}
    </h2>
    <button
      type="button"
      class="toggle"
      aria-expanded={!collapsed}
      aria-controls="resource-pane-body"
      onclick={onToggle}
    >
      {collapsed ? 'Show list' : 'Hide list'}
      <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true">
        <path d={collapsed ? 'M3 4.5 6 7.5l3-3' : 'M3 7.5 6 4.5l3 3'} stroke="currentColor" />
      </svg>
    </button>
  </div>

  <div class="body" id="resource-pane-body" hidden={collapsed}>
    {#if groups.length > 0}
      <ResourceList {groups} {selectedId} {onSelect} headingLevel={3} idBase="pane-group" light />
    {:else}
      <!-- The district page's default: no category on, so no points and no
           rows. Hiding the pane instead would leave nobody knowing it exists. -->
      <p class="empty">Turn on a category under Resources, below the map, to list its resources.</p>
    {/if}
  </div>
</section>

<style>
  .pane {
    position: absolute;
    top: var(--space-400);
    left: var(--space-400);
    z-index: 2;

    display: flex;
    flex-direction: column;
    width: 320px;
    max-height: var(--pane-max);

    background: var(--color-surface);
    /* A shadow, not a border (Andrew, 2026-10-20). Over land the basemap is
       nearly the pane's off-white, so the edge has to come from somewhere;
       the 0.3px black border drew a full pixel of black all round and was
       about a tenth of the pane's ink. The bottom sheet's shadow, softened. */
    box-shadow: 0 1px 6px rgb(0 0 0 / 0.14);
    border-radius: 1px; /* the Popup's literal; no token for it */
  }

  .is-collapsed {
    width: auto;
  }

  .header {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-400);
    padding: var(--space-300);
  }

  .title {
    margin: 0;
    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .toggle {
    display: flex;
    align-items: center;
    gap: var(--space-100);
    background: none;
    border: 0;
    font: inherit;
    font-size: var(--font-size-caption);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    cursor: pointer;
    /* 24px target (WCAG 2.5.8) on an 11px label, taken as padding and pulled
       back so the header keeps the frame's height. Desktop and pointer only. */
    padding-block: calc((24px - 1lh) / 2);
    margin-block: calc((24px - 1lh) / -2);
    padding-inline: var(--space-100);
    margin-inline: calc(var(--space-100) * -1);
  }

  .body {
    flex: 1 1 auto;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding-bottom: var(--space-200);
  }

  .body[hidden] {
    display: none;
  }

  .empty {
    margin: 0;
    padding: var(--space-300) var(--space-300) var(--space-200);
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
    color: var(--color-text-secondary);
  }
</style>
