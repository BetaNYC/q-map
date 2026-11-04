# R/qpl.R
#
# Queens Public Library branches, from QPL's own Open Data list (kh3d-xhq7).
#
# The one resource source that does NOT go through data/canonical/resources.csv.
# That file exists because the scraped sources (QNPD, FRANC) need a person to
# correct them, and a re-scrape must not undo the correction. QPL's list is the
# agency's own record of its branches, so the DAG fetches it every build and
# binds it onto the live canonical rows. A branch QPL opens or closes reaches
# the map without anyone reseeding, at the cost of no per-branch hand override:
# a wrong branch is fixed upstream, or by moving that branch to a manual row.
#
# FacDB also lists the branches (67 PUBLIC LIBRARY rows). They have been
# excluded by the category crosswalk since 2026-10-20, and
# validate_qpl_branches() fails the build if any other source publishes a
# Queens Library record, so branch details come from QPL alone.
#
# Fields shipped, per Andrew 2026-11-04: name, address, phone, and the branch
# page URL (where QPL publishes hours) as `hours_url`.

QPL_URL <- "https://data.cityofnewyork.us/resource/kh3d-xhq7.json"
QPL_VIEW_URL <- "https://data.cityofnewyork.us/api/views/kh3d-xhq7.json"
PLUTO_URL <- "https://data.cityofnewyork.us/resource/64uk-42ks.json"

QPL_OPERATOR <- "Queens Public Library"

# QPL had 66 branches when this was written (2026-07-08 vintage). There is no
# independent list to anti_join against, so this range is what catches a
# truncated or empty response. A swing outside it is a broken fetch, not a
# library opening; widen it if QPL really grows.
QPL_MIN_BRANCHES <- 60
QPL_MAX_BRANCHES <- 80

# Any record from any source naming the library system. Matches "Queens Public
# Library", "Queens Library-Astoria", "Queens Borough Public Library".
QPL_NAME_PATTERN <- "queens\\s+(borough\\s+)?(public\\s+)?library"

# --- fetch ------------------------------------------------------------------

# The branch list as QPL publishes it, plus the date QPL last updated it.
#
# `latitude`, `longitude` and `point` are NOT read. QPL publishes them rounded
# to two decimal places (59 rows) or one (7) - up to 0.6 km from the building,
# far enough to put a branch in the wrong district. The branch is located from
# its BBL instead; see get_qpl_branch_lots().
get_qpl_branches <- function(url = QPL_URL, view_url = QPL_VIEW_URL) {
  parsed <- httr::parse_url(url)
  parsed$query <- list(
    `$select` = paste("name,address,city,postcode,borough,phone",
                      "hours_can_be_viewed_via_branch_url_",
                      "community_board,bin,bbl", sep = ","),
    `$limit` = 5000
  )
  raw <- jsonlite::fromJSON(httr::build_url(parsed), flatten = TRUE)

  # The URL column is a Socrata `url` type, which arrives as {url: "..."} and
  # flattens to `hours_can_be_viewed_via_branch_url_.url`.
  url_col <- grep("^hours_can_be_viewed_via_branch_url_", names(raw), value = TRUE)
  if (length(url_col) != 1) {
    stop("QPL branches: expected one hours URL column, found ",
         length(url_col), " - the upstream schema has changed")
  }

  # The view's rowsUpdatedAt is when QPL last changed the data. That is the
  # honest `verified_on`; the build date would claim a check nobody made.
  meta <- jsonlite::fromJSON(view_url)
  updated <- as.Date(as.POSIXct(meta$rowsUpdatedAt, origin = "1970-01-01",
                                tz = "America/New_York"))

  raw |>
    tibble::as_tibble() |>
    transmute(
      name = trimws(name), address = trimws(address), city = trimws(city),
      postcode, borough, phone = trimws(phone),
      hours_url = trimws(.data[[url_col]]),
      community_board, bin, bbl,
      rows_updated = as.character(updated)
    )
}

