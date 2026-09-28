<script lang="ts">
  import { browser } from '$app/environment';
  import CdtaCard from '$lib/components/CdtaCard.svelte';
  import DistrictPicker from '$lib/components/DistrictPicker.svelte';
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

<!-- Screen 01. Figma: "01 Entry - Mobile", node 86:1910.

     THREE OF THE FRAME'S ELEMENTS ARE NOT HERE, and the omissions are
     deliberate rather than unfinished:

     AlertBanner      Awaiting design. The endpoint exists and
                      $lib/alerts.ts reads it into three states; the component
                      that renders them does not. §7.7 still holds: no layout
                      space is reserved, so there is no placeholder.

     Address input    Both belong to the same half of this screen: finding your
     "Use my location" district by LOCATION rather than by name. The address
                      field needs a geocoder, which nothing in the pipeline or
                      the contract provides; the button needs the Geolocation
                      API plus point-in-polygon against cdta.geojson, which
                      arrives with the map.

     The map picker IS built — it needed nothing the address field and the
     location button need. The 14 cards remain the accessible picker; the map
     is a decorative shortcut to the same destinations. See web/README.md. -->
<div class="screen">
  <EntryHeader />

  <!-- Client-only: MapLibre needs a DOM and a WebGL context, and a
       prerendered page has neither. The cards below render regardless, so the
       screen is complete without JS. -->
  {#if browser}
    <DistrictPicker districts={data.all} />
  {/if}

  <!-- districts.json covers all 59 CDTAs citywide; only the Queens 14 have
       pages, so the load filters on `boro` rather than on a slug prefix. -->
  <ul class="cards">
    {#each data.queens as district (district.slug)}
      <li><CdtaCard {district} /></li>
    {/each}
  </ul>
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-600);

    /* §3: 390px baseline, 16px gutters, 358px measure. */
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
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
