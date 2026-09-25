<script lang="ts">
  import { fallbackNote, interpolate } from '$lib/gaps';
  import type { DisplayedGap } from '$lib/types';

  /**
   * One derived "resource gap" finding, on the district screen. Exactly three
   * per district, one per ranked hazard.
   *
   * Figma: GapSentence, node 15:1687 — a single 14px paragraph at the full
   * 336px measure, wrapping freely.
   *
   * THE COMPONENT HAS NO COPY IN IT, AND THAT IS THE POINT.
   *
   * The pipeline emits `sentence_template` and `facts`; this interpolates and
   * renders. Where a gap found nothing, or an estimate is unreliable, the
   * pipeline has ALREADY swapped in different wording — "None of ... sit in an
   * area that floods" instead of "0% of ...", and a hedged phrasing where a
   * language estimate has a coefficient of variation above 30.
   *
   * So there is no branch on `value` here, no zero check, no pluralisation
   * logic. A frontend that added one would double up on a decision already made
   * upstream with more information than it has. §7.2.
   *
   * This is also why it takes the whole gap rather than a pre-rendered string:
   * the interpolation is the component's job, and keeping it here means one
   * place knows that `{district}` comes from `facts` and not from the payload
   * root.
   */

  interface Props {
    gap: DisplayedGap;
  }

  let { gap }: Props = $props();

  const sentence = $derived(interpolate(gap.sentence_template, gap.facts));
  const note = $derived(fallbackNote(gap));
</script>

<div class="gap">
  <p class="sentence">{sentence}</p>

  {#if note}
    <!-- Only on a cross-cutting gap filling a ranked hazard's empty slot.
         Absent on all 42 sentences today, so this has never rendered against
         real data — see $lib/gaps. Without it the sentence silently appears to
         be about a hazard it does not measure. -->
    <p class="note">{note}</p>
  {/if}
</div>

<style>
  .gap {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
  }

  .sentence {
    margin: 0;

    /* Prose, not tight. Every one of the 42 wraps to two or three lines at the
     * 358px measure — this is the longest-running text in the app. */
    line-height: var(--line-height-prose);

    /* Figma sets word-break: break-word on the frame. Long place names and
     * "(incl. Filipino)" style parentheticals are what it is for. */
    overflow-wrap: break-word;
  }

  .note {
    margin: 0;
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);
    line-height: var(--line-height-prose);
  }
</style>
