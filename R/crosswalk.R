# R/crosswalk.R
#
# The geography spine. ~59 rows, hand-verifiable, committed to git as a
# reviewable CSV. Every other artifact joins through it.
#
# Built by scripts/00_build_crosswalk.R, NOT derived at runtime. The DAG reads
# the committed CSV as a format = "file" target and validates it.

CDTA_SERVICE_URL <- paste0(
  "https://services5.arcgis.com/GfwWNkhOj9bNBqoJ/arcgis/rest/services/",
  "NYC_Community_District_Tabulation_Areas_2020/FeatureServer/0/query"
)

# DOHMH's Heat Vulnerability Index, published as a feature service keyed on
# CommDist (a BoroCD). Tier 1 - fetched, not mirrored.
#
# Despite "2024" in the service name this is the 2023 vintage: Year_Description
# is 2023 on every row, and all 59 scores match the NYC EH Data Portal's manual
# CDTA export exactly. The service simply removes the manual export step.
HVI_SERVICE_URL <- paste0(
  "https://services1.arcgis.com/8cuieNI8NbqQZQVJ/ArcGIS/rest/services/",
  "HVI_by_CDTA_CRAD_2024/FeatureServer/0/query"
)

# Borough abbreviations as they appear in CDTA2020 codes and in the DCP LEP
# workbook's "Community District" column.
BORO_ABBREV <- c("MN" = 1L, "BX" = 2L, "BK" = 3L, "QN" = 4L, "SI" = 5L)

# The four PUMAs that legitimately cover two community districts each.
# 2020 PUMAs were redrawn to nest with NYC CDs, but not completely: these four
# remain merged. All are Manhattan/Bronx, so Queens is unaffected.
# Verified against the ACS 2024 5-yr PUMS workbook, 2026-08-27.
PUMA_SHARED_ALLOWLIST <- c("4121", "4165", "4221", "4263")

# Districts served by a COAD. FRANC covers the Rockaways only; every other
# district is coad = NA, which is the common case the 02 screen must handle.
COAD_BY_CDTA <- c("QN14" = "FRANC")

# Fetch all 59 community-district CDTAs, citywide.
#
# CDTAType = 0 excludes the 12 Joint Interest Areas (parks and airports:
# QN80 LaGuardia, QN83 JFK, MN64 Central Park, ...). Note that CDTAType comes
# back as a STRING, so the server-side filter is written unquoted for ArcGIS
# but any client-side comparison must use "0", not 0.
#
# Citywide, not Queens-only: PIPELINE_DESIGN.md's standing decision is
# "compute citywide, display Queens" - percentiles and composites need all 59.
get_cdta <- function(url = CDTA_SERVICE_URL) {
  parsed <- httr::parse_url(url)
  parsed$query <- list(
    where = "CDTAType = 0",
    outFields = "*",
    outSR = 4326,
    f = "geojson"
  )
  read_sf(httr::build_url(parsed)) |> st_make_valid()
}

# Read the CDTA feature service response into the crosswalk's core columns.
#
# The CD number is parsed out of CDTAName, which encodes the CD relationship as
# free text - "QN01 Astoria-Queensbridge (CD 1 Equivalent)" vs "(CD 2
# Approximation)". There is no separate column for it. All 59 rows match one of
# those two forms; assert_matches() in validate_cdta_crosswalk() enforces that.
CDTA_NAME_PATTERN <- "\\(CD ([0-9]+) (Equivalent|Approximation)\\)$"

cdta_core <- function(cdta) {
  cdta |>
    st_drop_geometry() |>
    transmute(
      cdta2020 = CDTA2020,
      cdta_name = CDTAName,
      boro_code = as.integer(BoroCode),
      boro_name = BoroName,
      county_fips = CountyFIPS,
      cd_num = as.integer(sub(paste0(".*", CDTA_NAME_PATTERN), "\\1", CDTAName)),
      # BoroCD, the Community Health Profiles join key: borough code + 2-digit CD
      borocd = boro_code * 100L + cd_num,
      # The NYC EH Data Portal keys its HVI export on a DOHMH GeoID, NOT on the
      # CDTA2020 string. The scheme is county FIPS with leading zeros stripped,
      # times 100, plus the CD number: QN01 -> 81*100+1 = 8101, SI03 -> 8503.
      # PIPELINE_DESIGN.md 2 called this join "identity"; it is not.
      hvi_geoid = as.integer(county_fips) * 100L + cd_num,
      cd_label = paste("Community District", cd_num),
      # "QN01 Astoria-Queensbridge (CD 1 Equivalent)" -> "Astoria-Queensbridge".
      # Derived from CDTAName rather than taken from an external source: the HVI
      # feature service spells the same district "Long Island City and Astoria
      # (CD1)", a different naming scheme entirely, so it cannot supply this.
      display_name = sub(
        paste0(" ", CDTA_NAME_PATTERN), "",
        sub("^[A-Z]{2}[0-9]{2} ", "", CDTAName)
      ),
      # The URL segment. Stored, not derived at runtime, so it can never drift
      # from what has been linked. Queens ships as q01..q14 per the wireframes;
      # other boroughs get the lowercased CDTA code as a stable placeholder.
      slug = ifelse(
        boro_code == 4L,
        sprintf("q%02d", cd_num),
        tolower(cdta2020)
      ),
      coad = unname(COAD_BY_CDTA[cdta2020])
    ) |>
    arrange(cdta2020)
}