# PLUTO tax lots for the branches' BBLs: the coordinates QPL's own are too
# coarse to supply, and an independent community district to check QPL's
# against.
#
# BBL rather than geocoding the address. On 2026-11-04 PLUTO resolved all 66
# BBLs and its `cd` agreed with QPL's `community_board` on all 66. GeoSearch on
# the address returned the wrong building for two (Ridgewood: 60-20 Madison for
# 20-12; Douglaston: 243-01 Northern Blvd for 249-01).
get_qpl_branch_lots <- function(bbls, url = PLUTO_URL) {
  bbls <- unique(bbls[!is.na(bbls)])
  parsed <- httr::parse_url(url)
  parsed$query <- list(
    `$select` = "bbl,address,cd,latitude,longitude,version",
    `$where` = sprintf("bbl in (%s)", paste0("'", bbls, "'", collapse = ",")),
    `$limit` = 5000
  )
  jsonlite::fromJSON(httr::build_url(parsed)) |>
    tibble::as_tibble() |>
    transmute(
      # PLUTO stores the BBL as text with a decimal tail: "4000190025.00000000".
      bbl = sub("\\..*$", "", bbl),
      lot_address = address,
      lot_cd = cd,
      lon = as.numeric(longitude),
      lat = as.numeric(latitude),
      pluto_version = version
    )
}

# --- normalise --------------------------------------------------------------

# "(718) 528 8490" and "718 471-2573" -> "(718) 528-8490". Two of 66 arrive in
# a different shape; anything not ten digits is left as published, and the
# check reports it.
format_phone_us <- function(x) {
  d <- gsub("\\D", "", x)
  ifelse(nchar(d) == 10,
         sprintf("(%s) %s-%s", substr(d, 1, 3), substr(d, 4, 6), substr(d, 7, 10)),
         x)
}

# Onto the union schema (CANONICAL_COLUMNS in R/resources.R), plus `hours_url`,
# which only this source carries. Fields QPL does not publish stay NA.
build_qpl_branches <- function(raw, lots) {
  located <- left_join(raw, lots, by = "bbl")

  tibble::tibble(
    # QPL publishes no id. The name is unique across the list (checked), so
    # the slug is the id - which means a renamed branch gets a new permalink.
    resource_id = paste0("qpl:", slugify(located$name)),
    source = "qpl",
    source_id = located$bbl,
    provenance = "queens_library_branches",
    verified_on = located$rows_updated,
    name = located$name,
    operator = QPL_OPERATOR,
    canonical_category = "libraries-and-community",
    subcategory = "Public library",
    address = paste_na(located$address, located$city,
                       paste("NY", located$postcode)),
    lon = located$lon,
    lat = located$lat,
    geocode_boro = "Queens",
    geocode_match = paste0(located$lot_address, " (PLUTO ",
                           located$pluto_version, ", BBL ", located$bbl, ")"),
    in_queens = TRUE,
    serves_queens = TRUE,
    is_coad_member = FALSE,
    phone = format_phone_us(located$phone),
    hours_url = located$hours_url,
    removed_reason = NA_character_
  )
}

# --- validation -------------------------------------------------------------

