import { describe, expect, it } from 'vitest';
import { splitPhones } from './phones';

const tels = (s: string) => splitPhones(s).filter((r) => r.tel).map((r) => [r.text, r.tel]);

describe('splitPhones', () => {
  it('links a hyphenated number as E.164', () => {
    expect(tels('Call 212-389-6670.')).toEqual([['212-389-6670', 'tel:+12123896670']]);
  });

  it('accepts a leading 1-', () => {
    expect(tels('Call 1-800-752-6633 now')).toEqual([['1-800-752-6633', 'tel:+18007526633']]);
  });

  it('links 911, 311 and 988 as dialled', () => {
    expect(tels('Call 911. Call 311; or call or text 988.')).toEqual([
      ['911', 'tel:911'],
      ['311', 'tel:311'],
      ['988', 'tel:988']
    ]);
  });

  it('keeps the surrounding text, in order', () => {
    expect(splitPhones('Call 311; outside NYC, 212-639-9675. Interpreters.').map((r) => r.text).join('')).toBe(
      'Call 311; outside NYC, 212-639-9675. Interpreters.'
    );
  });

  it('leaves names, short codes and other digits alone', () => {
    expect(tels('Ask NYC311, text OUT to 773454, 24/7, 175 languages, KA-01510')).toEqual([]);
  });

  it('returns one plain run for text with no number', () => {
    expect(splitPhones('Stay inside.')).toEqual([{ text: 'Stay inside.' }]);
  });
});
