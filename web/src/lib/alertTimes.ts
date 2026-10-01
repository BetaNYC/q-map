/**
 * Alert times, as the alerts page and banner show them.
 *
 *   active:  Sent 8:56 AM ET (9 min ago) – Until 10:56 AM
 *   ended:   Sent 7:19 AM ET – Ended 9:19 AM
 *   banner:  9 min ago
 *
 * The wording is the Figma frames' (06 Alerts - Mobile/*): the relative time in
 * parentheses, a spaced en dash, no middle dots. ALERTS_SERVICE.md: every
 * observed alert expires exactly two hours after it is sent, so "Until" is
 * always known.
 *
 * NEW YORK TIME, STATED. A visitor outside New York — or a phone set to another
 * zone — must read the same clock the alert was issued against, so the zone is
 * fixed to America/New_York and labelled "ET" once per line. "ET" rather than
 * EDT/EST: it is right all year and nobody has to think about which.
 *
 * Pure functions of their inputs, `now` included, so every case is testable
 * without a clock.
 */

const ZONE = 'America/New_York';

const timeFormat = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONE,
  hour: 'numeric',
  minute: '2-digit'
});

const dateFormat = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONE,
  month: 'short',
  day: 'numeric'
});

const dayKey = new Intl.DateTimeFormat('en-CA', { timeZone: ZONE }); // 2026-09-29

/**
 * "8:56 AM". Engines disagree on the space before AM/PM — Node emits U+0020,
 * current Chrome and Safari U+202F — so it is normalised to one non-breaking
 * space: identical output everywhere, and "AM" never wraps onto its own line.
 */
export function clockTime(at: Date): string {
  return timeFormat.format(at).replace(/[\s ]+(AM|PM)$/, ' $1');
}

/**
 * The clock time, with the date prepended when it is not today in New York.
 * An alert sent at 11:30 PM is still live at 1:10 AM, and "Sent 11:30 PM"
 * would then read as tonight.
 */
function stamp(at: Date, now: Date): string {
  const time = clockTime(at);
  return dayKey.format(at) === dayKey.format(now) ? time : `${dateFormat.format(at)}, ${time}`;
}

/** "just now", "9 min ago", "1 hr ago", "1 hr 46 min ago". */
export function relativeTime(at: Date, now: Date): string {
  const minutes = Math.floor((now.getTime() - at.getTime()) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} hr ago` : `${hours} hr ${rest} min ago`;
}

/** The AlertDetail Times line for a live alert. */
export function activeTimes(sent: Date, expires: Date, now: Date): string {
  return `Sent ${stamp(sent, now)} ET (${relativeTime(sent, now)}) – Until ${stamp(expires, now)}`;
}

/**
 * The Times line for an ended alert. No relative time: an ended alert is
 * history, and "(1 hr 46 min ago)" would imply it is still being counted.
 * `endedAt` is when it stopped — its expiry, or earlier if it was cancelled
 * or superseded (see alerts.svelte.ts).
 */
export function endedTimes(sent: Date, endedAt: Date, now: Date): string {
  return `Sent ${stamp(sent, now)} ET – Ended ${stamp(endedAt, now)}`;
}

/** The AlertBanner link label. The banner shows at most two entries. */
export function bannerLinkLabel(activeCount: number): string {
  if (activeCount <= 1) return 'View details';
  if (activeCount === 2) return 'View both alerts';
  return `View all ${activeCount} alerts`;
}
