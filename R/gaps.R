# R/gaps.R
#
# The resource-gap registry: config, documentation and acquisition backlog in
# one committed CSV.
#
# The 33 candidate indicators collapse to five primitives, because the
# "in high-HVI areas" / "in the flood zone" qualifiers are a `subpopulation`
# argument rather than a new computation. Gap 1 and gap 3 are the same call
# with a filter. Unblocking a dataset is a status flip, not new plumbing.
#
# All 33 keep a row, including the eight retired ones, so gap_id stays a stable
# reference back to the source inventory and the reasoning survives.

GAP_PRIMITIVES <- c("access_threshold", "access_mean", "supply_ratio",
                    "exposure_overlay", "composite")
GAP_STATUSES <- c("available", "blocked_on_data", "deferred", "retired")
GAP_POLARITY <- c("higher_is_worse", "higher_is_better")

# A registry-only pseudo-hazard. It has no page in the hazard catalog, so a
# cross-cutting gap can only ever reach a district through fall-through.
GAP_PSEUDO_HAZARDS <- "cross-cutting"

# Cooling TOWERS are not cooling CENTERS. The towers dataset (y4fw-iqfr) is
# building HVAC equipment tracked for Legionella risk. Wiring one into a heat
# gap would produce a plausible-looking, confidently wrong number on the hazard
# that leads 11 of the 14 district pages.
FORBIDDEN_FACILITY_SETS <- c("cooling_tower", "y4fw-iqfr")

read_gap_registry <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    gap_id = readr::col_integer(),
    priority = readr::col_integer(),
    threshold_min = readr::col_double(),
    .default = readr::col_character()
  ))
}

