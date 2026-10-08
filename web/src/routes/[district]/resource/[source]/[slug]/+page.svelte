<script lang="ts">
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import ResourceField from '$lib/components/ResourceField.svelte';
  import FrozenHead from '$lib/components/FrozenHead.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import { groupsFor, listingNote, mapsHref, platformOf } from '$lib/resourceDetail';
  import { mapReturnPath } from '$lib/resources';

  let { data } = $props();

  /* Back to the map this resource was tapped in, not to the district page.
     Derived from the record, so it is static in the prerendered HTML. */
  const backHref = $derived(mapReturnPath(data.resource, data.district.slug));

  /* The address opens the device's maps app (decision 5c). The prerendered
     HTML carries a web map link, which works everywhere; in the browser it is
     upgraded to geo: on Android and Apple Maps on iOS. */
  let platform = $state<'android' | 'ios' | 'other'>('other');
  $effect(() => {
    platform = platformOf(navigator);
  });

  const groups = $derived(
    groupsFor(data.resource).map((g) => ({
      ...g,
      fields: g.fields.map((f) =>
        f.maps
          ? { ...f, lines: f.lines.map((l) => ({ ...l, href: mapsHref(platform, data.resource.lat, data.resource.lon, data.resource.name) })) }
          : f
      )
    }))
  );
</script>

<svelte:head>
  <title>{data.resource.name} | {data.district.display_name} | Queens Resource Map</title>
</svelte:head>

<!-- Screen 05. Figma: "05 Resource Detail - Mobile", node 186:1071 - About,
     Contact and Access groups between rules, then "About this listing".
     Groups with no fields are left out; 12 FRANC records have none at all and
     the page is then the header and the listing note. -->
<div class="screen">
  <!-- Frozen while the page scrolls. -->
  <FrozenHead>
    <PageHeader
      title={data.resource.name}
      secondary={data.categoryLabel}
      back={{ href: backHref, label: data.district.display_name }}
    />
  </FrozenHead>

  {#each groups as group (group.title)}
    <HorizontalRule />
    <section class="group" aria-labelledby="group-{group.title}">
      <h2 id="group-{group.title}" class="heading">{group.title}</h2>
      {#each group.fields as field (field.label)}
        <ResourceField {field} />
      {/each}
    </section>
  {/each}

  <HorizontalRule />
  <section class="group listing" aria-labelledby="group-listing">
    <h2 id="group-listing" class="heading">About this listing</h2>
    <p class="note">{listingNote(data.resource)}</p>
    <p class="note">In an emergency, call <a href="tel:911">911</a>.</p>
  </section>
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);

    /* §3: 390px baseline, 16px gutters, 358px measure. */
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  .group {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    padding: var(--space-300);
  }

  .listing {
    gap: var(--space-200);
  }

  .heading {
    margin: 0;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .note {
    margin: 0;
    font-size: var(--font-size-small);
    line-height: var(--line-height-prose);
  }
</style>
