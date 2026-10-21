<script lang="ts">
  import { displayName, listSubtitle, type ListGroup } from '$lib/resourceList';

  /**
   * The resources the map is showing, as a list: one group per category, a
   * row per resource. Figma: ResourceListGroupHeader 265:163 and
   * ResourceListItem 265:162. Used by the desktop pane over the docked map and
   * by the phone sheet's List tab.
   *
   * WHY IT EXISTS (measured, 2026-10-20): 128 points sit on top of one another
   * at 47 spots, up to 15 deep, and a click reaches only the top one. And map
   * points are not focusable, so without this a keyboard or screen-reader user
   * could reach no resource from the map at all. This list is that route.
   *
   * A ROW SELECTS, IT DOES NOT NAVIGATE. Clicking one does what clicking its
   * point does, for every source (Andrew, 2026-10-20): the caller writes
   * `?resource=`, the map eases to the point and the Popup opens. The detail
   * page is the Popup's link, as before. So a row is a <button>, and the
   * selected one carries aria-current.
   *
   * Selection runs the other way too: when a point is clicked on the map, the
   * effect below scrolls its row into view.
   */

  interface Props {
    groups: ListGroup[];
    /** The resource in `?resource=`, if any. */
    selectedId: string | null;
    /** Fired with the row that was clicked, so focus can return to it when the
     *  Popup closes. */
    onSelect: (resourceId: string, row: HTMLElement) => void;
    /** Group headings' level: 3 under the desktop pane's own heading, 2 in the
     *  phone sheet, which has none. */
    headingLevel?: 2 | 3;
    /** Prefix for the heading ids, so two lists can coexist. */
    idBase: string;
    /** The desktop pane's lighter treatment: see `.is-light` below. */
    light?: boolean;
    /** Fired with the row under the mouse or keyboard focus, null when none,
     *  so the map can draw that row's point hovered. */
    onHover?: (resourceId: string | null) => void;
  }

  let { groups, selectedId, onSelect, headingLevel = 3, idBase, light = false, onHover }: Props =
    $props();

  /**
   * The row being pointed at, mirrored onto its point (Andrew, 2026-10-21).
   *
   * Mouse only, not touch: a tap fires pointerenter with no pointerleave
   * until the next tap elsewhere, which would leave a point stuck hovered on
   * a phone. Keyboard focus counts too, when it is visible focus, so tabbing
   * down the list shows each point in turn.
   */
  let hovered: string | null = null;

  function hover(id: string | null) {
    if (hovered === id) return;
    hovered = id;
    onHover?.(id);
  }

  // A row can vanish under the pointer (its category switched off) without a
  // pointerleave; so can the whole list. Neither may leave a point hovered.
  $effect(() => {
    const ids = new Set(groups.flatMap((g) => g.rows.map((r) => r.resource_id)));
    if (hovered && !ids.has(hovered)) hover(null);
  });
  $effect(() => () => hover(null));

  let root = $state<HTMLElement>();

  /**
   * Bring the selected row into view inside the list's own scroller.
   *
   * Not scrollIntoView(): that scrolls EVERY scrollable ancestor, and on the
   * phone the map screen is an overflow-hidden flex column one viewport tall,
   * which a programmatic scroll can still shift, pushing the sheet off screen.
   * This scrolls only the nearest scroller, and only as far as needed.
   *
   * The group headings are sticky, so "in view" starts below the heading
   * sitting over the top of the scroller, not at its top edge.
   */
  $effect(() => {
    const id = selectedId;
    if (!root || !id) return;
    const row = root.querySelector<HTMLElement>(`[data-resource-id="${CSS.escape(id)}"]`);
    const scroller = row && nearestScroller(row);
    if (!row || !scroller) return;

    const heading = row.closest('section')?.querySelector<HTMLElement>('.heading');
    const top = row.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
    const bottom = top + row.offsetHeight;
    const clear = heading?.offsetHeight ?? 0;
    if (top < clear) scroller.scrollTop += top - clear;
    else if (bottom > scroller.clientHeight) scroller.scrollTop += bottom - scroller.clientHeight;
  });

  function nearestScroller(el: HTMLElement): HTMLElement | null {
    for (let node = el.parentElement; node; node = node.parentElement) {
      const { overflowY } = getComputedStyle(node);
      if ((overflowY === 'auto' || overflowY === 'scroll') && node.scrollHeight > node.clientHeight) return node;
    }
    return null;
  }
</script>

