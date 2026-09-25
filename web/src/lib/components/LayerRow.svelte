<script lang="ts">
  import { swatchFor, type MapLayer } from '$lib/layers';

  /**
   * A map overlay's toggle in the Layers tab.
   *
   * Follows ResourceRow — same `<button aria-pressed>`, same 48px hit area,
   * same page-owned state, same off treatment. See that file for the reasoning
   * behind the toggle class; it is not repeated here.
   *
   * Figma: LayerRow, node I75:1644;73:423;75:1640 and siblings.
   *
   * WHAT DIFFERS FROM ResourceRow:
   *
   *   The leading element is a SOLID SWATCH, not an outlined letter — a legend
   *   key tying the row to a colour on the map. It carries no border and no
   *   text.
   *
   *   There is no count. A layer is one thing, not a collection.
   *
   * THE OFF STATE DIMS THE SWATCH TO 35%. Figma's boolean visibility property
   * drops the swatch's opacity rather than recolouring it — greying it would
   * remove the one thing identifying which overlay the row controls, and 35%
   * of the layer's own colour still reads as that layer.
   *
   * The label takes ResourceRow's treatment alongside it: regular weight,
   * secondary colour. Every LayerRow instance in the frames is drawn `visible:
   * true`, so that half is inherited from the sibling component rather than
   * read off an off-state instance — worth confirming.
   */

  interface Props {
    layer: MapLayer;
    /** Whether this overlay is currently drawn on the map. */
    pressed: boolean;
    onToggle: (layerId: string) => void;
  }

  let { layer, pressed, onToggle }: Props = $props();

  // listableLayers() guarantees a swatch, so this is never the fallback in
  // practice; currentColor keeps a mis-wired row visible rather than invisible.
  const swatch = $derived(swatchFor(layer) ?? 'currentColor');
</script>

<button type="button" class="row" aria-pressed={pressed} onclick={() => onToggle(layer.layer_id)}>
  <span class="swatch" style="background: {swatch}" aria-hidden="true"></span>
  <span class="label">{layer.label}</span>
</button>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 10px; /* Figma's literal; the space scale has no 10 */
    width: 100%;

    /* 16px + the 16px swatch + 16px = 48px, over the 44px minimum. */
    padding-block: var(--space-400);
    padding-inline: 0;

    background: none;
    border: 0;
    text-align: left;
    font: inherit;
    color: var(--color-text-primary);
    cursor: pointer;

    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  /* Off: regular weight and secondary colour on the text, as ResourceRow. */
  .row[aria-pressed='false'] {
    font-weight: var(--font-weight-regular);
    color: var(--color-text-secondary);
  }

  /* Off: the swatch dims to 35% rather than changing hue, so it still reads as
   * this layer's colour. Figma's boolean visibility property. */
  .row[aria-pressed='false'] .swatch {
    opacity: 0.35;
  }

  .swatch {
    flex-shrink: 0;
    width: var(--space-400);
    height: var(--space-400);
    border-radius: var(--radius-sm);

    /* The swatch is the only carrier of the layer's identity, and these fills
     * are pale. A hairline keeps the lightest of them (#9bbde9) from
     * disappearing into the sheet — the swatch is a UI component under WCAG
     * 1.4.11, which wants 3:1 against its background, and #9bbde9 on
     * --color-surface is nowhere near that.
     *
     * It sits inside the element, so it dims with the swatch rather than
     * outlining an otherwise faded square. */
    box-shadow: inset 0 0 0 0.75px rgb(0 0 0 / 0.18);

    /* Toggling is a state change the eye should be able to follow, but the
     * sheet is scrollable and motion is an accessibility setting, not a
     * default. */
    transition: opacity 120ms ease;
  }

  @media (prefers-reduced-motion: reduce) {
    .swatch {
      transition: none;
    }
  }

  .label {
    flex: 1 0 0;
    min-width: 0;
    overflow-wrap: break-word;
  }
</style>
