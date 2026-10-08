<script lang="ts">
  import type { Snippet } from 'svelte';

  /**
   * The top of a page that stays put while the rest scrolls under it (Andrew,
   * 2026-10-07): PageHeader, and on the district page COAD; on hazard and
   * alerts pages the rule beneath the header too, as the frozen edge.
   * SiteHeader freezes above it on its own (top: 0); this block freezes just
   * below it.
   *
   * Phone and desktop alike: the window scrolls on both (the root layout keeps
   * it that way), so `position: sticky` against the viewport is all it takes.
   *
   * ONLY WHEN THE WINDOW IS AT LEAST 600px TALL. On a phone's district page the
   * frozen part is about a quarter of the screen. On a landscape phone, or at
   * 200% zoom and beyond (which shrinks the CSS viewport), it would be most of
   * it, and a reader could not see the content at all. WCAG 1.4.10 (Reflow) is
   * that failure. Below 600px everything scrolls as before.
   *
   * KEYBOARD FOCUS. Tabbing scrolls the focused link into view, and without
   * help it can land under a frozen header (WCAG 2.2, 2.4.11). The block
   * publishes its height, and app.css sets `scroll-padding-top` from it, so the
   * browser scrolls focused elements clear of the frozen region.
   */

  let { children }: { children: Snippet } = $props();

  let el = $state<HTMLDivElement>();

  $effect(() => {
    if (!el) return;
    const root = document.documentElement;
    const observer = new ResizeObserver(() => {
      root.style.setProperty('--frozen-head-height', `${el!.offsetHeight}px`);
    });
    observer.observe(el);
    return () => {
      observer.disconnect();
      root.style.removeProperty('--frozen-head-height');
    };
  });
</script>

<div class="frozen" bind:this={el}>
  {@render children()}
</div>

<style>
  /* Takes the parent .screen's place in the column: its gap between children,
     unchanged, so nothing moves while the page is at the top. */
  .frozen {
    display: flex;
    flex-direction: column;
    gap: inherit;
  }

  @media (min-height: 600px) {
    .frozen {
      position: sticky;
      top: var(--site-header-height);
      z-index: 2;
      background: var(--color-surface);

      /* Run under the screen's 24px top padding and 16px gutters, so the
         frozen block is opaque edge to edge and keeps the title 24px below
         the site header once it is stuck. */
      margin-top: calc(-1 * var(--space-600));
      padding-top: var(--space-600);
      margin-inline: calc(-1 * var(--gutter));
      padding-inline: var(--gutter);
    }
  }
</style>
