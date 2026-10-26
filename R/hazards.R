# R/hazards.R
#
# The per-district hazard ordering.
#
# Model: two hazard CATEGORIES ranked on a common 1-5 score, compared
# UNWEIGHTED, with ties broken by geographic specificity. Seven are pinned
# below them in a fixed order.
#
# The scores underneath are the expert-reviewed model from
# queens-hazard-ranking (index.qmd, a4c1429), adopted 2026-09-22 and asserted
# against data/canonical/hazard_ranking_reviewed.csv: three measured
# sub-hazards, coastal storm, heavy rain and extreme heat. That review is
# unchanged and still asserted score for score.
#
# What changed on 2026-10-26 is what gets RANKED. The SME partners' final
# messaging regroups the hazards into nine categories, two of which nest the
# measured sub-hazards (content/hazards/*.yml `parts`). A category scores the
# worst of its measured parts - see CATEGORY_PARTS. METHODOLOGY.md, "Nine
# hazard categories", records the decision and its effect: Flooding now leads
# 13 of 14 districts, where heat led 11 under the three-way ranking.
#
# It replaced `risk = severity x exposure` (2026-09-22), whose editorial
# severity weights were provisional pending the review. METHODOLOGY.md, "The
# reviewed ranking is the source of truth", carries that history.

# --- the nine hazards -------------------------------------------------------

# The measured sub-hazards and the score column each one carries in
# `hazard_measures`. These are the REVIEWED scores. Kept as an explicit map
# rather than deriving the column from the slug, so a renamed measure fails
# loudly at `all_of()` instead of silently ranking on nothing.
#
# The names are part ids in content/hazards/*.yml and `part` values in the gap
# registry; validate_hazard_parts() holds the three in step.
PART_SCORE_COL <- c(
  `coastal-storm` = "score_coastal_storm",
  `heavy-rain`    = "score_heavy_rain",
  `extreme-heat`  = "score_extreme_heat"
)

# Which measured parts score each ranked category. A category scores the MAX
# of its parts: the worst-case reading the review already took inside coastal
# storm (max surge index across a district's tracts), applied one level up.
# "How bad is flooding here" is answered by whichever kind of flooding is
# worse, not an average that would let a dry district dilute a surge-exposed
# one.
#
# Extreme cold is a part of Temperature Extremes with no measure, so it is
# absent here and the category scores on heat alone.
CATEGORY_PARTS <- list(
  flooding               = c("coastal-storm", "heavy-rain"),
  `temperature-extremes` = c("extreme-heat")
)

# The ranked categories, in TIE-BREAK order: geographic specificity, as in the
# review. Flooding holds coastal storm and heavy rain, both of which the review
# placed ahead of extreme heat. Three districts tie (QN03, QN12, QN13) and
# all three resolve to Flooding first.
#
# This vector is the tie-break, so its order is load-bearing, not cosmetic.
HAZARD_PRIORITY <- c("flooding", "temperature-extremes")

# The score column each ranked category carries, built in
# build_hazard_measures() as the max of its parts.
HAZARD_SCORE_COL <- c(
  flooding               = "score_flooding",
  `temperature-extremes` = "score_temperature_extremes"
)

# Pinned hazards occupy positions 3-9 in this fixed order, set by Andrew
# 2026-10-26 to follow the SME document. A hazard is pinned when the project
# does not compare it across districts - a different claim from "least
# dangerous", hence HAZARD_PIN_REASON below.
#
# Hazmat is pinned despite BEING measured, and despite scoring high: Queens
# carries atypically many chemically intensive businesses, so the measure put
# it first or second in 11 of 14 districts while separating them poorly.
# Infectious disease is measured too (PIVI), and scores 1 or 2 everywhere.
HAZARD_PINNED <- c(
  "air-quality",
  "hazmat",
  "chemical-threats",
  "utility-interruption",
  "infectious-disease",
  "cyberattack",
  "mass-casualty"
)

# The district payload's hazard labels. The same strings as each content
# file's `label`; validate_hazard_labels() asserts they agree.
HAZARD_LABELS <- c(
  flooding               = "Flooding",
  `temperature-extremes` = "Temperature Extremes",
  `air-quality`          = "Air Quality",
  hazmat                 = "Hazmat Release",
  `chemical-threats`     = "Chemical Threats",
  `utility-interruption` = "Utility Interruption",
  `infectious-disease`   = "Infectious Disease Outbreak",
  cyberattack            = "Cyberattack",
  `mass-casualty`        = "Mass Casualty Incident"
)

