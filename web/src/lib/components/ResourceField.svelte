<script lang="ts">
  import type { Field } from '$lib/resourceDetail';

  /**
   * One field on the resource detail page: a small grey label over its value.
   * Figma: ResourceField, node 185:46 — style=text|link. The style is not a
   * prop here: a line is a link when it carries an href.
   *
   * A field can hold several lines - two phone numbers, two email addresses -
   * each its own link.
   */

  interface Props {
    field: Field;
  }

  let { field }: Props = $props();
</script>

<div class="field">
  <p class="label">{field.label}</p>
  {#each field.lines as line, i (i)}
    {#if line.href}
      <a class="value" href={line.href} rel={line.external ? 'noopener noreferrer' : undefined}>{line.text}</a>
    {:else}
      <p class="value">{line.text}</p>
    {/if}
  {/each}
</div>

<style>
  .field {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-100);
  }

  .label {
    margin: 0;
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
    color: var(--color-text-secondary);
  }

  .value {
    margin: 0;
    font-size: var(--font-size-body);
    line-height: var(--line-height-prose);
    overflow-wrap: anywhere;
  }
</style>
