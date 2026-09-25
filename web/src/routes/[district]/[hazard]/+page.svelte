<script lang="ts">
  import { base } from '$app/paths';
  import ConditionsPanel from '$lib/components/ConditionsPanel.svelte';
  import HazardHeader from '$lib/components/HazardHeader.svelte';
  import HazardItem from '$lib/components/HazardItem.svelte';
  import Section from '$lib/components/Section.svelte';
  import { measureLine } from '$lib/hazards';
  import type { ConditionsMetric } from '$lib/types';

  let { data } = $props();

  const district = $derived(data.district);
  const content = $derived(data.content);

  /**
   * §7.6: skip any section with no `items` AND no `body`.
   *
   * Six of eight hazards are unwritten stubs, and even an authored one carries
   * empty sections. NOT `status === 'stub'` — status is ABSENT on the authored
   * ones, so testing the string treats authored content as a stub.
   *
   * `current-conditions` is the exception: it is data-backed, so it renders
   * even though it has neither items nor body.
   */
  const sections = $derived(
    content.sections.filter(
      (s) => s.id === 'current-conditions' || s.items.length > 0 || s.body
    )
  );

  /** Both metrics, not just `chip_metric` — that names what screen 01's chip
   *  shows, and this section is the fuller readout. */
  const conditionMetrics = $derived.by(() => {
    if (!data.conditions) return [] as ConditionsMetric[];
    return Object.entries(data.conditions)
      .filter(([, v]) => typeof v === 'object' && v !== null && 'geography_label' in v)
      .map(([, v]) => v as ConditionsMetric);
  });

  /**
   * §5: the originating page writes the state into the link.
   *
   * `?layers=` comes from the hazard's own map_layers — the override's, where
   * one applies, which is how q14's coastal storm opens with the evacuation
   * zones and surge layers that no other district gets.
   *
   * `?categories=` IS NOT CARRIED, because the field it would come from does
   * not exist. `DATA_CONTRACT.md` §6 documents `default_resource_categories`
   * on all 8 hazard files; it is absent from all 8, from the YAML source, and
   * from every committed version of the outputs. See web/README.md. Without
   * it the map opens on its default, which is every category showing.
   */
  const mapHref = $derived.by(() => {
    const params = new URLSearchParams();
    if (content.map_layers?.length) params.set('layers', content.map_layers.join(','));
    params.set('hazard', content.slug);
    return `${base}/${district.slug}/map?${params}`;
  });
</script>

<svelte:head>
  <title>{content.label} in {district.display_name} | Queens Resource Map</title>
</svelte:head>

<!-- Screen 03. Figma: "03 Hazard - Mobile", nodes 40:200 and 58:403. -->
<div class="screen">
  <HazardHeader
    label={content.label}
    districtSlug={district.slug}
    districtName={district.display_name}
  />

  <!-- The measure and score for a ranked hazard, the reason for a pinned one.
       measureLine() swaps in the score-0 copy where a number would mislead. -->
  <p class="measure">{measureLine(data.hazard)}</p>

  {#if content.summary}
    <p class="summary">{content.summary}</p>
  {/if}

  <!-- §7.3: render this even for the five hazards with no layers at all —
       the resources are the point of the map.

       UNDESIGNED: neither hazard frame draws this button. It borrows the
       visual language of screen 01's "Use my location" control rather than
       inventing one. Flagged in web/README.md. -->
  <a class="map-button" href={mapHref}>
    See resources on the map
  </a>

  {#if sections.length === 0}
    <p class="empty">Guidance for this hazard has not been written yet.</p>
  {/if}

  {#each sections as section (section.id)}
    <!-- A hazard section's title is optional: the Extreme Heat page carries
         every heading on a group instead. Section renders one only when there
         is one. -->
    {#if section.title}
      <Section title={section.title}>
        {@render sectionBody(section)}
      </Section>
    {:else}
      <div class="untitled">{@render sectionBody(section)}</div>
    {/if}
  {/each}
</div>

{#snippet sectionBody(section: (typeof sections)[number])}
  {#if section.id === 'current-conditions' && data.conditions}
    <!-- Data-backed: conditions.json in place of authored content (§7.6). -->
    <ConditionsPanel metrics={conditionMetrics} />
  {/if}

  <!-- Every section carries both keys and one of them is empty. -->
  {#if section.body}
    <p class="prose">{section.body}</p>
  {/if}

  {#if section.items.length}
    <ul class="items">
      {#each section.items as item, i (item.label + i)}
        <li><HazardItem {item} /></li>
      {/each}
    </ul>
  {/if}
{/snippet}

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  .measure {
    margin: 0;
    padding-inline: var(--space-200);
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);
    line-height: var(--line-height-prose);
  }

  .summary,
  .prose,
  .empty {
    margin: 0;
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }

  .summary,
  .empty {
    padding-inline: var(--space-200);
  }

  /* Screen 01's Location control: solid secondary fill, off-white text, 3px
     radius, 12px padding. #fefcfa on #707070 is 4.84:1 — AA for text under
     24px. Padding lifted to clear the 44px minimum. */
  .map-button {
    display: block;
    margin-inline: var(--space-200);
    padding: var(--space-300);
    min-height: var(--touch-target-min);

    background: var(--color-text-secondary);
    color: var(--color-surface);
    border-radius: 3px;
    text-decoration: none;
    line-height: var(--line-height-prose);
  }

  .untitled {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    padding: 10px;
  }

  .items {
    list-style: none;
    margin: 0;
    padding: 0;
    width: 100%;
  }
</style>
