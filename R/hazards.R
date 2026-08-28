# R/hazards.R
#
# The per-district hazard ordering.
#
# Model: risk = severity x exposure. Severity is a citywide editorial constant;
# exposure is the local measure normalised against the citywide maximum, so a
# genuine zero stays zero. Two earlier approaches - pure citywide percentile,
# and anchoring severity to the JRA's Planning Priority Scores - were
# prototyped and rejected on evidence. See METHODOLOGY.md for both, and for the
# expert-review questions this model is provisional pending.

# --- the eight hazards ------------------------------------------------------

# Ranked hazards, in the order their severity weights place them citywide.
# PROVISIONAL, adopted 2026-08-28 pending expert review. Reasoning per weight
# is in METHODOLOGY.md; do not adjust these without updating it.
HAZARD_SEVERITY <- c(
  `coastal-storm` = 1.00,
  `extreme-heat`  = 0.80,
  `heavy-rain`    = 0.70,
  `hazmat`        = 0.40
)

# Pinned hazards occupy positions 5-8 in this fixed order. A hazard is pinned
# when it has no district-level measure that meaningfully varies across the
# districts being displayed. Infectious disease is first because it is the only
# one of the four that is actually measured - its position is an observed
# result, not an absence.
HAZARD_PINNED <- c(
  "infectious-disease",
  "extreme-cold",
  "blackout-cyberattack",
  "mass-casualty"
)

HAZARD_LABELS <- c(
  `coastal-storm`        = "Coastal Storm",
  `extreme-heat`         = "Extreme Heat",
  `heavy-rain`           = "Heavy Rain",
  `hazmat`               = "Hazmat / Chemical",
  `infectious-disease`   = "Infectious Disease",
  `extreme-cold`         = "Extreme Cold",
  `blackout-cyberattack` = "Blackout & Cyberattack",
  `mass-casualty`        = "Mass Casualty"
)

# Why each pinned hazard is pinned, carried into the payload so the UI can be
# honest rather than implying "least dangerous".
HAZARD_PIN_REASON <- c(
  `infectious-disease`   = "measured citywide, but does not vary across Queens",
  `extreme-cold`         = "no district-level measure published",
  `blackout-cyberattack` = "no district-level measure published",
  `mass-casualty`        = "not scored by district; see METHODOLOGY.md"
)

# --- Tier-1 hazard inputs ---------------------------------------------------

PIVI_SERVICE_URL <- paste0(
  "https://services1.arcgis.com/8cuieNI8NbqQZQVJ/arcgis/rest/services/",
  "Pandemic_Influenza_Vulnerability_Index/FeatureServer/0/query"
)

# NOTE the literal spaces in the service name. Unencoded, the request returns
# nothing at all rather than erroring - which is how this layer was missed on a
# first pass and a much weaker 207-point EPA layer used in its place.
CHEM_SERVICE_URL <- paste0(
  "https://services3.arcgis.com/A6Zjpzrub8ESZ3c7/arcgis/rest/services/",
  "Chemically%20Intensive%20Small%20Businesses_2/FeatureServer/0/query"
)

FVI_SERVICE_URL <- paste0(
  "https://services3.arcgis.com/A6Zjpzrub8ESZ3c7/arcgis/rest/services/",
  "NYC_Flood_Vulnerability_Index/FeatureServer/0/query"
)

fetch_attributes <- function(url, fields, extra = list()) {
  parsed <- httr::parse_url(url)
  parsed$query <- c(list(
    where = "1=1", outFields = fields, returnGeometry = "false", f = "json"
  ), extra)
  jsonlite::fromJSON(httr::build_url(parsed))$features$attributes
}

get_pivi <- function(url = PIVI_SERVICE_URL) {
  out <- fetch_attributes(url, "COMMDIST,PIVI") |>
    transmute(borocd = as.integer(COMMDIST), pivi = as.integer(PIVI)) |>
    arrange(borocd)
  assert_row_count(out, 59, 59)
  assert_no_na(out, c("borocd", "pivi"))
  out
}

# Chemically Intensive Small Businesses, one polygon per community district.
#
# The count field is published as `top_3`. It is a COUNT (range 4-202), not a
# flag and not a rank - nothing in the schema says so, and a reader who assumes
# otherwise will interpret 202 as a position. Renamed on ingest for that
# reason. The name also suggests the count covers only the top three
# chemically-intensive business categories; confirm with DOHMH before
# publishing the raw number as a fact. Relative order is safe to rank on.
get_chem_businesses <- function(url = CHEM_SERVICE_URL) {
  out <- fetch_attributes(url, "BoroCD,top_3") |>
    transmute(borocd = as.integer(BoroCD), chem_business_count = as.integer(top_3)) |>
    arrange(borocd)
  assert_row_count(out, 59, 59)
  assert_no_na(out, c("borocd", "chem_business_count"))
  out
}

