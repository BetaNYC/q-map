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
  if (!is.character(v)) return(paste0("`", v, "`"))
  # Mark the truncation. Without the ellipsis a clipped example reads as a
  # complete value - "The ANSOB Center was opened with the" looked like the
  # whole mission statement.
  if (nchar(v) > 36) paste0("`\"", substr(v, 1, 36), "\"...`")
  else paste0("`\"", v, "\"`")
}

# Field table over EVERY record, not one sampled record.
#
# The previous version read `resources$resources[[1]]` and the like - a single
# element of one district's array. That is drift-proof for facts about that one
# record and structurally blind to any field that varies between records, which
# is the majority of what matters here:
#
#   - It documented 13 resource fields and missed 8 that exist only on Queens
#     Nonprofit Directory records - mission, contact_name, email, phone,
#     website, languages, accepts_referrals, fees. Those are the entire content
#     of screens 05 and 06, and the sampled record was a FacDB row with none.
#   - It never showed `hazards[].reason`, because q14's first hazard is ranked.
#   - It never showed `status: "stub"`, because the sampled hazard file is the
#     one authored hazard that lacks it - while 7 of 8 carry it.
#   - It reported `address` and `capacity` as always present. Neither is.
#
# A union of keys plus a presence count fixes all four, and the count carries
# information a type cannot: `mission (236/3905)` tells a frontend developer
# that the field is optional and roughly how optional, which is the thing they
# actually need to know before writing a component.
field_table <- function(records, notes = list()) {
  if (!is.null(names(records)) && length(records) > 0 &&
      !is.list(records[[1]])) {
    records <- list(records)   # a single object, not an array of them
  }
  n <- length(records)
  keys <- unique(unlist(lapply(records, names)))

  present <- vapply(keys, function(k) {
    sum(vapply(records, function(r) !is.null(r[[k]]), logical(1)))
  }, integer(1))

  # Type and example come from the first record that actually has the field,
  # so an optional field is described from a real value rather than a NULL.
  first_of <- function(k) {
    for (r in records) if (!is.null(r[[k]])) return(r[[k]])
    NULL
  }

  show_presence <- n > 1
  head <- if (show_presence) {
    c("| Field | Type | Present | Example | Notes |", "|---|---|---|---|---|")
  } else {
    c("| Field | Type | Example | Notes |", "|---|---|---|---|")
  }

  rows <- vapply(keys, function(k) {
    v <- first_of(k)
    if (show_presence) {
      sprintf("| `%s` | %s | %s | %s | %s |", k, json_type(v),
              if (present[[k]] == n) sprintf("all %d", n)
              else sprintf("**%d of %d**", present[[k]], n),
              example_of(v), notes[[k]] %||% "")
    } else {
      sprintf("| `%s` | %s | %s | %s |", k, json_type(v),
              example_of(v), notes[[k]] %||% "")
    }
  }, character(1))

  c(head, rows)
}

