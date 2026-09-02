# R/access.R
#
# The DAG side of the r5r access measures. It READS walk times; it never routes.
#
# scripts/04_access_measures.R runs locally with r5r, a JVM and a 100 MB OSM
# extract, and publishes two files in the data-v* release:
#
#   access_stats.csv    geoid x facility_set -> minutes_to_nearest, within_*
#   block_weights.csv   geoid -> pop, lon, lat
#
# Keeping the routing out of the DAG is the whole point of section 8b. This
# file is what makes the separation pay: sf and dplyr only, no Java.

# --- reading ------------------------------------------------------------------

# geoid is a 15-digit identifier and MUST be read as character. A default read
# parses it as a double - at 15 significant digits that is the edge of double
# precision, and it broke a join during development by silently becoming
# numeric on one side only.
read_access_stats <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    geoid = readr::col_character(),
    facility_set = readr::col_character(),
    minutes_to_nearest = readr::col_double(),
    .default = readr::col_logical()
  ))
}

read_block_weights <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    geoid = readr::col_character(),
    pop = readr::col_double(),
    lon = readr::col_double(),
    lat = readr::col_double()
  ))
}

# --- blocks to districts ------------------------------------------------------

COUNTY_BORO <- c("005" = "BX", "047" = "BK", "061" = "MN",
                 "081" = "QN", "085" = "SI")

# Assign every block to a CDTA, CONSTRAINED TO ITS OWN BOROUGH.
#
# An unconstrained point-in-polygon put 2,408,943 residents in Queens against a
# published county total of 2,405,464 - 3,479 too many. CDTA polygons follow
# the shoreline out into open water, so a block across the county line can have
# its interior point fall inside a Queens polygon. Unconstrained, every Queens
# per-capita figure carries other boroughs' residents.
#
# The constraint is free: the block GEOID already holds the county FIPS in
# positions 3-5, and the CDTA code holds the borough.
#
# Two further notes, both learned on the tract version of this join:
#
#   - CDTAType = 0 excludes the 12 Joint Interest Areas, which leaves HOLES -
#     Central Park, Flushing Meadows, JFK, Jamaica Bay. A block whose interior
#     point lands in one matches nothing. On tracts that silently dropped
#     296,865 residents. Here it is 64 blocks and 2,760 residents, because
#     blocks are small - but they are recovered rather than dropped, by falling
#     back to the nearest CDTA within the same borough.
#   - The interior point comes from TIGER's INTPTLAT20/INTPTLON20, which is
#     guaranteed to fall inside the block. A centroid is not, for the same
#     reason point_on_surface beat centroid for the district markers.
blocks_to_cdta <- function(weights, cdta_boundaries) {
  bw <- weights |>
    mutate(county = substr(geoid, 3, 5),
           boro = unname(COUNTY_BORO[county]))

  if (anyNA(bw$boro)) {
    stop("block_weights.csv holds county FIPS outside the five boroughs: ",
         paste(unique(bw$county[is.na(bw$boro)]), collapse = ", "))
  }

  poly <- cdta_boundaries |>
    sf::st_transform(4326) |>
    dplyr::transmute(cdta2020 = CDTA2020, boro = substr(CDTA2020, 1, 2))

  out <- lapply(unique(bw$boro), function(bo) {
    pts <- bw |> filter(boro == bo) |>
      sf::st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE)
    pg <- poly |> filter(boro == bo)

    j <- sf::st_join(pts, pg["cdta2020"], join = sf::st_within)
    miss <- is.na(j$cdta2020)
    if (any(miss)) {
      j$cdta2020[miss] <- pg$cdta2020[sf::st_nearest_feature(j[miss, ], pg)]
    }
    j$fallback <- miss
    sf::st_drop_geometry(j)
  }) |> bind_rows()

  out |> select(geoid, cdta2020, pop, fallback)
}

# Borough population must reconcile to the published 2020 count exactly. This
# is a decennial complete count, not an estimate, so "close" is a defect.
validate_block_cdta <- function(bc) {
  published <- c(BX = 1472654, BK = 2736074, MN = 1694251,
                 QN = 2405464, SI = 495747)

  if (anyNA(bc$cdta2020)) {
    stop("blocks_to_cdta: ", sum(is.na(bc$cdta2020)), " blocks unassigned")
  }

  got <- bc |>
    mutate(boro = substr(cdta2020, 1, 2)) |>
    group_by(boro) |>
    summarise(pop = sum(pop), .groups = "drop")

  bad <- got |>
    mutate(want = unname(published[boro]), diff = pop - want) |>
    filter(diff != 0)

  if (nrow(bad) > 0) {
    stop("blocks_to_cdta: borough population does not reconcile to the 2020 ",
         "census - ",
         paste(sprintf("%s off by %+d", bad$boro, bad$diff), collapse = ", "),
         ". A block is being assigned across a county line, which inflates ",
         "every per-capita figure in the receiving borough.")
  }
  TRUE
}

# --- the two primitives -------------------------------------------------------
#
# WORKED EXAMPLE: `all_residents` only.
#
# The registry names four subpopulations - all_residents, hvi_4_or_5,
# stormwater_flood_area and hurricane_evac_zone_1_2. The last three are spatial
# filters over blocks and are a separate increment; this pair implements the
# shape, against the three gaps that need no filter (1, 13, 21).
#
# subpopulation_blocks() is the seam they extend through: add a case, and both
# primitives gain the subpopulation without further change.

