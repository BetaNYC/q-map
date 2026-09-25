<script lang="ts">
  import { base } from '$app/paths';
  import ArrowRightIcon from '$lib/icons/ArrowRightIcon.svelte';
  import { detailLinkText, detailPath, subtitleFor } from '$lib/resources';
  import type { Resource } from '$lib/types';

  /**
   * The map popup. Three lines — name, subtitle, address — plus a conditional
   * detail link.
   *
   * Figma: Popup, node 77:1708.
   *
   * IT NEEDS A JOIN. The map feature carries only resource_id, name, category,
   * source and is_coad_member. `address` and `operator` are not on the feature
   * and come from resources/<slug>.json, joined on resource_id. The category
   * LABEL is a third lookup, from the district payload's resource_categories —
   * the feature and the record both carry only the slug.
   *
   * This component takes the joined result rather than doing the join, so it
   * stays renderable from a list, a permalink or a map click without knowing
   * which.
   *
   * THREE BOOLEANS IN FIGMA, TWO HERE. Figma exposes hasAddress, hasDetail and
   * hasOperator. The first two are real. The third is not: the subtitle is
   * never empty, because `category` is present on all 3,795 records, so the
   * fallback always resolves. §7.4 is explicit that this is why there is no
   * boolean for it. Modelling one would invite a caller to hide a line that
   * cannot be empty.
   */

  interface Props {
    resource: Resource;
    /** Resolved from the district's resource_categories — the record has only a slug. */
    categoryLabel: string;
    districtSlug: string;
    /** Fired by the close control. Focus returns to the trigger in the caller. */
    onClose?: () => void;
  }

  let { resource, categoryLabel, districtSlug, onClose }: Props = $props();

  let container = $state<HTMLElement>();

  /**
   * §10: "focus moves into it on open and returns to the trigger on close;
   * Escape closes; a visible close control is required".
   *
   * Focus moves to the popup itself rather than to the close button — the
   * close button is the LAST thing a keyboard user wants to land on, and
   * putting focus on the container means the name and address are announced
   * before the controls.
   *
   * `tabindex="-1"` makes the container programmatically focusable without
   * adding it to the tab order. Returning focus is the caller's job, because
   * only the caller knows what the trigger was — a map point or a list row.
   */
  $effect(() => {
    container?.focus();
  });

  function onKeydown(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    // Stop the map's own Escape handling (exiting fullscreen, cancelling a
    // gesture) from also firing on the same press.
    event.stopPropagation();
    onClose?.();
  }

  const subtitle = $derived(subtitleFor(resource, categoryLabel));
  const href = $derived(detailPath(resource, districtSlug));
</script>

<!-- role="dialog" so a screen reader announces the boundary, and
     aria-labelledby points at the name so entering it says which resource.
     Not `aria-modal`: the map behind stays usable and nothing is trapped. -->
<div
  class="popup"
  bind:this={container}
  role="dialog"
  tabindex="-1"
  aria-labelledby="popup-name"
  onkeydown={onKeydown}