validate_qpl_branches <- function(raw, lots, branches, resources_cdta,
                                  canonical, crosswalk, cx) {
  fail <- function(...) stop("QPL branches: ", ..., call. = FALSE)

  # 1. The fetch is whole. See QPL_MIN_BRANCHES.
  if (nrow(raw) < QPL_MIN_BRANCHES || nrow(raw) > QPL_MAX_BRANCHES) {
    fail(nrow(raw), " branches, expected ", QPL_MIN_BRANCHES, "-",
         QPL_MAX_BRANCHES, ". A truncated fetch, or QPL has really changed - ",
         "check kh3d-xhq7 before widening the range.")
  }

  # 2. Every field the resource page shows is present on every branch.
  blank <- function(x) is.na(x) | !nzchar(x)
  for (col in c("name", "address", "phone", "hours_url", "bbl",
                "community_board")) {
    n <- sum(blank(raw[[col]]))
    if (n > 0) fail(n, " branch(es) with no ", col)
  }
  if (any(raw$borough != "QUEENS")) fail("a branch outside Queens")
  bad_url <- raw |> filter(!startsWith(hours_url, "https://www.queenslibrary.org/"))
  if (nrow(bad_url) > 0) {
    fail("hours URL not on queenslibrary.org: ",
         paste(head(bad_url$name, 3), collapse = ", "))
  }

  # 3. Every branch BBL is a PLUTO lot, and PLUTO returned nothing else. Two
  #    ways: a branch with no lot has no coordinates, and an extra lot means
  #    the BBL query matched something it should not have.
  assert_keys_match(distinct(raw, bbl), distinct(lots, bbl), by = "bbl",
                    label_x = "QPL branches", label_y = "PLUTO lots")
  if (any(duplicated(lots$bbl))) fail("PLUTO returned a BBL twice")

  # 4. Two agencies agree on the district. PLUTO's `cd` and QPL's
  #    `community_board` are independent, so a mistyped BBL - which would
  #    plot the branch on someone else's lot - shows up as a disagreement.
  cd <- left_join(raw, lots, by = "bbl") |> filter(lot_cd != community_board)
  if (nrow(cd) > 0) {
    fail("PLUTO and QPL disagree on the community district of ",
         paste(head(cd$name, 3), collapse = ", "))
  }

  # 5. The ids are unique and route-safe. The frontend builds
  #    /q{NN}/resource/qpl/<slug> and refuses anything else.
  assert_unique(branches, "resource_id")
  bad_id <- branches |> filter(!grepl("^qpl:[a-z0-9-]{1,60}$", resource_id))
  if (nrow(bad_id) > 0) fail("bad resource_id ", paste(bad_id$resource_id, collapse = ", "))

  bad_phone <- branches |> filter(!grepl("^\\(\\d{3}\\) \\d{3}-\\d{4}$", phone))
  if (nrow(bad_phone) > 0) {
    fail("phone not ten digits: ", paste(head(bad_phone$name, 3), collapse = ", "))
  }

  # 6. Located, inside the NYC box, in a category the crosswalk knows.
  off <- branches |>
    filter(is.na(lon) | is.na(lat) | lon < -74.3 | lon > -73.6 |
             lat < 40.4 | lat > 41.0)
  if (nrow(off) > 0) fail("unlocated or off-map: ", paste(off$name, collapse = ", "))
  vocab <- cx$canonical_category[cx$canonical_category != "exclude"]
  if (!all(branches$canonical_category %in% vocab)) {
    fail("category not in the resource crosswalk")
  }

  # 7. Every branch is published, in the district QPL says it is in. Two ways
  #    on resource_id, so a branch dropped by the point-in-polygon join fails
  #    here rather than vanishing from the map.
  published <- resources_cdta |> filter(source == "qpl")
  assert_keys_match(select(branches, resource_id), select(published, resource_id),
                    by = "resource_id", label_x = "QPL branches",
                    label_y = "published resources")
  placed <- published |>
    left_join(select(crosswalk, cdta2020, borocd), by = "cdta2020") |>
    left_join(select(raw, name, community_board), by = "name") |>
    filter(is.na(borocd) | as.character(borocd) != community_board)
  if (nrow(placed) > 0) {
    fail("placed outside QPL's community district: ",
         paste(head(placed$name, 3), collapse = ", "))
  }

  # 8. Branch details come from QPL alone. A live record from any other source
  #    that names the library system is a duplicate dot, or FacDB detail
  #    leaking back in through a reseed. Remove it in resources.csv with a
  #    removed_reason.
  leak <- live_resources(canonical) |>
    filter(grepl(QPL_NAME_PATTERN, name, ignore.case = TRUE) |
             grepl(QPL_NAME_PATTERN, dplyr::coalesce(operator, ""),
                   ignore.case = TRUE))
  if (nrow(leak) > 0) {
    fail(nrow(leak), " live non-QPL record(s) name Queens Library: ",
         paste(head(leak$resource_id, 3), collapse = ", "),
         ". Branches come from kh3d-xhq7 only.")
  }
  TRUE
}
