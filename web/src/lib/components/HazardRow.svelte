<script lang="ts">
  import { base } from '$app/paths';
  import { measureLine, rankChip, severityFor } from '$lib/hazards';
  import type { Hazard } from '$lib/types';

  /**
   * WORKED EXAMPLE — the navigating row.
   *
   * Resource Row and CDTA Card are the same shape: an <a> that fills the row,
   * a fixed-width leading element, and a flexible body. Agree this one and the
   * rest follow without re-asking.
   *
   * Figma: HazardRow, node 14:1400 (ranked) and 14:1431 (pinned). One component
   * with a boolean, not two variants — the 48px and 62px instance heights in
   * Figma are content-driven, because a pinned row's reason wraps to two lines.
   *
   * Five things this establishes:
   *
   * 1. IT IS A LINK, NOT A BUTTON (handoff §10). Hazard rows navigate, so they
   *    need a real href — middle-click and open-in-new-tab have to work. The <a>
   *    wraps the whole row so the hit area is the row, not the label.
   *
   * 2. THE HIT AREA IS THE TOUCH TARGET. 12px padding top and bottom around a
   *    24px chip gives 48px, clearing WCAG 2.5.5's 44px minimum. The padding is
   *    on the <a>, so the target and the ink are the same rectangle rather than
   *    a small link floating in a tall row.
   *
   * 3. RANK IS IN THE ACCESSIBLE NAME. §10: the chips are numbered with
   *    coloured fills and the NUMBER carries the meaning. It is real text inside
   *    the link, so the accessible name reads "1 Coastal Storm Storm Surge Flood
   *    Vulnerability Index: 5/5" — colour is decoration on top of that, never
   *    the only channel.
   *
   * 4. THE CHIP HAS THREE STATES, NOT TWO. Ranked and scored shows the number
   *    and is announced. Pinned is an empty coloured box — decoration, so
   *    aria-hidden, with `reason` carrying the meaning. Ranked but scoring 0
   *    shows "-" in the pinned grey and is also hidden: the hazard holds a
   *    ranked position but does not apply here. rankChip() in $lib/hazards owns
   *    that decision so the markup stays one branch.
   *
   * 5. SCORE IS TEXT, NOT A SCALE. §10 again. measureLine() builds it, reading
   *    "4 out of 5" rather than "4/5" — a solidus is announced as "slash" — and
   *    swapping in the score-0 copy where a number would mislead.
   */

  interface Props {
    hazard: Hazard;
    /** The stored district slug, e.g. "q14" — never derived from cdta2020. */
    districtSlug: string;
  }

  let { hazard, districtSlug }: Props = $props();

  // $derived rather than computing in the markup: each value is read once and
  // the template stays declarative.
  const severity = $derived(severityFor(hazard));
  const measure = $derived(measureLine(hazard));
  const chip = $derived(rankChip(hazard));
</script>

<a class="row" href="{base}/{districtSlug}/{hazard.slug}">
  <span class="chip" data-severity={severity} aria-hidden={chip.decorative ? 'true' : undefined}>
    {#if chip.text}{chip.text}{/if}
  </span>

  <span class="body">
    <span class="label">{hazard.label}</span>
    <span class="measure">{measure}</span>
  </span>
</a>

<style>
  .row {
    display: flex;
    align-items: flex-start;
    gap: var(--space-300);

    /* 12px + the 24px chip + 12px = 48px, over the 44px minimum. */
    padding-block: var(--space-300);

    /* The row is a link but is not styled as one — the label carries no
     * underline in the design and the whole row is the affordance. */
    color: inherit;
    text-decoration: none;
  }

  .chip {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--space-600);
    height: var(--space-600);
    border-radius: var(--radius-sm);

    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  /* Fill by rank position. Kept in CSS rather than built as a style string in
   * the component, so every colour still comes from the token file. */
  .chip[data-severity='extreme'] {
    background: var(--color-severity-extreme-fill);
  }
  .chip[data-severity='severe'] {
    background: var(--color-severity-severe-fill);
  }
  .chip[data-severity='moderate'] {
    background: var(--color-severity-moderate-fill);
  }
  .chip[data-severity='minor'] {
    background: var(--color-severity-minor-fill);
  }

  .body {
    flex: 1 0 0;
    min-width: 0; /* or a long unbroken label refuses to wrap and overflows */
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
  }

  .label {
    line-height: var(--line-height-tight);
  }

  .measure {
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);

    /* Prose, not tight: a pinned row's reason wraps to two lines. This is the
     * one place the row departs from Figma, which sets every text node to
     * line-height: normal — see web/README.md. */
    line-height: var(--line-height-prose);
  }
</style>