<div class="list" class:is-light={light} bind:this={root}>
  {#each groups as group (group.category.slug)}
    <section aria-labelledby="{idBase}-{group.category.slug}">
      <svelte:element this={`h${headingLevel}`} class="heading" id="{idBase}-{group.category.slug}">
        <span class="mark" aria-hidden="true">{group.mark}</span>
        <span class="label">{group.category.label}</span>
        <span class="count">
          {group.rows.length}
          <span class="visually-hidden">resources</span>
        </span>
      </svelte:element>

      <ul class="rows">
        {#each group.rows as resource (resource.resource_id)}
          {@const subtitle = listSubtitle(resource)}
          <li>
            <button
              type="button"
              class="row"
              data-resource-id={resource.resource_id}
              aria-current={resource.resource_id === selectedId ? 'true' : undefined}
              onclick={(e) => onSelect(resource.resource_id, e.currentTarget)}
              onpointerenter={(e) => e.pointerType === 'mouse' && hover(resource.resource_id)}
              onpointerleave={(e) => e.pointerType === 'mouse' && hover(null)}
              onfocus={(e) => e.currentTarget.matches(':focus-visible') && hover(resource.resource_id)}
              onblur={() => hover(null)}
            >
              <span class="name">{displayName(resource.name)}</span>
              {#if subtitle}
                <span class="line">{subtitle}</span>
              {/if}
              <!-- Absent on every FRANC record. -->
              {#if resource.address}
                <span class="line">{resource.address}</span>
              {/if}
            </button>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</div>

<style>
  .list {
    display: flex;
    flex-direction: column;
  }

  /* ResourceListGroupHeader. Deliberately NOT the toggle row's look: a rule
     under it and a grey count, so it never reads as something to switch.
     Sticky, so the category stays named while its rows scroll under it. */
  .heading {
    position: sticky;
    top: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: var(--space-200);
    margin: 0;
    padding: var(--space-400) var(--space-300) var(--space-200);
    background: var(--color-surface);
    border-bottom: 0.4px solid var(--color-text-primary);

    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
  }

  /* The panel's category mark, and the letter on this category's points. */
  .mark {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--space-400);
    height: var(--space-400);
    border: 0.75px solid currentColor;
    border-radius: var(--radius-sm);
    font-family: var(--font-mono-icon);
    font-style: italic;
    font-weight: var(--font-weight-regular);
    /* Optical centring (2026-10-21). Centred by its line box, a lowercase
       letter sits low: c, e, o and s measured 1.1px below centre in a 16px
       mark, 1.5px in a 20px point. Text lands on whole pixels, so the finest
       available correction is one step up, which this is. Measured in the
       app: c/e/o/s within 0.25px of centre; ascender letters (b, d, hc, l)
       0.75-0.9px high, the usual trade when lowercase marks are centred on
       their x-height. g and f keep their descenders. Same rule in
       MapToggle, ResourceRow, ResourceList and Map.svelte's point. */
    padding-bottom: 0.1em;
  }

  .label {
    flex: 1 0 0;
    min-width: 0;
  }

  .count {
    flex-shrink: 0;
    font-weight: var(--font-weight-regular);
    color: var(--color-text-secondary);
  }

  .rows {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  /* ResourceListItem: the Popup's three lines in the Popup's type. */
  .row {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
    width: 100%;
    padding: var(--space-200) var(--space-300);

    background: none;
    border: 0;
    border-bottom: 1px solid var(--color-border);
    text-align: left;
    font: inherit;
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    cursor: pointer;
    overflow-wrap: break-word;
  }

  .row:hover {
    background: var(--color-surface-muted);
  }

  /* Selected: the fill alone (Andrew, 2026-10-20, dropping the side bar).
     aria-current carries it for anyone who cannot see the colour. */
  .row[aria-current='true'] {
    background: var(--color-accent-muted);
  }

  /* Inside the row, so neighbouring rows and the pane's edge cannot clip it. */
  .row:focus-visible {
    outline-offset: -2px;
  }

  .name {
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
  }

  /* The desktop pane, lighter (Andrew, 2026-10-20: the pane outweighed the
     rest of the page). Measured on q14 at 1440x900, with the pane's shadow
     in place of its border: about 20% less ink, one more row in 389px.
     Names drop to 12px bold, the toolbar labels' size; the operator and
     address go grey, so the name is the only black text in a row; the group
     rule goes from 0.4px black to the 1px grey of the row dividers, which
     stay. #707070 is 4.84:1 on the surface, AA. */
  .is-light .name {
    font-size: var(--font-size-small);
  }

  .is-light .line {
    color: var(--color-text-secondary);
  }

  /* Back to black on a filled row: #707070 is 4.17:1 on the selected blue
     and about the same on the hover grey, under AA's 4.5 (axe, 2026-10-20). */
  .is-light .row:hover .line,
  .is-light .row[aria-current='true'] .line {
    color: var(--color-text-primary);
  }

  .is-light .heading {
    border-bottom: 1px solid var(--color-border);
  }

  /* DEPARTURE FROM THE FRAME, phones only: 44px rows (§10). A FRANC row is one
     line, 33px at the frame's 8px padding. Desktop keeps the frame's density,
     as MapToggle does: a pointer, and WCAG 2.5.8's 24px is met. */
  @media (max-width: 1023.98px) {
    .row {
      min-height: var(--touch-target-min);
      justify-content: center;
    }
  }
</style>
