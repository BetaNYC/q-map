<script lang="ts">
  import { browser } from '$app/environment';
  import { base } from '$app/paths';
  import AddressSearch from '$lib/components/AddressSearch.svelte';
  import AlertBanner from '$lib/components/AlertBanner.svelte';
  import CdtaCard from '$lib/components/CdtaCard.svelte';
  import DistrictPicker from '$lib/components/DistrictPicker.svelte';
  import EntryPanel from '$lib/components/EntryPanel.svelte';
  import LocateButton from '$lib/components/LocateButton.svelte';
  import { DOCKED_QUERY } from '$lib/mapView';
  import { MediaQuery } from 'svelte/reactivity';

  let { data } = $props();

  /**
   * Desktop (Andrew, 2026-10-07): the docked map is beside the page, so the
   * "Select on map" panel is hidden, and its DistrictPicker is not mounted.
   *
   * "Choose Community District" is collapsed by default on every width
   * (Andrew, 2026-10-14). It used to open itself on desktop, which also needed
   * the map panel's `open` to be the opposite of `docked` so the two exclusive
   * panels did not fight. With the list closed everywhere, the map panel is
   * simply open by default, as the phone frames draw it.
   */
  const docked = new MediaQuery(DOCKED_QUERY, false);
</script>

<svelte:head>
  <title>Queens Readiness Resources</title>
  <meta
    name="description"
    content="Emergency preparedness for the 14 Queens community districts: hazards, local resources and where the gaps are."
  />
</svelte:head>

<!-- Screen 01. Figma: "01 Entry - Mobile/NoAlert (revised)" (map open, the
     default), ".../Neighborhoods open", ".../Both closed", and the
     OneAlert / TwoAlert / GreaterThanTwoAlerts (revised) banner variants.

     Order: banner, about, General Resources, then "View neighborhood
     resources" over the address field, "Use my location" and the two panels.
     The site name above all of it is SiteHeader. The panels are one exclusive
     accordion (EntryPanel): opening one closes the other, the map is open by
     default on phones (hidden on desktop), and both may be closed.

     The address field (step 4) and "Use my location" (step 3) come first:
     finding a district by where you are, before choosing it by name. -->
<div class="screen">
  <!-- Renders only while an alert is active; nothing, and no reserved space,
       otherwise (§7.7). Reads the visit's AlertsStore from the root layout. -->
  <AlertBanner />

  <p class="about">
    Queens has resources to help you prepare and find support. Explore the hazards your neighborhood faces and local resources you can access to prepare, respond, or recover. 
    You can start small and make a plan that fits your household, or find help now if something is happening. <br><br>
    The Queens Resource Map (Q-Map) is a tool created by the NYC Preparedness and Recovery Institute (<a href="https://pandemicresponse.columbia.edu/" rel="noopener noreferrer">PRI</a>) in collaboration with <a href="https://beta.nyc" rel="noopener noreferrer">BetaNYC</a>. 
    It is designed to provide a dynamic, community-informed platform connecting residents and community-based organizations to critical resources before, during, and after emergencies. 
  </p>

  <!-- General Resources (/general): steps for any emergency and where to get
       help. Drawn as the "Use my location" control is (Figma: Location), but
       a link, not a button: it goes to a page rather than doing something
       here, and a screen reader should announce it as a link. -->
  <a class="general-link" href="{base}/general">
    <span class="label">General Resources</span>
  </a>

  <!-- The ways to reach a district page, under one heading (Andrew,
       2026-10-14) so they read as a group and apart from General Resources
       above. An h2: SiteHeader's site name is this page's h1. -->
  <section class="neighborhood" aria-labelledby="neighborhood-heading">
    <h2 id="neighborhood-heading" class="section-heading">View Queens neighborhood resources</h2>

    <!-- Both go straight to the district they find, and say why when they
         can't. The address field uses NYC GeoSearch; neither renders without
         JavaScript, and the panels below always work. -->
    <AddressSearch districts={data.all} />
    <LocateButton districts={data.all} />

    <EntryPanel name="entry-view" label="Choose Community District">
      <!-- districts.json covers all 59 CDTAs citywide; only the Queens 14 have
           pages, so the load filters on `boro` rather than on a slug prefix. -->
      <ul class="cards">
        {#each data.queens as district (district.slug)}
          <li><CdtaCard {district} /></li>
        {/each}
      </ul>
    </EntryPanel>

    <!-- Hidden on desktop by CSS, so it is gone at first paint rather than
         when JS arrives. The picker is not mounted there either: the docked map
         does its job, and a second MapLibre in a hidden panel would still cost
         a WebGL context. -->
    <div class="picker-panel">
      <EntryPanel name="entry-view" label="Select on map" open>
        <!-- Client-only: MapLibre needs a DOM and a WebGL context, and a
             prerendered page has neither. Without JavaScript the panel says so and
             points at the list, which works without it. -->
        {#if browser && !docked.current}
          <DistrictPicker districts={data.all} />
        {:else}
          <p class="fallback">The map needs JavaScript. Choose your district from the list above.</p>
        {/if}
      </EntryPanel>
    </div>
  </section>
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-300); /* the revised frame's 12 */

    /* §3: 390px baseline, 16px gutters, 358px measure. */
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  /* DOCKED_QUERY, $lib/mapView.ts. */
  @media (min-width: 1024px) {
    .picker-panel {
      display: none;
    }
  }

  /* LocateButton's outlined button, as a link: sunken fill, 0.5px secondary
     outline, 3px radius, 12px padding, at least 44px tall (WCAG 2.5.5). */
  .general-link {
    display: flex;
    align-items: center;
    min-height: var(--touch-target-min);
    padding: var(--space-300);
    box-sizing: border-box;
    background: var(--color-surface-sunken);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    color: var(--color-text-primary);
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    text-decoration: none;
  }

  /* Optical centring, as in EntryPanel and LocateButton - see the note there. */
  .general-link .label {
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .general-link .label {
      position: relative;
      top: 0.1em;
    }
  }

  /* Same 12px rhythm as .screen, so wrapping the controls moved nothing. */
  .neighborhood {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    /* A step more space above the heading than between the controls, so it
       reads as heading what follows rather than closing what came before. */
    margin-top: var(--space-300);
  }

  /* title/section, as Section's titles ("Hazard Areas"), inset 8px to line up
     with the about text above. */
  .section-heading {
    margin: 0;
    padding-inline: var(--space-200);
    font-size: var(--font-size-section);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .about {
    margin: 0;
    padding-inline: var(--space-200);
    font-size: var(--font-size-body);
    line-height: var(--line-height-prose);
  }

  .fallback {
    margin: 0;
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);
  }

  .cards {
    list-style: none;
    margin: 0;
    padding: 0;

    /* Figma spaces the cards 12px apart — pitch 64 on a 52px card. */
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
  }
</style>
