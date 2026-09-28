import { describe, expect, it } from 'vitest';
import { fetchAlerts, type AlertsState } from './alerts';

// fetchAlerts() is the one read in the app whose wrong answer is a false
// all-clear. These pin every path to 'unavailable', and the only two that may
// say anything else. No test touches the network.

const URL = 'https://example.invalid/';
const NOW = new Date('2026-09-28T19:00:00Z');

/** A healthy envelope polled 2 minutes before NOW, with overrides. */
const envelope = (overrides: object = {}) => ({
  type: 'FeatureCollection',
  generated_at: '2026-09-28T18:58:00Z',
  feed_healthy: true,
  health_detail: null,
  features: [],
  ...overrides
});

const feature = (expires: string) => ({
  type: 'Feature',
  geometry: null,
  properties: { headline: `until ${expires}`, expires }
});

/** A fetch that answers with `body` (JSON-encoded unless already a string). */
const replying = (body: unknown, status = 200) =>
  (async () =>
    new Response(typeof body === 'string' ? body : JSON.stringify(body), {
      status
    })) as typeof fetch;

const run = (fetchFn: typeof fetch, timeoutMs?: number) =>
  fetchAlerts({ fetchFn, now: NOW, url: URL, timeoutMs });

const reason = (state: AlertsState) => (state.status === 'unavailable' ? state.reason : state.status);

describe('unavailable: no claim either way', () => {
  // VITE_ALERTS_URL is unset under Vitest, as in local dev and PR builds. This
  // also guarantees no test can reach the live Worker by omitting `url`.
  it('when the URL is unset, as in local dev and PR builds', async () => {
    expect(await fetchAlerts({ fetchFn: replying(envelope()), now: NOW })).toEqual({
      status: 'unavailable',
      reason: 'not_configured'
    });
  });

  it('when the URL is empty', async () => {
    const state = await fetchAlerts({ fetchFn: replying(envelope()), now: NOW, url: '' });
    expect(reason(state)).toBe('not_configured');
  });

  it("on the Worker's pre-first-poll 503", async () => {
    expect(reason(await run(replying({ error: 'no poll has completed' }, 503)))).toBe('http_503');
  });

  it('on a network or CORS failure', async () => {
    const failing = (async () => {
      throw new TypeError('Failed to fetch');
    }) as typeof fetch;
    expect(reason(await run(failing))).toBe('fetch_failed');
  });

  it('on a body that is not JSON, e.g. a proxy error page', async () => {
    expect(reason(await run(replying('<html>Bad gateway</html>')))).toBe('fetch_failed');
  });

  it('on JSON that is not the envelope', async () => {
    expect(reason(await run(replying({ ok: true })))).toBe('malformed');
    expect(reason(await run(replying(envelope({ generated_at: 'soon' }))))).toBe('malformed');
    expect(reason(await run(replying(envelope({ features: null }))))).toBe('malformed');
  });

  it('when the Worker reports itself unhealthy', async () => {
    const body = envelope({ feed_healthy: false, health_detail: 'alerts_uninterpreted' });
    expect(reason(await run(replying(body)))).toBe('unhealthy');
  });

  it('when the last successful poll is more than 15 minutes old', async () => {
    const body = envelope({ generated_at: '2026-09-28T18:44:59Z' });
    expect(reason(await run(replying(body)))).toBe('stale');
  });

  it('when the request hangs past the timeout', async () => {
    const hanging = ((_url: string, init: RequestInit) =>
      new Promise((_resolve, reject) =>
        init.signal!.addEventListener('abort', () => reject(init.signal!.reason))
      )) as unknown as typeof fetch;
    // 50 ms rather than the real 8 s; the abort path is the same.
    expect(reason(await run(hanging, 50))).toBe('fetch_failed');
  });
});

describe('none: a claim of no active alerts', () => {
  it('for a fresh, healthy, empty envelope', async () => {
    expect(await run(replying(envelope()))).toEqual({
      status: 'none',
      asOf: new Date('2026-09-28T18:58:00Z')
    });
  });

  it('at 14 minutes old - inside the staleness window', async () => {
    const body = envelope({ generated_at: '2026-09-28T18:46:00Z' });
    expect((await run(replying(body))).status).toBe('none');
  });

  it('when every alert in the snapshot has since expired', async () => {
    const body = envelope({ features: [feature('2026-09-28T14:00:00-04:00')] });
    expect((await run(replying(body))).status).toBe('none');
  });
});

describe('active', () => {
  it("drops expired and unparseable-expiry alerts, keeping the Worker's order", async () => {
    const body = envelope({
      features: [
        feature('2026-09-28T16:00:00-04:00'), // 20:00Z - live
        feature('2026-09-28T14:59:00-04:00'), // 18:59Z - expired a minute ago
        feature('whenever'), // unparseable - treated as expired
        feature('2026-09-28T15:30:00-04:00') // 19:30Z - live
      ]
    });
    const state = await run(replying(body));
    if (state.status !== 'active') throw new Error(`expected active, got ${state.status}`);
    expect(state.alerts.map((a) => a.properties.expires)).toEqual([
      '2026-09-28T16:00:00-04:00',
      '2026-09-28T15:30:00-04:00'
    ]);
  });
});
