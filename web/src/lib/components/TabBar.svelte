<script lang="ts">
  /**
   * The map sheet's Resources / Layers tabs. Figma: Tab Bar, node
   * I68:1103;68:1057 — a 0.5px rule beneath, the active tab bold and
   * underlined, the inactive one regular.
   *
   * REAL TABS, not styled buttons (§10): `role="tablist"`, each tab
   * `role="tab"` with `aria-selected` and `aria-controls`, and the panel
   * `role="tabpanel"` back-referenced by `aria-labelledby`. Without that, a
   * screen reader gets two buttons and no indication that one of them is
   * currently showing.
   *
   * Arrow-key navigation is part of the tab pattern rather than a nicety: with
   * `tabindex="-1"` on the inactive tab, Tab moves past the whole tablist in
   * one press and Left/Right moves between tabs, which is what a screen-reader
   * user expects once `role="tablist"` is announced.
   *
   * The tabs sit at x 79.33 and 218.67 in a 358px bar, which is
   * `justify-content: space-evenly` with two 60px items — not the
   * `justify-between` Figma's export reports for the outer frame.
   */

  interface Tab {
    id: string;
    label: string;
  }

  interface Props {
    tabs: Tab[];
    active: string;
    onSelect: (id: string) => void;
    /** Prefix for the generated tab/panel ids, so two tab bars can coexist. */
    idBase: string;
  }

  let { tabs, active, onSelect, idBase }: Props = $props();

  let buttons: HTMLButtonElement[] = [];

  function onKeydown(event: KeyboardEvent, index: number) {
    const last = tabs.length - 1;
    let next: number | null = null;

    if (event.key === 'ArrowRight') next = index === last ? 0 : index + 1;
    else if (event.key === 'ArrowLeft') next = index === 0 ? last : index - 1;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = last;
    if (next === null) return;

    event.preventDefault();
    onSelect(tabs[next].id);
    // Focus follows selection in an automatic tablist, which is the right
    // choice here: switching tabs swaps the panel's whole contents, so leaving
    // focus behind would strand it on a control that no longer relates.
    buttons[next]?.focus();
  }
</script>

<div class="tabbar" role="tablist">
  {#each tabs as tab, i (tab.id)}
    <button
      bind:this={buttons[i]}
      type="button"
      role="tab"
      id="{idBase}-tab-{tab.id}"
      aria-selected={tab.id === active}
      aria-controls="{idBase}-panel"
      tabindex={tab.id === active ? 0 : -1}
      class="tab"
      class:is-active={tab.id === active}
      onclick={() => onSelect(tab.id)}
      onkeydown={(e) => onKeydown(e, i)}
    >
      {tab.label}
    </button>
  {/each}
</div>

<style>
  .tabbar {
    display: flex;
    align-items: center;
    justify-content: space-evenly;
    width: 100%;
    padding-bottom: 6px;
    border-bottom: 0.5px solid var(--color-text-secondary);
  }

  .tab {
    background: none;
    border: 0;
    font: inherit;
    color: var(--color-text-primary);
    cursor: pointer;

    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);

    /* 44px (WCAG 2.5.5) on a 12px label. The bar itself stays 19px tall in the
       design, so the target is taken as padding and pulled back with a
       negative margin rather than growing the bar. */
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
    padding-inline: var(--space-200);
  }

  /* Bold AND underlined. Weight alone is not a reliable cue at 12px, and
     aria-selected carries it for anyone who cannot see either. */
  .is-active {
    font-weight: var(--font-weight-bold);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
</style>
