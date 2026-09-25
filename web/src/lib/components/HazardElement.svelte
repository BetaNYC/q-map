<script lang="ts">
  import type { HazardItem } from '$lib/types';

  /**
   * The Link and Note shapes — a heading, optionally a destination name beside
   * it, and an optional sentence of context beneath.
   *
   * Figma: HazardElement, node 61:738 and the instances inside NestedContainer
   * 61:676. 12px padding, heading and body 12px apart, the destination name
   * right-aligned in a wrapping row.
   *
   * THE WHOLE ELEMENT IS THE ANCHOR, not just the blue text. In the frame only
   * the destination name is styled as a link, which at 14px is about a 17px
   * tap target — under the 44px every row component in this app was just fixed
   * to. Wrapping the block makes the target the whole element and the
   * accessible name the heading plus the destination:
   *
   *     "Get personalized flood guidance, Blue Dots"
   *
   * The body stays inside the anchor too. It is context for the same
   * destination, and excluding it would leave a dead strip inside an otherwise
   * tappable block.
   *
   * `label` is the heading for every shape — a note's, a link's, a group's, a
   * phone's provider — so the key never means two things. `link_label` is the
   * optional second string. An item with `url` and no `link_label` renders the
   * heading as the link, which is what the twenty items authored before the
   * field existed still do.
   *
   * A Note is the same stack without the anchor, which is why one component
   * covers both shapes.
   */

  interface Props {
    item: HazardItem;
  }

  let { item }: Props = $props();
</script>

{#snippet content()}
  <span class="header">
    <span class="label">{item.label}</span>
    {#if item.link_label}
      <span class="link-label">{item.link_label}</span>
    {/if}
  </span>

  {#if item.body}
    <span class="body">{item.body}</span>
  {/if}
{/snippet}

{#if item.url}
  <!-- External, and opened in place: this is emergency guidance, and a
       surprise new tab is worse than a back button. -->
  <a class="element is-link" href={item.url}>{@render content()}</a>
{:else}
  <div class="element">{@render content()}</div>
{/if}

<style>
  .element {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);

    /* VERTICAL ONLY. The frame gives this element no padding at all and spaces
       instances with a 24px gap on the parent; the padding here is doing two
       jobs the frame does not have to think about — it is what keeps a
       header-only element (one 14px line, ~17px) above the 44px minimum, and
       12 + 12 between neighbours reproduces that 24px gap without a second
       source of spacing.

       Horizontal padding was the part with no justification: it inset every
       element 12px further right than drawn, and by a different amount than
       PhoneElement, which had none. The anchor still fills the full width, so
       the hit area is unchanged. */
    padding-block: var(--space-300);
  }

  .is-link {
    color: inherit;
    text-decoration: none;
  }

  .header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;

    /* 12px between rows, 20px between label and link. The 20px is the frame's
       "min-gap spacer" (60:88) — a 20x5px invisible node sitting between the
       two text nodes, which is how Figma writes a minimum column gap. It is a
       gap, not an element, so it is not transcribed as one.

       The wrap is kept for every variant. 40:134 draws a non-wrapping header,
       but its label and link are both `white-space: nowrap`, so a long pair
       would overflow the 358px measure rather than break. Wrapping is the safe
       reading of the same intent, and `overflow-wrap: break-word` below is
       kept over the frame's nowrap for the same reason.

       Figma's `min-width: 220px` on this row is not carried: it exists to make
       the frame wrap at the right point, which flex-wrap does on its own. */
    gap: var(--space-300) 20px;
    width: 100%;
  }

  .label {
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  /* Blue and underlined even though the anchor is the whole block: it is the
   * only cue naming where the block goes, and the heading beside it is bold
   * black. Colour alone would not be enough, hence the underline. */
  .link-label {
    color: var(--color-link);
    text-decoration: underline;
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  .body {
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }

  /* The whole block is interactive, so it needs a hover and focus treatment of
   * its own — a link whose text is not underlined gives no other signal. */
  .is-link:hover .link-label {
    text-decoration-thickness: 2px;
  }
</style>
