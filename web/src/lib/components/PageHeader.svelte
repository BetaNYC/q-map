<script lang="ts">
  import { base } from '$app/paths';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import ArrowLeftIcon from '$lib/icons/ArrowLeftIcon.svelte';
  import ArrowRightIcon from '$lib/icons/ArrowRightIcon.svelte';

  /**
   * The one page header: district, hazard, map, resource and alerts screens.
   * Figma: `PageHeader`, node 226:95 (spec sheet beside it on 02 Components).
   *
   * It replaces DistrictHeader, HazardHeader and ResourceHeader, which had
   * drifted apart: titles at 16 or 24px from the screen edge, back links at 36
   * or 44, 0 to 12px of padding below (audit, 2026-10-07). One component means
   * one set of numbers. Placed inside a `.screen` padded 24/16:
   *
   *   title                     24px from the screen edge (8px in)
   *   secondary line, back link 28px (12px in: the 4px indent every header used)
   *   between rows              12px
   *   below the header          12px, then the page's rule
   *   top                       nothing: the screen's 24px sets it
   *
   * Entry has no page header. The site name is its title, in SiteHeader.
   */

  interface Props {
    title: string;
    /** The grey line under the title: the community district, the category,
     *  the alerts' scope and time. Always secondary: it is metadata. */
    secondary?: string;
    back?: {
      /** Site-relative, without `base`. */
      href: string;
      /** What the link shows. */
      label: string;
      /**
       * The accessible name, when the visible label alone does not say where
       * the link goes ("Back"). It must contain the visible label (WCAG 2.5.3),
       * so a voice user saying what they see still hits it.
       */
      name?: string;
    };
    /** Hazard pages on phones: the "See resources on the map" button, with the
     *  rule above it. Hidden on desktop, where the map is already beside the
     *  page. */
    mapHref?: string;
  }

  let { title, secondary, back, mapHref }: Props = $props();
</script>

<header class="header">
  <h1 class="title">{title}</h1>

  {#if secondary || back}
    <div class="body">
      {#if secondary}
        <p class="secondary">{secondary}</p>
      {/if}

      {#if back}
        <a class="back" href="{base}{back.href}" aria-label={back.name}>
          <ArrowLeftIcon />
          {back.label}
        </a>
      {/if}
    </div>
  {/if}

  {#if mapHref}
    <!-- `display: contents` on phones, so the rule and the button stay direct
         flex items of the header and its gaps are unchanged. A wrapper only so
         desktop can remove both together. The two run the full width, as the
         page's own rules do. -->
    <div class="map-link">
      <HorizontalRule />

      <!-- Figma: MapLink, full width. -->
      <a class="map-button" href={mapHref}>
        <span class="map-label">See resources on the map</span>
        <ArrowRightIcon />
      </a>
    </div>
  {/if}
</header>

<style>
  .header {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--space-300);
    padding-bottom: var(--space-300);
  }

  .title {
    margin: 0;
    padding-inline: var(--space-200);
    font-size: var(--font-size-title);
    font-weight: var(--font-weight-title);
    letter-spacing: var(--letter-spacing-title);
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  .body {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-300);
    padding-left: var(--space-300);
    padding-right: var(--space-200);
    font-size: var(--font-size-small);
  }

  .secondary {
    margin: 0;
    color: var(--color-text-secondary);
    line-height: var(--line-height-tight);
  }

  .back {
    display: flex;
    align-items: center;
    gap: var(--space-100);
    /* Black, not link blue: the frames draw back links as chrome rather than
       links into content. The arrow is the affordance. */
    color: var(--color-text-primary);
    text-decoration: none;
    line-height: var(--line-height-tight);
    /* A 44px target (§10) around a 12px line: padding grows the target, the
       negative margin gives the space back so the ink stays where the design
       puts it and the row pitch is unchanged. */
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
  }

  .map-link {
    display: contents;
  }

  /* Hidden on desktop (Andrew, 2026-10-07): the docked map is already beside
     the page, showing this hazard's layers (DOCKED_QUERY, $lib/mapView.ts). */
  @media (min-width: 1024px) {
    .map-link {
      display: none;
    }
  }

  /* MapLink: the outlined button shared with EntryPanel and LocateButton -
     sunken fill, 0.5px secondary outline, 3px radius, 12px padding, at least
     44px tall (WCAG 2.5.5). #0a0a0a on #f5f7f9 is 18.4:1. */
  .map-button {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-200);
    padding: var(--space-300);
    min-height: var(--touch-target-min);
    box-sizing: border-box;
    background: var(--color-surface-sunken);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    color: inherit;
    font-weight: var(--font-weight-bold);
    text-decoration: none;
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  /* Optical centring, as in EntryPanel - see the note there. */
  .map-label {
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .map-label {
      position: relative;
      top: 0.1em;
    }
  }
</style>
