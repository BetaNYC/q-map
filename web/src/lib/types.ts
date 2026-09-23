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
}
