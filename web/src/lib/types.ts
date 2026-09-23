// Types transcribed from DATA_CONTRACT.md. Only the fields the app reads today
// are declared; this file grows as screens land, and DATA_CONTRACT.md is the
// authority — if the two disagree, the contract is right and this is stale.
//
// Optionality here mirrors the contract's *presence counts*, not its types.
// `coad` is `string | null` because the contract says "1 of 59", and
// "design for null as the common case".

/** DATA_CONTRACT.md §2 — `districts.json`, all 59 CDTAs citywide. */
export interface DistrictIndexEntry {
  /** `"QN14"`. The join key against cdta.geojson. */
  cdta2020: string;
  /** `"q14"`. The URL segment — stored, never derived, so a link cannot drift. */
  slug: string;
  /** `"The Rockaways"`. Not derivable from cd_label, and vice versa. */
  display_name: string;
  /** `"Community District 14"`. */
  cd_label: string;
  boro: string;
  /** `[lon, lat]`, guaranteed inside the polygon. NOT a centroid — QN14's falls in Jamaica Bay. */
  point_on_surface: [number, number];
  /** `[xmin, ymin, xmax, ymax]`, EPSG:4326. */
  bbox: [number, number, number, number];
  /** Present in 1 of 59. */
  coad: string | null;
}

/**
 * DATA_CONTRACT.md §3 — `districts/<slug>.json`, the 14 Queens districts.
 *
 * Scaffold subset. hazards[], risk_profile, population, resource_categories,
 * gaps_displayed, hazard_overrides and meta are declared as the screens that
 * render them land (build steps 5 and 7).
 */
export interface DistrictPayload {
  cdta2020: string;
  slug: string;
  display_name: string;
  cd_label: string;
  boro: string;
  /** Present in 1 of 14. */
  coad: string | null;
  /** Present in 1 of 14, in exactly the same district as `coad`. */
  coad_name: string | null;
  /** Always 8, already ordered. Positions 1-3 ranked, 4-8 pinned. */
  hazards: Hazard[];
  /** Derived per district — do not hardcode a global list. */
  resource_categories: ResourceCategory[];
  /** Up to 3, one per ranked hazard. */
  gaps_displayed: DisplayedGap[];
}

/**
 * DATA_CONTRACT.md §3, `gaps_displayed[]`.
 *
 * The sentence is NOT in the payload — `sentence_template` plus `facts` are,
 * and $lib/gaps interpolates. Exactly three per district today.
 */
export interface DisplayedGap {
  gap_id: number;
  hazard_slug: string;
  hazard_label: string;
  label: string;
  value: number;
  unit: string;
  /** `higher_is_worse` or `higher_is_better`. Data, not a UI assumption. */
  polarity: string;
  status: string;
  sentence_template: string;
  /** Keys vary by gap — interpolate by name, never a fixed set. */
  facts: Record<string, string | number>;
  /** The rank of the hazard this gap measures. Always 1-3. */
  risk_rank: number;
  /** Only on a cross-cutting gap filling a ranked hazard's empty slot.
   *  Absent on all 42 sentences today. */
  fallback_from?: string;
}

/**
 * DATA_CONTRACT.md §4, `resources[]` — the fields the popup and detail screens
 * read. The full record carries phone, website, languages, fees and more;
 * those land with the resource detail screen.
 */
export interface Resource {
  /** Stable across rebuilds — permalinks depend on it. `source:slug`. */
  resource_id: string;
  name: string;
  /** Present on 3,441 of 3,795 — absent on every QNPD and FRANC record. */
  operator?: string;
  /** A slug; the label comes from the district's resource_categories. */
  category: string;
  source: string;
  /** Missing on 82 records — all 79 FRANC, plus 3 FacDB. */
  address?: string;
  lon: number;
  lat: number;

  /* Detail-screen fields. Present on QNPD records almost without exception;
   * on FRANC records ONLY `mission` ever appears (67 of 79) — address, phone,
   * contact, email, languages, fees, referrals and website are all zero. */
  mission?: string;
  phone?: string;
  contact_name?: string;
  email?: string;
  languages?: string;
  /** Free text, never a boolean: "None", "Yes", "$40 registration fee". */
  fees?: string;
  /** "Yes" on 164 records, "No" on 4. */
  accepts_referrals?: string;
  website?: string;
}

/**
 * DATA_CONTRACT.md §6 — one entry in a hazard section.
 *
 * Exactly one of four shapes, and the pipeline rejects an entry that is none of
 * them or more than one. The discriminant is which optional key is present:
 *
 *   Link   label + url
 *   Group  label + items   (nests one level only)
 *   Note   label + note: true
 *   Phone  label + tel, optionally tty
 *
 * Any shape may additionally carry `body`, a sentence beneath the label.
 */
export interface HazardItem {
  /** The item's heading — the same meaning for all four shapes. */
  label: string;
  /** The destination's own name, shown beside the heading. Links only. */
  link_label?: string;
  body?: string;
  url?: string;
  note?: true;
  tel?: string;
  tty?: string;
  items?: HazardItem[];
}

/** DATA_CONTRACT.md §6, `sections[]`. */
export interface HazardSection {
  /** From a closed vocabulary. `current-conditions` is data-backed. */
  id: string;
  /** Optional. A section without one renders no heading — every heading on the
   *  Extreme Heat screen belongs to a group, not a section. */
  title?: string;
  /** Always present, often []. */
  items: HazardItem[];
  /** Always present, often "". */
  body: string;
}

/** DATA_CONTRACT.md §6 — `hazards/<slug>.json`, citywide authored guidance. */
export interface HazardContent {
  slug: string;
  label: string;
  jra_category: string;
  /** `"stub"` on 6 of 8. ABSENT on the two authored ones — test for absence,
   *  not for `status === 'stub'`. */
  status?: string;
  /** Optional since 2026-09-23 — neither authored screen renders one. */
  summary?: string;
  sections: HazardSection[];
  default_resource_categories: string[];
  map_layers: string[];
}

/**
 * DATA_CONTRACT.md §3, `resource_categories[]` — what THIS district holds.
 *
 * Not to be confused with `default_resource_categories` on a hazard payload,
 * which is a flat list of slugs saying what the map opens with.
 */
export interface ResourceCategory {
  /** Matches `resources[].category` and the map layer's `category` property. */
  slug: string;
  label: string;
  /** Resources of this category located in this district. Spans 1 to 261. */
  count: number;
}

/**
 * DATA_CONTRACT.md §3, `hazards[]`.
 *
 * `score` and `reason` are mutually exclusive and `ranked` is the discriminant:
 * 42 of 112 entries carry `score`, the other 70 carry `reason`. Verified across
 * all 14 payloads — no entry carries both, and none carries neither.
 */
export interface Hazard {
  slug: string;
  label: string;
  /** 1-8. Authoritative — never re-sort on `score`. */
  rank: number;
  /** true for positions 1-3. */
  ranked: boolean;
  /** Ranked only. Integer 0-5 on one shared scale. */
  score?: number;
  /** Pinned only. Why this hazard is pinned rather than ranked. */
  reason?: string;
}
