<script lang="ts">
  import { base } from '$app/paths';
  import ConditionsPanel from '$lib/components/ConditionsPanel.svelte';
  import ContentSections from '$lib/components/ContentSections.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import FrozenHead from '$lib/components/FrozenHead.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import type { ConditionsMetric, HazardSection } from '$lib/types';

  let { data } = $props();

  const district = $derived(data.district);
  const content = $derived(data.content);


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
  <title>{content.label} in {district.display_name} | Queens Readiness Resources</title>
</svelte:head>

<!-- Screen 03. Figma: "03 Hazard - Mobile", nodes 40:200 and 58:403. -->
<div class="screen">
  <!-- The header owns the map button and the rule beneath the back link (§7.3
       renders that button even for the five hazards with no layers at all —
       the resources are the point of the map).

       THE MEASURE DOES NOT RENDER HERE. The measure ("Heat Vulnerability
       Index: 4 out of 5") is the same measureLine() string, in the same type,
       that HazardRow already shows on the district screen one tap above.

       THE SUMMARY DOES, again (Andrew, 2026-10-14): the SME-reviewed copy
       opens every hazard with a two-sentence description of it, written as
       `summary`. It was dropped on 2026-09-23 with the measure, when no
       authored summary said anything the screen needed. -->
  <!-- Frozen while the page scrolls, with the rule under it as its edge. -->
  <FrozenHead>
    <PageHeader
      title={content.label}
      back={{ href: `/${district.slug}`, label: district.display_name }}
      {mapHref}
    />

    <HorizontalRule />
  </FrozenHead>

  {#if content.parts.length}
    <!-- STOPGAP (2026-10-26), pending Andrew's layout for sub-hazards.
         Flooding and Temperature Extremes carry `parts` instead of
         `sections` (DATA_CONTRACT.md §6): each part is a full sub-page with
         its own summary and sections. This stacks them in order, each under
         its label, with a rule between - existing components only, and the
         part heading borrows Section's title tokens. Outline (Andrew,
         2026-10-26): the hazard label is the page's one h1, each part an h2,
         its sections h3. Open: jump links, whether the rule is right, and
         the part heading's visual weight - it currently matches the section
         headings. `id` is the stable part anchor. -->
    {#each content.parts as part, i (part.id)}
      {#if i > 0}
        <HorizontalRule />
      {/if}
      <h2 class="part-title" id={part.id}>{part.label}</h2>
      <ContentSections
        summary={part.summary}
        sections={part.sections}
        emptyText="Guidance for this hazard has not been written yet."
        dataSection={conditionsSection}
        headingLevel={3}
      />
    {/each}
  {:else}
    <ContentSections
      summary={content.summary}
      sections={content.sections}
      emptyText="Guidance for this hazard has not been written yet."
      dataSection={conditionsSection}
    />
  {/if}
</div>

{#snippet conditionsSection(section: HazardSection)}
  {#if section.id === 'current-conditions' && data.conditions}
    <!-- Data-backed: conditions.json in place of authored content (§7.6). -->
    <ConditionsPanel metrics={conditionMetrics} />
  {/if}
{/snippet}


<style>
  /* Section's title tokens and inset (see the stopgap note above). */
  .part-title {
    margin: 0;
    padding: 10px;
    font-size: var(--font-size-section);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .screen {
    display: flex;
    flex-direction: column;
    /* 4px, per both frames. Was 12px, which stacked on top of every block's
       own padding and opened each interval a step wider than drawn. */
    gap: var(--space-100);
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }
</style>
