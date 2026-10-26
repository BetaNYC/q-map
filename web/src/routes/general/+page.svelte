<script lang="ts">
  import ContentSections from '$lib/components/ContentSections.svelte';
  import FrozenHead from '$lib/components/FrozenHead.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';

  let { data } = $props();

  const content = $derived(data.content);
</script>

<svelte:head>
  <title>{content.label} | Queens Readiness Resources</title>
  <meta
    name="description"
    content="Steps that help in any emergency, and where to get help in New York City."
  />
</svelte:head>

<!-- General Resources: the SME-reviewed "General" copy, linked from the entry
     page. Laid out as a hazard page is: frozen header, the summary, then the
     sections (ContentSections). -->
<div class="screen">
  <!-- Frozen while the page scrolls, with the rule under it as its edge.
       "Back" as on Alerts: the site name is already in SiteHeader above, and
       the accessible name says where it goes (WCAG 2.5.3). -->
  <FrozenHead>
    <PageHeader
      title={content.label}
      back={{ href: '/', label: 'Back', name: 'Back to Queens Readiness Resources' }}
    />

    <HorizontalRule />
  </FrozenHead>

  <ContentSections
    summary={content.summary}
    sections={content.sections}
    emptyText="This page has not been written yet."
  />
</div>

<style>
  /* The hazard page's column: 4px between blocks, the 390px frame, 16px
     gutters, 24px above and below. */
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }
</style>
