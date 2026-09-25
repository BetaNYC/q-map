<script lang="ts">
  import TrendIcon from '$lib/icons/TrendIcon.svelte';
  import type { ConditionsMetric } from '$lib/types';

  /**
   * The Conditions row. Figma: node 14:1142 — a component that appears in none
   * of the five screens, with three `direction` variants.
   *
   * A 24px fill holding an arrow, beside two lines: a sentence naming the
   * direction, and the numbers beneath it.
   *
   * THREE CHANNELS CARRY THE DIRECTION, which is what makes the colour safe to
   * use: the words ("are increasing"), the arrow's shape, and the fill. §10
   * requires that colour never be the only one, and here it is the last of
   * three rather than the first.
   *
   * GEOGRAPHY GOES IN THE FIRST LINE. The frame's copy is "Respiratory illness
   * emergency department visits are increasing" — no geography anywhere. But
   * this renders on a district-scoped page and the figure is citywide, and the
   * contract is explicit that `geography_label` is "the string that stops a
   * citywide figure reading as local". Composing the sentence as
   * "<metric> in <geography_label> are <direction>" satisfies that inside the
   * design's own sentence shape rather than bolting a line on. Flagged in
   * web/README.md.
   *
   * "LAST WEEK" IS CORRECT. The contract describes `direction` as change over
   * "the last two weeks", which reads like `previous` is a fortnight back. It
   * is not: `previous` equals `series[length - 2].value` on both metrics,
   * dated exactly seven days before `value`. Verified against the real file.
   *
   * `trend` IS NOT SHOWN. The design has two lines and neither is it. The
   * contract's warning about `trend` is specifically that showing only
   * `direction` *beside a sparkline* puts an arrow against a visibly falling
   * line — there is no sparkline here, so the warning does not apply. The
   * field is in the payload if a later design wants it.
   */

  interface Props {
    metrics: ConditionsMetric[];
  }

  let { metrics }: Props = $props();

  /** `direction` is "up" | "down" | "flat"; the frame's copy for each. */
  function verb(direction: string): string {
    if (direction === 'up') return 'increasing';
    if (direction === 'down') return 'decreasing';
    return 'flat';
  }

  function tone(direction: string): 'up' | 'down' | 'flat' {
    return direction === 'up' ? 'up' : direction === 'down' ? 'down' : 'flat';
  }
</script>

<div class="conditions">
  {#each metrics as metric (metric.metric)}
    <div class="row">
      <span class="fill" data-direction={tone(metric.direction)}>
        <TrendIcon direction={tone(metric.direction)} />
      </span>

      <span class="body">
        <span class="headline">
          {metric.metric} in {metric.geography_label} are {verb(metric.direction)}
        </span>
        <span class="detail">
          {metric.value}% {metric.unit_label} compared to {metric.previous}% last week
        </span>
      </span>
    </div>
  {/each}
</div>

<style>
  .conditions {
    display: flex;
    flex-direction: column;
    width: 100%;
  }

  .row {
    display: flex;
    align-items: flex-start;
    gap: var(--space-300);
    padding: var(--space-300);
  }

  .fill {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--space-600);
    border-radius: var(--radius-sm);
  }

  .fill[data-direction='up'] {
    background: var(--color-trend-up-fill);
  }
  .fill[data-direction='down'] {
    background: var(--color-trend-down-fill);
  }
  .fill[data-direction='flat'] {
    background: var(--color-trend-flat-fill);
  }

  .body {
    flex: 1 0 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
  }

  .headline {
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }

  .detail {
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }
</style>
