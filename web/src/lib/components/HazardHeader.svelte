<script lang="ts">
  import { base } from '$app/paths';
  import ArrowLeftIcon from '$lib/icons/ArrowLeftIcon.svelte';

  /**
   * The hazard screen's header. Figma: HazardHeader, node 58:404 — the hazard
   * label at 18px over a back link to the district.
   *
   * ResourceHeader without the category line. Both back links are a property
   * of the route rather than history.back(), for the same reason: a shared
   * link has no history to go back to.
   */

  interface Props {
    label: string;
    districtSlug: string;
    districtName: string;
  }

  let { label, districtSlug, districtName }: Props = $props();
</script>

<header class="header">
  <h1 class="label">{label}</h1>

  <div class="body">
    <a class="back" href="{base}/{districtSlug}">
      <ArrowLeftIcon />
      {districtName}
    </a>
  </div>
</header>

<style>
  .header {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-300);
    padding-inline: var(--space-200);
    padding-bottom: var(--space-200);
  }

  .label {
    margin: 0;
    font-size: var(--font-size-title);
    font-weight: var(--font-weight-title);
    letter-spacing: var(--letter-spacing-title);
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  .body {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding-left: var(--space-100);
    font-size: var(--font-size-small);
  }

  .back {
    display: flex;
    align-items: center;
    gap: var(--space-100);
    color: var(--color-text-primary);
    text-decoration: none;
    line-height: var(--line-height-tight);
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
  }
</style>
