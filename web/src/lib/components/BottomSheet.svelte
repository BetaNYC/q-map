<script lang="ts">
  import type { Snippet } from 'svelte';

  /**
   * The map screen's bottom sheet — peek and expanded, with a drag handle.
   *
   * Lifted from d26's `Sidebar.svelte`, which handoff §3 says is worth taking
   * rather than rebuilding, and which carries two findings that are easy to
   * rediscover the hard way. Both are below, marked.
   *
   * Figma: the Bottom Sheet frames in "04 Map - Mobile" — a 36x4 handle, the
   * sheet at 123px in Peek and filling the body in Show.
   */

  interface Props {
    /** The frozen header — the tab bar. Stays put while the body scrolls. */
    header: Snippet;
    /** The scrolling contents. */
    children: Snippet;
    /** Accessible name for the sheet itself. */
    label: string;
  }

  let { header, children, label }: Props = $props();

  /** Matches --sheet-peek. Kept in sync by hand, as in d26. */
  const PEEK_PX = 123;
  /** Matches .is-expanded's height. */
  const EXPANDED_FRAC = 0.72;

  let expanded = $state(false);
  let sheetEl = $state<HTMLElement>();
  let scrollEl = $state<HTMLElement>();

  let dragging = $state(false);
  let dragHeight = $state<number | null>(null);
  let dragStartY = 0;
  let dragStartH = 0;
  let dragMoved = false;
  let suppressClick = false;

  function stageHeight(): number {
    return (sheetEl?.offsetParent as HTMLElement | null)?.clientHeight ?? window.innerHeight;
  }

  function onPointerDown(e: PointerEvent) {
    if (!sheetEl) return;
    dragging = true;
    dragMoved = false;
    dragStartY = e.clientY;
    dragStartH = sheetEl.offsetHeight;
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  }

  function onPointerMove(e: PointerEvent) {
    if (!dragging) return;
    const dy = dragStartY - e.clientY; // drag up = grow
    if (Math.abs(dy) > 4) dragMoved = true;
    dragHeight = Math.max(PEEK_PX, Math.min(stageHeight() * 0.9, dragStartH + dy));
  }

  function onPointerUp() {
    if (!dragging) return;
    dragging = false;
    if (dragMoved) {
      const mid = (PEEK_PX + stageHeight() * EXPANDED_FRAC) / 2;
      expanded = (dragHeight ?? PEEK_PX) >= mid;
      suppressClick = true; // a click fires after a drag; ignore it
    }
    dragHeight = null;
  }

  function onClick() {
    // §10: a non-gesture way to collapse the sheet is required. Swipe alone is
    // insufficient, so the handle is a real button that toggles on tap and on
    // Enter/Space, and the drag is an enhancement on top.
    if (suppressClick) {
      suppressClick = false;
      return;
    }
    expanded = !expanded;
  }

  $effect(() => {
    if (!sheetEl) return;

    /**
     * LIFTED FIX 1 — publish the sheet's live height as a CSS custom property.
     *
     * The map's own controls have to sit above the sheet's top edge as it
     * moves, including mid-transition. A media query cannot know where the
     * edge is, and reading it per frame from the map would couple the two
     * components. A ResizeObserver writing `--sheet-height` on :root lets the
     * map position against it in pure CSS.
     */
    const measureGutter = () => {
      if (!scrollEl) return;
      /**
       * LIFTED FIX 2 — measure the reserved scrollbar gutter at runtime.
       *
       * `scrollbar-gutter: stable` below reserves space whether or not the
       * content scrolls, which stops the panel's width changing the moment a
       * scrollbar appears — wrapping prose then reflows, which can change the
       * height, which can remove the scrollbar, and the panel never settles.
       *
       * The reserved width is 0 on overlay-scrollbar systems and ~15px with
       * classic ones, and on macOS it differs by INPUT DEVICE. So it is
       * measured rather than guessed: a hardcoded value is wrong for whichever
       * kind the device is not, and the content's right edge stops lining up
       * with the header's.
       */
      scrollEl.style.setProperty(
        '--scrollbar-gutter-w',
        `${scrollEl.offsetWidth - scrollEl.clientWidth}px`
      );
    };

    measureGutter();

    const ro = new ResizeObserver(() => {
      document.documentElement.style.setProperty('--sheet-height', `${sheetEl!.offsetHeight}px`);
      measureGutter();
    });
    ro.observe(sheetEl);

    return () => {
      ro.disconnect();
      document.documentElement.style.removeProperty('--sheet-height');
    };
  });
</script>

<section
  class="sheet"
  class:is-expanded={expanded}
  class:is-dragging={dragging}
  style={dragHeight !== null ? `height:${dragHeight}px` : undefined}
  bind:this={sheetEl}
  aria-label={label}
>
  <div class="frozen">
    <button
      type="button"
      class="handle"
      aria-expanded={expanded}
      onpointerdown={onPointerDown}
      onpointermove={onPointerMove}
      onpointerup={onPointerUp}
      onpointercancel={onPointerUp}
      onclick={onClick}
    >
      <span class="grip" aria-hidden="true"></span>
      <span class="visually-hidden">
        {expanded ? 'Collapse the list' : 'Expand the list'}
      </span>
    </button>

    {@render header()}
  </div>

  <div class="scroll" bind:this={scrollEl}>
    {@render children()}
  </div>
</section>

<style>
  .sheet {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 2;

    display: flex;
    flex-direction: column;
    height: var(--sheet-peek, 123px);

    background: var(--color-surface);
    border-radius: 8px 8px 0 0;
    box-shadow: 0 -2px 12px rgb(0 0 0 / 0.12);

    /* The handle is 36x4 at the top; the sheet's own padding matches the
       358px measure inside a 390px frame. */
    padding-inline: var(--gutter);

    transition: height 220ms ease;
  }

  /* Dragging follows the finger, so the transition has to be off or every
     frame animates toward the last one and the sheet lags behind the touch. */
  .is-dragging {
    transition: none;
  }

  .is-expanded {
    height: 72%;
  }

  /* §10: the sheet transition must respect prefers-reduced-motion. */
  @media (prefers-reduced-motion: reduce) {
    .sheet {
      transition: none;
    }
  }

  .frozen {
    flex-shrink: 0;
  }

  .handle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    /* The grip is 4px tall; the target is 44px (WCAG 2.5.5). */
    height: var(--touch-target-min);
    background: none;
    border: 0;
    cursor: grab;
    /* Stop the browser claiming the vertical gesture for page scroll. */
    touch-action: none;
  }

  .grip {
    width: 36px;
    height: 4px;
    border-radius: 2px;
    background: var(--color-border);
  }

  .scroll {
    flex: 1 1 auto;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;

    /* See LIFTED FIX 2. --scrollbar-gutter-w is written at runtime. */
    --scrollbar-gutter-w: 0px;
    scrollbar-gutter: stable;
    padding-right: max(0px, calc(var(--space-200) - var(--scrollbar-gutter-w)));
  }
</style>
