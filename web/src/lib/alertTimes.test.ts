import { describe, expect, it } from 'vitest';
import { activeTimes, bannerLinkLabel, clockTime, endedTimes, relativeTime } from './alertTimes';

const NBSP = ' ';
const at = (iso: string) => new Date(iso);

describe('clockTime', () => {
  it('is New York time, whatever the machine zone, in summer and winter', () => {
    expect(clockTime(at('2026-09-29T12:56:30Z'))).toBe(`8:56${NBSP}AM`); // EDT
    expect(clockTime(at('2026-01-15T13:00:00Z'))).toBe(`8:00${NBSP}AM`); // EST
  });

  it('never lets AM/PM wrap away from the time', () => {
    expect(clockTime(at('2026-09-29T22:04:55Z'))).toMatch(/^6:04 PM$/);
  });
});

describe('relativeTime', () => {
  const sent = at('2026-09-29T12:56:30Z');
  it.each([
    [0, 'just now'],
    [59, 'just now'],
    [60, '1 min ago'],
    [9 * 60, '9 min ago'],
    [60 * 60, '1 hr ago'],
    [106 * 60, '1 hr 46 min ago'],
    [120 * 60, '2 hr ago'],
  ])('%is -> %s', (seconds, expected) => {
    expect(relativeTime(sent, new Date(sent.getTime() + seconds * 1000))).toBe(expected);
  });
});

describe('activeTimes', () => {
  it('matches the Figma wording: parenthetical, spaced en dash, no middle dot', () => {
    const line = activeTimes(at('2026-09-29T12:56:30Z'), at('2026-09-29T14:56:30Z'), at('2026-09-29T13:05:30Z'));
    expect(line).toBe(`Sent 8:56${NBSP}AM ET (9 min ago) – Until 10:56${NBSP}AM`);
    expect(line).not.toContain('·');
  });

  it('dates a time that is not today in New York', () => {
    // Sent 11:30 PM on the 28th, read at 1:10 AM on the 29th.
    const line = activeTimes(at('2026-09-29T03:30:00Z'), at('2026-09-29T05:30:00Z'), at('2026-09-29T05:10:00Z'));
    expect(line).toBe(`Sent Sep 28, 11:30${NBSP}PM ET (1 hr 40 min ago) – Until 1:30${NBSP}AM`);
  });
});

describe('endedTimes', () => {
  it('has no relative time', () => {
    expect(endedTimes(at('2026-09-29T11:19:11Z'), at('2026-09-29T13:19:11Z'), at('2026-09-29T13:21:00Z'))).toBe(
      `Sent 7:19${NBSP}AM ET – Ended 9:19${NBSP}AM`
    );
  });
});

describe('bannerLinkLabel', () => {
  it.each([
    [1, 'View details'],
    [2, 'View both alerts'],
    [3, 'View all 3 alerts'],
    [6, 'View all 6 alerts'],
  ])('%i -> %s', (n, label) => expect(bannerLinkLabel(n)).toBe(label));
});
