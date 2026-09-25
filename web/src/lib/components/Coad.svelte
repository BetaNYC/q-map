<script lang="ts">
  import InfoIcon from '$lib/icons/InfoIcon.svelte';
  import HorizontalRule from './HorizontalRule.svelte';
  import type { DistrictPayload } from '$lib/types';

  /**
   * The COAD notice. Figma: COAD, node 63:792 — a rule, an info mark beside a
   * sentence, and another rule.
   *
   * RENDERS IN 1 OF 14 DISTRICTS. `coad` and `coad_name` are null in the other
   * thirteen, and null is the common case rather than the edge (handoff §7.7).
   * The caller decides whether to mount this; it does not render an empty
   * notice.
   *
   * The sentence composes as `{display_name} is served by the {coad_name}`.
   * Figma's mock reads "Far Rockaway is served by…" while q14's display_name is
   * "The Rockaways" — the payload wins, per §7.7's stated composition.
   *
   * The info mark is aria-hidden: it decorates a sentence that already says
   * what it means, and as a text node it would be read out as the letter "i".
   */

  interface Props {
    district: DistrictPayload;
  }

  let { district }: Props = $props();
</script>

<aside class="coad">
  <HorizontalRule />

  <div class="row">
    <span class="mark"><InfoIcon /></span>
    <p class="sentence">
      {district.display_name} is served by the {district.coad_name}
    </p>
  </div>

  <HorizontalRule />
</aside>

<style>
  .coad {
    display: flex;
    flex-direction: column;
    padding-block: var(--space-100);
  }

  .row {
    display: flex;
    align-items: flex-start;
    gap: 10px; /* Figma's literal; the space scale has no 10 */
    padding: 10px;
  }

  /* The 24px box the icon sits in — bordered, 2px radius, matching the mark
     box on ResourceRow. The icon itself is 24px, so the border wraps it. */
  .mark {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 0.75px solid var(--color-text-primary);
    border-radius: var(--radius-sm);
  }

  .sentence {
    flex: 1 0 0;
    min-width: 0;
    margin: 0;
    /* Wraps to two lines at the 358px measure on every district that has one. */
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }
</style>
