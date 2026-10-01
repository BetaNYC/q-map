import { describe, expect, it } from 'vitest';
import { inline, parseBody } from './alertBody';

// Real bodies, as the Worker's cleanBody() serves them (alerts/worker fixtures).
const WATERBODY =
  'Due to recent precipitation, waterbody advisories have been issued for waterways in your area. For more information and a list of impacted waterbodies, visit http://bit.ly/3KFvQQJ or call 3-1-1.';
const NWS = [
  'The National Weather Service has issued the following:',
  'What: Coastal Flood Statement',
  'Where: Staten Island',
  'Preparedness Actions:',
  '- Avoid driving through or coming in contact with flood waters.',
  '- New York City residents, please call 311 if you encounter flooding.',
  '',
  'Info: www.weather.gov/okx/.',
].join('\n');

describe('parseBody', () => {
  it('links the URL and the phone number in a real alert, leaving the sentence intact', () => {
    expect(parseBody(WATERBODY)).toEqual([
      {
        type: 'p',
        lines: [[
          { type: 'text', text: 'Due to recent precipitation, waterbody advisories have been issued for waterways in your area. For more information and a list of impacted waterbodies, visit ' },
          { type: 'link', text: 'http://bit.ly/3KFvQQJ', href: 'http://bit.ly/3KFvQQJ' },
          { type: 'text', text: ' or call ' },
          { type: 'tel', text: '3-1-1', href: 'tel:311' },
          { type: 'text', text: '.' },
        ]],
      },
    ]);
  });

  it("keeps an NWS relay's lines, turns its bullets into a list, and links a scheme-less URL", () => {
    const blocks = parseBody(NWS);
    expect(blocks.map((b) => b.type)).toEqual(['p', 'ul', 'p']);
    expect(blocks[0]).toMatchObject({ type: 'p', lines: { length: 4 } });
    expect(blocks[1]).toMatchObject({ type: 'ul', items: { length: 2 } });
    expect(blocks[1].type === 'ul' && blocks[1].items[1]).toContainEqual({ type: 'tel', text: '311', href: 'tel:311' });
    expect(blocks[2]).toEqual({
      type: 'p',
      lines: [[{ type: 'text', text: 'Info: ' }, { type: 'link', text: 'www.weather.gov/okx/', href: 'https://www.weather.gov/okx/' }, { type: 'text', text: '.' }]],
    });
  });

  it('separates paragraphs on blank lines', () => {
    expect(parseBody('One.\n\nTwo.\n\n\nThree.').map((b) => b.type)).toEqual(['p', 'p', 'p']);
  });
});

describe('inline: hostile and edge input', () => {
  it('never produces a link or markup from HTML in the text', () => {
    const pieces = inline('<img src=x onerror=alert(1)> <a href="javascript:alert(1)">x</a>');
    expect(pieces.every((p) => p.type === 'text')).toBe(true);
    expect(pieces.map((p) => p.text).join('')).toBe('<img src=x onerror=alert(1)> <a href="javascript:alert(1)">x</a>');
  });

  it('only http(s) and www. become links', () => {
    for (const s of ['javascript:alert(1)', 'data:text/html,hi', 'ftp://example.org', 'mailto:a@b.org']) {
      expect(inline(s).some((p) => p.type === 'link')).toBe(false);
    }
  });

  it('does not treat digits inside longer numbers as 311 or 911', () => {
    for (const s of ['1-800-311-2000', 'Route 9112', '39111', '2311']) {
      expect(inline(s).some((p) => p.type === 'tel')).toBe(false);
    }
  });

  it('strips closing punctuation from a URL', () => {
    expect(inline('(see http://on.nyc.gov/1kdbhe2).')).toContainEqual({ type: 'link', text: 'http://on.nyc.gov/1kdbhe2', href: 'http://on.nyc.gov/1kdbhe2' });
  });
});
