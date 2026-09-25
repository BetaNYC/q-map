<script lang="ts">
  import HazardElement from './HazardElement.svelte';
  // Svelte 5 recursion: a component imports itself by name. <svelte:self> is
  // deprecated and does not survive the runes compiler cleanly.
  import Self from './HazardItem.svelte';
  import NestedContainer from './NestedContainer.svelte';
  import PhoneElement from './PhoneElement.svelte';
  import type { HazardItem } from '$lib/types';

  /**
   * Picks the leaf for one item. Not a Figma component — the glue the hazard
   * screen (step 7) needs, and the only place that knows how the four shapes
   * map onto three components.
   *
   * The discriminant is which optional key is present, and ORDER MATTERS: a
   * Group is checked first because its children are items of any shape, and
   * `items` is the only key that makes this recursive. The pipeline guarantees
   * exactly one shape per entry, so the chain cannot fall through ambiguously.
   *
   * Link and Note both land on HazardElement — the only difference is the
   * anchor, which that component derives from `url` itself.
   *
   * Groups nest one level only, which the pipeline enforces. This will recurse
   * as deep as the data goes rather than capping it: a depth limit here would
   * silently drop content if the rule upstream ever changed, where recursion
   * would simply render it.
   */

  interface Props {
    item: HazardItem;
  }

  let { item }: Props = $props();
</script>

{#if item.items}
  <NestedContainer label={item.label}>
    {#snippet children()}
      {#each item.items as child, i (child.label + i)}
        <Self item={child} />
      {/each}
    {/snippet}
  </NestedContainer>
{:else if item.tel}
  <PhoneElement {item} />
{:else}
  <HazardElement {item} />
{/if}