# Why each pinned hazard is pinned, carried into the payload so the UI can be
# honest rather than implying "least dangerous".
#
# PROVISIONAL. Andrew will rewrite these after the 2026-10-26 refactor. The
# existing strings are kept where their hazard survived; the new hazards get
# a statement that is true of them, not a final one. Air quality in particular
# CAN be compared by neighborhood (NYCCAS), so it does not get "comparison not
# available".
HAZARD_PIN_REASON <- c(
  `air-quality`          = "Not yet compared by neighborhood",
  hazmat                 = "Queens has more of these businesses than other boroughs",
  `chemical-threats`     = "Neighborhood-level comparison not available",
  `utility-interruption` = "Neighborhood-level comparison not available",
  `infectious-disease`   = "Queens neighborhoods score low on the Pandemic Influenza Vulnerability Index",
  cyberattack            = "Neighborhood-level comparison not available",
  `mass-casualty`        = "Neighborhood-level comparison not available"
)

# No ZERO_SCORE_REASON any more. A ranked hazard that scored 0 used to drop
# below the pinned ones (coastal storm, in the five districts with no surge
# tract). No category can score 0 now: Flooding includes the heavy-rain
# quintile and Temperature Extremes is HVI, both 1-5 by construction.
# validate_hazard_measures() asserts the floor rather than keeping a branch
# that cannot run, with a reason string nobody would see until it was wrong.

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
# The population-weighted measure this function used to return (population
# share x population-weighted mean surge index) is gone - nothing reads it now
# that the ranking is the reviewed one.
#
# pop_total / pop_exposed / pop_share_exposed stay: they produce
# surge_pop_pct, which ships in risk_profile and the district page displays.
# Under the reviewed method they read as inconsistent with the ranking - QN07
# is 30.1% exposed and scores 4, QN10 is 23% and scores 5 - because share and
# worst-case are different facts. That is expected, and it is why the district
# band has to say which claim it is making.
coastal_per_cdta <- function(fvi, tract_cdta, tract_pop, index_col = "ss_cur") {
  fvi |>
    inner_join(tract_cdta, by = "geoid") |>
    inner_join(tract_pop, by = "geoid") |>
    mutate(idx = .data[[index_col]]) |>
    group_by(cdta2020) |>
    summarise(
      pop_total = sum(pop, na.rm = TRUE),
      pop_exposed = sum(pop[!is.na(idx)], na.rm = TRUE),
      # An NA index means the tract is NOT exposed, so it is dropped rather
      # than scored 0. A district whose every tract is NA yields 0 here, and a
      # district with no row at all is coalesced to 0 in
      # build_hazard_measures() - both routes reproduce the report's
      # replace_na(max_ss_cur_fvi, 0).
      coastal_max_fvi = if (any(!is.na(idx))) max(idx[!is.na(idx)]) else 0,
      .groups = "drop"
    ) |>
    mutate(pop_share_exposed = ifelse(pop_total > 0, pop_exposed / pop_total, 0))
}

# --- the ranking model ------------------------------------------------------

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

  out <- crosswalk |>
    select(cdta2020, borocd) |>
    left_join(hvi, by = "borocd") |>
    left_join(pivi, by = "borocd") |>
    left_join(chem, by = "borocd") |>
    left_join(rename(rain, rain_pct = pct_area), by = "cdta2020") |>
    left_join(
      select(coastal, cdta2020, coastal_max_fvi,
             coastal_pop_share = pop_share_exposed),
      by = "cdta2020"
    ) |>
    # A district with no exposed tracts is absent from the coastal aggregation
    # rather than present with a zero. Make the zero explicit, or it becomes NA
    # and the hazard silently drops out of that district's ordering.
    mutate(
      coastal_max_fvi = coalesce(coastal_max_fvi, 0),
      coastal_pop_share = coalesce(coastal_pop_share, 0),
      rain_pct = coalesce(rain_pct, 0)
    ) |>
    mutate(
      # Reported percentiles, not ranking inputs - they ship inside the stat
      # objects in risk_profile so a reader can place a district citywide.
      hvi_pct = midrank_pct(hvi),
      chem_pct = midrank_pct(chem_business_count)
    ) |>
    # The reviewed scores, all on the published 1-5 footing, which is what
    # lets them be compared without severity weights.
    #
    # Note what is NOT here: hazmat. The review pins it because
    # Queens has atypically many chemically intensive businesses, so the
    # measure ranked it 1st or 2nd in 11 of 14 districts and separated them
    # poorly. chem_business_count stays in the payload as district context and
    # still feeds the chem_businesses map layer.
    mutate(
      score_coastal_storm = as.integer(coastal_max_fvi),
      score_heavy_rain    = quintile_citywide(rain_pct),
      # HVI is already published 1-5, so it is the score unchanged - no
      # normalisation, no re-ranking.
      score_extreme_heat  = as.integer(hvi)
    )

  # The ranked categories: each the max of its measured parts
  # (CATEGORY_PARTS). Driven by the map rather than written out, so adding a
  # measured part to a category changes its score without a second edit.
  for (cat in names(CATEGORY_PARTS)) {
    parts <- out[unname(PART_SCORE_COL[CATEGORY_PARTS[[cat]]])]
    out[[HAZARD_SCORE_COL[[cat]]]] <- as.integer(do.call(pmax, unname(as.list(parts))))
  }
  out
}

