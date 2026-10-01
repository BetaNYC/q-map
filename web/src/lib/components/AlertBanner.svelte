<script lang="ts">
  import { base } from '$app/paths';
  import { bannerLinkLabel } from '$lib/alertTimes';
  import { useAlerts } from '$lib/alertsContext';
  import AlertIcon from '$lib/icons/AlertIcon.svelte';
  import AlertEntry from './AlertEntry.svelte';

  /**
   * The entry page's banner. Figma: AlertBanner, node 176:908.
   *
   * RENDERS ONLY WHILE AN ALERT IS ACTIVE. Loading, unavailable and "none" all
   * render nothing, and no space is reserved (handoff §7.7) — so it can never
   * break or shift a page while there is nothing to say. Ended alerts never
   * appear here (AlertsStore, rule 4).
   *
   * At most two entries, newest first; the link label carries the full count.
   *
   * THE WHOLE BANNER IS THE TAP TARGET, but the link's accessible name is only
   * its label — a stretched link (the ::after below), not an <a> wrapped round
   * the whole block, which would read every entry out as one link name. The
   * heading gives "View details" its context.
   *
   * A labelled region, NOT a live region: it appears on every page load, and
   * announcing it each time would be noise.
   */

  const alerts = useAlerts();
  const active = $derived(alerts.view.status === 'ready' ? alerts.view.active : []);
</script>

{#if active.length > 0}
  <section class="banner" aria-labelledby="alert-banner-heading">
    <span class="mark"><AlertIcon /></span>
    <div class="text">
      <h2 id="alert-banner-heading" class="heading">Emergency Alerts</h2>
      <ul class="entries">
        {#each active.slice(0, 2) as alert (alert.properties.guid)}
          <li><AlertEntry properties={alert.properties} showTime now={alerts.now} /></li>
        {/each}
      </ul>
      <a class="link" href="{base}/alerts">{bannerLinkLabel(active.length)}</a>
    </div>
  </section>
{/if}

<style>
  .banner {
    position: relative;
    display: flex;
    align-items: flex-start;
    gap: var(--space-300);
    padding: var(--space-400) var(--space-300);
    background: var(--color-surface-alert);
    border-radius: var(--space-100); /* Figma binds the radius to space/100 */
  }

  /* The bordered 24px mark, as on COAD. */
  .mark {
    flex-shrink: 0;
    display: flex;
    border: 0.75px solid var(--color-text-primary);
    border-radius: var(--radius-sm);
  }

  .text {
    flex: 1 1 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-300);
  }

  .heading {
    margin: 0;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .entries {
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .link {
    font-size: var(--font-size-small);
  }

  /* Stretched link: the whole banner is the hit area. */
  .link::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
  }
</style>
