<script lang="ts">
  import { splitPhones } from '$lib/phones';

  /**
   * Authored text with its phone numbers made tappable ($lib/phones.ts).
   * Inline: renders runs and links only, so the caller keeps its own element
   * and styles. The links take the app's inline link colour.
   */
  let { text }: { text: string } = $props();

  const runs = $derived(splitPhones(text));
</script>

{#each runs as run, i (i)}{#if run.tel}<a class="tel" href={run.tel}>{run.text}</a>{:else}{run.text}{/if}{/each}

<style>
  /* Above HazardElement's stretched link, so a number is tapped on its own
     rather than opening the item's destination. */
  .tel {
    position: relative;
    z-index: 1;
  }
</style>
