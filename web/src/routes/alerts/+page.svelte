<script lang="ts">
  import { clockTime } from '$lib/alertTimes';
  import { useAlerts } from '$lib/alertsContext';
  import AlertDetail from '$lib/components/AlertDetail.svelte';
  import HorizontalRule from '$lib/components/HorizontalRule.svelte';
  import FrozenHead from '$lib/components/FrozenHead.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';

  /**
   * Screen 06, Emergency Alerts. Figma: "06 Alerts - Mobile/Active",
   * "/ActiveWithEnded", "/None", "/Unavailable".
   *
   * A standalone route: reachable from the banner, and by link or bookmark when
   * nothing is active — so the four states must each say what they mean.
   * `unavailable` in particular must never read as all-clear.
   *
   * The prerendered HTML is always `loading`: alerts load in the browser, from
   * the visit's one AlertsStore ($lib/alertsContext).
   *
   * No active alerts, but ended ones earlier in this visit: the "none" message,
   * then the ended alerts beneath it (decided 2026-09-30; no frame).
   */

  const NOTIFY_PORTAL = 'https://a858-nycnotify.nyc.gov/notifynyc/';
  const NOTIFY_SIGNUP = 'https://www.nyc.gov/notifynyc';

  const alerts = useAlerts();
  const view = $derived(alerts.view);

  const subtitle = $derived(
    view.status === 'ready'
      ? `Queens and citywide – As of ${clockTime(view.asOf)} ET`
      : view.status === 'unavailable'
        ? "Queens and citywide – Can't update right now"
        : 'Queens and citywide'
  );
</script>

<svelte:head>
  <title>Emergency Alerts | Queens Resource Map</title>
  <meta name="description" content="Active Notify NYC emergency alerts for Queens and the whole city." />
</svelte:head>

<div class="screen">
  <!-- "Back" (Figma, 2026-10-07): the site name is already in SiteHeader
       above, so the link no longer repeats it. The accessible name says where
       it goes, and starts with what it shows (WCAG 2.5.3). -->
  <!-- Frozen while the page scrolls, with the rule under it as its edge. -->
  <FrozenHead>
    <PageHeader
      title="Emergency Alerts"
      secondary={subtitle}
      back={{ href: '/', label: 'Back', name: 'Back to Queens Resource Map' }}
    />

    <HorizontalRule />
  </FrozenHead>

  <!-- Announced once when the state settles; the alert list itself is not in
       the live region, so a 2-minute refresh does not re-read it. -->
  <div aria-live="polite">
    {#if view.status === 'loading'}
      <div class="status"><p class="detail">Checking for alerts…</p></div>
    {:else if view.status === 'unavailable'}
      <div class="status">
        <h2 class="heading">Alerts can't be loaded right now</h2>
        <p class="detail">This doesn't mean there are no alerts. Check Notify NYC directly for current emergency alerts.</p>
        <a class="small-link" href={NOTIFY_PORTAL} rel="noopener noreferrer">Go to Notify NYC</a>
      </div>
    {:else if view.active.length === 0}
      <div class="status">
        <h2 class="heading">No active alerts for Queens</h2>
        <p class="detail">Notify NYC has no active alerts for Queens or for the whole city right now. This page checks again every 2 minutes.</p>
      </div>
    {/if}
  </div>

  {#if view.status === 'ready' && view.alerts.length > 0}
    {#if view.active.length === 0}<HorizontalRule />{/if}
    <ul class="alerts">
      {#each view.alerts as alert, i (alert.feature.properties.guid)}
        <li>
          {#if i > 0}<HorizontalRule />{/if}
          <AlertDetail {alert} now={alerts.now} />
        </li>
      {/each}
    </ul>
  {/if}

  <HorizontalRule />

  <section class="about" aria-labelledby="about-alerts">
    <h2 id="about-alerts" class="heading">About these alerts</h2>
    <p class="detail">
      Alerts come from Notify NYC, New York City's official emergency notification service. This page shows alerts
      for Queens and for the whole city, in English, and checks for new ones every 2 minutes.
    </p>
    <a class="small-link" href={NOTIFY_SIGNUP} rel="noopener noreferrer">Sign up for Notify NYC alerts</a>
    <p class="detail">In an emergency, call <a href="tel:911">911</a>.</p>
  </section>
</div>

<style>
  .screen {
    display: flex;
    flex-direction: column;
    gap: var(--space-100);

    /* §3: 390px baseline, 16px gutters, 358px measure. */
    max-width: 390px;
    margin-inline: auto;
    padding-inline: var(--gutter);
    padding-block: var(--space-600);
  }

  .status,
  .about {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-200);
    padding: var(--space-300);
  }

  .heading {
    margin: 0;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .detail {
    margin: 0;
    font-size: var(--font-size-small);
    line-height: var(--line-height-prose);
  }

  .small-link {
    font-size: var(--font-size-small);
  }

  .alerts {
    margin: 0;
    padding: 0;
    list-style: none;
  }
</style>