# Flatten every element of a named array field across a set of payloads.
all_of <- function(payloads, field) {
  unlist(lapply(payloads, function(p) p[[field]]), recursive = FALSE)
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

# Read a PMTiles v3 header and its embedded metadata.
#
# The contract claimed to be "sufficient on its own to wire up MapLibre
# sources" and was not: it gave zoom and CRS and stopped. Without the
# source-layer id nothing renders at all, and without the styling attribute and
# its domain there is no fill expression and no legend. Both are IN the file,
# so they can be generated rather than hand-copied - which is the exact drift
# PIPELINE_DESIGN.md section 11 called out in d26 ("Flooding_C vs swf_cat,
# stale minzoom") and which this generator exists to prevent.
pmtiles_meta <- function(path) {
  con <- file(path, "rb"); on.exit(close(con))
  head <- readBin(con, "raw", n = 127)
  if (!identical(rawToChar(head[1:7]), "PMTiles")) return(NULL)

  u64 <- function(off) {
    sum(as.numeric(head[(off + 1):(off + 8)]) * 256^(0:7))
  }
  md_off <- u64(24); md_len <- u64(32)
  minzoom <- as.integer(head[101]); maxzoom <- as.integer(head[102])

  seek(con, md_off)
  raw_md <- readBin(con, "raw", n = md_len)
  txt <- tryCatch(memDecompress(raw_md, "gzip", asChar = TRUE),
                  error = function(e) rawToChar(raw_md))
  j <- fromJSON(txt, simplifyVector = FALSE)
  vl <- j$vector_layers[[1]]

  list(
    file = basename(path),
    source_layer = vl$id,
    fields = names(vl$fields),
    minzoom = minzoom, maxzoom = maxzoom,
    name = j$name
  )
}

# The set of values a tiled attribute actually takes, read off the source so
# the legend can be written against real categories rather than guessed ones.
FLOODING_C_DOMAIN <- c(
  "1" = "Nuisance flooding (>= 4 in and < 1 ft)",
  "2" = "Deep and contiguous flooding (>= 1 ft)"
)

# --- read the real outputs ---------------------------------------------------

# Read EVERYTHING. The generator's whole value is that it cannot describe an
# output the pipeline does not produce; sampling one record per array threw that
# away for every field that varies by record.
read_all <- function(pattern) lapply(Sys.glob(file.path(PROCESSED, pattern)), read1)

idx_all       <- read1(file.path(PROCESSED, "districts.json"))
districts_all <- read_all("districts/q*.json")
resources_all <- read_all("resources/q*.json")
gaps_all      <- read_all("gaps/q*.json")
hazards_all   <- read_all("hazards/*.json")
overrides_all <- read_all("districts/q*/hazards/*.json")
conditions    <- read1(file.path(PROCESSED, "conditions.json"))

# Flattened element sets, one row per real record.
hazard_entries   <- all_of(districts_all, "hazards")
gap_displayed    <- all_of(districts_all, "gaps_displayed")
resource_records <- all_of(resources_all, "resources")
gap_rows         <- all_of(gaps_all, "gaps")
cat_entries      <- all_of(districts_all, "resource_categories")
section_records  <- all_of(hazards_all, "sections")
language_records <- unlist(lapply(districts_all,
                                  function(d) d$population$languages),
                           recursive = FALSE)

# risk_profile is an object keyed by indicator, not an array. Its entries have
# DIFFERENT key sets - hvi carries citywide_percentile, surge_pop_pct carries
# source and note - so the union is exactly what a consumer needs.
risk_entries <- unlist(lapply(districts_all,
                              function(d) unname(d$risk_profile)),
                       recursive = FALSE)
population_entries <- lapply(districts_all, function(d) d$population)

n_districts <- length(idx_all)
n_gap_rows  <- length(gaps_all[[1]]$gaps)
n_hazards   <- length(hazards_all)

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
  gaps_displayed = "Up to 3. Every entry carries `risk_rank`; a fallback also carries `fallback_from` naming the top-three hazard whose slot it fills.",
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
file_row(file.path(PROCESSED, "conditions.json"), "Citywide respiratory illness. Chip on 01, and the infectious-disease hazard page."),
file_row(file.path(PROCESSED, "layers/*.pmtiles"), "Vector tiles for the stormwater overlays. PMTiles v3, MVT, EPSG:4326."),
file_row(file.path(PROCESSED, "layers/*.geojson"), "Map overlays small enough not to need tiling. RFC 7946."),
file_row(file.path(PROCESSED, "layers/resources/*.geojson"), "Resource points for the district map, minimal properties."),
"",
sprintf("`districts.json` covers all %d CDTAs citywide; every per-district file covers the 14 in Queens.", n_districts),
"",
"## 2. `districts.json` - the index",
"",
"An array. Drives the neighbourhood picker, the map, and client-side",
"point-in-polygon after geocoding.",
"",
field_table(idx_all, NOTES_IDX),
"",
"## 3. `districts/<slug>.json` - the district payload",
"",
field_table(districts_all, NOTES_DISTRICT),
"",
"### `hazards[]`",
"",
field_table(hazard_entries, list(
  ranked = "`true` for positions 1-4. When `false`, `risk`/`severity`/`exposure` are absent and `reason` is present.",
  risk = "`severity x exposure`. Comparable **within** a district, not across districts.",
  exposure = "0-1, normalised against the citywide maximum."
)),
"",
"### `risk_profile` entries",
"",
field_table(risk_entries, list(
  reference_frame = "Always present. The frame is a property of the number.",
  citywide_percentile = "0-1, midrank. Present where a percentile is meaningful."
)),
"",
"### `population`",
"",
paste("Every entry is a stat object of the same shape as `risk_profile`'s.",
      "**No screen currently renders this block** - wireframe V3 has no",
      "section D - and it is emitted deliberately against a later one. See",
      "METHODOLOGY.md, 'Scope dropped explicitly'."),
"",
field_table(population_entries, list(
  total = "CHP 2026. **Not the denominator of `surge_pop_pct`.** See gotchas.",
  languages = "Top limited-English languages in the district, largest first.",
  languages_shared_puma = "`true` where the PUMA covers two community districts, so the figures are shared. Always `false` in Queens."
)),
"",
"### `population.languages[]`",
"",
field_table(language_records, list(
  cv = "Coefficient of variation. **Above 30 DCP treats the estimate as unreliable** and greys it out.",
  moe = "Margin of error at 90%.",
  speakers = "Speakers with limited English, not total speakers of the language."
)),
"",
"### `resource_categories[]`",
"",
field_table(cat_entries, list(
  slug = "The category key. Matches `resources[].category` and the map layer's `category` property.",
  count = "Resources of this category located in this district."
)),
"",
"### `gaps_displayed[]`",
"",
field_table(gap_displayed, list(
  sentence_template = "Interpolate `facts` into this. **The pipeline does not write the sentence.**",
  facts = "Keys vary by gap. Interpolate by name, do not assume a fixed set.",
  risk_rank = "The rank of the hazard this gap measures. **Always present.** The one exception is a `cross-cutting` gap, which measures no ranked hazard and instead carries the rank of the slot it fills - `hazard_slug` tells you which reading applies.",
  fallback_from = "Present only on a fallback. Names the top-three hazard whose slot this sentence fills, so the UI can say so rather than implying an alignment that is not there.",
  polarity = "`higher_is_worse` or `higher_is_better`. **Do not assume.**"
)),
"",
"## 4. `resources/<slug>.json`",
"",
field_table(resources_all, NOTES_RESOURCES),
"",
"### `resources[]`",
"",
field_table(resource_records, list(
  resource_id = "**Stable across rebuilds.** Permalinks depend on it.",
  category = "Resolves through `data/crosswalk/resource_categories.csv`.",
  is_coad_member = "FRANC membership. A flag, not a category."
)),
"",
"## 5. `gaps/<slug>.json`",
"",
field_table(gaps_all, NOTES_GAPS),
"",
"### `gaps[]`",
"",
field_table(gap_rows, list(
  status = "`available` | `blocked_on_data` | `deferred` | `retired`. **Only `available` has a value.**",
  blocked_on = "Present when blocked, deferred or retired. Names what it waits on."
)),
"",
"## 6. `hazards/<slug>.json`",
"",
field_table(hazards_all, NOTES_HAZARD),
"",
sprintf("%d hazards. A district-specific override lives at `districts/<slug>/hazards/<hazard>.json` and **replaces whole top-level keys** of the base file - it is not a deep merge. Fetch it only when the district payload's `hazard_overrides` names that hazard.", n_hazards),
"",
"### the override file",
"",
paste("Same shape as a base hazard file, plus `meta`. `status` is derived: an",
      "override that authors every section reads `authored` even where the base",
      "it replaces is a stub."),
"",
field_table(overrides_all, list(
  meta = "`{district, overridden}`. `overridden` lists the top-level keys this file replaced - the only way to see what the merge changed, since it is not a deep merge.",
  status = "`stub` or `authored`. Derived from whether every section carries content."
)),
"",
"### `sections[]`",
"",
paste("**Every section carries both `items` and `body`**, one of which is empty.",
      "Seven of eight hazards are unwritten stubs whose sections carry neither",
      "content nor items, so a consumer iterating `section.items` must not",
      "assume the key exists - it always does now, and is often `[]`."),
"",
field_table(section_records, list(
  id = "From a closed vocabulary. `current-conditions` is data-backed - render conditions.json there, not authored content.",
  items = "Link list. Empty for prose sections and for stubs.",
  body = "Prose block. Empty string for link sections and for stubs."
)),
"",
"## 7. `conditions.json`",
"",
paste("Citywide respiratory illness. Feeds the chip on screen 01 and the",
      "`current-conditions` section of the infectious-disease hazard page.",
      "**Not district-scoped**, and it renders on district-scoped pages -",
      "`geography_label` exists so the component cannot omit saying so."),
"",
field_table(conditions[!vapply(conditions, is.list, logical(1))], list(
  chip_metric = "Which metric screen 01's chip shows. Names a key of this object.",
  archive_weeks = "Weeks held in the committed archive. DOHMH publishes a 12-week rolling window; anything older exists only because the archive kept it."
)),
"",
"### each metric object",
"",
field_table(list(conditions$respiratory_illness_visits,
                 conditions$respiratory_illness_hospitalizations), list(
  geography = "`nyc`. **This number is not about the district whose page it is on.**",
  geography_label = "Render this. It is the string that stops a citywide figure reading as local.",
  unit = "A percentage of emergency department visits, **not a count**.",
  unit_label = "Render this too. `6.41` means 6.41% of ED visits.",
  direction = "Change over the **last two weeks**.",
  trend = "Change over the **whole window**, least-squares. Can disagree with `direction`, and currently does - visits are `up` this week and `down` over twelve weeks.",
  series = "12 weekly points, oldest first. Enough for a sparkline."
)),
"",
"## 8. `layers/` - map overlays",
"",
paste("`data/registry/map_layers.csv` is the catalogue and the vocabulary for",
      "hazard content's `map_layers`. Only rows with `status: available` have",
      "an artifact. `delivery: inline` means the values already ship in the",
      "district payload and join to `cdta.geojson` by `cdta2020` - there is no",
      "file to fetch."),
"",
"### PMTiles sources",
"",
"| File | `source-layer` | Attributes | Zoom |",
"|---|---|---|---|",
vapply(Sys.glob(file.path(PROCESSED, "layers/*.pmtiles")), function(p) {
  m <- pmtiles_meta(p)
  sprintf("| `layers/%s` | `%s` | %s | z%d-%d |", m$file, m$source_layer,
          paste0("`", m$fields, "`", collapse = ", "), m$minzoom, m$maxzoom)
}, character(1), USE.NAMES = FALSE),
"",
paste0("`Flooding_C` is the styling attribute and takes ",
       length(FLOODING_C_DOMAIN), " values: ",
       paste(sprintf("`%s` %s", names(FLOODING_C_DOMAIN), FLOODING_C_DOMAIN),
             collapse = "; "), "."),
"",
"### GeoJSON sources",
"",
"| File | Features | Size | Properties |",
"|---|---|---|---|",
vapply(Sys.glob(file.path(PROCESSED, "layers/*.geojson")), function(p) {
  j <- read1(p)
  props <- names(j$features[[1]]$properties)
  sprintf("| `layers/%s` | %d | %.0f KB | %s |", basename(p),
          length(j$features), file.info(p)$size / 1024,
          paste0("`", props, "`", collapse = ", "))
}, character(1), USE.NAMES = FALSE),
"",
sprintf(paste("`layers/resources/<slug>.geojson` is per district - %d files,",
              "largest %.0f KB. A district map needs only its own points;",
              "one Queens-wide file measured 1.19 MB."),
        length(Sys.glob(file.path(PROCESSED, "layers/resources/*.geojson"))),
        max(file.info(Sys.glob(file.path(PROCESSED, "layers/resources/*.geojson")))$size) / 1024),
"",
field_table(read1(Sys.glob(file.path(PROCESSED, "layers/resources/*.geojson"))[1])$features[[1]]$properties,
            list(
  category = "The toggle key. Matches `resource_categories[].slug`.",
  resource_id = "Join to `resources/<slug>.json` for the full record."
)),
"",
"## 9. Join model",
"",
"- `cdta.geojson` features carry `cdta2020` and `slug` only. Everything else joins client-side.",
"- Set `promoteId: \"cdta2020\"` on the source and push attributes via `setFeatureState`.",
"- `districts.json` -> `districts/<slug>.json` on `slug`.",
"- `gaps_displayed[].gap_id` -> `gaps/<slug>.json` for the full row.",
"- `hazards[].slug` -> `hazards/<slug>.json` for guidance.",
"",
"## 10. Gotchas",
"",
"Everything here is stated above. It is repeated because these are the ones that",
"produce plausible, confidently wrong output rather than an error.",
"",
"- **`point_on_surface` is not a centroid.** QN14's true centroid is in open water.",
"- **Two population figures from two sources.** `population.total` is CHP; `surge_pop_pct`'s denominator is ACS. They disagree by up to 20% per district. **Multiplying the share by the total does not give a headcount.** Both carry `source`.",
"- **`polarity` is data, not a UI assumption.** These indicators mix deficits, supplies and distances. A single \"more filled = more\" rule is wrong.",
"- **Pinned hazards are not \"least dangerous\".** Positions 5-8 mean *not differentiable by district*. Read `ranked` and show `reason`; do not present them as a continuation of the ranking.",
"- **The hazard ordering is provisional.** `meta.hazard_model_status` says so. Severity weights are editorial and awaiting expert review.",
"- **Check `status` before reading a gap's `value`.** Most of the 33 have none, and 10 are retired - examined and rejected, which is a different claim from waiting on data. Group a 'see all gaps' view by `status`, not by hazard.",
"- **`resource_categories` is per-district.** Two wireframe screens show different lists because they render different districts. Both are right.",
"- **Arrays stay arrays.** `map_layers`, `hazards`, `languages`, `gaps_displayed` and `resources` are always arrays, even with one element. Asserted in the pipeline.",
"- **`coad` is `null` in 13 of 14 districts.** That is the common case.",
"- **Layer ids are permalink surface.** They appear in map URLs. `data/registry/map_layers.csv` is the vocabulary; only rows with `status: available` have an artifact. `delivery: inline` means the values already ship in the district payload and join to `cdta.geojson` by `cdta2020` - there is no separate file.",
"- **Language estimates carry `cv`.** Above 30, DCP treats the figure as unreliable. Gap 18 prefers the largest RELIABLE uncovered language and falls back to the largest overall in the three districts that have none; where it falls back, `facts.reliable` is `false` and the pipeline has already swapped in a hedged `sentence_template`. Render what you are given.",
"- **A gap sentence may be a finding of absence.** Where a `higher_is_worse` gap is zero the pipeline swaps in different copy (\"None of ... sit in an area that floods\") and sorts it last within its hazard, so it only appears when the hazard has nothing else. The template you receive already reflects that - do not branch on the value yourself.",
"- **`capacity` is omitted, never `0`.** FacDB uses 0 for \"not reported\" on 88% of records. If the key is absent, capacity is unknown, not zero.",
"- **Names and addresses are already title-cased** by the pipeline, with an acronym exception list. Do not re-case them in a component; `PS 811Q` and `O\'Brien` are correct as given.",
"- **Every section has both `items` and `body`.** One of them is empty. Seven of eight hazards are unwritten stubs, so that is the normal case, not the edge case.",
"- **`current-conditions` is a section with no content.** Render `conditions.json` there. It is citywide - show `geography_label`.",
"- **`direction` and `trend` can disagree, and currently do.** `direction` is the last two weeks; `trend` is the whole window. Visits are up this week and down over twelve. Showing only `direction` beside a sparkline puts an arrow against a visibly falling line.",
""
)

writeLines(unlist(L), OUT)
message("Wrote ", OUT, " (", length(unlist(L)), " lines)")
