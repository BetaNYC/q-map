<script lang="ts">
  import type { SVGAttributes } from 'svelte/elements';

  /**
   * The back arrow on DistrictHeader's "Change location" link.
   *
   * Exported from Figma (node I14:1387;14:1383). The asset's own path, with
   * `stroke="#0A0A0A"` swapped for currentColor and 12px for 1em, so it
   * follows the 12px text it sits beside rather than being pinned.
   *
   * aria-hidden — "Change location" carries the meaning.
   */
  let { ...rest }: SVGAttributes<SVGSVGElement> = $props();
</script>

<svg
  viewBox="0 0 12 12"
  fill="none"
  stroke="currentColor"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
  {...rest}
>
  <path d="M5.25 2.25L1.5 6L5.25 9.75M1.5 6H10.5" />
</svg>

<style>
  svg {
    width: 1em;
    height: 1em;
    flex-shrink: 0;
    display: block;
  }
</style>
