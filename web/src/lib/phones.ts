/**
 * Phone numbers in authored text, made tappable (Andrew, 2026-10-14).
 *
 * The SME-reviewed copy ("Core Readiness Messages by Threat") asks that phone
 * numbers stay "visible and tappable; residents should not have to open a
 * website to call". The numbers live inside descriptions ("Call 212-389-6670")
 * rather than as separate phone items, so the text is split into plain runs
 * and numbers, and each number becomes a `tel:` link where it stands.
 *
 * Two shapes are recognised:
 *
 *   - North American numbers written with hyphens, optionally led by `1-`:
 *     "212-389-6670", "1-800-752-6633". Dialled as E.164 (+1...).
 *   - The three-digit services the copy names: 911, 311, 988. Dialled as is.
 *
 * Deliberately not matched: SMS short codes ("text OUT to 773454" is a text,
 * not a call), numbers glued to letters ("NYC311" is a name), and anything
 * written with dots or brackets, which the copy does not use. A number has to
 * stand on its own: no letter, digit or hyphen directly before or after.
 */
export type TextRun = { text: string; tel?: undefined } | { text: string; tel: string };

const PHONE = /(?<![\w-])(?:(1-)?(\d{3})-(\d{3})-(\d{4})|(911|311|988))(?![\w-])/g;

export function splitPhones(text: string): TextRun[] {
  const runs: TextRun[] = [];
  let last = 0;
  for (const m of text.matchAll(PHONE)) {
    const at = m.index ?? 0;
    if (at > last) runs.push({ text: text.slice(last, at) });
    const tel = m[5] ? m[5] : `+1${m[2]}${m[3]}${m[4]}`;
    runs.push({ text: m[0], tel: `tel:${tel}` });
    last = at + m[0].length;
  }
  if (last < text.length) runs.push({ text: text.slice(last) });
  return runs;
}