>
  <div class="lines">
    <p class="name" id="popup-name">{resource.name}</p>

    <!-- Unconditional. Operator where it differs from the name, category label
         otherwise — see $lib/resources for the comparison rule. -->
    <p class="subtitle">{subtitle}</p>

    <!-- Missing on 82 of 3,795 records: all 79 FRANC, plus 3 FacDB. -->
    {#if resource.address}
      <p class="address">{resource.address}</p>
    {/if}
  </div>

  {#if href}
    <!-- §10: link text must stand alone. The visible text is §7.4's wording,
         and the resource name is appended in the accessible name so a screen
         reader hears "Contact and services, Greek Cultural Center, Inc."
         rather than a string that could belong to any of 248 links. -->
    <!-- detailPath() returns a site-relative path; `base` is applied here, the
         same as every other link in the app. Without it this resolves to the
         origin root and 404s under /q-map/. -->
    <a class="detail" href="{base}{href}">
      <span aria-hidden="true">{detailLinkText(resource)}</span>
      <span class="visually-hidden">{detailLinkText(resource)}, {resource.name}</span>
      <ArrowRightIcon />
    </a>
  {/if}

  {#if onClose}
    <!-- §10 requires a visible close control; dismissing by tapping the map is
         not enough, and Escape alone is not reachable by touch. Figma draws no
         close control on the Popup component — flagged in web/README.md. -->
    <button type="button" class="close" onclick={onClose}>
      <span class="visually-hidden">Close {resource.name}</span>
      <span aria-hidden="true">&times;</span>
    </button>
  {/if}
</div>

<style>
  .popup {
    position: relative;
    /* Focused programmatically on open; the ring would otherwise draw around
       the whole card for a mouse user who never asked for it. :focus-visible
       still applies to the controls inside. */
    outline: none;

    /* A COLUMN, not a row. The frame used to put the detail link to the right
       of the three lines; it now sits below them, under a 16px gap. The lines
       therefore get the full 256px measure instead of splitting it with the
       link, which is what stops a three-line name from becoming a five-line
       one. */
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-400);
    width: 280px;

    padding-inline: var(--space-300);
    padding-block: var(--space-200);

    border: 0.4px solid var(--color-text-primary);
    border-radius: 1px; /* Figma's literal; no token for it */

    /* Figma applies opacity: 0.95 to the whole frame. Here it is 95% on the
     * BACKGROUND only, so the text composites at full strength.
     *
     * The distinction matters because this sits over map imagery. §10 already
     * flags it: "the popup's 95% white fill sits over map imagery, so the
     * composite is what matters." Fading the text as well makes its contrast a
     * function of whatever tiles happen to be underneath, which cannot be
     * measured or guaranteed. The fill still reads as translucent.
     *
     * Revert to `opacity: .95` on the element for literal fidelity. */
    background: rgb(254 252 250 / 0.95); /* --color-off-white/primary at 95% */

    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
  }

  .lines {
    /* Figma's text nodes are `w-full`. In a row that fell out of the layout;
       in a column the block would hug its longest word instead, so it is
       stretched explicitly. Without this, names wrap at unpredictable widths. */
    align-self: stretch;

    display: flex;
    flex-direction: column;
    gap: var(--space-200);
    min-width: 0;

    /* Reserve the close glyph's ink. The control is a 44px box pinned to the
       top-right, but the × inside it draws about 8px wide centred at 22px in,
       so it covers the last ~14px of the content box. In the old row layout
       that overlapped the detail link, which was short and right-aligned and
       never reached it. In a column it would sit on top of the NAME, and names
       are long. 16px is the next token up from the 14px actually needed.

       Figma draws no close control at all — see the note on .close. */
    padding-right: var(--space-400);
  }

  .lines p {
    margin: 0;
    overflow-wrap: break-word;
  }

  .name {
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
  }

  .detail {
    display: flex;
    align-items: center;
    gap: var(--space-100);

    /* `flex: 1 0 0` and `justify-content: flex-end` are gone with the row: the
       link no longer claims the leftover width, it hugs its text at the left
       edge under the address. Figma still carries `justify-end` on this frame,
       but the frame hugs its content inside an `items-start` column, so it has
       nothing to distribute and no visible effect. */
    font-size: var(--font-size-caption);
    color: inherit;
    white-space: nowrap;
  }

  .close {
    position: absolute;
    top: 0;
    right: 0;

    /* 44px hit area (WCAG 2.5.5) on a glyph that draws far smaller. The box
     * extends past the text it sits beside; `.lines` reserves the glyph's ink
     * so nothing renders underneath it, and the button is last in the source
     * so a touch in the overlap resolves to close. */
    width: var(--touch-target-min);
    height: var(--touch-target-min);

    display: flex;
    align-items: center;
    justify-content: center;

    background: none;
    border: 0;
    font: inherit;
    font-size: var(--font-size-body);
    color: var(--color-text-primary);
    cursor: pointer;
  }
</style>
