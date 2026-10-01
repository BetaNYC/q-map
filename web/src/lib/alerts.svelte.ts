import { fetchAlerts, STALE_AFTER_MS, type AlertFeature, type FetchAlertsOptions } from './alerts';

/**
 * Live alerts for a page: polls the Worker, and remembers what this page has
 * already shown.
 *
 * WORKED EXAMPLE — the pattern for live, client-only state in this otherwise
 * prerendered app. `fetchAlerts()` ($lib/alerts.ts) answers one question once;
 * this turns it into something a component can render for as long as the page
 * is open. Everything it decides, it decides here — the banner and the alerts
 * page only read `view`.
 *
 *   const alerts = new AlertsStore();
 *   $effect(() => alerts.start());      // start() returns its own cleanup
 *
 * Nothing runs until start(), and $effect never runs on the server, so a
 * prerendered page always ships `loading` — never a snapshot of real alerts
 * frozen into the HTML (the rule $lib/alerts.ts exists to enforce).
 *
 * FOUR RULES IT ENCODES
 *
 * 1. POLL EVERY 2 MINUTES, AND NOT WHILE HIDDEN. The Worker polls Notify NYC
 *    every 2 minutes, so polling faster buys nothing. A hidden tab stops, and
 *    fetches once on return — a phone left on the page overnight shows the
 *    morning's alerts, not last night's.
 *
 * 2. ENDED, NOT VANISHED. An alert this page has shown, and which then stops
 *    being active, stays in the list as `ended` until the page is reloaded:
 *    greyed, its link inert (Figma: AlertDetail state=ended). It ends one of
 *    two ways — it passes `expires` (checked every 30 s, between polls), or it
 *    drops out of the feed early (cancelled or superseded). Disappearing text
 *    under someone's thumb is the failure this prevents.
 *
 * 3. ONE FAILED POLL IS NOT AN OUTAGE. `fetchAlerts()` says `unavailable` on
 *    any failure, including a single dropped request on a train. The last good
 *    answer is kept while it is inside the Worker's own 15-minute staleness
 *    window, and only then does the view become `unavailable`. That is the same
 *    rule fetchAlerts applies to the Worker's `generated_at` — applied here to
 *    our own last success, so a flaky connection does not flicker the banner.
 *
 * 4. ENDED ALERTS NEVER REACH THE BANNER. `active` is what the banner reads;
 *    `alerts` (active + ended) is what the page reads.
 */

export interface AlertView {
  feature: AlertFeature;
  /** Set once, the first time this page saw it stop being active. */
  endedAt: Date | null;
}

export type AlertsView =
  | { status: 'loading' }
  | { status: 'unavailable' }
  /**
   * `alerts` is every alert this page has shown, newest first within each
   * group: active ones (in the Worker's order) then ended ones. `active` is the
   * live subset — empty means no active alert, even if `alerts` still holds
   * ended ones from earlier in the visit.
   */
  | { status: 'ready'; asOf: Date; alerts: AlertView[]; active: AlertFeature[] };

export interface AlertsStoreOptions {
  /** Seams for tests. Pages pass nothing. */
  fetchOptions?: Omit<FetchAlertsOptions, 'now'>;
  clock?: () => number;
  pollMs?: number;
  tickMs?: number;
  doc?: Pick<Document, 'visibilityState' | 'addEventListener' | 'removeEventListener'>;
}

const POLL_MS = 2 * 60 * 1000;
const TICK_MS = 30 * 1000;

interface Seen {
  feature: AlertFeature;
  endedAt: Date | null;
}

export class AlertsStore {
  /** The last successful answer, and when we got it (our clock, not theirs). */
  #last = $state<{ asOf: Date; active: AlertFeature[]; at: number } | null>(null);
  #failed = $state(false);
  /** Everything this page has shown, by guid, in first-seen order. */
  #seen = $state<Record<string, Seen>>({});
  /** Advanced every tick, so expiry is noticed between polls. */
  #now = $state(0);

  readonly #opts: Required<Omit<AlertsStoreOptions, 'fetchOptions' | 'doc'>> &
    Pick<AlertsStoreOptions, 'fetchOptions' | 'doc'>;

