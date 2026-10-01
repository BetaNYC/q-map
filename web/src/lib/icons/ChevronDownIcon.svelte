<script lang="ts">
  import type { SVGAttributes } from 'svelte/elements';

  /**
   * The disclosure chevron. Figma: DisclosureButton's icon/chevron-down, 16px,
   * 1.5 stroke. One glyph: EntryPanel rotates it to point up when open, rather
   * than swapping to a second icon.
   */
  let { ...rest }: SVGAttributes<SVGSVGElement> = $props();
</script>

<svg
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.5"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
  {...rest}
>
  <path d="m6 9 6 6 6-6" />
</svg>

<style>
  svg {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
    display: block;
  }
</style>
