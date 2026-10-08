<script lang="ts">
  /**
   * One cell of the desktop map toolbar. Figma: `MapToggle`, node 220:55,
   * adapted from d26's "Layer Toggle Row".
   *
   * The same toggle as ResourceRow and LayerRow, at d26's density: a 24px row
   * rather than 48, so twelve categories and four layers fit in a band under
   * the map. The on/off treatment is theirs: bold primary ink when on;
   * regular, secondary ink when off; a layer swatch outlined at 35% when off.
   *
   * DEPARTURE FROM §10: 24px tall, not 44. This is a desktop, pointer-only
   * control (the toolbar does not exist below 1024px), and 24px is WCAG 2.2's
   * minimum target size (2.5.8, AA). d26 drew 22. At 44 the band would take
   * about 300px of a 900px window. Revert by raising `padding-block`.
   */

  interface Props {
    pressed: boolean;
    label: string;
    onToggle: () => void;
    /** Resource toggles: the category mark (src/lib/categories.ts). */
    mark?: string;
    /** Resource toggles: the district's count for the category. */
    count?: number;
    /** Layer toggles: the layer's map colour (src/lib/layers.ts). */
    swatch?: string;
  }

  let { pressed, label, onToggle, mark, count, swatch }: Props = $props();
</script>

<button type="button" class="toggle" aria-pressed={pressed} onclick={onToggle}>
  {#if swatch}
    <span class="swatch" style="--swatch: {swatch}" aria-hidden="true"></span>
  {:else if mark}
    <span class="mark" aria-hidden="true">{mark}</span>
  {/if}

  <!-- One line, ellipsised: a 248px cell. The full label is still the
       button's accessible name, and the title shows it on hover. -->
  <span class="label" title={label}>{label}</span>

  {#if count !== undefined}
    <span class="count">
      {count}
      <!-- As ResourceRow: a bare number read aloud means nothing. -->
      <span class="visually-hidden">resources</span>
    </span>
  {/if}
</button>

<style>
  .toggle {
    display: flex;
    align-items: center;
    gap: var(--space-200);
    width: 100%;
    min-width: 0;
    padding-block: var(--space-100);
    padding-inline: 0;

    background: none;
    border: 0;
    text-align: left;
    font: inherit;
    cursor: pointer;

    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
    font-weight: var(--font-weight-bold);
    color: var(--color-text-primary);
  }

  .toggle[aria-pressed='false'] {
    font-weight: var(--font-weight-regular);
    color: var(--color-text-secondary);
  }

  .mark {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--space-400);
    height: var(--space-400);
    border: 0.75px solid currentColor;
    border-radius: var(--radius-sm);
    font-family: var(--font-mono-icon);
    font-style: italic;
    font-weight: var(--font-weight-regular);
  }

  .swatch {
    flex-shrink: 0;
    box-sizing: border-box;
    width: var(--space-400);
    height: var(--space-400);
    border-radius: var(--radius-sm);
    background: var(--swatch);
    border: 1px solid var(--swatch);
    /* LayerRow's hairline: the stormwater (limited) swatch is #cedef0, which
       nearly vanishes on the surface without it. Inside the element, so it
       dims with the swatch when off. */
    box-shadow: inset 0 0 0 0.75px rgb(0 0 0 / 0.18);
  }

  /* Off: outlined, at 35% (LayerRow's off state, and Figma's). */
  .toggle[aria-pressed='false'] .swatch {
    background: none;
    opacity: 0.35;
  }

  .label {
    flex: 1 1 auto;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .count {
    flex-shrink: 0;
    text-align: right;
  }
</style>
