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
   * The heading level is h2 by default: every screen has exactly one h1 (the
   * district name, the hazard label) and these sit directly under it.
   *
   * `level` admits 3 and nothing else (2026-10-26). A hazard with parts puts an
   * h2 part heading between the h1 and its sections, so those sections are
   * h3. Typed as 2 | 3 rather than a number, so a caller cannot skip a level.
   * The visual style does not change with the level.
   */

  interface Props {
    title: string;
    level?: 2 | 3;
    children: Snippet;
  }

  let { title, level = 2, children }: Props = $props();
</script>

<section class="section">
  <svelte:element this={`h${level}`} class="title">{title}</svelte:element>
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