# Read the DCP LEP workbook's PUMA <-> community district mapping.
#
# Two traps. The sheet has a two-row split header on rows 5-6, so the header
# must be supplied rather than inferred (skip = 6 mangles it). And the geography
# is given as a human-readable string - "QN CD 1", or "BX CDs 1 & 2" for the
# four merged PUMAs - which has to be parsed back into BoroCD integers.
#
# PUMA20 is read as character throughout: it is a 4-digit code, and coercing to
# numeric would strip any future leading zero.
LEP_SHEET <- "Top 10 Langs Spkn (LEP) by PUMA"

get_lep_puma_crosswalk <- function(path) {
  raw <- readxl::read_excel(
    path,
    sheet = LEP_SHEET,
    skip = 6,
    col_names = c(
      "borough", "puma2020", "cd_string",
      "puma_rank", "language", "estimate", "moe", "cv"
    ),
    col_types = c(
      "text", "text", "text",
      "text", "text", "numeric", "numeric", "numeric"
    )
  )

  raw |>
    filter(!is.na(puma2020), !is.na(cd_string)) |>
    distinct(puma2020, cd_string) |>
    # "QN CD 1" -> boro QN, cds "1"; "BX CDs 1 & 2" -> boro BX, cds "1 & 2"
    mutate(
      boro_abbrev = sub("^([A-Z]{2}) CDs? .*$", "\\1", cd_string),
      cd_list = sub("^[A-Z]{2} CDs? ", "", cd_string)
    ) |>
    # One row per (puma, cd). The four merged PUMAs fan out to two rows each,
    # which is what makes puma2020 non-unique in the finished crosswalk.
    tidyr::separate_longer_delim(cd_list, delim = " & ") |>
    mutate(
      cd_num = as.integer(trimws(cd_list)),
      boro_code = unname(BORO_ABBREV[boro_abbrev]),
      borocd = boro_code * 100L + cd_num
    ) |>
    select(borocd, puma2020)
}

# Fetch the Heat Vulnerability Index, keyed on CommDist (BoroCD).
#
# The service returns 70 rows: the 59 community districts plus 11 Joint
# Interest Areas. Filtering on "has an HVI value" is WRONG and returns 60 -
# ten JIAs are null but BX28 Pelham Bay Park carries a score of 1, so a park
# would silently enter any per-capita denominator. Filter on the JIA name
# pattern instead, which yields exactly 59 and leaves no nulls behind.
HVI_JIA_PATTERN <- "\\(JIA [0-9]+"

get_hvi <- function(url = HVI_SERVICE_URL) {
  parsed <- httr::parse_url(url)
  parsed$query <- list(
    where = "1=1",
    outFields = "CommDist,Neighborhood_CD,HVI,Year_Description",
    returnGeometry = "false",
    f = "json"
  )
  raw <- jsonlite::fromJSON(httr::build_url(parsed))$features$attributes

  out <- raw |>
    filter(!grepl(HVI_JIA_PATTERN, Neighborhood_CD)) |>
    transmute(
      borocd = as.integer(CommDist),
      hvi = as.integer(HVI),
      hvi_year = as.integer(Year_Description)
    ) |>
    arrange(borocd)

  # The JIA filter leans on a name convention; assert the result rather than
  # trusting it, so a rename upstream fails here instead of downstream.
  if (nrow(out) != 59) {
    stop(paste0("HVI service: expected 59 community districts after removing ",
                "JIAs, got ", nrow(out)))
  }
  assert_no_na(out, c("borocd", "hvi"))
  out
}

