<script lang="ts">
  import { base } from '$app/paths';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import ArrowLeftIcon from '$lib/icons/ArrowLeftIcon.svelte';
  import ArrowRightIcon from '$lib/icons/ArrowRightIcon.svelte';

  /**
   * The hazard screen's header. Figma: HazardHeader, nodes 40:204 and 58:404 —
   * the hazard label at 18px, a back link to the district, a rule, and the map
   * button.
   *
   * ResourceHeader without the category line. Both back links are a property
   * of the route rather than history.back(), for the same reason: a shared
   * link has no history to go back to.
   *
   * IT OWNS THE MAP BUTTON NOW. The button used to be a sibling on the route,
   * carrying a comment reading "UNDESIGNED: neither hazard frame draws this
   * button" — it borrowed screen 01's dark Location control for want of
   * anything to copy. The 2026-09-25 revision draws it in both frames, inside
   * this component, below a rule, as screen 01's sunken CDTA Card instead. The
   * open question is closed; the styling below is the answer.
   *
   * RESTYLED IN CYCLE 2, STEP 7 to Figma's MapLink (node 185:47): the outlined
   * button of the entry page's panels, full width, with an arrow — it goes to
   * another page rather than opening anything, so not the panels' chevron.
   */

  interface Props {
    label: string;
    districtSlug: string;
    districtName: string;
    /**
     * Already absolute (base applied) — built by the route from map_layers.
     *
     * OPTIONAL, because the map screen renders this same header and is already
     * the map. Omitted, the rule and the button both go with it and the header
     * is a title over a back link, which is what screen 04 draws.
     */
    mapHref?: string;
  }

  let { label, districtSlug, districtName, mapHref }: Props = $props();
</script>

<header class="header">
  <h1 class="label">{label}</h1>

  <div class="body">
    <a class="back" href="{base}/{districtSlug}">
      <ArrowLeftIcon />
      {districtName}
    </a>
  </div>

  {#if mapHref}
    <HorizontalRule />

    <!-- Figma: MapLink, full width (it replaced the 10px-inset frame). -->
    <a class="map-button" href={mapHref}>
      <span class="map-label">See resources on the map</span>
      <ArrowRightIcon />
    </a>
  {/if}
</header>

<style>
  .header {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--space-300);

    /* NO horizontal inset, unlike DistrictHeader's 8px. The frame hands that
       job to the children instead — the back link insets itself 4px, the map
       frame 10px — and runs the rule the full width.

       This is also what keeps the rules on a hazard page in one line: the
       header's rule and the route's section rules both end up 26px from the
       viewport edge (16px screen gutter + HorizontalRule's own 10px). Keeping
       the 8px would push the header's to 34px and put two rules on the same
       page at different insets.

       Consequences: the hazard <h1> sits 8px left of the district and resource
       <h1>s, and screen 04's header moves with it, since the map screen
       renders this same component. Revert by restoring `padding-inline:
       var(--space-200)` here. */
    padding-bottom: var(--space-300);
  }

  .label {
    margin: 0;
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
    padding-left: var(--space-100);
    font-size: var(--font-size-small);
  }

  .back {
    display: flex;
    align-items: center;
    gap: var(--space-100);
    color: var(--color-text-primary);
    text-decoration: none;
    line-height: var(--line-height-tight);
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
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
