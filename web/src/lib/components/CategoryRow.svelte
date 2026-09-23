<script lang="ts">
  import { base } from '$app/paths';
  import type { ResourceCategory } from '$lib/types';

  /**
   * The resource-category row on the district screen.
   *
   * Replicates HazardRow's navigating-row shape — see that file for the
   * reasoning behind the link, the hit area and the accessible name; it is not
   * repeated here. What differs is below.
   *
   * Figma: CategoryRow, node 14:1603. 46.67px tall — 12px padding, a 22.67px
   * content row, 12px padding — so the hit area already cleared 44px before the
   * touch-target pass.
   *
   * IT IS A LINK, NOT A TOGGLE. Handoff §10 calls category rows toggles with
   * aria-pressed, but that describes a map-sheet control the Figma does not
   * contain; the sheet holds only Resource Row and LayerRow. This row navigates
   * to the map with its own category showing and the rest hidden:
   *
   *     /q14/map?categories=food-assistance
   *
   * which is §5's rule that the originating page writes the state into the
   * link. One category, so no comma-joining here — the map screen reads the
   * parameter as a list and this is a list of one.
   *
   * THE COUNT IS A NUMBER, NEVER A PROPORTIONAL ENCODING (§7.3). Within one
   * district the counts span 1 to 261; a bar, a dot size or a type ramp across
   * that ratio is unreadable. It is right-aligned in a fixed 32px column so the
   * numerals line up down the list, which is the only "comparison" the design
   * offers and the honest one.
   */

  interface Props {
    category: ResourceCategory;
    /** The stored district slug, e.g. "q14". */
    districtSlug: string;
  }

  let { category, districtSlug }: Props = $props();
</script>

<a class="row" href="{base}/{districtSlug}/map?categories={category.slug}">
  <span class="label">{category.label}</span>
  <span class="count">
    {category.count}
    <!-- The link's accessible name would otherwise end in a bare number.
         "Children and youth, 134" tells a screen-reader user nothing about what
         134 counts; §10 requires link text that stands alone. -->
    <span class="visually-hidden">resources</span>
  </span>
</a>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: var(--space-300);

    /* 12px + the 22.67px content row + 12px = 46.67px, over the 44px minimum.
     * The padding is on the <a>, so the hit area and the fill are the same
     * rectangle. */
    padding-block: var(--space-300);
    padding-inline: var(--space-200);

    background: var(--color-surface-sunken);

    /* Figma draws this radius from space/100, not from radius/sm — 4px, not
     * 2px. Transcribed as drawn; flagged in web/README.md as a token the design
     * borrows from the spacing scale. */
    border-radius: var(--space-100);

    color: inherit;
    text-decoration: none;
  }

  .label {
    flex: 1 0 0;
    min-width: 0;
    overflow-wrap: break-word; /* Figma sets word-break: break-word on this row */
    line-height: var(--line-height-tight);
  }

  .count {
    flex-shrink: 0;
    width: 32px;
    text-align: right;
    line-height: var(--line-height-tight);
  }
</style>
