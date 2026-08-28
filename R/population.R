# R/population.R
#
# Population, age, language and social-cohesion figures - section D of the 02
# screen - plus the census-tract population used to weight the Flood
# Vulnerability Index onto districts.

# --- Community Health Profiles ----------------------------------------------
#
# Tier-2 mirror produced by scripts/02_mirror_tabular.R. Keyed on borocd, with
# six extra rows (ID 0-5) carrying the city and borough baselines. Those are
# kept: the wireframe's "average among citywide Community Districts" framing
# needs a comparison frame, and reference_frame is a field rather than copy.
read_chp <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, name_repair = "unique_quiet")
}

CHP_BASELINE_IDS <- 0:5

chp_districts <- function(chp) chp |> filter(borocd >= 100)
chp_citywide <- function(chp) chp |> filter(borocd == 0)

validate_chp <- function(chp) {
  assert_row_count(chp_districts(chp), 59, 59)
  if (nrow(chp_citywide(chp)) != 1) {
    stop("CHP: expected exactly one citywide row (borocd == 0)")
  }
  required <- c("borocd", "Name", "Overall_Pop", "Age65plus",
                "Ltd_Eng_Prof", "Helpful_Neighbor")
  missing <- setdiff(required, names(chp))
  if (length(missing) > 0) {
    stop("CHP: missing expected column(s): ", paste(missing, collapse = ", "))
  }
  assert_no_na(chp_districts(chp), c("borocd", "Overall_Pop"))
  TRUE
}

# --- DCP LEP languages ------------------------------------------------------
#
# Tier-2 mirror. One row per (PUMA, language); each PUMA's block opens with a
# "Total" row that is the LEP denominator, then ranks 1..10.
#
# cv is the coefficient of variation - DCP greys out unreliable estimates in the
# published workbook, and it is carried through so the frontend can do the same
# rather than presenting a 37% CV figure with the same confidence as a 4% one.
read_lep <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    puma2020 = readr::col_character(),
    language = readr::col_character(),
    estimate = readr::col_double(),
    moe = readr::col_double(),
    cv = readr::col_double(),
    .default = readr::col_character()
  ))
}

validate_lep <- function(lep) {
  if (dplyr::n_distinct(lep$puma2020) != 55) {
    stop("LEP: expected 55 PUMAs, got ", dplyr::n_distinct(lep$puma2020))
  }
  if (!any(lep$language == "Total")) {
    stop("LEP: no Total rows - the per-PUMA denominator is missing")
  }
  TRUE
}

# Top languages for one district, excluding the Total row.
#
# Joined on puma2020. Four citywide PUMAs cover two community districts each
# (all Manhattan/Bronx - Queens is 1:1), so those districts share language
# figures. puma_shared marks them, and the payload carries the flag so the
# frontend can qualify the sentence rather than implying district-specific data.
lep_for_district <- function(lep, puma, n = 5) {
  rows <- lep |> filter(puma2020 == puma, language != "Total")
  if (nrow(rows) == 0) return(list())
  rows |>
    arrange(desc(estimate)) |>
    head(n) |>
    transmute(
      name = language,
      speakers = as.integer(estimate),
      moe = round(moe, 1),
      cv = round(cv, 2)
    ) |>
    purrr::transpose()
}

# --- census tract population ------------------------------------------------
#
# Needed only to population-weight the Flood Vulnerability Index onto districts,
# per PIPELINE_DESIGN.md 2's rule for census-tract sources.
#
# Requires a Census API key. Note that R reads only the FIRST .Renviron it
# finds: this project has its own (Socrata keys), which shadows ~/.Renviron
# entirely, so the key must be read explicitly. `uvr run` does not appear to
# load either automatically, which is why data-research.R also calls
# readRenviron() by hand.
ACS_YEAR <- 2023
NYC_COUNTY_FIPS <- c("005", "047", "061", "081", "085")

census_api_key <- function() {
  key <- Sys.getenv("CENSUS_API_KEY")
  if (!nzchar(key)) {
    readRenviron("~/.Renviron")
    key <- Sys.getenv("CENSUS_API_KEY")
  }
  if (!nzchar(key)) {
    stop("CENSUS_API_KEY not set. Add it to .Renviron, or export it in CI.")
  }
  key
}

get_tract_population <- function(year = ACS_YEAR, counties = NYC_COUNTY_FIPS) {
  key <- census_api_key()
  out <- lapply(counties, function(cty) {
    u <- sprintf(paste0("https://api.census.gov/data/%d/acs/acs5",
                        "?get=B01003_001E&for=tract:*&in=state:36&in=county:%s&key=%s"),
                 year, cty, key)
    raw <- jsonlite::fromJSON(u)
    tibble::as_tibble(raw[-1, , drop = FALSE], .name_repair = "minimal") |>
      setNames(raw[1, ]) |>
      transmute(
        geoid = paste0(state, county, tract),
        pop = as.numeric(B01003_001E)
      )
  }) |> bind_rows()

  # ACS suppresses nothing at this level, but a negative sentinel would poison
  # every weighted mean downstream.
  if (any(out$pop < 0, na.rm = TRUE)) {
    stop("ACS tract population contains negative values")
  }
  assert_unique(out, "geoid")
  out
}

# Assign each census tract to the CDTA it overlaps most.
#
# A point-on-surface join looks like the obvious choice - CDTAs are built up
# from tracts, so tracts ought to nest - but it is WRONG here, and quietly so.
# The CDTA layer is filtered to CDTAType = 0, which excludes the 12 Joint
# Interest Areas, leaving holes in the coverage: Central Park, Flushing
# Meadows, Forest Park, JFK, Jamaica Bay. A tract whose interior point lands in
# one of those holes matches nothing.
#
# Measured: point-on-surface dropped 53 tracts holding 296,865 residents, 41 of
# them Manhattan tracts around Central Park. Largest-overlap recovers all of
# them. A tract straddling a JIA is correctly assigned to the neighbouring
# district, since the JIA itself has no residents.
tract_to_cdta <- function(tracts, cdta) {
  t2 <- st_transform(tracts, 2263)
  c2 <- select(st_transform(cdta, 2263), CDTA2020)

  suppressWarnings(st_join(t2, c2, join = st_intersects, largest = TRUE)) |>
    st_drop_geometry() |>
    transmute(geoid = as.character(geoid), cdta2020 = CDTA2020)
}

# Dropped population is the failure mode this join has, so measure it rather
# than assuming. A tract that matches nothing removes its residents from every
# per-capita and share figure downstream, silently.
validate_tract_cdta <- function(tract_cdta, tract_pop, max_dropped_pop = 5000) {
  unmatched <- tract_cdta |>
    filter(is.na(cdta2020)) |>
    left_join(tract_pop, by = "geoid")

  dropped <- sum(unmatched$pop, na.rm = TRUE)
  if (dropped > max_dropped_pop) {
    stop(paste0(
      nrow(unmatched), " census tract(s) did not match a CDTA, holding ",
      format(dropped, big.mark = ","), " residents - over the ",
      format(max_dropped_pop, big.mark = ","), " tolerance. ",
      "Every per-capita figure downstream is missing these people."
    ))
  }
  TRUE
}
