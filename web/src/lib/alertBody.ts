/**
 * An alert's `body` -> blocks of text, links and phone numbers, for
 * AlertBody.svelte to render as ordinary elements.
 *
 * NO HTML, EVER. The body is third-party text relayed from Notify NYC. It is
 * never passed to {@html}: this module returns data, and the component renders
 * each piece as a text node or an <a> whose href this module built. A body
 * containing "<img onerror=...>" renders as those characters, visibly.
 *
 * The shapes come from the real alerts (ALERTS_SERVICE.md, "Body"):
 *   - paragraphs separated by a blank line
 *   - NWS relays keep single newlines meaningful ("What:", "Where:", "When:"
 *     lines) and use "- " bullets
 *   - links as http://bit.ly/..., http://on.nyc.gov/..., and scheme-less
 *     www.weather.gov/okx/
 *   - phone numbers as "311" and "3-1-1"
 */

export type Inline =
  | { type: 'text'; text: string }
  | { type: 'link'; text: string; href: string }
  | { type: 'tel'; text: string; href: string };

export type Block =
  /** Lines of one paragraph; rendered with a line break between each. */
  | { type: 'p'; lines: Inline[][] }
  | { type: 'ul'; items: Inline[][] };

/**
 * A URL starts with http(s):// or www. - so no other scheme (javascript:,
 * data:) can ever become an href. Trailing sentence punctuation is not part of
 * it: "visit www.weather.gov/okx/." links to .../okx/.
 */
const URL_RE = /\b(?:https?:\/\/|www\.)[^\s<>"']+/gi;
const TRAILING = /[.,;:!?)\]]+$/;

/** 311 and 911 - the numbers an alert tells you to call. Not inside longer numbers. */
const PHONE_RE = /(?<![\d-])(3-1-1|311|9-1-1|911)(?![\d-])/g;

const BULLET = /^-\s+/;

export function parseBody(body: string): Block[] {
  const blocks: Block[] = [];
  for (const chunk of body.split(/\n{2,}/)) {
    const lines = chunk.split('\n').map((l) => l.trim()).filter(Boolean);
    let para: Inline[][] = [];
    let list: Inline[][] = [];
    const flushPara = () => { if (para.length) blocks.push({ type: 'p', lines: para }); para = []; };
    const flushList = () => { if (list.length) blocks.push({ type: 'ul', items: list }); list = []; };
    for (const line of lines) {
      if (BULLET.test(line)) {
        flushPara();
        list.push(inline(line.replace(BULLET, '')));
      } else {
        flushList();
        para.push(inline(line));
      }
    }
    flushPara();
    flushList();
  }
  return blocks;
}

/** One line of text -> text, link and tel pieces. */
export function inline(text: string): Inline[] {
  const out: Inline[] = [];
  let last = 0;
  for (const m of text.matchAll(URL_RE)) {
    const raw = m[0].replace(TRAILING, '');
    const start = m.index!;
    phones(text.slice(last, start), out);
    out.push({ type: 'link', text: raw, href: raw.startsWith('www.') ? `https://${raw}` : raw });
    last = start + raw.length;
  }
  phones(text.slice(last), out);
  return out;
}

function phones(text: string, out: Inline[]): void {
  let last = 0;
  for (const m of text.matchAll(PHONE_RE)) {
    if (m.index! > last) out.push({ type: 'text', text: text.slice(last, m.index) });
    out.push({ type: 'tel', text: m[0], href: `tel:${m[0].replace(/-/g, '')}` });
    last = m.index! + m[0].length;
  }
  if (last < text.length) out.push({ type: 'text', text: text.slice(last) });
}
