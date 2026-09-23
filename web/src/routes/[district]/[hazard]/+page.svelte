<script lang="ts">
  import { base } from '$app/paths';
  import HazardItem from '$lib/components/HazardItem.svelte';
  import { measureLine } from '$lib/hazards';

  let { data } = $props();

  /**
   * §7.6: skip any section with no `items` AND no `body`.
   *
   * Six of eight hazards are unwritten stubs, and even an authored one carries
   * empty sections — heavy-rain's `general` has neither. Every section always
   * has both keys, so the test is on emptiness, not on presence.
   *
   * NOT `status === 'stub'`: status is ABSENT on the two authored hazards, so
   * testing for the string would treat authored content as a stub.
   */
  const sections = $derived(data.content.sections.filter((s) => s.items.length > 0 || s.body));
</script>

<!-- SCAFFOLD. The hazard screen proper is step 7; this renders the real
     sections so the four item shapes are exercised. -->

<p><a href="{base}/{data.district.slug}">{data.district.display_name}</a></p>

<h1>{data.hazard.label}</h1>
<p>{measureLine(data.hazard)}</p>

<!-- `summary` became optional 2026-09-23: neither authored screen renders one,
     and requiring it had forced placeholder prose into every file. -->
{#if data.content.summary}
  <p>{data.content.summary}</p>
{/if}

{#if sections.length === 0}
  <p>No guidance has been written for this hazard yet.</p>
{/if}

{#each sections as section (section.id)}
  <section>
    <!-- `title` is optional. A section that omits it orders the page without
         announcing itself — which is how the Extreme Heat screen is built:
         every heading there belongs to a group, not a section. Rendering an
         empty <h2> would put a blank heading into the outline. -->
    {#if section.title}
      <h2>{section.title}</h2>
    {/if}

    <!-- Every section carries both keys and one of them is empty. A prose
         section has `body`; a link section has `items`. -->
    {#if section.body}
      <p>{section.body}</p>
    {/if}

    {#if section.items.length}
      <ul>
        {#each section.items as item, i (item.label + i)}
          <li><HazardItem {item} /></li>
        {/each}
      </ul>
    {/if}
  </section>
{/each}

<style>
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
</style>
