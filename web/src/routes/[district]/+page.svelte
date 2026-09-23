<script lang="ts">
  import { base } from '$app/paths';
  import CategoryRow from '$lib/components/CategoryRow.svelte';
  import GapSentence from '$lib/components/GapSentence.svelte';
  import HazardRow from '$lib/components/HazardRow.svelte';
  import InfoIcon from '$lib/icons/InfoIcon.svelte';

  let { data } = $props();
</script>

<!-- SCAFFOLD ONLY. The district screen — hazard rows, resource categories, gap
     sentences — is built in step 5. -->

<p><a href="{base}/">All districts</a></p>

<!-- display_name and cd_label are both shipped and both rendered; neither is
     derivable from the other (handoff §2). -->
<h1>{data.district.display_name}</h1>
<p>{data.district.cd_label} · {data.district.cdta2020}</p>

{#if data.district.coad_name}
  <!-- Renders in 1 of 14 districts. null is the common case, not the edge.
       The real COAD component is built in step 5; the icon sits here now so it
       is exercised on a real page rather than shipped unrendered. It is
       aria-hidden, so the sentence reads on its own. -->
  <p>
    <InfoIcon />
    {data.district.display_name} is served by the {data.district.coad_name}
  </p>
{/if}

<!-- The Hazards section proper — header, spacing, the HorizontalBreak — is
     step 5. The list is here now so HazardRow is exercised against all 8 real
     entries, ranked and pinned, rather than a mock.

     A <ul> because it is a list of 8 and a screen reader should say so.
     `rank` is the key AND the order: hazards[] arrives already ordered and
     §7.1 is explicit that re-sorting on score would silently reorder the ties,
     which 8 of 14 districts have. -->
<ul class="hazards">
  {#each data.district.hazards as hazard (hazard.slug)}
    <li>
      <HazardRow {hazard} districtSlug={data.district.slug} />
    </li>
  {/each}
</ul>

<!-- The ResourceMap section proper is step 5. The list is here so CategoryRow
     is exercised against every category a real district holds — the count is
     derived per district and q14's runs from 1 to 261. -->
<ul class="categories">
  {#each data.district.resource_categories as category (category.slug)}
    <li><CategoryRow {category} districtSlug={data.district.slug} /></li>
  {/each}
</ul>

<!-- The ResourceGap section proper is step 5. Exactly three per district, one
     per ranked hazard, already ordered by risk_rank. -->
<ul class="gaps">
  {#each data.district.gaps_displayed as gap (gap.gap_id)}
    <li><GapSentence {gap} /></li>
  {/each}
</ul>

<style>
  .hazards,
  .categories,
  .gaps {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  /* Figma spaces CategoryRow instances 8px apart (pitch 54.67 on a 46.67 row).
     HazardRow rows butt together, so only this list needs the gap. */
  .categories {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  /* Figma spaces GapSentence instances ~24px apart (pitch 69 on a 45px
     two-line sentence, 52 on a 28px one-liner). */
  .gaps {
    display: flex;
    flex-direction: column;
    gap: var(--space-600);
  }
</style>
