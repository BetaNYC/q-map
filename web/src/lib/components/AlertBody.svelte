<script lang="ts">
  import { parseBody, type Inline } from '$lib/alertBody';

  /**
   * An alert's body text, with its links and phone numbers made tappable.
   *
   * Rendered from parseBody()'s data — text nodes and <a> elements whose href
   * that module built. NEVER {@html}: the body is third-party text
   * ($lib/alertBody.ts).
   *
   * `interactive={false}` (an ended alert) renders every link as plain text:
   * an alert that has ended should not invite action.
   */

  interface Props {
    body: string;
    interactive?: boolean;
  }

  let { body, interactive = true }: Props = $props();

  const blocks = $derived(parseBody(body));
</script>

{#snippet piece(p: Inline)}
  {#if p.type === 'text' || !interactive}{p.text}{:else if p.type === 'tel'}<a href={p.href}>{p.text}</a>{:else}<a href={p.href} rel="noopener noreferrer">{p.text}</a>{/if}
{/snippet}

<div class="body">
  {#each blocks as block, b (b)}
    {#if block.type === 'p'}
      <p>
        {#each block.lines as line, i (i)}{#if i > 0}<br />{/if}{#each line as p, j (j)}{@render piece(p)}{/each}{/each}
      </p>
    {:else}
      <ul>
        {#each block.items as item, i (i)}<li>{#each item as p, j (j)}{@render piece(p)}{/each}</li>{/each}
      </ul>
    {/if}
  {/each}
</div>

<style>
  .body {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
    font-size: var(--font-size-body);
    line-height: var(--line-height-prose);
    overflow-wrap: anywhere; /* long shortened URLs must not widen the page */
  }

  p,
  ul {
    margin: 0;
  }

  ul {
    padding-left: var(--space-400);
  }

  /* "3-1-1" must not break at its hyphens. */
  a[href^='tel:'] {
    white-space: nowrap;
  }
</style>
