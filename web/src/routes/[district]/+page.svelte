<script lang="ts">
  import CategoryRow from '$lib/components/CategoryRow.svelte';
  import Coad from '$lib/components/Coad.svelte';
  import DistrictHeader from '$lib/components/DistrictHeader.svelte';
  import GapSentence from '$lib/components/GapSentence.svelte';
  import HazardRow from '$lib/components/HazardRow.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import Section from '$lib/components/Section.svelte';

  let { data } = $props();

  const district = $derived(data.district);
</script>

<svelte:head>
  <!-- Both names, because a shared link's preview should say which district
       AND which community district — they are different strings and people
       search on both. -->
  <title>{district.display_name} — {district.cd_label} | Queens Resource Map</title>
</svelte:head>

<!-- Screen 02. Figma: "02 District - Mobile", node 13:839.
     390px frame, 16px gutters, 358px measure (handoff §3). -->
<div class="screen">
  <DistrictHeader {district} />

  <!-- 1 of 14 districts. `coad_name` is null in the same thirteen as `coad`,
       so either check works; this reads as the question being asked. -->
  {#if district.coad_name}
    <Coad {district} />
  {/if}

  <Section title="Hazard Areas">
    <!-- Always 8, already ordered, three ranked and five pinned. `rank` is
         authoritative — re-sorting on `score` would silently reorder the ties
         that 8 of 14 districts have (§7.1). -->
    <ul class="rows">
      {#each district.hazards as hazard (hazard.slug)}
        <li><HazardRow {hazard} districtSlug={district.slug} /></li>
      {/each}
    </ul>
  </Section>

  <HorizontalRule />

  <Section title="District Resource Map">
    <!-- Derived per district — never a hardcoded list of twelve (§6). Counts
         span 1 to 261 within one district, which is why they are numerals and
         not a bar (§7.3). -->
    <ul class="rows rows--spaced">
      {#each district.resource_categories as category (category.slug)}
        <li><CategoryRow {category} districtSlug={district.slug} /></li>
      {/each}
    </ul>
  </Section>

  <HorizontalRule />

  <Section title="Resource Gaps">
    <!-- Exactly three, one per ranked hazard, already ordered by risk_rank. -->
    <ul class="rows rows--gaps">
      {#each district.gaps_displayed as gap (gap.gap_id)}
        <li><GapSentence {gap} /></li>
      {/each}
    </ul>
  </Section>
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;

    /* §3: 390px baseline with 16px gutters gives the 358px measure the type
       and wrapping were designed against. Fluid above it — max-width keeps the
       measure rather than letting lines run on a larger phone. */
    max-width: calc(390px);
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
    width: 100%;
  }

  /* CategoryRow instances sit 8px apart; HazardRow instances butt together. */
  .rows--spaced {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  /* Gap sentences are 24px apart (Figma 15:1686). */
  .rows--gaps {
    display: flex;
    flex-direction: column;
    gap: var(--space-600);
    padding-block: 11px;
  }
</style>