validate_gap_registry <- function(reg, ranked_slugs, pinned_slugs) {
  required <- c("gap_id", "hazard_slug", "priority", "label", "primitive",
                "unit", "polarity", "status")
  missing <- setdiff(required, names(reg))
  if (length(missing) > 0) {
    stop("resource_gaps.csv: missing column(s) ", paste(missing, collapse = ", "))
  }
  assert_no_na(reg, required)
  assert_row_count(reg, 33, 33)
  assert_unique(reg, "gap_id")
  if (!identical(sort(reg$gap_id), 1:33)) {
    stop("resource_gaps.csv: gap_id must be exactly 1..33 - retired gaps keep ",
         "their row so the id stays a stable reference")
  }

  for (col in c("primitive", "status", "polarity")) {
    allowed <- switch(col, primitive = GAP_PRIMITIVES,
                      status = GAP_STATUSES, polarity = GAP_POLARITY)
    bad <- setdiff(reg[[col]], allowed)
    if (length(bad) > 0) {
      stop("resource_gaps.csv: unknown ", col, " value(s) ",
           paste(bad, collapse = ", "))
    }
  }

  live <- reg |> filter(status != "retired")

  # Selection walks the district's hazard ranking and picks by priority. A tie
  # inside a hazard would make the choice depend on row order, so the displayed
  # gap could change between rebuilds with no data change.
  dupes <- live |> count(hazard_slug, priority) |> filter(n > 1)
  if (nrow(dupes) > 0) {
    stop("resource_gaps.csv: (hazard_slug, priority) is not unique for ",
         paste(unique(dupes$hazard_slug), collapse = ", "),
         " - gap selection would not be deterministic")
  }

  known <- c(ranked_slugs, pinned_slugs, GAP_PSEUDO_HAZARDS)
  orphan <- live |> filter(!hazard_slug %in% known)
  if (nrow(orphan) > 0) {
    stop("resource_gaps.csv: live gap(s) ", paste(orphan$gap_id, collapse = ", "),
         " reference hazard_slug '",
         paste(unique(orphan$hazard_slug), collapse = ", "),
         "' which is not a hazard. Retire the gap or add the hazard.")
  }

  # A gap attached to a pinned hazard can never be displayed: pinned hazards
  # never enter the top three, and fall-through stops at the last ranked
  # hazard. Carrying one as live is a promise the pipeline cannot keep.
  unreachable <- live |> filter(hazard_slug %in% pinned_slugs)
  if (nrow(unreachable) > 0) {
    stop("resource_gaps.csv: gap(s) ",
         paste(unreachable$gap_id, collapse = ", "),
         " are attached to pinned hazard(s) ",
         paste(unique(unreachable$hazard_slug), collapse = ", "),
         " and can never be selected. Re-attach them to a ranked hazard or ",
         "retire them.")
  }

  # THE FEASIBILITY CHECK.
  #
  # The 02 screen promises up to three gap sentences, chosen by walking the
  # district's hazard ranking. If a ranked hazard has no available gap, every
  # district that leads with it falls straight through - and if several do, the
  # feature silently degrades to one or two sentences everywhere.
  #
  # This is the check that matters: the first draft of this registry had three
  # available gaps across two hazards, and extreme heat - which leads 11 of the
  # 14 districts - had none at all.
  by_hazard <- vapply(ranked_slugs, function(h) {
    sum(live$hazard_slug == h & live$status == "available")
  }, integer(1))
  barren <- names(by_hazard)[by_hazard == 0]
  if (length(barren) > 0) {
    stop("resource_gaps.csv: ranked hazard(s) ",
         paste(barren, collapse = ", "),
         " have no gap with status 'available'. Every district leading with ",
         "one of those will fall through, so the 02 screen cannot show three ",
         "sentences. Unblock a gap or accept fewer sentences explicitly.")
  }

  no_reason <- live |>
    filter(status %in% c("blocked_on_data", "deferred"),
           is.na(blocked_on) | !nzchar(blocked_on))
  if (nrow(no_reason) > 0) {
    stop("resource_gaps.csv: gap(s) ", paste(no_reason$gap_id, collapse = ", "),
         " are blocked or deferred with no blocked_on - the registry stops ",
         "working as an acquisition backlog")
  }

  retired_no_reason <- reg |>
    filter(status == "retired", is.na(blocked_on) | !nzchar(blocked_on))
  if (nrow(retired_no_reason) > 0) {
    stop("resource_gaps.csv: retired gap(s) ",
         paste(retired_no_reason$gap_id, collapse = ", "), " say nothing about why")
  }

  no_template <- live |>
    filter(status == "available",
           is.na(sentence_template) | !nzchar(sentence_template))
  if (nrow(no_template) > 0) {
    stop("resource_gaps.csv: available gap(s) ",
         paste(no_template$gap_id, collapse = ", "),
         " have no sentence_template but will be rendered as a sentence")
  }

  # Threshold-based primitives need a pinned threshold. The source inventory
  # left several ambiguous ("10/15 minutes", "X minutes"); they are
  # display-facing numbers and must not be decided incidentally in code.
  no_threshold <- live |>
    filter(primitive == "access_threshold", is.na(threshold_min))
  if (nrow(no_threshold) > 0) {
    stop("resource_gaps.csv: access_threshold gap(s) ",
         paste(no_threshold$gap_id, collapse = ", "), " have no threshold_min")
  }

  towers <- live |>
    filter(!is.na(facility_set),
           grepl(paste(FORBIDDEN_FACILITY_SETS, collapse = "|"),
                 facility_set, ignore.case = TRUE))
  if (nrow(towers) > 0) {
    stop("resource_gaps.csv: gap(s) ", paste(towers$gap_id, collapse = ", "),
         " resolve facility_set to the cooling TOWER registry. Cooling towers ",
         "are HVAC equipment, not places people shelter.")
  }

  TRUE
}

# A compact view of what the registry can actually deliver, for the build log.
gap_registry_summary <- function(reg, ranked_slugs) {
  reg |>
    filter(status != "retired") |>
    group_by(hazard_slug) |>
    summarise(
      live = dplyr::n(),
      available = sum(status == "available"),
      blocked = sum(status == "blocked_on_data"),
      deferred = sum(status == "deferred"),
      .groups = "drop"
    ) |>
    arrange(desc(available), hazard_slug)
}

# --- facility and hazard layers ---------------------------------------------

COOL_OPTIONS_URL <- paste0(
  "https://services6.arcgis.com/yG5s3afENB5iO9fj/arcgis/rest/services/",
  "Cool_Options/FeatureServer/0/query")
EVAC_ZONES_ID   <- "epne-qv9x"
EVAC_CENTERS_ID <- "p5md-weyf"
SOCRATA <- "https://data.cityofnewyork.us/resource/"

