<script lang="ts">
  import { browser } from '$app/environment';
  import AlertBanner from '$lib/components/AlertBanner.svelte';
  import CdtaCard from '$lib/components/CdtaCard.svelte';
  import DistrictPicker from '$lib/components/DistrictPicker.svelte';
  import EntryPanel from '$lib/components/EntryPanel.svelte';
  import EntryHeader from '$lib/components/EntryHeader.svelte';

  let { data } = $props();
</script>

<svelte:head>
  <title>Queens Resource Map</title>
  <meta
    name="description"
    content="Emergency preparedness for the 14 Queens community districts: hazards, local resources and where the gaps are."
  />
</svelte:head>

<!-- Screen 01. Figma: "01 Entry - Mobile/NoAlert (revised)" (map open, the
     default), ".../Neighborhoods open", ".../Both closed", and the
     OneAlert / TwoAlert / GreaterThanTwoAlerts (revised) banner variants.

     Order: header, banner, about, then the two panels. The panels are one
     exclusive accordion (EntryPanel): opening one closes the other, the map is
     open by default, and both may be closed.

     NOT HERE YET: the address field (FRONTEND_PLAN.md step 4, the geocoder) and
     "Use my location" (step 3). They arrive when they work, rather than as
     disabled controls in the meantime. -->
<div class="screen">
  <EntryHeader />

  <!-- Renders only while an alert is active; nothing, and no reserved space,
       otherwise (§7.7). Reads the visit's AlertsStore from the root layout. -->
  <AlertBanner />

  <p class="about">
    Lorem ipsum dolor sit amet, consectetur adipiscing elit,
    sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
    quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
  </p>

  <EntryPanel name="entry-view" label="Choose Community District">
    <!-- districts.json covers all 59 CDTAs citywide; only the Queens 14 have
         pages, so the load filters on `boro` rather than on a slug prefix. -->
    <ul class="cards">
      {#each data.queens as district (district.slug)}
        <li><CdtaCard {district} /></li>
      {/each}
    </ul>
  </EntryPanel>

  <EntryPanel name="entry-view" label="Select on map" open>
    <!-- Client-only: MapLibre needs a DOM and a WebGL context, and a
         prerendered page has neither. Without JavaScript the panel says so and
         points at the list, which works without it. -->
    {#if browser}
      <DistrictPicker districts={data.all} />
    {:else}
      <p class="fallback">The map needs JavaScript. Choose your district from the list above.</p>
    {/if}
  </EntryPanel>
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
