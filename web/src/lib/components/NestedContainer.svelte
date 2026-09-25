<script lang="ts">
  import type { Snippet } from 'svelte';

  /**
   * The Group shape — a label above its children, with a vertical rule down the
   * left of the nested block.
   *
   * Figma: NestedContainer, node 61:676. 12px padding; label and body 16px
   * apart; a 21px gutter carrying a right border in `border/default`, then the
   * children 8px further in, spaced 24px.
   *
   * NESTS ONE LEVEL ONLY (DATA_CONTRACT.md §6). The pipeline rejects deeper
   * nesting, so this takes a snippet rather than recursing on itself — the
   * caller decides what goes inside, and the one-level rule stays enforced
   * upstream where it belongs rather than being re-implemented here as a depth
   * counter.
   *
   * The rule is decorative: the indent and the label already convey grouping,
   * and the border colour is 1.35:1 against the page, well below anything that
   * could be carrying meaning. The group's semantics come from the caller
   * wrapping children in a list.
   */

  interface Props {
    label: string;
    children: Snippet;
  }

  let { label, children }: Props = $props();
</script>

<div class="container">
  <p class="label">{label}</p>

  <div class="body">
    <div class="rule" aria-hidden="true"></div>
    <div class="slot">
      {@render children()}
    </div>
  </div>
</div>

<style>
  .container {
    display: flex;
    flex-direction: column;
    gap: var(--space-400);

    /* VERTICAL ONLY, like the elements it holds. The frames are consistent
       about who owns the horizontal inset: whatever sits directly on the page
       supplies 12px, and nothing nested inside repeats it. This same component
       is drawn `p-12px` at page level (61:638) and `py` only inside a Section
       (58:413) — one rule, two contexts. The route's .untitled and Section
       supply the 12px, so a group label and a bare element beside it line up. */
    padding-block: var(--space-300);
  }

  .label {
    margin: 0;
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  .body {
    display: flex;
    align-items: stretch;
    width: 100%;
  }

  .rule {
    flex-shrink: 0;
    width: 21px;
    /* The line sits on the RIGHT edge of a 21px gutter, so the rule is 21px
       from the container edge and the children start 8px past it. */
    border-right: 1px solid var(--color-border);
  }

  .slot {
    display: flex;
    flex: 1 0 0;
    min-width: 0;
    flex-direction: column;

    /* NO GAP, and the frame's 24px is still what renders. The children pad
       themselves 12px top and bottom, so consecutive items sit 12 + 12 = 24px
       apart — the same arithmetic .items on the route already relies on.
       Setting the gap here as well as the padding is what produced 48px. */
    padding-left: var(--space-200);
  }
</style>
