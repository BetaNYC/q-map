<script lang="ts">
  import { base } from '$app/paths';
  import ArrowLeftIcon from '$lib/icons/ArrowLeftIcon.svelte';
  import type { DistrictPayload } from '$lib/types';

  /**
   * The district screen's header. Figma: DistrictHeader, node 14:1387.
   *
   * BOTH NAMES RENDER. `display_name` ("The Rockaways") at 18px and `cd_label`
   * ("Community District 14") at 12px. Neither is derivable from the other
   * (handoff §2), which is why both are shipped and both are drawn.
   *
   * "Change location" goes back to the entry screen, where the picker is. It is
   * an <a href>, not a history.back() — arriving from a shared link means there
   * is no back to go to, and the destination is a real page either way.
   *
   * The h1 is `display_name` alone. A screen reader hitting the page by
   * heading gets the neighbourhood, and "Community District 14" follows in the
   * same block without competing for the outline.
   */

  interface Props {
    district: DistrictPayload;
  }

  let { district }: Props = $props();
</script>

<header class="header">
  <h1 class="name">{district.display_name}</h1>

  <div class="body">
    <p class="label">{district.cd_label}</p>

    <a class="change" href="{base}/">
      <ArrowLeftIcon />
      Change location
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
    padding-block: var(--space-100);
  }

  .name {
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
    gap: var(--space-300);
    padding-left: var(--space-100);
    font-size: var(--font-size-small);
  }

  .label {
    margin: 0;
    color: var(--color-text-secondary);
    line-height: var(--line-height-tight);
  }

  .change {
    display: flex;
    align-items: center;
    gap: var(--space-100);

    /* Figma draws this in primary black, not link blue — it is navigation
       chrome rather than a link into content. The arrow is the affordance. */
    color: var(--color-text-primary);
    text-decoration: none;
    line-height: var(--line-height-tight);

    /* 44px hit area on a 12px line (WCAG 2.5.5), taken as padding so the ink
       stays where the design puts it. Negative margin keeps the row pitch. */
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
  }
</style>
