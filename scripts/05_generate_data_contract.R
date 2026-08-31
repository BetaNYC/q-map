# scripts/05_generate_data_contract.R
#
# Generates DATA_CONTRACT.md from the actual contents of data/processed/.
#
# d26's contract was hand-maintained and drifted: it named files that were never
# shipped, quoted a minzoom the code contradicted, and described ranks as
# inverted where the pipeline emitted them ascending. PIPELINE_DESIGN.md's
# Verification section draws the conclusion - generate the tables from the
# pipeline rather than maintaining them by hand.
#
# The split is deliberate: FACTS ARE GENERATED, MEANING IS AUTHORED. File
# inventories, field lists, types, counts and example values are read off the
# real outputs and cannot drift. The prose that says what a field means, and
# the gotchas, are written here as constants and are the part a human maintains.
#
# Usage:  uvr run scripts/05_generate_data_contract.R

library(jsonlite)
library(dplyr)

PROCESSED <- "data/processed"
OUT <- "DATA_CONTRACT.md"

# --- helpers ----------------------------------------------------------------

json_type <- function(x) {
  if (is.null(x)) "null"
  else if (is.logical(x)) "boolean"
  else if (is.numeric(x)) if (all(x == round(x), na.rm = TRUE)) "integer" else "number"
  else if (is.character(x)) "string"
  else if (is.list(x) && !is.null(names(x))) "object"
  else if (is.list(x)) "array"
  else class(x)[1]
}

example_of <- function(x) {
  if (is.null(x)) return("`null`")
  if (is.list(x) && is.null(names(x))) return(paste0("array[", length(x), "]"))
  if (is.list(x)) return("object")
  v <- x[[1]]
  if (is.character(v)) paste0("`\"", substr(v, 1, 36), "\"`") else paste0("`", v, "`")
}

