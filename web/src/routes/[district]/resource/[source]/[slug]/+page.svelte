<script lang="ts">
  import ResourceCard from '$lib/components/ResourceCard.svelte';
  import ResourceHeader from '$lib/components/ResourceHeader.svelte';

  let { data } = $props();
</script>

<svelte:head>
  <title>{data.resource.name} | {data.district.display_name} | Queens Resource Map</title>
</svelte:head>

<!-- Screen 05. Figma: "05 Resource Detail - Mobile", node 83:1780. -->
<div class="screen">
  <ResourceHeader
    name={data.resource.name}
    categoryLabel={data.categoryLabel}
    districtSlug={data.district.slug}
    districtName={data.district.display_name}
  />

  <!-- 12 of the 248 records have no card fields at all — all FRANC, all
       missing even a mission. ResourceCard renders nothing for those rather
       than an empty bordered box, so the page is the header alone. -->
  <ResourceCard resource={data.resource} />
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-400);

    /* §3: 390px baseline, 16px gutters, 358px measure. */
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }
</style>
