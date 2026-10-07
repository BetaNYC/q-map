<script lang="ts">
  import type { Snippet } from 'svelte';
  import ChevronDownIcon from '$lib/icons/ChevronDownIcon.svelte';

  /**
   * One of the entry page's two reveal panels: "Choose Community District"
   * (the cards) and "Select on map". Figma: DisclosureButton, node 178:856 —
   * open=false|true; frames "01 Entry - Mobile/NoAlert (revised)" and
   * ".../Neighborhoods open".
   *
   * WORKED EXAMPLE — a native <details>, not a button with JavaScript state.
   *
   * 1. ONE OPEN AT A TIME, WITH NO JAVASCRIPT. <details> elements sharing a
   *    `name` form an exclusive accordion: opening one closes the others
   *    (Chrome 120, Safari 17.2, Firefox 130). An older browser simply lets
   *    both be open — a harmless way to fail.
   *
   * 2. THE PICKER WORKS WITHOUT JAVASCRIPT. The cards are the accessible way to
   *    choose a district (the map is a shortcut). Behind a JS toggle, with the
   *    map open by default, a visitor without JS would have no way to reach
   *    them. <summary> opens and closes in plain HTML.
   *
   * 3. THE SEMANTICS COME FREE. <summary> is announced as a button with its
   *    expanded state and works from the keyboard; no ARIA is added, because
   *    the element already says it.
   *
   * DEPARTURE FROM THE FRAME: 44px tall, not the frame's 40 — the handoff's
   * touch-target minimum (§10). Revert by removing `min-height`.
   */

  interface Props {
    label: string;
    /** Panels sharing a name are mutually exclusive. */
    name: string;
    open?: boolean;
    children: Snippet;
  }

  let { label, name, open = false, children }: Props = $props();

  let details = $state<HTMLDetailsElement>();

  /**
   * `open` can change after hydration: the entry page opens the district list
   * on desktop, which prerender cannot know. Svelte does not repair an
   * attribute that differs from the server's HTML during hydration, so the
   * attribute alone would leave the list shut. This applies the prop to the
   * element whenever it changes, and otherwise leaves the reader's own
   * toggling alone.
   */
  $effect(() => {
    if (details) details.open = open;
  });
</script>

<details class="panel" {name} {open} bind:this={details}>
  <summary class="toggle">
    <span class="label">{label}</span>
    <ChevronDownIcon class="chevron" />
  </summary>
  <div class="content">
    {@render children()}
  </div>
</details>

<style>
  .toggle {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-200);
    min-height: var(--touch-target-min);
    padding: var(--space-300);
    box-sizing: border-box;
    background: var(--color-surface-sunken);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    cursor: pointer;
    list-style: none; /* the default disclosure triangle */
  }

  /* Optical centring. AUTHENTIC Sans Pro's line box carries 11px of ascent
     and 3px of descent at 14px, and CSS centres the whole box - so the
     capitals sat 1.5px high (measured). Figma trims text to its cap height
     (text-box-trim); the label does the same here. Where text-box is
     unsupported (Firefox), a 0.1em nudge does the same job. Scoped to this
     label: the site-wide text-box-trim question is still open
     (FRONTEND_STATUS.md, open question 4). */
  .label {
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .label {
      position: relative;
      top: 0.1em;
    }
  }

  .toggle::-webkit-details-marker {
    display: none; /* Safari's version of the triangle */
  }

  .toggle :global(.chevron) {
    transition: transform 150ms ease;
  }

  .panel[open] .toggle :global(.chevron) {
    transform: rotate(180deg);
  }

  @media (prefers-reduced-motion: reduce) {
    .toggle :global(.chevron) {
      transition: none;
    }
  }

  .content {
    padding-top: var(--space-300);
  }
</style>
