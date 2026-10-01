<script lang="ts">
  import { activeTimes, endedTimes } from '$lib/alertTimes';
  import type { AlertView } from '$lib/alerts.svelte';
  import AlertBody from './AlertBody.svelte';
  import AlertEntry from './AlertEntry.svelte';

  /**
   * One alert on the alerts page. Figma: AlertDetail, node 172:63 —
   * state=active|ended.
   *
   * ENDED: an alert that expired or was withdrawn while the page was open
   * (AlertsStore, rule 2). Its links render as plain text — the translations
   * link included, deliberately black: it is inactive, and link blue would
   * promise a destination that is no longer relevant.
   *
   * DEPARTURE FROM THE FRAME: the frame greys the ended state with 50% opacity.
   * That takes body text to ~3.6:1 and the grey times line to ~1.9:1 — both
   * below WCAG AA's 4.5:1 (handoff §10, a requirement). Here the whole block
   * takes --color-text-secondary instead (4.84:1). To match the frame exactly,
   * replace the `.ended` rule with `opacity: 0.5` — and accept the failure.
   * The state is also stated in words: the times line reads "… – Ended 9:19 AM".
   */

  interface Props {
    alert: AlertView;
    now: Date;
  }

  let { alert, now }: Props = $props();

  const p = $derived(alert.feature.properties);
  const ended = $derived(alert.endedAt !== null);
  const times = $derived(
    alert.endedAt
      ? endedTimes(new Date(p.sent), alert.endedAt, now)
      : activeTimes(new Date(p.sent), new Date(p.expires), now)
  );
</script>

<article class="detail" class:ended>
  <AlertEntry properties={p} as="h2" />
  <p class="times">{times}</p>
  <AlertBody body={p.body} interactive={!ended} />
  {#if p.translations_url}
    {#if ended}
      <p class="translations">View in ASL and 12 languages</p>
    {:else}
      <a class="translations" href={p.translations_url} rel="noopener noreferrer">View in ASL and 12 languages</a>
    {/if}
  {/if}
</article>

<style>
  .detail {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-200);
    padding: var(--space-300);
  }

  .detail > :global(*) {
    align-self: stretch;
  }

  .times {
    margin: 0;
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
    color: var(--color-text-secondary);
  }

  .translations {
    align-self: flex-start;
    margin: 0;
    font-size: var(--font-size-small);
    text-decoration: underline;
  }

  .ended {
    color: var(--color-text-secondary);
  }

  .ended :global(a) {
    color: inherit;
  }
</style>
