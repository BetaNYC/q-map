<script lang="ts">
  import CdtaCard from '$lib/components/CdtaCard.svelte';
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

     AlertBanner      Never renders in v1 (§7.7). Its boolean is always false,
                      there is no endpoint, and the Notify NYC poller is
                      unbuilt. §7.7 is explicit that no layout space should be
                      reserved for it, so there is no placeholder either.
                      ALERTS_SERVICE.md is the brief for when it lands.

     Map picker       358x350 in the frame, and named "MapPlaceholder" there
                      too. It needs MapLibre, cdta.geojson and the PMTiles
                      protocol — build step 8.

     Address input    Both belong to the same half of this screen: finding your
     "Use my location" district by LOCATION rather than by name. The address
                      field needs a geocoder, which nothing in the pipeline or
                      the contract provides; the button needs the Geolocation
                      API plus point-in-polygon against cdta.geojson, which
                      arrives with the map.

     What is left works: the 14 cards are a complete picker on their own. Three
     dead controls above them would promise something the build cannot do yet,
     which is worse than a shorter screen. See web/README.md. -->
<div class="screen">
  <EntryHeader />

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