build_cdta_crosswalk <- function(cdta, lep_path) {
  core <- cdta_core(cdta)
  puma <- get_lep_puma_crosswalk(lep_path)

  core |>
    left_join(puma, by = "borocd") |>
    mutate(puma_shared = puma2020 %in% PUMA_SHARED_ALLOWLIST) |>
    select(
      cdta2020, slug, borocd, puma2020, puma_shared, hvi_geoid,
      county_fips, boro_code, boro_name, cd_label, display_name, coad,
      cdta_name
    ) |>
    arrange(cdta2020)
}

write_cdta_crosswalk <- function(crosswalk, path) {
  readr::write_csv(crosswalk, path, na = "")
  path
}

read_cdta_crosswalk <- function(path) {
  readr::read_csv(path, col_types = readr::cols(
    cdta2020 = readr::col_character(),
    slug = readr::col_character(),
    borocd = readr::col_integer(),
    puma2020 = readr::col_character(),
    puma_shared = readr::col_logical(),
    hvi_geoid = readr::col_integer(),
    county_fips = readr::col_character(),
    boro_code = readr::col_integer(),
    boro_name = readr::col_character(),
    cd_label = readr::col_character(),
    display_name = readr::col_character(),
    coad = readr::col_character(),
    cdta_name = readr::col_character()
  ))
}

# Every assertion here is a claim PIPELINE_DESIGN.md's Verification section
# makes, except where a claim turned out to be wrong about the real data - see
# the puma2020 and hvi_geoid notes.
validate_cdta_crosswalk <- function(crosswalk, hvi) {
  # 59 community districts citywide, 14 in Queens. The count is corroborated
  # independently by the HVI export also having exactly 59 rows.
  assert_row_count(crosswalk, min = 59, max = 59)
  n_queens <- sum(crosswalk$boro_code == 4L)
  if (n_queens != 14L) {
    stop(paste0("Queens district count: ", n_queens, ", expected 14"))
  }

  # No Joint Interest Area survived the CDTAType filter. QN80-QN84, MN64 and
  # the rest are parks and airports; they carry no population and would break
  # every per-capita figure.
  jia <- crosswalk$cdta2020[!grepl(CDTA_NAME_PATTERN, crosswalk$cdta_name)]
  if (length(jia) > 0) {
    stop(paste0(
      length(jia), " non-community-district CDTA(s) present: ",
      paste(jia, collapse = ", ")
    ))
  }
  assert_matches(crosswalk, "cdta_name", CDTA_NAME_PATTERN)

  assert_no_na(crosswalk, c(
    "cdta2020", "slug", "borocd", "puma2020", "hvi_geoid",
    "county_fips", "boro_code", "boro_name", "cd_label", "display_name"
  ))
  assert_col_type(crosswalk, "puma2020", "character")
  assert_col_type(crosswalk, "county_fips", "character")

  # Three identifier schemes for the same 59 rows, each of which something
  # joins on. A silent many-to-one in any of them corrupts every figure on the
  # far side of that join.
  assert_unique(crosswalk, "cdta2020")
  assert_unique(crosswalk, "slug")
  assert_unique(crosswalk, "borocd")
  assert_unique(crosswalk, "hvi_geoid")

  # PUMA is the exception: not unique citywide, and legitimately so. Unique
  # within Queens; citywide, exactly the four known merged PUMAs repeat.
  assert_unique(filter(crosswalk, boro_code == 4L), "puma2020")
  assert_unique_except(crosswalk, "puma2020", PUMA_SHARED_ALLOWLIST)

  # The crosswalk's district set must match DOHMH's, both directions. Fails if
  # we carry a district DOHMH does not publish, and if DOHMH publishes one we
  # do not carry - the second direction being what catches silent upstream
  # change. This is also what keeps BX28 Pelham Bay Park out: it is a JIA that
  # nonetheless carries an HVI score, and only the crosswalk join excludes it.
  assert_keys_match(
    crosswalk, hvi, by = "borocd",
    label_x = "crosswalk", label_y = "HVI service"
  )

  # hvi_geoid is no longer HVI's join key - the service uses borocd - but it
  # remains the key for other NYC EH Data Portal exports, so its derivation is
  # still asserted to be well-formed rather than silently rotting.
  bad_geoid <- crosswalk$cdta2020[
    crosswalk$hvi_geoid != as.integer(crosswalk$county_fips) * 100L +
      (crosswalk$borocd %% 100L)
  ]
  if (length(bad_geoid) > 0) {
    stop(paste0(
      length(bad_geoid), " hvi_geoid value(s) do not match the county-FIPS ",
      "formula: ", paste(bad_geoid, collapse = ", ")
    ))
  }

  TRUE
}
