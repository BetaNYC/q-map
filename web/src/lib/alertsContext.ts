import { getContext, setContext } from 'svelte';
import { AlertsStore } from './alerts.svelte';

/**
 * One AlertsStore for the whole visit, created by the root layout.
 *
 * The root layout is never remounted by client-side navigation, so the store -
 * its polling loop, and the alerts it has already shown - survives moving from
 * the banner to the alerts page and back. One poll every 2 minutes per visit,
 * however many pages read it, and an alert that ended while the banner was on
 * screen is still listed as ended on the alerts page.
 */
const KEY = Symbol('alerts');

/** Root layout only. */
export function provideAlerts(): AlertsStore {
  const store = new AlertsStore();
  setContext(KEY, store);
  return store;
}

export function useAlerts(): AlertsStore {
  const store = getContext<AlertsStore | undefined>(KEY);
  if (!store) throw new Error('useAlerts() outside the root layout - provideAlerts() was not called');
  return store;
}