  constructor(opts: AlertsStoreOptions = {}) {
    this.#opts = {
      clock: opts.clock ?? Date.now,
      pollMs: opts.pollMs ?? POLL_MS,
      tickMs: opts.tickMs ?? TICK_MS,
      fetchOptions: opts.fetchOptions,
      doc: opts.doc ?? (typeof document === 'undefined' ? undefined : document)
    };
    this.#now = this.#opts.clock();
  }

  /** The store's clock, advanced every 30 s - relative times ("9 min ago") read it. */
  get now(): Date {
    return new Date(this.#now);
  }

  view: AlertsView = $derived.by(() => {
    const last = this.#last;
    const now = this.#now;
    // Rule 3: no answer yet, or the last good one has gone stale.
    if (!last) return this.#failed ? { status: 'unavailable' } : { status: 'loading' };
    if (this.#failed && now - last.at > STALE_AFTER_MS) return { status: 'unavailable' };

    const live = new Set(
      last.active.filter((f) => Date.parse(f.properties.expires) > now).map((f) => f.properties.guid)
    );
    const active = last.active.filter((f) => live.has(f.properties.guid));
    const ended = Object.values(this.#seen)
      .filter((s) => !live.has(s.feature.properties.guid))
      .map((s) => ({ feature: s.feature, endedAt: s.endedAt ?? this.#endedAt(s.feature, now) }))
      .sort((a, b) => Date.parse(b.feature.properties.sent) - Date.parse(a.feature.properties.sent));

    return {
      status: 'ready',
      asOf: last.asOf,
      active,
      alerts: [...active.map((feature) => ({ feature, endedAt: null })), ...ended]
    };
  });

  /** Begin polling. Returns the cleanup, so it can be returned from $effect. */
  start(): () => void {
    let poll: ReturnType<typeof setInterval> | undefined;
    const tick = setInterval(() => this.#tick(), this.#opts.tickMs);

    const run = () => {
      clearInterval(poll);
      void this.refresh();
      poll = setInterval(() => void this.refresh(), this.#opts.pollMs);
    };
    const onVisibility = () => {
      if (this.#opts.doc?.visibilityState === 'hidden') clearInterval(poll);
      else run();
    };

    this.#opts.doc?.addEventListener('visibilitychange', onVisibility);
    run();

    return () => {
      clearInterval(poll);
      clearInterval(tick);
      this.#opts.doc?.removeEventListener('visibilitychange', onVisibility);
    };
  }

  /** One poll. Public for tests; pages rely on start(). */
  async refresh(): Promise<void> {
    const at = this.#opts.clock();
    const state = await fetchAlerts({ ...this.#opts.fetchOptions, now: new Date(at) });
    this.#now = this.#opts.clock();

    if (state.status === 'unavailable') {
      this.#failed = true;
      return;
    }
    this.#failed = false;
    const active = state.status === 'active' ? state.alerts : [];
    this.#last = { asOf: state.asOf, active, at };
    this.#record(active);
  }

  #tick(): void {
    this.#now = this.#opts.clock();
    this.#freezeEnded();
  }

  /** Remember newly shown alerts; stamp the ones that just stopped (rule 2). */
  #record(active: AlertFeature[]): void {
    const next = { ...this.#seen };
    for (const f of active) next[f.properties.guid] = { feature: f, endedAt: null };
    this.#seen = next;
    this.#freezeEnded();
  }

  /**
   * Fix an ended alert's end time the first time it is seen ended, so a
   * cancelled alert keeps "Ended 9:04 AM" rather than creeping forward with
   * every tick.
   */
  #freezeEnded(): void {
    const now = this.#now;
    const live = new Set(
      (this.#last?.active ?? [])
        .filter((f) => Date.parse(f.properties.expires) > now)
        .map((f) => f.properties.guid)
    );
    let changed = false;
    const next = { ...this.#seen };
    for (const [guid, s] of Object.entries(next)) {
      if (s.endedAt === null && !live.has(guid)) {
        next[guid] = { ...s, endedAt: this.#endedAt(s.feature, now) };
        changed = true;
      }
    }
    if (changed) this.#seen = next;
  }

  /** Its expiry if that has passed; otherwise now — it was withdrawn early. */
  #endedAt(feature: AlertFeature, now: number): Date {
    const expires = Date.parse(feature.properties.expires);
    return new Date(Math.min(expires, now));
  }
}
