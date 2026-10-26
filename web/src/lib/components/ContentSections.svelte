<script lang="ts">
  import type { Snippet } from 'svelte';
  import HazardItem from '$lib/components/HazardItem.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import PhoneText from '$lib/components/PhoneText.svelte';
  import Section from '$lib/components/Section.svelte';
  import type { HazardSection } from '$lib/types';

  /**
   * The body of an authored content page: the summary, then the sections and
   * their items. Shared by the hazard pages and the standalone pages
   * (/general), which use the same schema (R/content.R, validate_sections).
   * Moved out of the hazard page on 2026-10-14 when the General page became
   * the second user, so the two render identically.
   */
  interface Props {
    summary?: string;
    /** As published: sections with neither items nor body are dropped here. */
    sections: HazardSection[];
    /** Shown when nothing is authored yet. */
    emptyText: string;
    /**
     * Content for a data-backed section (R: DATA_BACKED_SECTIONS), which has
     * no authored items or body. The hazard page passes the respiratory
     * conditions panel for `current-conditions`.
     */
    dataSection?: Snippet<[HazardSection]>;
    /** 3 inside a hazard part, whose own heading is the h2. */
    headingLevel?: 2 | 3;
  }

  let { summary, sections, emptyText, dataSection, headingLevel = 2 }: Props = $props();

  /**
   * §7.6: skip any section with no `items` AND no `body`.
   *
   * NOT `status === 'stub'` - status is ABSENT on the authored hazards, so
   * testing the string treats authored content as a stub. A data-backed
   * section is the exception: it has neither by design.
   */
  const shown = $derived(
    sections.filter((s) => s.id === 'current-conditions' || s.items.length > 0 || s.body)
  );
</script>

{#if summary}
  <!-- Paragraphs split on the line breaks a folded YAML block keeps. Phone
       numbers in it are tappable ($lib/phones.ts). -->
  <div class="summary">
    {#each summary.trim().split(/\n\s*\n|\n/) as paragraph, i (i)}
      <p class="prose"><PhoneText text={paragraph} /></p>
    {/each}
  </div>
{/if}

{#if shown.length === 0}
  <p class="empty">{emptyText}</p>
{/if}

{#each shown as section, i (section.id)}
  <!-- A RULE ONLY BEFORE A TITLED SECTION, and never before the first.
       The two hazard frames disagree on purpose: Heavy Rain (58:403)
       separates its two headed sections with a rule, while Extreme Heat
       (40:200) runs its three unheaded groups together with none. A heading
       earns the boundary; an unheaded group is a continuation. -->
  {#if i > 0 && section.title}
    <HorizontalRule />
  {/if}

  <!-- A section's title is optional: the Extreme Heat page carried every
       heading on a group instead. Those render unwrapped - the frame has no
       container around them, and the NestedContainers inside bring their own
       12px. -->
  {#if section.title}
    <Section title={section.title} level={headingLevel}>
      {@render sectionBody(section)}
    </Section>
  {:else}
    <div class="untitled">{@render sectionBody(section)}</div>
  {/if}
{/each}

{#snippet sectionBody(section: HazardSection)}
  {#if dataSection}
    {@render dataSection(section)}
  {/if}

  <!-- Every section carries both keys and one of them is empty. -->
  {#if section.body}
    <p class="prose"><PhoneText text={section.body} /></p>
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
  /* Aligned with the sections below it: Section's own 10px padding. */
  .summary {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    padding: 10px;
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

  /* An unheaded section has no wrapper in the frame - its contents sit
     directly on the page - so this supplies exactly what the page would: the
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
