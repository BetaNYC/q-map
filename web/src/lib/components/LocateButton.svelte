<script lang="ts">
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { loadBoundaries } from '$lib/boundaries';
  import { placePoint } from '$lib/geo';
  import type { DistrictIndexEntry } from '$lib/types';

  /**
   * "Use my location". Figma: Location, node 86:1938 — the outlined button
   * style shared with the entry panels (EntryPanel.svelte).
   *
   * Finds the device's position, places it in a district ($lib/geo), and goes
   * STRAIGHT to that district's page (decided 2026-09-30) — no confirmation.
   *
   * WHEN IT DOES NOT NAVIGATE, it says why, in a polite live region under the
   * button, and every message ends at the district list, which always works:
   *   - permission denied, unavailable, timed out
   *   - fixed too loosely to choose a district (accuracy > 2 km)
   *   - in another borough — named, since districts.json has all 59
   *   - in no district — outside NYC, or a park or airport (cdta.geojson
   *     holds no Joint Interest Areas)
   *
   * WITHOUT JAVASCRIPT it is hidden (the <noscript> style below) rather than
   * shown as a button that does nothing. It is rendered in the prerendered
   * HTML so it does not push the panels down when the page hydrates.
   */

  interface Props {
    /** All 59 — so a point in another borough can be named. */
    districts: DistrictIndexEntry[];
  }

  let { districts }: Props = $props();

  /** Beyond this, a fix cannot be trusted to land in the right district. */
  const MAX_ACCURACY_M = 2000;

  let busy = $state(false);
  let message = $state('');
  let supported = $state(true);

  $effect(() => {
    supported = 'geolocation' in navigator;
  });

  const LIST = 'Choose a district from the list.';

  function position(): Promise<GeolocationPosition> {
    return new Promise((resolve, reject) =>
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true,
        timeout: 15_000,
        maximumAge: 60_000
      })
    );
  }

  function failure(error: unknown): string {
    const code = (error as GeolocationPositionError)?.code;
    if (code === 1) return `Location access is turned off for this site. You can allow it in your browser's settings. ${LIST}`;
    if (code === 2) return `Your location isn't available right now. ${LIST}`;
    if (code === 3) return `Finding your location took too long. Try again, or ${LIST.toLowerCase()}`;
    return `Your location couldn't be matched to a district. ${LIST}`;
  }

  async function locate() {
    if (busy) return;
    busy = true;
    message = '';
    try {
      const [pos, features] = await Promise.all([position(), loadBoundaries()]);
      const { longitude, latitude, accuracy } = pos.coords;
      if (accuracy > MAX_ACCURACY_M) {
        message = `Your location is only known to within ${Math.round(accuracy / 1000)} km, which isn't precise enough to choose a district. ${LIST}`;
        return;
      }
      const placed = placePoint([longitude, latitude], features, districts);
      if (placed.kind === 'queens') {
        await goto(`${base}/${placed.district.slug}`);
        return;
      }
      message =
        placed.kind === 'elsewhere'
          ? `You're in ${placed.district.display_name}, ${placed.district.boro}. This map covers the 14 Queens community districts. ${LIST}`
          : `That location isn't in a Queens community district. It may be outside the city, or in a park or airport. ${LIST}`;
    } catch (error) {
      message = failure(error);
    } finally {
      busy = false;
    }
  }
</script>

<svelte:head>
  <noscript><style>.locate { display: none !important; }</style></noscript>
</svelte:head>

{#if supported}
  <div class="locate">
    <button type="button" class="button" onclick={locate} aria-busy={busy}>
      <span class="label">{busy ? 'Finding your location…' : 'Use my location'}</span>
    </button>
    <p class="message" role="status">{message}</p>
  </div>
{/if}

<style>
  .locate {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  /* The entry panels' outlined button (EntryPanel.svelte), as a <button>. */
  .button {
    display: flex;
    align-items: center;
    width: 100%;
    min-height: var(--touch-target-min);
    padding: var(--space-300);
    box-sizing: border-box;
    background: var(--color-surface-sunken);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    color: var(--color-text-primary);
    font: inherit;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    text-align: left;
    cursor: pointer;
  }

  .button[aria-busy='true'] {
    cursor: progress;
  }

  /* Optical centring, as in EntryPanel - see the note there. */
  .label {
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .label {
      position: relative;
      top: 0.1em;
    }
  }

  .message {
    margin: 0;
    padding-inline: var(--space-200);
    font-size: var(--font-size-small);
    line-height: var(--line-height-prose);
  }

  .message:empty {
    display: none;
  }
</style>
