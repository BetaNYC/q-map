<script lang="ts">
  import { base } from '$app/paths';
  import ConditionsPanel from '$lib/components/ConditionsPanel.svelte';
  import HazardHeader from '$lib/components/HazardHeader.svelte';
  import HazardItem from '$lib/components/HazardItem.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import Section from '$lib/components/Section.svelte';
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
  <!-- The header owns the map button and the rule beneath the back link (§7.3
       renders that button even for the five hazards with no layers at all —
       the resources are the point of the map).

       NEITHER THE MEASURE NOR THE SUMMARY RENDERS HERE ANY MORE. The measure
       ("Heat Vulnerability Index: 4 out of 5") was the same measureLine()
       string, in the same type, that HazardRow already shows on the district
       screen one tap above. The summary went with it on the same call. Both
       are absent from the revised frames. `content.summary` is still emitted
       by the pipeline and now renders nowhere in the app — noted in
       web/README.md so it is a known gap rather than a silent drop. -->
  <HazardHeader
    label={content.label}
    districtSlug={district.slug}
    districtName={district.display_name}
    {mapHref}
  />

  <HorizontalRule />

  {#if sections.length === 0}
    <p class="empty">Guidance for this hazard has not been written yet.</p>
  {/if}

  {#each sections as section, i (section.id)}
    <!-- A RULE ONLY BEFORE A TITLED SECTION, and never before the first.
         The two frames disagree on purpose: Heavy Rain (58:403) separates its
         two headed sections with a rule, while Extreme Heat (40:200) runs its
         three unheaded groups together with none. A heading earns the
         boundary; an unheaded group is a continuation. -->
    {#if i > 0 && section.title}
      <HorizontalRule />
    {/if}

    <!-- A hazard section's title is optional: the Extreme Heat page carries
         every heading on a group instead. Those render unwrapped — the frame
         has no container around them, and the NestedContainers inside bring
         their own 12px. -->
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
    /* 4px, per both frames. Was 12px, which stacked on top of every block's
       own padding and opened each interval a step wider than drawn. */
    gap: var(--space-100);
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  .prose,
  .empty {
    margin: 0;
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;
  }

  .empty {
    padding-inline: var(--space-200);
  }

  /* An unheaded section has no wrapper in the frame — its contents sit
     directly on the page — so this supplies exactly what the page would: the
     12px horizontal inset every top-level block carries, and nothing else. It
     is Section without the heading and without Section's 10px.

     The inset lives here rather than on the children because both kinds of
     child appear at this level: a NestedContainer group and a bare
     HazardElement note are siblings on the Extreme Heat frame, and they line
     up only if the container insets them together. */
  .untitled {
    display: flex;
    flex-direction: column;
    padding-inline: var(--space-300);
  }

  .items {
    list-style: none;
    margin: 0;
    padding: 0;
    width: 100%;
  }
</style>
