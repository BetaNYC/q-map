<script lang="ts">
  /**
   * The arrow in Conditions' 24px frame. Figma: node 14:1142, one icon per
   * `direction` variant.
   *
   * Exported from Figma rather than drawn — these are the assets' own paths,
   * with `stroke` swapped for currentColor so the glyph follows the text
   * colour rather than pinning itself to #0A0A0A.
   *
   * aria-hidden: the sentence beside it already says "are increasing" /
   * "are decreasing" / "are flat", so the arrow is the third channel carrying
   * that meaning, after the words and the fill. Announcing it would repeat the
   * sentence.
   */

  interface Props {
    direction: 'up' | 'down' | 'flat';
  }

  let { direction }: Props = $props();
</script>

<svg
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.5"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
>
  {#if direction === 'up'}
    <path d="M8 7H17V16" />
    <path d="M8 16L17 7" />
  {:else if direction === 'down'}
    <path d="M8 8L17 17" />
    <path d="M17 8V17H8" />
  {:else}
    <path d="M7.75 12.25H17.25" />
  {/if}
</svg>

<style>
  svg {
    display: block;
    width: var(--space-600);
    height: var(--space-600);
  }
</style>