# Flood Vulnerability Index, census tract.
#
# Two traps. The service caps at 2,000 records and there are 2,208 tracts, so
# it must be paginated or the last ~200 vanish silently. And the index columns
# are SPARSE: NULL means "not exposed", not "missing" - only 337 tracts
# citywide carry ss_cur. Never coalesce those NULLs to zero and average; the
# index is a quintile among exposed tracts only.
# Returned with geometry: the same tracts are needed both for the surge index
# and for the point-on-surface join that assigns tracts to districts.
get_fvi <- function(url = FVI_SERVICE_URL) {
  pages <- list()
  offset <- 0
  repeat {
    u <- paste0(url, "?where=1%3D1&outFields=geoid,ss_cur,ss_80s,tid_20s,fshri",
                "&returnGeometry=true&outSR=2263",
                "&resultOffset=", offset, "&resultRecordCount=2000&f=geojson")
    page <- read_sf(u)
    if (nrow(page) == 0) break
    pages[[length(pages) + 1]] <- page
    if (nrow(page) < 2000) break
    offset <- offset + 2000
  }
  out <- bind_rows(pages) |>
    mutate(
      geoid = as.character(geoid),
      across(c(ss_cur, ss_80s, tid_20s, fshri), as.integer)
    ) |>
    st_make_valid()

  # 2,208 tracts against a 2,000-record cap: without pagination the last ~200
  # disappear silently, which would quietly zero out coastal exposure for
  # whichever districts they fall in.
  if (nrow(out) < 2100) {
    stop(paste0("FVI: got ", nrow(out), " tracts, expected ~2208 - ",
                "pagination may have stopped early"))
  }
  assert_unique(st_drop_geometry(out), "geoid")
  out
}

# --- district-level hazard measures -----------------------------------------

# Coastal storm, aggregated tract -> CDTA and POPULATION-weighted.
#
# PIPELINE_DESIGN.md 2 requires population weighting for census-tract sources,
# and it matters here: a district's coastal risk is about how many people live
# in the surge zone, not how much of its area does. The Rockaways is the case
# that makes the difference visible.
#
# The measure is (share of district population in an exposed tract) x
# (population-weighted mean surge index among those tracts). The first term
# carries most of the signal; the second distinguishes a district with a lot of
# mildly exposed people from one with a lot of severely exposed people.
coastal_per_cdta <- function(fvi, tract_cdta, tract_pop, index_col = "ss_cur") {
  fvi |>
    inner_join(tract_cdta, by = "geoid") |>
    inner_join(tract_pop, by = "geoid") |>
    mutate(idx = .data[[index_col]]) |>
    group_by(cdta2020) |>
    summarise(
      pop_total = sum(pop, na.rm = TRUE),
      pop_exposed = sum(pop[!is.na(idx)], na.rm = TRUE),
      mean_index = if (sum(pop[!is.na(idx)], na.rm = TRUE) > 0) {
        stats::weighted.mean(idx[!is.na(idx)], pop[!is.na(idx)])
      } else 0,
      .groups = "drop"
    ) |>
    mutate(
      pop_share_exposed = ifelse(pop_total > 0, pop_exposed / pop_total, 0),
      coastal = pop_share_exposed * mean_index
    )
}

# --- the ranking model ------------------------------------------------------

# Exposure normalised against the citywide maximum rather than converted to a
# percentile. Percentile is uniform by construction, so a district with zero
# exposure still scores ~0.2 from ties at the bottom; max-normalisation keeps a
# real zero at zero, which is what makes the eligibility floor automatic.
#
# HVI is divided by its published 1-5 scale rather than by the observed max, so
# it is not re-ranked - the same rule METHODOLOGY.md applies to PIVI.
normalise_exposure <- function(x, scale_max = NULL) {
  m <- if (is.null(scale_max)) max(x, na.rm = TRUE) else scale_max
  if (!is.finite(m) || m <= 0) return(rep(0, length(x)))
  pmin(pmax(x / m, 0), 1)
}

