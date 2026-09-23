<script lang="ts">
  import { categoryInitial } from '$lib/categories';
  import type { ResourceCategory } from '$lib/types';

  /**
   * WORKED EXAMPLE — the toggling row. LayerRow is the same shape and follows
   * from this one.
   *
   * Figma: "Resource Row", node I68:1103;68:1048;68:1115. The name is a
   * misnomer worth knowing about before reading it: it renders a resource
   * CATEGORY and its count, not an individual resource. Every instance in the
   * map sheet is a category — "Children and youth 261", "Libraries and
   * community 69", "Parks and environment 65". Kept under the Figma name so the
   * design and the code still grep to each other.
   *
   * It is the same classification CategoryRow shows on the district screen, in
   * the sheet's visual language: 12px bold, an outlined initial box, no fill.
   *
   * HOW IT DIFFERS FROM THE NAVIGATING ROWS (HazardRow, CategoryRow, CdtaCard):
   *
   *   It is a <button aria-pressed>, not an <a href>. It does not go anywhere —
   *   it turns its category on and off on the map already on screen. §10 is
   *   explicit that layer and category rows are toggles and that real ARIA is
   *   mandatory, because the on/off cue is visual only.
   *
   *   State is owned by the page, not by this component. The map screen holds
   *   the selection because the selection lives in the URL (?categories=), and
   *   a row that toggled itself locally would immediately disagree with a
   *   shared link. This takes `pressed` and calls `onToggle`.
   *
   * THE MARK IS TEXT, NOT AN ICON. Figma renders a one- or two-letter mark in
   * NewComputerModernMono10 BookItalic inside a 16px outlined box — "c" for
   * Children and youth, "l" for Libraries, "hc" for Health care, "s" for
   * Housing and shelter. Mostly the label's first letter but not always, so
   * $lib/categories owns the rule; the build asserts all twelve stay distinct.
   * Decorative, so aria-hidden — the label is right beside it.
   *
   * THE OFF STATE IS WEIGHT AND COLOUR, from Figma's boolean visibility
   * property: the whole row drops from bold to regular and from
   * --color-text-primary to --color-text-secondary. Neither channel is
   * programmatically detectable, which is exactly why §10 makes aria-pressed
   * mandatory here rather than optional.
   */

  interface Props {
    category: ResourceCategory;
    /** Whether this category is currently showing on the map. */
    pressed: boolean;
    onToggle: (slug: string) => void;
  }

  let { category, pressed, onToggle }: Props = $props();

  const mark = $derived(categoryInitial(category));
</script>

<button type="button" class="row" aria-pressed={pressed} onclick={() => onToggle(category.slug)}>
  <span class="mark" aria-hidden="true">{mark}</span>

  <span class="label">{category.label}</span>

  <span class="count">
    {category.count}
    <!-- Same reason as CategoryRow: the accessible name would otherwise end in
         a bare number that means nothing read aloud. -->
    <span class="visually-hidden">resources</span>
  </span>
</button>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 10px; /* Figma's literal; the space scale has no 10 */
    width: 100%;

    /* 16px + the 16px initial box + 16px = 48px, over the 44px minimum. */
    padding-block: var(--space-400);
    padding-inline: 0;

    /* A <button> brings its own chrome. Strip it back to the row the design
     * draws, but keep the element, because the element is what carries the
     * pressed state to assistive technology. */
    background: none;
    border: 0;
    text-align: left;
    font: inherit;
    color: var(--color-text-primary);
    cursor: pointer;

    font-size: var(--font-size-small);

    /* ON: bold, primary. Figma's AUTHENTIC Sans Pro 130 at #0a0a0a. */
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  /* OFF: regular weight, secondary colour, applied to the whole row — label,
   * count, mark and the mark's border together. Figma expresses this as a
   * boolean visibility property swapping the row's text styles; the effect is
   * 611 -> 433 and #0a0a0a -> #707070.
   *
   * currentColor on the border means one declaration moves all four.
   *
   * #707070 measures 4.84:1 on --color-surface, which passes AA for text under
   * 24px. It is thinner than the palette was checked at, and it will not hold
   * where the sheet is translucent over map imagery — Andrew is addressing that
   * separately. Figma's behaviour is kept as-is here on purpose. */
  .row[aria-pressed='false'] {
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

  .label {
    flex: 1 0 0;
    min-width: 0;
    overflow-wrap: break-word;
  }

  .count {
    flex-shrink: 0;
    text-align: right;
  }
</style>
