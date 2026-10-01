import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AlertsStore, type AlertsStoreOptions, type AlertsView } from './alerts.svelte';

// A controllable clock and Worker. Real alert text is not needed here - the
// store only reads guid, sent and expires.
const T0 = Date.parse('2026-09-29T13:00:00Z');
let clock = T0;
let features: object[] = [];
let failing = false;

const feature = (guid: string, sent: string, expires: string) => ({
  type: 'Feature',
  geometry: null,
  properties: { guid, id: guid, sent, expires, event: guid },
});
const POLICE = feature('police', '2026-09-29T12:56:30Z', '2026-09-29T14:56:30Z');
const WATER = feature('water', '2026-09-29T11:19:11Z', '2026-09-29T13:19:11Z');

const fetchFn = (async () => {
  if (failing) throw new TypeError('Failed to fetch');
  return new Response(
    JSON.stringify({
      type: 'FeatureCollection',
      generated_at: new Date(clock).toISOString(),
      feed_healthy: true,
      health_detail: null,
      features,
    })
  );
}) as typeof fetch;

function store(doc?: AlertsStoreOptions['doc']) {
  return new AlertsStore({ clock: () => clock, fetchOptions: { fetchFn, url: 'https://example.invalid/' }, doc });
}
const guids = (v: AlertsView) => (v.status === 'ready' ? v.alerts.map((a) => [a.feature.properties.guid, a.endedAt ? 'ended' : 'active']) : v.status);

beforeEach(() => {
  clock = T0;
  features = [POLICE, WATER];
  failing = false;
  vi.useFakeTimers();
});
afterEach(() => vi.useRealTimers());

describe('AlertsStore', () => {
  it('is loading until the first answer, then ready with the Worker order', async () => {
    const s = store();
    expect(s.view.status).toBe('loading');
    await s.refresh();
    expect(guids(s.view)).toEqual([['police', 'active'], ['water', 'active']]);
  });

  it('ready with nothing active is the none state', async () => {
    features = [];
    const s = store();
    await s.refresh();
    expect(s.view).toMatchObject({ status: 'ready', active: [], alerts: [] });
  });

  it('an alert passing its expiry between polls becomes ended at its expiry', async () => {
    const s = store();
    const stop = s.start();
    await vi.advanceTimersByTimeAsync(0);
    clock = Date.parse('2026-09-29T13:20:00Z'); // water expired 13:19:11
    await vi.advanceTimersByTimeAsync(30_000); // one tick, no poll yet
    const v = s.view;
    if (v.status !== 'ready') throw new Error(v.status);
    expect(v.active.map((f) => f.properties.guid)).toEqual(['police']);
    expect(v.alerts[1]).toMatchObject({ endedAt: new Date('2026-09-29T13:19:11Z') });
    stop();
  });

  it('an alert withdrawn early ends when it is noticed, and the time does not creep', async () => {
    const s = store();
    await s.refresh();
    features = [WATER]; // police cancelled
    clock = T0 + 60_000;
    await s.refresh();
    const endedAt = () => (s.view.status === 'ready' ? s.view.alerts.find((a) => a.feature.properties.guid === 'police')?.endedAt : null);
    expect(endedAt()).toEqual(new Date(T0 + 60_000));
    clock = T0 + 5 * 60_000;
    await s.refresh();
    expect(endedAt()).toEqual(new Date(T0 + 60_000));
  });

  it('lists active first, then ended newest-first; ended never reach `active`', async () => {
    const s = store();
    await s.refresh();
    features = [];
    clock += 60_000;
    await s.refresh();
    const v = s.view;
    if (v.status !== 'ready') throw new Error(v.status);
    expect(v.active).toEqual([]);
    expect(guids(v)).toEqual([['police', 'ended'], ['water', 'ended']]);
  });

  it('keeps the last good answer through a failed poll, inside 15 minutes', async () => {
    const s = store();
    await s.refresh();
    failing = true;
    clock += 14 * 60_000;
    await s.refresh();
    expect(s.view.status).toBe('ready');
  });

  it('becomes unavailable once the last good answer is over 15 minutes old', async () => {
    const s = store();
    await s.refresh();
    failing = true;
    clock += 16 * 60_000;
    await s.refresh();
    expect(s.view.status).toBe('unavailable');
  });

  it('is unavailable at once if the first poll fails', async () => {
    failing = true;
    const s = store();
    await s.refresh();
    expect(s.view.status).toBe('unavailable');
  });

  it('polls every 2 minutes, stops while hidden, and fetches on return', async () => {
    const doc = Object.assign(new EventTarget(), { visibilityState: 'visible' as DocumentVisibilityState });
    const spy = vi.spyOn(AlertsStore.prototype, 'refresh');
    const s = store(doc as never);
    const stop = s.start();
    expect(spy).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(2 * 60_000);
    expect(spy).toHaveBeenCalledTimes(2);

    doc.visibilityState = 'hidden';
    doc.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(10 * 60_000);
    expect(spy).toHaveBeenCalledTimes(2);

    doc.visibilityState = 'visible';
    doc.dispatchEvent(new Event('visibilitychange'));
    expect(spy).toHaveBeenCalledTimes(3);

    stop();
    await vi.advanceTimersByTimeAsync(10 * 60_000);
    expect(spy).toHaveBeenCalledTimes(3);
    spy.mockRestore();
  });
});