REVIEWED_SCORE_COLS <- c("score_coastal_storm", "score_heavy_rain",
                         "score_extreme_heat")

validate_hazard_measures <- function(measures) {
  assert_row_count(measures, 59, 59)
  assert_unique(measures, "cdta2020")
  assert_no_na(measures, c("hvi", "pivi", "chem_business_count",
                           "rain_pct", "coastal_max_fvi", "coastal_pop_share",
                           REVIEWED_SCORE_COLS, unname(HAZARD_SCORE_COL)))

  # Every ranked hazard must have a score column, and every score column must
  # belong to a ranked hazard. This is the guard against the failure the
  # reviewed report itself hit: a hazard missing from the tie-break vector
  # sorts by NA rather than by priority, and the table still renders.
  if (!setequal(names(HAZARD_SCORE_COL), HAZARD_PRIORITY) ||
      !setequal(names(CATEGORY_PARTS), HAZARD_PRIORITY)) {
    stop("HAZARD_SCORE_COL, CATEGORY_PARTS and HAZARD_PRIORITY disagree on ",
         "which hazards are ranked")
  }
  # Every part a category scores on is a REVIEWED measure, so nothing ranks on
  # an unasserted number.
  if (!setequal(unname(PART_SCORE_COL), REVIEWED_SCORE_COLS) ||
      !all(unlist(CATEGORY_PARTS) %in% names(PART_SCORE_COL))) {
    stop("CATEGORY_PARTS / PART_SCORE_COL name a measure the reviewed score ",
         "set does not cover, so a hazard would rank on an unasserted measure")
  }
  # The category score is the max of its parts, recomputed here rather than
  # trusted: a later edit to build_hazard_measures() that averaged instead
  # would otherwise ship a plausible 1-5 nobody approved.
  for (cat in names(CATEGORY_PARTS)) {
    parts <- measures[unname(PART_SCORE_COL[CATEGORY_PARTS[[cat]]])]
    expect <- do.call(pmax, unname(as.list(parts)))
    if (!identical(as.integer(measures[[HAZARD_SCORE_COL[[cat]]]]), as.integer(expect))) {
      stop("Category score '", HAZARD_SCORE_COL[[cat]], "' is not the max of ",
           paste(CATEGORY_PARTS[[cat]], collapse = " and "))
    }
    # The floor build_hazards() relies on: no category can score 0, so every
    # ranked category is ranked in every district. See the note where
    # ZERO_SCORE_REASON used to be.
    if (any(measures[[HAZARD_SCORE_COL[[cat]]]] < 1L)) {
      stop("Category '", cat, "' scores 0 somewhere. build_hazards() no longer ",
           "places zero-scoring hazards; that branch needs restoring first.")
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
  # - that is the criterion that decides ranked against pinned. If one goes
  # flat, it belongs in the pinned set instead. Checked on the reviewed parts
  # AND on the categories: a max can flatten where its parts do not (Flooding
  # takes 4 values across Queens; its parts take 6 and 5).
  queens <- measures |> filter(substr(cdta2020, 1, 2) == "QN")
  for (s in c(REVIEWED_SCORE_COLS, unname(HAZARD_SCORE_COL))) {
    if (dplyr::n_distinct(queens[[s]]) < 3) {
      stop("Ranked hazard measure '", s, "' takes fewer than 3 distinct values ",
           "across Queens - it no longer meets the ranking criterion ",
           "(METHODOLOGY.md)")
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

# Assert the ORDER the reviewed scores produce, not just the scores.
#
# validate_hazard_ranking() locks the inputs; this locks the output. They are
# separate targets because they fail for different reasons: a score drift means
# a measure changed, an order drift with correct scores means the tie-break or
# the ranked/pinned split changed. Conflating them would make the message
# useless in either case.
#
# The expected order is DERIVED from the fixture here rather than stored beside
# it, so the two cannot disagree - the same reason the fixture holds scores
# only.
validate_hazard_order <- function(hazards, reviewed) {
  # The reviewed part scores, keyed by part id. Categories are then rebuilt
  # from them with CATEGORY_PARTS, independently of build_hazard_measures(),
  # so the order asserted here is "what the reviewed scores imply under the
  # category rule" - not the pipeline checking itself.
  parts <- reviewed |>
    transmute(
      cdta2020,
      `coastal-storm` = coastal_max_fvi,
      `heavy-rain`    = heavy_rain_quintile,
      `extreme-heat`  = hvi
    )
  categories <- tibble::tibble(cdta2020 = parts$cdta2020)
  for (cat in names(CATEGORY_PARTS)) {
    categories[[cat]] <- do.call(pmax, unname(as.list(parts[CATEGORY_PARTS[[cat]]])))
  }

  expected <- categories |>
    tidyr::pivot_longer(-cdta2020, names_to = "slug", values_to = "score") |>
    group_by(cdta2020) |>
    arrange(desc(score), match(slug, HAZARD_PRIORITY), .by_group = TRUE) |>
    summarise(expected = paste(slug, collapse = " > "), .groups = "drop")

  actual <- hazards |>
    filter(ranked, substr(cdta2020, 1, 2) == "QN") |>
    group_by(cdta2020) |>
    arrange(rank, .by_group = TRUE) |>
    summarise(actual = paste(slug, collapse = " > "), .groups = "drop")

  cmp <- inner_join(expected, actual, by = "cdta2020")
  if (nrow(cmp) != nrow(expected)) {
    stop("Hazard order check covers ", nrow(cmp), " of ", nrow(expected),
         " reviewed districts")
  }

  bad <- cmp[cmp$expected != cmp$actual, ]
  if (nrow(bad) > 0) {
    stop("Hazard order disagrees with the reviewed ranking in ", nrow(bad),
         " district(s):\n  ",
         paste0(bad$cdta2020, ": got '", bad$actual, "', reviewed '",
                bad$expected, "'", collapse = "\n  "))
  }
  TRUE
}

# Build the ordered hazard list for every district.
#
# `measures` is one row per CDTA carrying the category score columns
# (HAZARD_SCORE_COL). The ranked categories come first, ordered by score
# descending with HAZARD_PRIORITY breaking ties; then the pinned hazards in
# HAZARD_PINNED order. Every district ranks both categories.
#
# The zero-score branch is gone (2026-10-26). From 2026-10-14 a ranked hazard
# scoring 0 - coastal storm, in five districts - was unranked and placed
# below the pinned ones. Coastal storm is now a part of Flooding, whose score
# cannot be 0 (validate_hazard_measures asserts it), so the branch could not
# run.
build_hazards <- function(measures) {
  ranked <- measures |>
    select(cdta2020, all_of(unname(HAZARD_SCORE_COL))) |>
    tidyr::pivot_longer(-cdta2020, names_to = "score_col", values_to = "score") |>
    mutate(slug = names(HAZARD_SCORE_COL)[match(score_col, HAZARD_SCORE_COL)]) |>
    select(-score_col) |>
    group_by(cdta2020) |>
    # Score descending, then geographic specificity. HAZARD_PRIORITY covers
    # every ranked hazard (asserted in validate_hazard_measures), so match()
    # never returns NA here and the ordering is total and deterministic.
    arrange(desc(score), match(slug, HAZARD_PRIORITY), .by_group = TRUE) |>
    mutate(ranked = TRUE, rank = row_number()) |>
    ungroup()

  pinned <- tidyr::expand_grid(
    cdta2020 = unique(measures$cdta2020),
    slug = HAZARD_PINNED
  ) |>
    mutate(
      score = NA_integer_,
      rank = length(HAZARD_PRIORITY) + match(slug, HAZARD_PINNED),
      ranked = FALSE
    )

  bind_rows(ranked, pinned) |>
    mutate(
      label = unname(HAZARD_LABELS[slug]),
      pin_reason = if_else(ranked, NA_character_, unname(HAZARD_PIN_REASON[slug]))
    ) |>
    arrange(cdta2020, rank)
}

# The model's labels and the content files' labels are two copies of the same
# string - the district row and the hazard page title. Asserted equal so a
# rename in one cannot leave the row and the page disagreeing.
validate_hazard_labels <- function(content) {
  content_labels <- vapply(content, function(y) y$label, character(1))
  model <- HAZARD_LABELS[names(content_labels)]
  bad <- names(content_labels)[is.na(model) | model != content_labels]
  if (length(bad) > 0) {
    stop("Hazard label disagrees between R/hazards.R and content/hazards: ",
         paste0(bad, " ('", model[bad], "' vs '", content_labels[bad], "')",
                collapse = ", "))
  }
  TRUE
}

# Every measured part the model scores must be a part the content file
# authors, under the same id, in the category the model files it under. A
# part renamed in the YAML would otherwise leave the payload's `part_scores`
# naming an anchor that no longer exists on the page.
validate_hazard_parts <- function(content) {
  for (cat in names(CATEGORY_PARTS)) {
    authored <- vapply(content[[cat]]$parts %||% list(), function(p) p$id, character(1))
    missing <- setdiff(CATEGORY_PARTS[[cat]], authored)
    if (length(missing) > 0) {
      stop("R/hazards.R scores ", cat, " on part(s) ",
           paste(missing, collapse = ", "), " that content/hazards/", cat,
           ".yml does not author")
    }
  }
  TRUE
}
