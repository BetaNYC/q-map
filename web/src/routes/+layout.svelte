<script lang="ts">
  import '../app.css';
  import { provideAlerts } from '$lib/alertsContext';

  let { children } = $props();

  // One alerts poller for the visit - see $lib/alertsContext.ts. start() only
  // runs in the browser ($effect never runs during prerender) and returns its
  // own cleanup.
  const alerts = provideAlerts();
  $effect(() => alerts.start());
</script>

{@render children()}
