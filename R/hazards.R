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

# Coastal storm, aggregated tract -> CDTA, two ways.
#
# `coastal_max_fvi` is the REVIEWED measure: the worst-case tract, max(ss_cur)
# across the district. Adopted 2026-09-22 from queens-hazard-ranking@a4c1429,
# the source of truth for the ranking after expert review.
#
# This reverses the population weighting that `coastal` below applies, and with
# it PIPELINE_DESIGN.md 2's requirement that census-tract sources be
# population-weighted. The two answer different questions - "how much of this
# district is exposed" versus "how bad is it where it is worst" - and the
# review chose the latter. 2 is not amended; METHODOLOGY.md, "The reviewed
# ranking is the source of truth", records the departure and the evidence.
#
# `coastal` (population share x population-weighted mean index) is KEPT for now
# so this change does not alter any output on its own. build_hazards() still
# reads it; PR-2 switches the ranking to coastal_max_fvi and deletes it.
#
# pop_total / pop_exposed / pop_share_exposed stay regardless of that: they
# produce surge_pop_pct, which ships in risk_profile and the district page
# displays. Under the reviewed method they will read as inconsistent with the
# ranking - QN07 is 30.1% exposed and scores 4, QN10 is 23% and scores 5 -
# because share and worst-case are different facts. That is expected.
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
      # An NA index means the tract is NOT exposed, so it is dropped rather
      # than scored 0. A district whose every tract is NA yields 0 here, and a
      # district with no row at all is coalesced to 0 in
      # build_hazard_measures() - both routes reproduce the report's
      # replace_na(max_ss_cur_fvi, 0).
      coastal_max_fvi = if (any(!is.na(idx))) max(idx[!is.na(idx)]) else 0,
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

# Quintile rank 1-5, the reviewed method's way of putting a continuous measure
# on the same 1-5 footing as the published indices (HVI, FVI).
#
# This is deliberately the report's exact expression - cut() over quantile()
# with include.lowest - rather than a re-derivation, because the fixture in
# data/canonical/hazard_ranking_reviewed.csv was cut from that expression and
# validate_hazard_ranking() asserts equality. A subtly different quantile type
# would produce plausible off-by-one quintiles on the boundary districts.
#
# MUST be given all 59 CDTAs. The breaks are citywide; computing them over
# Queens alone would rescale every Queens score and still validate against
# every other check in the file. That is the failure mode PIPELINE_DESIGN.md
# warns about, so the caller's row count is asserted, not assumed.
quintile_citywide <- function(x) {
  if (length(x) != 59) {
    stop("quintile_citywide() needs all 59 CDTAs to place the breaks; got ",
         length(x), ". Queens-only input would rescale every score.")
  }
  breaks <- stats::quantile(x, probs = seq(0, 1, 0.2), na.rm = TRUE)
  as.integer(cut(x, breaks = breaks, labels = FALSE, include.lowest = TRUE))
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
      select(coastal, cdta2020, coastal, coastal_max_fvi,
             coastal_pop_share = pop_share_exposed),
      by = "cdta2020"
    ) |>
    # A district with no exposed tracts is absent from the coastal aggregation
    # rather than present with a zero. Make the zero explicit, or it becomes NA
    # and the hazard silently drops out of that district's ordering.
    mutate(
      coastal = coalesce(coastal, 0),
      coastal_max_fvi = coalesce(coastal_max_fvi, 0),
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
    ) |>
    # The REVIEWED scores, all on the published 1-5 footing. Added alongside
    # the exposure columns above rather than replacing them, so this change
    # alters no output on its own; PR-2 rewires build_hazards() onto these and
    # drops the four `normalise_exposure()` columns and `coastal`.
    #
    # Note what is NOT here: hazmat. The review pins it (position 4) because
    # Queens has atypically many chemically intensive businesses, so the
    # measure ranked it 1st or 2nd in 11 of 14 districts and discriminated
    # between them poorly. chem_business_count stays in the payload as context
    # and still feeds the chem_businesses map layer.
    mutate(
      score_coastal_storm = as.integer(coastal_max_fvi),
      score_heavy_rain    = quintile_citywide(rain_pct),
      # HVI is already published 1-5, so it is the score unchanged - no
      # normalisation, no re-ranking.
      score_extreme_heat  = as.integer(hvi)
    )
}

REVIEWED_SCORE_COLS <- c("score_coastal_storm", "score_heavy_rain",
                         "score_extreme_heat")

