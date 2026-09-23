<script lang="ts">
  import type { Snippet } from 'svelte';

  /**
   * A titled block on the district screen — "Hazard Areas", "District Resource
   * Map", "Resource Gaps".
   *
   * Figma: the ResourceGap frame (15:1681) is the measured instance — 10px
   * padding, a 14px bold heading, 12px to the content.
   *
   * NOT the hazard screen's section. That one's title is optional and its
   * headings often belong to groups instead; this one always has a title and
   * always renders it. Two different things that happen to share a word.
   *
   * The heading level is fixed at h2: the district screen has one h1
   * (DistrictHeader's display_name) and these three sit directly under it. A
   * `level` prop would invite a caller to produce a heading order that skips.
   */

  interface Props {
    title: string;
    children: Snippet;
  }

  let { title, children }: Props = $props();
</script>

<section class="section">
  <h2 class="title">{title}</h2>
  {@render children()}
</section>

<style>
  .section {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-300);
    padding: 10px; /* Figma's literal */
  }

  .title {
    margin: 0;
    /* 14px bold — the same size as body text. These are labels for blocks
       rather than a typographic hierarchy, and the design keeps them quiet. */
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }
</style>