subpopulation_blocks <- function(bc, subpopulation, inputs = list()) {
  switch(subpopulation,
    all_residents = bc,
    stop("subpopulation '", subpopulation, "' is not implemented. ",
         "Implemented: all_residents. See R/access.R."))
}

# Share of the subpopulation BEYOND the threshold - a deficit, not a supply.
# The registry's polarity says higher_is_worse for every gap using this, and
# that is only true because the value is the share who CANNOT reach one.
#
# A block with no facility within r5r's search cap has minutes_to_nearest NA
# and every within_* FALSE. Counting NA as "beyond" is correct and load-bearing:
# those are the worst-served blocks, and dropping them would understate exactly
# the deficit the gap exists to report.
access_threshold <- function(access, bc, facility_set, threshold_min,
                             subpopulation = "all_residents", inputs = list()) {
  col <- paste0("within_", as.integer(threshold_min))
  if (!col %in% names(access)) {
    stop("no `", col, "` column in access_stats.csv - thresholds available: ",
         paste(grep("^within_", names(access), value = TRUE), collapse = ", "))
  }

  sub <- subpopulation_blocks(bc, subpopulation, inputs)
  a <- access |> filter(facility_set == !!facility_set)

  sub |>
    inner_join(a |> select(geoid, reachable = all_of(col)), by = "geoid") |>
    group_by(cdta2020) |>
    summarise(
      denom = sum(pop),
      beyond = sum(pop[!reachable | is.na(reachable)]),
      .groups = "drop"
    ) |>
    transmute(cdta2020,
              value = ifelse(denom > 0, 100 * beyond / denom, NA_real_),
              facts_pct = round(ifelse(denom > 0, 100 * beyond / denom, NA_real_), 1),
              facts_people = round(beyond),
              facts_minutes = as.integer(threshold_min))
}

# The routing cap in scripts/04_access_measures.R. A value AT the cap is
# censored - it means "not found within 180 minutes", not "exactly 180 minutes"
# - and must never be averaged as though it were a measurement.
ACCESS_CAP_MINUTES <- 180

# A mean over a fragment of a district is not that district's mean. Below this
# share of the population reachable, the gap reports nothing rather than a
# number that looks like an answer.
ACCESS_MEAN_MIN_COVERAGE <- 0.5

# Population-weighted mean walk minutes.
#
# TWO GUARDS, both of which fired on real data the first time this ran.
#
# The Rockaways has 695 populated blocks. 694 have NO evacuation centre
# reachable within three hours, and the single block that does sits at exactly
# 180 minutes - the cap. Without these guards the gap reported "The average
# walk to a hurricane evacuation center in The Rockaways is 180 minutes", led
# QN14's section F with it, and every part of that sentence was wrong: it was
# not an average (n = 1 of 695), and 180 was the censoring boundary rather than
# a measurement.
#
#   1. CENSORING. Values at or above the cap are folded into "unreachable".
#      r5r returns the cap as a boundary, so a capped value is indistinguishable
#      from not-found and cannot be treated as a point estimate.
#   2. COVERAGE FLOOR. If less than half the population can reach the facility
#      at all, there is no district mean to report. The value is NA, the gap
#      becomes unavailable for that district, and selection falls through -
#      which is section 8d working as designed.
#
# What is lost is a real and striking finding, and it should not vanish with
# the number: no hurricane evacuation centre is reachable on foot from the
# Rockaways at all. That belongs in hazard-page copy, alongside the fact that
# Queens holds 15 of the city's 60 centres and none are on the peninsula.
access_mean <- function(access, bc, facility_set,
                        subpopulation = "all_residents", inputs = list()) {
  sub <- subpopulation_blocks(bc, subpopulation, inputs)
  a <- access |> filter(facility_set == !!facility_set)

  sub |>
    inner_join(a |> select(geoid, minutes_to_nearest), by = "geoid") |>
    mutate(reached = !is.na(minutes_to_nearest) &
                     minutes_to_nearest < ACCESS_CAP_MINUTES) |>
    group_by(cdta2020) |>
    summarise(
      pop_total = sum(pop),
      pop_known = sum(pop[reached]),
      wmean = if (sum(pop[reached]) > 0) {
        stats::weighted.mean(minutes_to_nearest[reached], pop[reached])
      } else NA_real_,
      .groups = "drop"
    ) |>
    mutate(
      coverage = pop_known / pop_total,
      wmean = ifelse(coverage >= ACCESS_MEAN_MIN_COVERAGE, wmean, NA_real_)
    ) |>
    transmute(cdta2020,
              value = wmean,
              facts_minutes = round(wmean),
              facts_unreachable_pct = round(100 * (1 - coverage), 1),
              # A primitive that cannot answer for a district must SAY SO.
              # Silence is still a failure - validate_gap_values() only accepts
              # a missing value when a reason travels with it.
              facts_unavailable_reason = ifelse(
                is.na(wmean),
                sprintf("no %s reachable on foot by %.0f%% of residents",
                        gsub("_", " ", facility_set), 100 * (1 - coverage)),
                NA_character_))
}
