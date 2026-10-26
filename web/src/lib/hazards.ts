import type { Hazard } from './types';

/**
 * Hazard copy and presentation rules that are NOT in the payload.
 *
 * Kept out of the component so the strings are greppable and testable, and so
 * HazardRow stays about layout.
 */

/**
 * The measure each measured PART's score quotes. Deliberately not in the
 * payload (handoff §7.1) — hardcoded per part id.
 *
 * Keyed by part since 2026-10-26: the ranked hazards are now the categories
 * Flooding and Temperature Extremes, each scoring the max of its parts
 * (`part_scores`). The lookup is total over the parts that appear: across all
 * 14 payloads, `part_scores` names exactly these three. Verified against
 * data/processed/, not assumed.
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

/**
 * Since 2026-10-26 there are two ranked positions, so 'moderate' is never
 * reached; it stays in the ramp so a third ranked category needs no change
 * here. The score-0 grey is gone: a category's score is never 0 (the max of
 * its parts, one of which is always 1-5).
 */
export function severityFor(hazard: Hazard): Severity {
  return hazard.ranked ? (RANK_SEVERITY[hazard.rank - 1] ?? 'minor') : 'minor';
}

/**
 * What the rank chip shows, and whether a screen reader should hear it.
 *
 *   ranked   "2"   announced. §10: the number carries the meaning, colour is
 *                  decoration on top of it.
 *   pinned   none  empty chip, not announced. Decoration; `reason` carries
 *                  what a pinned row means.
 *
 * The third state, "-" for a ranked hazard scoring 0, went with the
 * 2026-10-26 categories: no category can score 0.
 */
export function rankChip(hazard: Hazard): { text: string | null; decorative: boolean } {
  if (!hazard.ranked) return { text: null, decorative: true };
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

  // The category's score is the max of its parts, so quote the part that set
  // it: "Storm Surge Flood Vulnerability Index: 5 out of 5" is a true sentence
  // about QN14's Flooding, where "Flooding: 5 out of 5" would not say which
  // kind. A tie goes to the first part in `part_scores` (the pipeline orders
  // them coastal storm, then heavy rain). Whether Flooding should show BOTH
  // parts is a design question, left open.
  const parts = hazard.part_scores ?? [];
  const lead = parts.find((p) => p.score === hazard.score) ?? parts[0];
  const label = lead ? MEASURE_LABEL[lead.part] : undefined;

  // "4 out of 5", not "4/5". A screen reader reads a solidus as "slash", and
  // handoff §10's own example is written out in words.
  return label
    ? `${label}: ${hazard.score} out of ${SCORE_MAX}`
    : `${hazard.score} out of ${SCORE_MAX}`;
}
