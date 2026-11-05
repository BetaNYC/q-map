<script lang="ts">
  import { RAMP_KEYS } from '$lib/map/palette';

  /**
   * A graded layer's colour key, shown under its toggle while the layer is on
   * (legend option A, 2026-11-05). Figma: `LayerRamp`, node 299:187.
   *
   * 196px wide - the width at which FEMA's "1% + waves" fits on one line
   * under its cell - and never wider than its row. Cells 8px tall with 2px of
   * surface between them; labels in caption/metadata, secondary ink, 4px
   * below.
   *
   * Read out as one image with a sentence, since the cells alone say nothing.
   */

  interface Props {
    layerId: string;
  }

  let { layerId }: Props = $props();

  const key = $derived(RAMP_KEYS[layerId]);
  const description = $derived.by(() => {
    if (!key) return '';
    const l = key.labels;
    return 'ends' in l
      ? `Colour key: ${key.ramp.classes.length} shades, from ${l.ends[0]} (lightest) to ${l.ends[1]} (darkest).`
      : `Colour key, lightest to darkest: ${l.perClass.join(', ')}.`;
  });
</script>

{#if key}
  <div class="ramp" role="img" aria-label={description} style="--classes: {key.ramp.classes.length}">
    <div class="cells">
      {#each key.ramp.classes as c (c.value)}
        <span class="cell" style="background: {c.color}; opacity: {c.opacity ?? key.opacity}"></span>
      {/each}
    </div>
    {#if 'ends' in key.labels}
      <div class="labels ends"><span>{key.labels.ends[0]}</span><span>{key.labels.ends[1]}</span></div>
    {:else}
      <div class="labels per-class">
        {#each key.labels.perClass as label (label)}<span>{label}</span>{/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .ramp {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
    width: 196px;
    max-width: 100%;
  }

  .cells,
  .per-class {
    display: grid;
    grid-template-columns: repeat(var(--classes), 1fr);
    gap: 2px;
  }

  .cell {
    height: 8px;
  }

  .labels {
    font-size: var(--font-size-caption);
    line-height: var(--line-height-tight);
    color: var(--color-text-secondary);
  }

  .ends {
    display: flex;
    justify-content: space-between;
    gap: var(--space-200);
  }

  .ends span:last-child {
    text-align: right;
  }
</style>