# Assemble every district-level hazard measure, citywide, on one row per CDTA.
#
# Citywide because the exposure normalisation and the reported percentiles are
# both defined against all 59 districts - computing only Queens would change
# every number on a Queens page.
build_hazard_measures <- function(crosswalk, hvi, pivi, chem, rain, coastal) {
  midrank_pct <- function(x) {
    n <- length(x)
    vapply(x, function(v) {
      (sum(x < v, na.rm = TRUE) + 0.5 * sum(x == v, na.rm = TRUE)) / n
    }, numeric(1))
  }

  crosswalk |>
    select(cdta2020, borocd) |>
    left_join(hvi, by = "borocd") |>
    left_join(pivi, by = "borocd") |>
    left_join(chem, by = "borocd") |>
    left_join(rename(rain, rain_pct = pct_area), by = "cdta2020") |>
    left_join(
      select(coastal, cdta2020, coastal, coastal_pop_share = pop_share_exposed),
      by = "cdta2020"
    ) |>
    # A district with no exposed tracts is absent from the coastal aggregation
    # rather than present with a zero. Make the zero explicit, or it becomes NA
    # and the hazard silently drops out of that district's ordering.
    mutate(
      coastal = coalesce(coastal, 0),
      coastal_pop_share = coalesce(coastal_pop_share, 0),
      rain_pct = coalesce(rain_pct, 0)
    ) |>
    mutate(
      hvi_pct = midrank_pct(hvi),
      chem_pct = midrank_pct(chem_business_count),
      # HVI is normalised against its published 1-5 scale, not the observed
      # maximum, so it is never re-ranked. The others have no published scale
      # and normalise against the citywide max.
      `extreme-heat`  = normalise_exposure(hvi, scale_max = 5),
      `heavy-rain`    = normalise_exposure(rain_pct),
      `coastal-storm` = normalise_exposure(coastal),
      `hazmat`        = normalise_exposure(chem_business_count)
    )
}

validate_hazard_measures <- function(measures) {
  assert_row_count(measures, 59, 59)
  assert_unique(measures, "cdta2020")
  assert_no_na(measures, c("hvi", "pivi", "chem_business_count",
                           "rain_pct", "coastal", names(HAZARD_SEVERITY)))

  # Exposure must be a proportion. A value outside 0-1 means the normalisation
  # divided by the wrong maximum, which would silently reorder every district.
  for (h in names(HAZARD_SEVERITY)) {
    v <- measures[[h]]
    if (any(v < 0 | v > 1)) {
      stop("Exposure for '", h, "' falls outside 0-1")
    }
  }

  # Each ranked hazard must actually vary across the districts being displayed
  # - that is the criterion that put four hazards in the ranked set and four in
  # the pinned one. If one goes flat, it belongs in the pinned set instead.
  queens <- measures |> filter(substr(cdta2020, 1, 2) == "QN")
  for (h in names(HAZARD_SEVERITY)) {
    if (dplyr::n_distinct(round(queens[[h]], 6)) < 3) {
      stop("Ranked hazard '", h, "' takes fewer than 3 distinct values across ",
           "Queens - it no longer meets the ranking criterion (METHODOLOGY.md)")
    }
  }
  TRUE
}

# Build the ordered hazard list for every district.
#
# `measures` is one row per CDTA with columns named for each ranked hazard slug,
# each already normalised to 0-1 exposure.
build_hazards <- function(measures) {
  ranked <- names(HAZARD_SEVERITY)

  long <- measures |>
    select(cdta2020, all_of(ranked)) |>
    tidyr::pivot_longer(all_of(ranked), names_to = "slug", values_to = "exposure") |>
    mutate(
      severity = unname(HAZARD_SEVERITY[slug]),
      risk = severity * exposure
    ) |>
    group_by(cdta2020) |>
    # Ties are broken by severity, then slug, so the ordering is deterministic
    # across rebuilds - a district with two zero-exposure hazards must not
    # reshuffle them between runs.
    arrange(desc(risk), desc(severity), slug, .by_group = TRUE) |>
    mutate(rank = row_number(), ranked = TRUE) |>
    ungroup()

  pinned <- tidyr::expand_grid(
    cdta2020 = unique(measures$cdta2020),
    slug = HAZARD_PINNED
  ) |>
    mutate(
      exposure = NA_real_, severity = NA_real_, risk = NA_real_,
      rank = length(ranked) + match(slug, HAZARD_PINNED),
      ranked = FALSE
    )

  bind_rows(long, pinned) |>
    mutate(
      label = unname(HAZARD_LABELS[slug]),
      pin_reason = unname(HAZARD_PIN_REASON[slug])
    ) |>
    arrange(cdta2020, rank)
}
