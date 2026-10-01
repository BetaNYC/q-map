<script lang="ts">
  import { relativeTime } from '$lib/alertTimes';
  import type { AlertProperties } from '$lib/alerts';

  /**
   * One alert's identity: the event, where, and (in the banner) how long ago.
   * Figma: AlertEntry, node 144:2637 — variants scope=queens|citywide|unknown.
   *
   * THE PLACE LINE IS COMPOSED HERE, from `scope` and `location`
   * (ALERTS_SERVICE.md, "The headline is the location"):
   *   queens   -> "Hillside Avenue, Queens"   or "Queens"
   *   citywide -> "Midtown, Citywide"         or "Citywide"
   *   unknown  -> "Hillside Avenue"           or nothing — an unrecognised tag
   *               names no borough, so none is claimed
   * `location` is shown verbatim and never interpreted.
   *
   * `event` is null only for a headline outside the grammar; the raw headline
   * stands in.
   */

  interface Props {
    properties: AlertProperties;
    /** h2 on the alerts page, where each alert is a section; p in the banner. */
    as?: 'p' | 'h2';
    /** The banner's "9 min ago" line. Needs `now`. */
    showTime?: boolean;
    now?: Date;
  }

  let { properties, as = 'p', showTime = false, now }: Props = $props();

  const SCOPE_LABEL = { queens: 'Queens', citywide: 'Citywide', unknown: null } as const;

  const place = $derived.by(() => {
    const scope = SCOPE_LABEL[properties.scope];
    if (properties.location && scope) return `${properties.location}, ${scope}`;
    return properties.location ?? scope;
  });
</script>

<div class="entry">
  <svelte:element this={as} class="event">{properties.event ?? properties.headline}</svelte:element>
  {#if place}<p class="place">{place}</p>{/if}
  {#if showTime && now}
    <p class="time">{relativeTime(new Date(properties.sent), now)}</p>
  {/if}
</div>

<style>
  .entry {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
  }

  .event,
  .place,
  .time {
    margin: 0;
    overflow-wrap: break-word;
  }

  .event {
    font-size: var(--font-size-small);
    font-weight: var(--font-weight-bold);
  }

  .time {
    color: var(--color-text-secondary);
  }

  /* DEPARTURE FROM THE FRAME: in the banner the time is primary black, not the
     frame's secondary grey. #707070 on the banner's #f8e8dc is 4.14:1, under
     WCAG AA's 4.5:1 (handoff §10) - axe flagged it. On the page background the
     grey passes (4.84:1), so only the banner changes. */
  :global(.banner) .time {
    color: var(--color-text-primary);
  }
</style>
