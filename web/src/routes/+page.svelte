<script lang="ts">
  import CdtaCard from '$lib/components/CdtaCard.svelte';

  let { data } = $props();
</script>

<!-- SCAFFOLD ONLY. The entry screen — alert banner, map picker, address input,
     14 CDTA cards — is built in step 5 from the Figma frames. What is here
     exists to prove the data path end to end and to give the prerenderer links
     to crawl. No layout is being invented. -->

<h1>Queens Resource Map</h1>
<p>{data.queens.length} Queens districts of {data.all.length} citywide.</p>

<!-- The entry screen proper — header, alert banner, map picker, address input —
     is step 5. The card list is here so CdtaCard is exercised against all 14
     real districts. -->
<ul class="cards">
  {#each data.queens as district (district.slug)}
    <li><CdtaCard {district} /></li>
  {/each}
</ul>

<style>
  .cards {
    list-style: none;
    margin: 0;
    padding: 0;

    /* Figma spaces the cards 12px apart (pitch 64 on a 52px card). */
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
  }
</style>
