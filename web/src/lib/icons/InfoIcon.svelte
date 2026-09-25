<script lang="ts">
  import type { SVGAttributes } from 'svelte/elements';

  /**
   * WORKED EXAMPLE — the icon component shape. AlertIcon.svelte is the same
   * pattern and the only thing that differs is the path.
   *
   * The info mark on the COAD component. Renders on the district and map
   * screens of the one district in fourteen that has a COAD.
   *
   * This is the letter `i` from NewComputerModernMono10 BookItalic, the
   * `icon/default` Figma token — the glyph outline extracted from the font
   * rather than traced, so the curves are the ones the design shows. Scale is
   * 12/1000 (the token's 12px against the font's unitsPerEm), placed centred in
   * the 24x24 IconFrame Figma draws it in. The ink measures 4.164 x 7.272px,
   * which is the 7 Figma reports.
   *
   * The font's Y axis points up from the baseline and SVG's points down from
   * the top-left; that flip and the centring are baked into the coordinates, so
   * there is deliberately no `transform` attribute here for an SVGO pass or a
   * careless edit to strip.
   *
   * Glyph outline (C) 2019-2021 Antonis Tsolomitis, from New Computer Modern,
   * released under the GUST Font License.
   * See http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt
   *
   * Inline SVG rather than the webfont for one reason above all: in Figma this
   * is a text node containing the character "i", and built as text a screen
   * reader would read "i" into the middle of "<district> is served by the
   * <coad_name>". aria-hidden removes it. The payload difference against a
   * subsetted font is noise (~1.4 KB of path against ~2 KB of font); this is an
   * accessibility fix that happens to also drop a network request.
   */

  // Rest props so a caller can pass a class. aria-hidden and focusable are not
  // overridable on purpose: the meaning is carried by the adjacent sentence, so
  // this is decorative in every context it appears in. An icon that ever needs
  // its own accessible name is a different component, not a prop on this one.
  let { ...rest }: SVGAttributes<SVGSVGElement> = $props();
</script>

<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false" {...rest}>
  <path
    d="M13.566 8.892C13.566 8.544 13.386 8.364 13.038 8.364C12.726 8.364 12.414 8.664 12.414 8.976C12.414 9.288 12.642 9.516 12.954 9.516C13.29 9.516 13.566 9.228 13.566 8.892ZM11.826 10.296C11.406 10.296 10.974 10.488 10.554 10.884C10.134 11.28 9.918 11.7 9.918 12.12C9.918 12.372 10.062 12.492 10.362 12.492C10.59 12.492 10.746 12.384 10.818 12.168C11.046 11.46 11.37 11.112 11.802 11.112C12.006 11.112 12.114 11.208 12.114 11.388C12.114 11.448 12.09 11.52 12.054 11.616L11.082 14.052C11.022 14.22 10.986 14.388 10.986 14.544C10.986 15.204 11.514 15.636 12.174 15.636C12.594 15.636 13.026 15.432 13.446 15.036C13.866 14.64 14.082 14.232 14.082 13.812C14.082 13.56 13.926 13.428 13.626 13.428C13.35 13.428 13.242 13.548 13.17 13.776C13.05 14.208 12.666 14.82 12.198 14.82C11.994 14.82 11.886 14.724 11.886 14.544C11.886 14.484 12.102 13.92 12.522 12.864L12.798 12.144C12.942 11.784 13.014 11.532 13.014 11.388C13.014 10.74 12.474 10.296 11.826 10.296Z"
  />
</svg>

<style>
  svg {
    /* 24px, the IconFrame. From the token rather than a literal, and set here
     * rather than as width/height attributes so there is one place to change. */
    width: var(--space-600);
    height: var(--space-600);

    /* Block, or the svg sits on the text baseline and inherits the descender
     * gap, which throws out the 24px row it is supposed to fill. */
    display: block;

    /* fill is currentColor on the element, so colour comes from whatever the
     * surrounding text is using — today --color-text-primary via body. */
  }
</style>
