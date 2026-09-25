<script lang="ts">
  import type { Snippet } from 'svelte';

  /**
   * A titled block. Used by both content screens: the district's "Hazard
   * Areas", "District Resource Map" and "Resource Gaps", and the hazard
   * screen's authored sections ("Preparedness", "Response").
   *
   * Figma: ResourceGap (15:1681) on the district screen, Section1/Section2
   * (58:407, 58:417) on the hazard screen.
   *
   * ONE COMPONENT, BOTH SCREENS. This file used to claim it was "NOT the
   * hazard screen's section… two different things that happen to share a
   * word", while the hazard route imported it anyway. The 2026-09-25 revision
   * settled that: both frames now draw the same 16px heading, so they are one
   * thing. A hazard section whose title is absent is not this component — the
   * route renders those unwrapped, which is what the Extreme Heat frame draws.
   *
   * The heading level is fixed at h2: both screens have exactly one h1 (the
   * district name, the hazard label) and these sit directly under it. A
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

    /* 10px, Figma's literal on the district frames. The hazard frames draw
       12px on the same block. Taking the district's number keeps that screen
       untouched and costs the hazard screen 2px a side — recorded rather than
       silently absorbed. */
    padding: 10px;
  }

  .title {
    margin: 0;
    /* 16px bold (title/section). Was 14px, matching body text, back when these
       were read as quiet block labels. Both frames now set them a step above
       the content they head, so they are a real typographic level.
       NestedContainer's label stays at 14px — that is a group heading inside a
       section, not a section title. */
    font-size: var(--font-size-section);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }
</style>