# Field table for one object, one row per top-level key.
field_table <- function(obj, notes = list()) {
  rows <- vapply(names(obj), function(k) {
    sprintf("| `%s` | %s | %s | %s |", k, json_type(obj[[k]]),
            example_of(obj[[k]]), notes[[k]] %||% "")
  }, character(1))
  c("| Field | Type | Example | Notes |", "|---|---|---|---|", rows)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

file_row <- function(path, note) {
  n <- length(Sys.glob(path))
  sz <- sum(file.info(Sys.glob(path))$size, na.rm = TRUE)
  sprintf("| `%s` | %d | %s | %s |",
          sub(paste0("^", PROCESSED, "/"), "", path), n,
          if (sz > 1024^2) sprintf("%.1f MB", sz/1024^2) else sprintf("%.0f KB", sz/1024),
          note)
}

read1 <- function(p) fromJSON(p, simplifyVector = FALSE)

# --- read the real outputs ---------------------------------------------------

idx      <- read1(file.path(PROCESSED, "districts.json"))[[1]]
district <- read1(file.path(PROCESSED, "districts/q14.json"))
resources<- read1(file.path(PROCESSED, "resources/q14.json"))
gaps     <- read1(file.path(PROCESSED, "gaps/q14.json"))
hazard   <- read1(file.path(PROCESSED, "hazards/extreme-heat.json"))

n_districts <- length(read1(file.path(PROCESSED, "districts.json")))
n_gap_rows  <- length(gaps$gaps)
n_hazards   <- length(Sys.glob(file.path(PROCESSED, "hazards/*.json")))

# --- authored notes ----------------------------------------------------------

NOTES_IDX <- list(
  slug = "**The URL segment.** Stored, not derived - a published link must never drift.",
  point_on_surface = "`[lon, lat]`. **Not a centroid** - guaranteed inside the polygon. QN14's true centroid falls in Jamaica Bay.",
  bbox = "`[xmin, ymin, xmax, ymax]`, EPSG:4326.",
  coad = "`null` for 13 of 14 districts. Design for null as the common case."
)

NOTES_DISTRICT <- list(
  hazards = "Always 8, ordered. Positions 1-4 are ranked, 5-8 pinned. See gotchas.",
  risk_profile = "Every entry is a **stat object**, never a bare number.",
  population = "`total` is a stat object too, and its `source` differs from `surge_pop_pct`'s. See gotchas.",
  resource_categories = "**Derived per district.** Do not hardcode a global list.",
  hazard_overrides = "Slugs with district-specific guidance. Fetch the override file only for these.",
  gaps_displayed = "Up to 3. Each carries `risk_rank`, and `fallback_from` when drawn from outside the top three.",
  meta = "Carries `hazard_model_status`. Currently `provisional_pending_expert_review`."
)

NOTES_RESOURCES <- list(
  count = "Equals `length(resources)`. Asserted in the pipeline.",
  resources = "Only resources **located** in the district. Organisations serving Queens from outside it are in the canonical file but not here."
)

NOTES_GAPS <- list(
  computed = sprintf("Of %d registry rows. The rest ship with a status and no value.", n_gap_rows),
  gaps = "**All 33 rows always appear**, so absence is legible. Check `status` before reading `value`."
)

NOTES_HAZARD <- list(
  sections = "`preparedness`, `response` and `general` are always present. Others are hazard-specific.",
  map_layers = "Layer ids from `data/registry/map_layers.csv`. **Always an array**, even with one element.",
  jra_category = "The NYC JRA hazard this maps to. q-map's 8 re-cut the JRA's 10."
)

# --- assemble ----------------------------------------------------------------

L <- c(
"# Data contract",
"",
sprintf(paste("> Generated by `scripts/05_generate_data_contract.R` from the actual",
              "contents of `data/processed/` on %s. **Do not edit by hand** -",
              "regenerate. Field lists, types, counts and examples are read off",
              "the real outputs; the prose is authored in the generator."),
        format(Sys.Date())),
"",
paste("This document is the interface the frontend consumes from the `{targets}`",
      "pipeline. **It is sufficient on its own to wire up MapLibre sources and",
      "load attribute data - no pipeline code needs to be read.** Where it is",
      "ambiguous, flag it and ask; do not guess."),
"",
"## 1. Output inventory",
"",
"All paths are relative to the deployed data root. The frontend loads everything",
"from the same origin; nothing is fetched from Socrata, ArcGIS or GitHub",
"Releases at runtime.",
"",
"| Artifact | Files | Size | What it is |",
"|---|---|---|---|",
file_row(file.path(PROCESSED, "districts.json"), "The entry index. Loaded once."),
file_row(file.path(PROCESSED, "cdta.geojson"), "59 simplified polygons, EPSG:4326."),
file_row(file.path(PROCESSED, "districts/q*.json"), "The 02-screen payload, one per Queens district."),
file_row(file.path(PROCESSED, "resources/q*.json"), "Per-district resource lists, detail inlined."),
file_row(file.path(PROCESSED, "gaps/q*.json"), "The full gap matrix per district."),
file_row(file.path(PROCESSED, "hazards/*.json"), "Authored hazard guidance, citywide."),
file_row(file.path(PROCESSED, "districts/q*/hazards/*.json"), "District-specific hazard overrides. Rare."),
file_row(file.path(PROCESSED, "layers/*.pmtiles"), "Vector tiles for hazard-page overlays. PMTiles v3, MVT, z10-16, EPSG:4326."),
"",
sprintf("`districts.json` covers all %d CDTAs citywide; every per-district file covers the 14 in Queens.", n_districts),
"",
"## 2. `districts.json` - the index",
"",
"An array. Drives the neighbourhood picker, the map, and client-side",
"point-in-polygon after geocoding.",
"",
field_table(idx, NOTES_IDX),
"",
"## 3. `districts/<slug>.json` - the district payload",
"",
field_table(district, NOTES_DISTRICT),
"",
"### `hazards[]`",
"",
field_table(district$hazards[[1]], list(
  ranked = "`true` for positions 1-4. When `false`, `risk`/`severity`/`exposure` are absent and `reason` is present.",
  risk = "`severity x exposure`. Comparable **within** a district, not across districts.",
  exposure = "0-1, normalised against the citywide maximum."
)),
"",
"### `risk_profile` entries",
"",
field_table(district$risk_profile$hvi, list(
  reference_frame = "Always present. The frame is a property of the number.",
  citywide_percentile = "0-1, midrank. Present where a percentile is meaningful."
)),
"",
"### `gaps_displayed[]`",
"",
field_table(district$gaps_displayed[[1]], list(
  sentence_template = "Interpolate `facts` into this. **The pipeline does not write the sentence.**",
  facts = "Keys vary by gap. Interpolate by name, do not assume a fixed set.",
  risk_rank = "The rank of the hazard this gap is about.",
  polarity = "`higher_is_worse` or `higher_is_better`. **Do not assume.**"
)),
"",
"## 4. `resources/<slug>.json`",
"",
field_table(resources, NOTES_RESOURCES),
"",
"### `resources[]`",
"",
field_table(resources$resources[[1]], list(
  resource_id = "**Stable across rebuilds.** Permalinks depend on it.",
  category = "Resolves through `data/crosswalk/resource_categories.csv`.",
  is_coad_member = "FRANC membership. A flag, not a category."
)),
"",
"## 5. `gaps/<slug>.json`",
"",
field_table(gaps, NOTES_GAPS),
"",
"### `gaps[]`",
"",
field_table(gaps$gaps[[1]], list(
  status = "`available` | `blocked_on_data` | `deferred` | `retired`. **Only `available` has a value.**",
  blocked_on = "Present when blocked, deferred or retired. Names what it waits on."
)),
"",
"## 6. `hazards/<slug>.json`",
"",
field_table(hazard, NOTES_HAZARD),
"",
sprintf("%d hazards. A district-specific override lives at `districts/<slug>/hazards/<hazard>.json` and **replaces whole top-level keys** of the base file - it is not a deep merge. Fetch it only when the district payload's `hazard_overrides` names that hazard.", n_hazards),
"",
"## 7. Join model",
"",
"- `cdta.geojson` features carry `cdta2020` and `slug` only. Everything else joins client-side.",
"- Set `promoteId: \"cdta2020\"` on the source and push attributes via `setFeatureState`.",
"- `districts.json` -> `districts/<slug>.json` on `slug`.",
"- `gaps_displayed[].gap_id` -> `gaps/<slug>.json` for the full row.",
"- `hazards[].slug` -> `hazards/<slug>.json` for guidance.",
"",
"## 8. Gotchas",
"",
"Everything here is stated above. It is repeated because these are the ones that",
"produce plausible, confidently wrong output rather than an error.",
"",
"- **`point_on_surface` is not a centroid.** QN14's true centroid is in open water.",
"- **Two population figures from two sources.** `population.total` is CHP; `surge_pop_pct`'s denominator is ACS. They disagree by up to 20% per district. **Multiplying the share by the total does not give a headcount.** Both carry `source`.",
"- **`polarity` is data, not a UI assumption.** These indicators mix deficits, supplies and distances. A single \"more filled = more\" rule is wrong.",
"- **Pinned hazards are not \"least dangerous\".** Positions 5-8 mean *not differentiable by district*. Read `ranked` and show `reason`; do not present them as a continuation of the ranking.",
"- **The hazard ordering is provisional.** `meta.hazard_model_status` says so. Severity weights are editorial and awaiting expert review.",
"- **Check `status` before reading a gap's `value`.** Most of the 33 have none.",
"- **`resource_categories` is per-district.** Two wireframe screens show different lists because they render different districts. Both are right.",
"- **Arrays stay arrays.** `map_layers`, `hazards`, `languages`, `gaps_displayed` and `resources` are always arrays, even with one element. Asserted in the pipeline.",
"- **`coad` is `null` in 13 of 14 districts.** That is the common case.",
"- **Layer ids are permalink surface.** They appear in map URLs. `data/registry/map_layers.csv` is the vocabulary; only rows with `status: available` have an artifact. `delivery: inline` means the values already ship in the district payload and join to `cdta.geojson` by `cdta2020` - there is no separate file.",
"- **Language estimates carry `cv`.** Above 30, DCP treats the figure as unreliable; `facts.reliable` says so. One district's top result has a CV of 49.",
""
)

writeLines(unlist(L), OUT)
message("Wrote ", OUT, " (", length(unlist(L)), " lines)")
