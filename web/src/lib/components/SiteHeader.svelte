<script lang="ts">
  import { base } from '$app/paths';
  import About from './About.svelte';

  /**
   * "Queens Resource Map" on every page. Figma: `SiteHeader`, node 229:956.
   *
   * Full width on phones; the top of the 390px sidebar on desktop, so the
   * docked map keeps its full height (it lives in the root layout's first
   * column). The name sits 24px from the edge, in line with PageHeader titles.
   *
   * ONE h1 PER PAGE. On the entry page the site name IS the page's title, so
   * it is the h1 there, and the entry page has no PageHeader. Everywhere else
   * it is a link home and not a heading: the page's own title is its h1, and
   * two h1s would leave a screen reader's heading list with two "page titles".
   *
   * This <header> is the page's banner landmark. Page headers sit inside
   * <main> (root layout), which is what stops them being banners too.
   */

  interface Props {
    /** True on the entry page: the name is the h1, not a link to itself. */
    isHome: boolean;
  }

  let { isHome }: Props = $props();
</script>

<header class="site">
  {#if isHome}
    <h1 class="name">Queens Resource Map</h1>
  {:else}
    <a class="name" href="{base}/">Queens Resource Map</a>
  {/if}
  <About />
</header>

<style>
  .site {
    display: flex;
    align-items: center;
    /* The name at the left edge, About at the right. */
    justify-content: space-between;
    gap: var(--space-300);
    /* min-height, not height: with text enlarged (WCAG 1.4.4) the bar grows
       rather than clipping the name. */
    min-height: var(--site-header-height);
    box-sizing: border-box;
    /* No vertical padding: the 44px minimum centres the name. An 18px name's
       line box is ~22px, so Figma's 12px padding would make the bar ~47px and
       the phone map page, which subtracts 44, would scroll. */
    /* The 390px frame's spacing: name 24px in, About's right edge on the page
       buttons' (.screen's 16px gutter). Wider than 390px, the extra width is
       split evenly on both sides, as .screen's `margin-inline: auto` does, so
       both stay in line with the centred column below. 390px is .screen's
       max-width; % padding is of the header's container's width. */
    --frame-margin: max(0px, (100% - 390px) / 2);
    padding-inline: calc(var(--frame-margin) + var(--space-600)) calc(var(--frame-margin) + var(--gutter));
    background: var(--color-surface);
    border-bottom: 1px solid var(--color-border);
  }

  /* Frozen at the top while the page scrolls (Andrew, 2026-10-07), on windows
     tall enough to spare it: see FrozenHead for the 600px reasoning. Above
     FrozenHead, which sticks just below it. */
  @media (min-height: 600px) {
    .site {
      position: sticky;
      top: 0;
      z-index: 3;
    }
  }

  /* title/map-heading (Andrew, 2026-10-07): the page titles' style. */
  .name {
    margin: 0;
    font-size: var(--font-size-title);
    font-weight: var(--font-weight-title);
    letter-spacing: var(--letter-spacing-title);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    text-decoration: none;
    /* Optical centring, as in LocateButton: the font's line box puts the
       glyphs off-centre, so trim it to cap height and baseline. */
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .name {
      position: relative;
      top: 0.1em;
    }
  }
</style>