validate_hazard_measures <- function(measures) {
  assert_row_count(measures, 59, 59)
  assert_unique(measures, "cdta2020")
  assert_no_na(measures, c("hvi", "pivi", "chem_business_count",
                           "rain_pct", "coastal", "coastal_max_fvi",
                           names(HAZARD_SEVERITY), REVIEWED_SCORE_COLS))

  # Exposure must be a proportion. A value outside 0-1 means the normalisation
  # divided by the wrong maximum, which would silently reorder every district.
  for (h in names(HAZARD_SEVERITY)) {
    v <- measures[[h]]
    if (any(v < 0 | v > 1)) {
      stop("Exposure for '", h, "' falls outside 0-1")
    }
  }

  # The reviewed scores share one scale, which is the whole reason they can be
  # compared without severity weights. Coastal admits 0 because "no exposed
  # tract" is a real zero; the two indices are published 1-5 and a 0 there
  # would mean a failed join, not an unexposed district.
  for (s in REVIEWED_SCORE_COLS) {
    v <- measures[[s]]
    lo <- if (s == "score_coastal_storm") 0L else 1L
    if (any(v < lo | v > 5L)) {
      stop("Reviewed score '", s, "' falls outside ", lo, "-5, so it is not on ",
           "the 1-5 footing the unweighted ranking depends on")
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

# --- the reviewed ranking, as an asserted fixture ---------------------------

# data/canonical/hazard_ranking_reviewed.csv is the expert-reviewed source of
# truth for the three ranked scores. Human-owned and commented, so read with
# comment.char and explicit types rather than letting readr guess.
read_reviewed_ranking <- function(path) {
  readr::read_csv(
    path,
    comment = "#",
    col_types = readr::cols(
      cdta2020            = readr::col_character(),
      coastal_max_fvi     = readr::col_integer(),
      heavy_rain_quintile = readr::col_integer(),
      hvi                 = readr::col_integer()
    )
  )
}

# Assert the computed scores reproduce the reviewed fixture exactly.
#
# This is the target that makes the review load-bearing: change a measure
# without re-running queens-hazard-ranking and re-cutting the fixture, and the
# build stops here rather than shipping a ranking nobody approved.
#
# Two-way anti_join rather than a row count, per the house rule - it catches a
# district the pipeline scores that the review does not, as well as one that
# has gone missing. A count would pass on a swap.
validate_hazard_ranking <- function(measures, reviewed) {
  # Fixture column names are the report's; map them onto the pipeline's.
  expected <- reviewed |>
    transmute(
      cdta2020,
      score_coastal_storm = coastal_max_fvi,
      score_heavy_rain    = heavy_rain_quintile,
      score_extreme_heat  = hvi
    )

  computed <- measures |>
    filter(substr(cdta2020, 1, 2) == "QN") |>
    select(cdta2020, all_of(REVIEWED_SCORE_COLS))

  extra   <- anti_join(computed, expected, by = "cdta2020")
  missing <- anti_join(expected, computed, by = "cdta2020")
  if (nrow(extra) > 0 || nrow(missing) > 0) {
    or_none <- function(x) if (length(x) == 0) "none" else paste(x, collapse = ", ")
    stop("Reviewed ranking covers ", nrow(expected), " districts, pipeline ",
         nrow(computed), ". Scored but not reviewed: ", or_none(extra$cdta2020),
         "; reviewed but not scored: ", or_none(missing$cdta2020))
  }

  # Compare column by column so the message names the measure that drifted,
  # not just the district. A district can disagree on one score and agree on
  # the other two, and which one it is decides where to look.
  drift <- character(0)
  joined <- inner_join(computed, expected, by = "cdta2020",
                       suffix = c("", "_reviewed"))
  for (s in REVIEWED_SCORE_COLS) {
    bad <- joined[joined[[s]] != joined[[paste0(s, "_reviewed")]], ]
    if (nrow(bad) > 0) {
      drift <- c(drift, paste0(
        s, ": ", paste0(bad$cdta2020, " (", bad[[s]], " vs reviewed ",
                        bad[[paste0(s, "_reviewed")]], ")", collapse = ", ")
      ))
    }
  }
  if (length(drift) > 0) {
    stop("Hazard scores disagree with the reviewed ranking:\n  ",
         paste(drift, collapse = "\n  "),
         "\nEither a measure changed, or queens-hazard-ranking needs ",
         "re-running and data/canonical/hazard_ranking_reviewed.csv re-cut.")
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
