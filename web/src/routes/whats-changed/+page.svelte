<script lang="ts">
  /**
   * What's changed: every change to the map a reader would notice, newest first.
   *
   * The list is generated from WHATS-CHANGED.md at the repo root by
   * scripts/whats_changed.py (`npm run whats-changed`, also run before every build)
   * into $lib/whats-changed.html, without its own h1: PageHeader supplies the page's
   * only h1. The fragment carries its own scoped style and its filter script, and
   * starts with the filter hidden, so with JavaScript off every entry shows.
   */
  import PageHeader from '$lib/components/PageHeader.svelte';
  import fragment from '$lib/whats-changed.html?raw';
</script>

<svelte:head>
  <title>What's changed | Queens Resource Map</title>
  <meta
    name="description"
    content="Every change to the Queens Resource Map a reader would notice, newest first."
  />
</svelte:head>

<div class="screen">
  <PageHeader
    title="What's changed"
    back={{ href: '/', label: 'Back', name: 'Back to Queens Resource Map' }}
  />

  <!-- Generated from WHATS-CHANGED.md; the renderer escapes every field. -->
  <!-- eslint-disable-next-line svelte/no-at-html-tags -->
  {@html fragment}
</div>

<style>
  /* The General Resources page's column, wider: this page is text only. */
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
    max-width: 720px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }
</style>
