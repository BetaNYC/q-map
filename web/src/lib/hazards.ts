import type { Hazard } from './types';

/**
 * Hazard copy and presentation rules that are NOT in the payload.
 *
 * Kept out of the component so the strings are greppable and testable, and so
 * HazardRow stays about layout.
 */

/**
 * The measure a ranked hazard's score is quoting. Deliberately not in the
 * payload (handoff §7.1) — hardcoded per slug.
 *
 * The lookup is total over the ranked set: across all 14 district payloads,
 * exactly three slugs are ever ranked — coastal-storm, heavy-rain and
 * extreme-heat, 14 times each — and the ranked and pinned sets never overlap.
 * Verified against data/processed/, not assumed.
 */
const MEASURE_LABEL: Record<string, string> = {
  'coastal-storm': 'Storm Surge Flood Vulnerability Index',
  'heavy-rain': 'Stormwater Flooding Quintile Rank',
  'extreme-heat': 'Heat Vulnerability Index'
};

/** The shared 1-5 scale. Scores observed across all payloads run 0-5. */
export const SCORE_MAX = 5;

/**
 * Rank position to rank-chip fill.
 *
 * Read off the Figma frames rather than inferred: rank 1 is severity/extreme,
 * 2 is severe, 3 is moderate, and every pinned row is severity/minor. It maps
 * from POSITION, not from `score` — q14's rank 1 scores 5 and q11's scores 3,
 * and both are drawn extreme.
 *
 * Note the tension this creates, which handoff §7.1 names: an
 * extreme -> severe -> moderate -> minor ramp across positions 1, 2, 3, pinned
 * reads as a descending severity scale, and pinned hazards are NOT less
 * dangerous — hazmat is pinned because it scores high everywhere in Queens.
 * The `reason` line is what stops that misreading, which is why it is never
 * optional in the markup.
 */
const RANK_SEVERITY = ['extreme', 'severe', 'moderate'] as const;
export type Severity = (typeof RANK_SEVERITY)[number] | 'minor';

export function severityFor(hazard: Hazard): Severity {
  // A ranked hazard scoring 0 takes the pinned grey, not its rank colour. It
  // occupies a ranked position but does not apply to the district, and an amber
  // "moderate" chip beside "does not experience coastal flooding" said two
  // contradictory things at once. Affects 5 of 14 districts.
  if (hazard.ranked && hazard.score === 0) return 'minor';

  return hazard.ranked ? (RANK_SEVERITY[hazard.rank - 1] ?? 'minor') : 'minor';
}

/**
 * What the rank chip shows, and whether a screen reader should hear it.
 *
 * Three states, not two — the middle one is why this returns an object rather
 * than a string:
 *
 *   ranked, scored     "3"   announced. §10: the number carries the meaning,
 *                            colour is decoration on top of it.
 *   ranked, score 0    "-"   shown, NOT announced. The dash is a visual
 *                            placeholder holding the chip's shape in the
 *                            column; "dash Coastal Storm Neighborhood does
 *                            not experience coastal flooding" reads worse than
 *                            the sentence alone, which already says it.
 *   pinned             none  empty chip, not announced. Decoration; `reason`
 *                            carries what a pinned row means.
 */
export function rankChip(hazard: Hazard): { text: string | null; decorative: boolean } {
  if (!hazard.ranked) return { text: null, decorative: true };
  if (hazard.score === 0) return { text: '-', decorative: true };
  return { text: String(hazard.rank), decorative: false };
}

/**
 * The second line of a hazard row.
 *
 * Ranked: the measure and the score. Pinned: the reason. One or the other is
 * always present, so this never returns an empty string for real data.
 */
export function measureLine(hazard: Hazard): string {
  if (!hazard.ranked) {
    return hazard.reason ?? '';
  }

  // Coastal storm alone admits score 0, meaning the district has no exposed
  // tract — five districts, and in all five it sits at rank 3. "0/5" would read
  // as a measured low score rather than a hazard that does not apply here.
  if (hazard.score === 0) {
    return 'Neighborhood does not experience coastal flooding';
  }

  // "4 out of 5", not "4/5". A screen reader reads a solidus as "slash", and
  // handoff §10's own example is written out in words.
  return `${MEASURE_LABEL[hazard.slug]}: ${hazard.score} out of ${SCORE_MAX}`;
}
