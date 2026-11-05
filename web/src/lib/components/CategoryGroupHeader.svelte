<script lang="ts">
  /**
   * The heading of a colour group of resource categories (legend option A,
   * 2026-11-05). Figma: `CategoryGroupHeader`, node 299:200.
   *
   * The swatch is the colour every mark in the group carries, drawn as a mark
   * without its letter: 16px, 0.75px border, radius/sm. With the group name it
   * is the legend for the marks below it.
   */

  interface Props {
    label: string;
    /** The group's fill (categoryFill); null draws the plain surface. */
    fill: string | null;
    /** h2 in the phone sheet, h3 under the toolbar's "Resources" h2. */
    level?: 2 | 3;
    id?: string;
  }

  let { label, fill, level = 3, id }: Props = $props();
</script>

<svelte:element this={`h${level}`} class="group-header" {id}>
  <span class="swatch" style={fill ? `background: ${fill}` : undefined} aria-hidden="true"></span>
  {label}
</svelte:element>

<style>
  .group-header {
    display: flex;
    align-items: center;
    gap: var(--space-200);
    margin: 0;
    padding-block: var(--space-100);
    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
  }

  .swatch {
    flex-shrink: 0;
    width: var(--space-400);
    height: var(--space-400);
    box-sizing: border-box;
    border: 0.75px solid var(--color-text-primary);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
  }
</style>
