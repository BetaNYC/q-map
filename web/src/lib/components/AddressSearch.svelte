<script lang="ts">
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { loadBoundaries } from '$lib/boundaries';
  import { placePoint } from '$lib/geo';
  import { fetchSuggestions, isBareZip, type Suggestion } from '$lib/geosearch';
  import type { DistrictIndexEntry } from '$lib/types';

  /**
   * The entry page's address field. Figma: Address, node 86:1932.
   *
   * Type a street address, pick a match, go to its district - the same
   * navigation as "Use my location", through the same $lib/geo placement.
   *
   * AN ARIA 1.2 COMBOBOX (the WAI-ARIA "editable combobox with list
   * autocomplete" pattern): the input keeps focus throughout; the highlighted
   * match is announced through aria-activedescendant; ↓/↑ move, Enter picks,
   * Escape closes. Matches are chosen on mousedown with preventDefault, so
   * tapping one does not blur the input first and close the list under the
   * finger.
   *
   * THE SUGGESTION LIST IS NOT IN FIGMA. It is styled from the system - the
   * panel buttons' outline, 44px rows, borough in secondary grey - and is for
   * review.
   *
   * IT DEGRADES TO THE LIST. GeoSearch is a third-party runtime dependency;
   * a failure says so and points at the districts, which always work.
   * Without JavaScript the field is hidden (the <noscript> style) rather than
   * shown as an input that does nothing.
   *
   * A bare ZIP code is never sent (decision 3) - see isBareZip().
   */

  interface Props {
    /** All 59 - so an address in another borough can be named. */
    districts: DistrictIndexEntry[];
  }

  let { districts }: Props = $props();

  const LIST = 'Choose a district from the list.';
  const DEBOUNCE_MS = 250;
  const MIN_CHARS = 3;

  let value = $state('');
  let suggestions = $state<Suggestion[]>([]);
  let open = $state(false);
  let active = $state(-1);
  let message = $state('');
  let busy = $state(false);

  let timer: ReturnType<typeof setTimeout> | undefined;
  let inflight: AbortController | undefined;

  function close() {
    open = false;
    active = -1;
  }

  function onInput() {
    message = '';
    clearTimeout(timer);
    inflight?.abort();
    const text = value;
    if (isBareZip(text)) {
      suggestions = [];
      close();
      message = "Enter a street address. A ZIP code can cover more than one district, so it can't choose one.";
      return;
    }
    if (text.trim().length < MIN_CHARS) {
      suggestions = [];
      close();
      return;
    }
    timer = setTimeout(() => search(text), DEBOUNCE_MS);
  }

  async function search(text: string) {
    const controller = new AbortController();
    inflight = controller;
    try {
      const found = await fetchSuggestions(text, { signal: controller.signal });
      if (controller.signal.aborted) return;
      suggestions = found;
      active = -1;
      open = found.length > 0;
      if (found.length === 0) message = `No matching address found. Check the spelling, or ${LIST.toLowerCase()}`;
    } catch (error) {
      if (controller.signal.aborted || (error as Error)?.name === 'AbortError') return;
      suggestions = [];
      close();
      message = `Address search isn't available right now. ${LIST}`;
    }
  }

  async function choose(s: Suggestion) {
    value = s.label;
    close();
    busy = true;
    message = '';
    try {
      const placed = placePoint(s.point, await loadBoundaries(), districts);
      if (placed.kind === 'queens') {
        await goto(`${base}/${placed.district.slug}`);
        return;
      }
      message =
        placed.kind === 'elsewhere'
          ? `${s.label} is in ${placed.district.display_name}, ${placed.district.boro}. This map covers the 14 Queens community districts. ${LIST}`
          : `${s.label} isn't in a Queens community district. It may be in a park or airport. ${LIST}`;
    } catch {
      message = `That address couldn't be matched to a district just now. ${LIST}`;
    } finally {
      busy = false;
    }
  }

  function onKeydown(event: KeyboardEvent) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      if (!suggestions.length) return;
      event.preventDefault();
      open = true;
      const step = event.key === 'ArrowDown' ? 1 : -1;
      active = (active + step + suggestions.length) % suggestions.length;
    } else if (event.key === 'Enter') {
      if (!open || !suggestions.length) return;
      event.preventDefault();
      choose(suggestions[Math.max(active, 0)]);
    } else if (event.key === 'Escape') {
      if (open) {
        event.preventDefault();
        close();
      }
    }
  }
</script>

<svelte:head>
  <noscript><style>.address { display: none !important; }</style></noscript>
</svelte:head>

<div class="address">
  <label class="visually-hidden" for="address-input">Street address</label>
  <input
    id="address-input"
    class="input"
    type="text"
    role="combobox"
    aria-autocomplete="list"
    aria-expanded={open}
    aria-controls="address-options"
    aria-activedescendant={open && active >= 0 ? `address-option-${active}` : undefined}
    aria-busy={busy}
    autocomplete="street-address"
    placeholder="Enter your street address"
    bind:value
    oninput={onInput}
    onkeydown={onKeydown}
    onblur={close}
  />

  <ul id="address-options" class="options" role="listbox" aria-label="Matching addresses" hidden={!open}>
    {#each suggestions as s, i (s.id)}
      <li
        id="address-option-{i}"
        class="option"
        class:active={i === active}
        role="option"
        aria-selected={i === active}
        onmousedown={(e) => {
          e.preventDefault();
          choose(s);
        }}
      >
        <span class="label">{s.label}</span>
        <span class="borough">{s.borough}</span>
      </li>
    {/each}
  </ul>

  <p class="message" role="status">{message}</p>
  <p class="note">Addresses are sent to GeoSearch, NYC City Planning's address service.</p>
</div>

<style>
  .address {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  /* Figma: Address - off-white, 0.5px secondary outline, 3px radius. */
  .input {
    width: 100%;
    min-height: var(--touch-target-min);
    padding: var(--space-300);
    box-sizing: border-box;
    background: var(--color-surface);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    color: var(--color-text-primary);
    font: inherit;
    font-size: var(--font-size-body);
  }

  .input::placeholder {
    color: var(--color-text-secondary);
    opacity: 1;
  }

  .options {
    margin: 0;
    padding: 0;
    list-style: none;
    background: var(--color-surface);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    overflow: hidden;
  }

  .options[hidden] {
    display: none;
  }

  .option {
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 2px;
    min-height: var(--touch-target-min);
    padding: var(--space-200) var(--space-300);
    box-sizing: border-box;
    cursor: pointer;
  }

  .option + .option {
    border-top: 0.5px solid var(--color-border);
  }

  .option.active,
  .option:hover {
    background: var(--color-surface-sunken);
  }

  .label {
    font-size: var(--font-size-body);
    line-height: var(--line-height-tight);
  }

  .borough,
  .note {
    font-size: var(--font-size-small);
    color: var(--color-text-secondary);
    line-height: var(--line-height-tight);
  }

  .message,
  .note {
    margin: 0;
    padding-inline: var(--space-200);
  }

  .message {
    font-size: var(--font-size-small);
    line-height: var(--line-height-prose);
  }

  .message:empty {
    display: none;
  }
</style>
