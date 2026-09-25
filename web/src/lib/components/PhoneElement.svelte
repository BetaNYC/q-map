<script lang="ts">
  import type { HazardItem } from '$lib/types';

  /**
   * The Phone shape — a provider, its number, and optionally a TTY number.
   *
   * Figma: PhoneElement, node I61:744;40:146;61:754. Provider bold on the left,
   * number right-aligned, blue and underlined; TTY on a second row at 12px with
   * a grey "TTY" label.
   *
   * §10: TTY NUMBERS NEED A LABEL, "or a screen reader announces two phone
   * numbers with no way to tell them apart". The visible "TTY" text handles the
   * sighted case; the accessible names handle the rest. Each link carries
   * visually-hidden context so it reads as "Con Edison phone, 1-800-752-6633"
   * and "Con Edison TTY, 1-800-642-2308" rather than two bare numbers.
   *
   * The hidden text comes BEFORE the visible number so the accessible name
   * still contains the visible label, which WCAG 2.5.3 requires.
   *
   * DATA_CONTRACT.md §6 is blunt about these: `tel` and `tty` are the one thing
   * the link checker does not cover. The format is asserted (1-NXX-NXX-XXXX) so
   * a mangled number cannot ship, but a number that has changed hands will
   * pass. They are the least-verified content on the page.
   */

  interface Props {
    item: HazardItem;
  }

  let { item }: Props = $props();

  /** "1-800-752-6633" -> "tel:+18007526633". E.164, which every dialler takes. */
  function telHref(number: string): string {
    return `tel:+${number.replace(/\D/g, '')}`;
  }
</script>

<div class="phone-element">
  <div class="row">
    <p class="provider">{item.label}</p>
    <a class="number" href={telHref(item.tel ?? '')}>
      <span class="visually-hidden">{item.label} phone, </span>{item.tel}
    </a>
  </div>

  {#if item.tty}
    <div class="row tty">
      <p class="tty-label">TTY</p>
      <a class="number" href={telHref(item.tty)}>
        <span class="visually-hidden">{item.label} TTY, </span>{item.tty}
      </a>
    </div>
  {/if}
</div>

<style>
  .phone-element {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);

    /* Matches HazardElement, so the two carry the same rhythm and the same
       left edge inside a group. Without it a group of phones sat 24px apart
       while a group of links sat 48px apart and 12px further right — visible
       on Extreme Heat, where `utility-interruptions` and `cooling` are
       siblings. See NestedContainer's .slot. */
    padding-block: var(--space-300);
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-200);
    width: 100%;
    line-height: var(--line-height-tight);
  }

  .provider {
    margin: 0;
    font-weight: var(--font-weight-bold);
  }

  .tty {
    font-size: var(--font-size-small);
  }

  .tty-label {
    margin: 0;
    color: var(--color-text-secondary);
  }

  .number {
    color: var(--color-link);
    text-decoration: underline;
    white-space: nowrap;

    /* TARGET SIZE. These are inline links inside a labelled value, not list
     * rows — the 44px table in §10 covers Resource Row, LayerRow, CategoryRow
     * and HazardRow, all of which pass.
     *
     * WCAG 2.1 AA, which §10 names, has no target-size criterion. 2.2 added
     * 2.5.8 at 24px AA, with an explicit exception for targets "in a sentence
     * or block of text" — which these are. 44px is 2.5.5, AAA.
     *
     * Padded to clear 24px anyway, because a 14px phone link on a phone is
     * genuinely hard to hit. NOT to 44px: that needs +15px a side against an
     * 8px gap between lines, so adjacent targets would overlap — which 2.5.8
     * prohibits in the same breath. The negative margin keeps the layout. */
    display: inline-block;
    padding-block: 5px;
    margin-block: -5px;
  }
</style>
