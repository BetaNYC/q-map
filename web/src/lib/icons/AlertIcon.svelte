<script lang="ts">
  import type { SVGAttributes } from 'svelte/elements';

  /**
   * The alert mark on the AlertBanner component.
   *
   * NOT RENDERED IN V1. The alert banner's boolean is always false, there is no
   * endpoint and the Notify NYC poller is unbuilt (handoff §7.7). This exists
   * because the glyph was extracted in the same pass as InfoIcon's and throwing
   * it away would mean re-deriving the transform later; it costs nothing until
   * ALERTS_SERVICE.md lands.
   *
   * The character `!` from NewComputerModernMono10 BookItalic, the
   * `icon/default` token. Extracted, flipped and centred exactly as
   * InfoIcon.svelte describes — see that file for the reasoning, which is not
   * repeated here. Ink measures 2.784 x 7.464px in the 24x24 frame.
   *
   * Glyph outline (C) 2019-2021 Antonis Tsolomitis, from New Computer Modern,
   * released under the GUST Font License.
   * See http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt
   */
  let { ...rest }: SVGAttributes<SVGSVGElement> = $props();
</script>

<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false" {...rest}>
  <path
    d="M12.816 8.268C12.456 8.268 12.192 8.556 12.12 8.892L11.244 12.936C11.22 13.044 11.208 13.128 11.196 13.164C11.196 13.416 11.364 13.548 11.712 13.548C12.036 13.548 12.144 13.5 12.228 13.188L13.344 9.096C13.38 8.976 13.392 8.892 13.392 8.832C13.392 8.52 13.128 8.268 12.816 8.268ZM11.868 15.036C11.868 14.64 11.676 14.448 11.304 14.448C10.92 14.448 10.608 14.772 10.608 15.156C10.608 15.468 10.86 15.732 11.172 15.732C11.544 15.732 11.868 15.408 11.868 15.036Z"
  />
</svg>

<style>
  svg {
    width: var(--space-600);
    height: var(--space-600);
    display: block;
  }
</style>
