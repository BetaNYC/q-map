<script lang="ts">
  import type { SVGAttributes } from 'svelte/elements';

  /**
   * The arrow on the popup's detail link.
   *
   * Exported from Figma (Popup, node 77:1704) rather than drawn — this is the
   * asset's own vector data, with two changes:
   *
   *   stroke="black"  ->  currentColor, so it follows the link's colour rather
   *                       than pinning itself to #000.
   *   13px            ->  1em, so it scales with the 11px caption text it sits
   *                       beside instead of being fixed while the text moves.
   *
   * aria-hidden because the link's own text carries the meaning — an arrow
   * announced as "arrow" after "Contact and services" is noise.
   */
  let { ...rest }: SVGAttributes<SVGSVGElement> = $props();
</script>

<svg
  viewBox="0 0 13 13"
  fill="none"
  stroke="currentColor"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
  {...rest}
>
  <path d="M2.70833 6.5H10.2917" />
  <path d="M6.5 2.70833L10.2917 6.5L6.5 10.2917" />
</svg>

<style>
  svg {
    width: 1em;
    height: 1em;
    flex-shrink: 0;
    display: block;
  }
</style>
