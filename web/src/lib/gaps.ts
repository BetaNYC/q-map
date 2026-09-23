import type { DisplayedGap } from './types';

/**
 * Gap sentences.
 *
 * **The pipeline does not write the sentence** (handoff §7.2). It emits a
 * `sentence_template` and a `facts` object, and the frontend interpolates.
 */

/**
 * Substitute `{key}` placeholders from `facts`.
 *
 * Interpolate BY NAME, never by position or a fixed set — the keys vary per
 * gap. Eight names appear across the 42 sentences shipped today (district,
 * exposed, language, minutes, pct, per_10k, speakers, total) and that list is
 * not a contract.
 *
 * `{district}` resolves from `facts.district`, NOT from the payload root. The
 * pipeline puts it in facts precisely so there is one lookup and no special
 * case, and the root's `display_name` is not always the string the sentence
 * wants.
 *
 * A missing key throws rather than rendering a literal "{pct}". Every
 * placeholder resolving inside `facts` is asserted upstream, and every page is
 * prerendered, so this fails the build rather than a visitor's screen.
 */
export function interpolate(template: string, facts: DisplayedGap['facts']): string {
  return template.replace(/\{(\w+)\}/g, (_match, key: string) => {
    if (!(key in facts)) {
      throw new Error(`gap sentence: "{${key}}" has no value in facts (${Object.keys(facts).join(', ')})`);
    }
    return String(facts[key]);
  });
}

/**
 * DO NOT BRANCH ON `value` (§7.2).
 *
 * Where a gap found nothing, or the estimate is unreliable, the pipeline has
 * already swapped in different copy — a zero-finding reads "None of ... sit in
 * an area that floods", and an unreliable language estimate arrives hedged.
 * The template received is already the correct one, singular. A frontend that
 * checks for zero and substitutes its own wording doubles up.
 *
 * This file therefore has no conditional copy at all, and that absence is the
 * feature. The one exception is below, and it is about provenance rather than
 * about the value.
 */

/**
 * `fallback_from` appears only on a `cross-cutting` gap standing in for a
 * ranked hazard that had nothing to report. §7.2 says to handle it: when
 * present, say which hazard's slot the sentence fills.
 *
 * ABSENT ON ALL 42 SENTENCES ACROSS ALL 14 DISTRICTS TODAY, so this path has
 * never rendered against real data and the copy is not designed. It is written
 * to degrade safely — a humanised slug rather than a lookup that could miss.
 */
export function fallbackNote(gap: DisplayedGap): string | null {
  if (!gap.fallback_from) return null;

  const hazard = gap.fallback_from.replace(/-/g, ' ');
  return `Shown in place of ${hazard}, which had nothing to report for this district.`;
}