# NYC OEM Cool Options.
#
# Cooling CENTERS only open during a declared heat emergency, so "distance to a
# cooling center" is not a standing condition anyone can measure. Cool Options
# is the year-round list, and Space_type separates indoor rooms from spray
# showers and pools. The heat gaps use INDOOR ONLY: a spray shower is not the
# relief an older adult needs during a heat wave.
#
# Finder_status is deliberately ignored. It is live open/closed state, and
# baking a seasonal snapshot into a standing indicator would make the number
# wrong for most of the year.
get_cool_options <- function(url = COOL_OPTIONS_URL, indoor_only = TRUE) {
  parsed <- httr::parse_url(url)
  parsed$query <- list(
    where = if (indoor_only) "Space_type='Cooling Center'" else "1=1",
    outFields = "Facility_name,Location_type,Space_type,Borough_name,Accessible",
    outSR = 4326, f = "geojson"
  )
  x <- read_sf(httr::build_url(parsed))
  if (nrow(x) == 0) stop("Cool Options returned no features")
  x
}

get_socrata_geo <- function(id, select = NULL, where = NULL) {
  q <- list(`$limit` = 50000)
  if (!is.null(select)) q$`$select` <- select
  if (!is.null(where)) q$`$where` <- where
  parsed <- httr::parse_url(paste0(SOCRATA, id, ".geojson"))
  parsed$query <- q
  read_sf(httr::build_url(parsed))
}

# Hurricane evacuation zones. Zone X is "not in any zone" and must be dropped,
# or 150 square miles of the city reads as evacuation-zone area.
get_evac_zones <- function(id = EVAC_ZONES_ID) {
  x <- get_socrata_geo(id) |> st_make_valid()
  zone_col <- intersect(c("hurricane_", "hurricane_evacuation_zone"), names(x))[1]
  x$zone <- x[[zone_col]]
  out <- x |> filter(zone %in% as.character(1:6))
  if (nrow(out) < 6) stop("Evacuation zones: expected zones 1-6, got ", nrow(out))
  out
}

# Hurricane evacuation centers.
#
# NOT ayer-cga7. That id, cited in the research script and in section 8f as the
# place to check for capacity, is a map visualisation asset with ZERO columns -
# 60 rows of empty objects. p5md-weyf is the actual dataset. It has no capacity
# field either, so gaps 15 and 19 stay blocked.
get_evac_centers <- function(id = EVAC_CENTERS_ID) {
  x <- get_socrata_geo(id)
  if (nrow(x) < 50) stop("Evacuation centers: expected ~60, got ", nrow(x))
  x
}

# Solid waste and wastewater facilities, from FacDB.
#
# These are deliberately EXCLUDED from the resource crosswalk - a wastewater
# plant is not somewhere a resident seeks help - but they are hazard sources,
# so they are fetched separately here.
get_hazard_facilities <- function(facgroup, boro = "QUEENS") {
  parsed <- httr::parse_url(FACDB_URL)
  parsed$query <- list(
    `$where` = sprintf("boro='%s' AND facgroup='%s'", boro, facgroup),
    `$select` = "uid,facname,facgroup,facsubgrp,latitude,longitude",
    `$limit` = 5000
  )
  x <- jsonlite::fromJSON(httr::build_url(parsed)) |> tibble::as_tibble()
  x |>
    mutate(lon = na_if_zero(as.numeric(longitude)),
           lat = na_if_zero(as.numeric(latitude))) |>
    filter(!is.na(lon), !is.na(lat)) |>
    st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE)
}

# --- language coverage ------------------------------------------------------

read_language_crosswalk <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    is_covered = readr::col_logical(),
    is_aggregate = readr::col_logical(),
    .default = readr::col_character()
  ))
}

validate_language_crosswalk <- function(lx, lep) {
  assert_no_na(lx, c("lep_language", "is_covered", "is_aggregate"))
  assert_unique(lx, "lep_language")

  # Every language in the workbook must be classified, or a new one silently
  # counts as "not covered by Notify NYC" without anyone deciding that.
  observed <- setdiff(unique(lep$language), "Total")
  missing <- setdiff(observed, lx$lep_language)
  if (length(missing) > 0) {
    stop("languages.csv: unclassified language(s) in the LEP workbook: ",
         paste(missing, collapse = ", "))
  }

  # Notify NYC publishes in 13 languages; 12 appear in the workbook (English is
  # the base language and is not an LEP category).
  n_cov <- sum(lx$is_covered)
  if (n_cov != 12) {
    stop("languages.csv: expected 12 covered languages, got ", n_cov,
         " - has Notify NYC's language list changed?")
  }
  if (any(lx$is_covered & lx$is_aggregate)) {
    stop("languages.csv: a language cannot be both covered and an aggregate bucket")
  }
  TRUE
}
