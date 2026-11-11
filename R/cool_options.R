# R/cool_options.R
#
# NYC OEM Cool Options as resources, under their own category: Cooling options.
#
# The second resource source, after R/qpl.R, that does NOT go through
# data/canonical/resources.csv, and for the same reason: it is the agency's own
# list, so the DAG reads it every build and a site OEM adds or drops reaches
# the map without anyone reseeding. A wrong site is fixed upstream.
#
# It reuses the `cool_options` target the heat gaps already read
# (get_cool_options() in R/gaps.R): indoor rooms only, `Space_type ==
# "Cooling Center"`. One fetch, so the map and gap 2 can never be describing
# two different lists.
#
# Library branches are listed twice, deliberately (Andrew, 2026-11-11). 49 of
# Queens' 117 indoor Cool Options are QPL branches, which are already
# resources under Libraries and community. Both records ship: the category is
# what a heat-wave map turns on, and dropping the branches from it would leave
# out the largest kind of cool option. The two points stack only when
# Libraries is on too, which is not a default.
#
# Fields shipped: name, address, phone, and "older adults only" as the
# subcategory where OEM restricts a site by age. `Accessible`, `Pet_friendly`
# and the opening hours are not in the union schema and are not shipped.
# `Finder_status` is live open/closed state and stays ignored, as for the gaps.

COOL_SOURCE <- "cool"

# Queens had 117 indoor Cool Options when this was written (2026-11-11). As for
# QPL_MIN_BRANCHES, the range is what catches a truncated or empty response.
COOL_MIN_QUEENS <- 90
COOL_MAX_QUEENS <- 150

# Older adult centres carry the restriction in their name as well as in
# `Age_restriction`: "Middle Village OAC -OLDER ADULTS ONLY". The suffix is
# moved into the subcategory, so the name reads as a name.
COOL_AGE_SUFFIX <- "\\s*-\\s*OLDER ADULTS ONLY\\s*$"

# Onto the union schema (CANONICAL_COLUMNS in R/resources.R). The category
# resolves through the crosswalk like any other source's - `cool`, field
# `Space_type` - so its label is stated once, in
# data/crosswalk/resource_categories.csv.
build_cool_option_resources <- function(cool_options, cx) {
  x <- cool_options |>
    sf::st_transform(4326) |>
    dplyr::filter(Borough_name == "Queens")
  xy <- sf::st_coordinates(x)
  x <- sf::st_drop_geometry(x)

  mapped <- map_category(cx, COOL_SOURCE, x$Space_type, "Space_type")
  older_only <- x$Age_restriction %in% "Yes"

  tibble::tibble(
    # NYCEM_ID is OEM's own id ("CC1051"), unique across the citywide list
    # (checked), so a renamed site keeps its permalink.
    resource_id = paste0(COOL_SOURCE, ":", tolower(x$NYCEM_ID)),
    source = COOL_SOURCE,
    source_id = x$NYCEM_ID,
    provenance = "nyc_oem_cool_options",
    # When OEM last edited the list, not the build date: the build date would
    # claim a check nobody made.
    verified_on = x$data_updated,
    name = display_case(trimws(sub(COOL_AGE_SUFFIX, "", x$Facility_name,
                                   ignore.case = TRUE))),
    canonical_category = mapped$canonical_category,
    subcategory = ifelse(older_only, "Indoor cool option, older adults only",
                         "Indoor cool option"),
    address = paste_na(display_case(trimws(x$Address)), "Queens",
                       paste("NY", x$ZIP_code)),
    lon = xy[, 1],
    lat = xy[, 2],
    geocode_boro = "Queens",
    geocode_match = "NYC OEM Cool Options geometry",
    in_queens = TRUE,
    serves_queens = TRUE,
    is_coad_member = FALSE,
    phone = format_phone_us(trimws(x$Phone)),
    removed_reason = NA_character_
  )
}

# --- validation -------------------------------------------------------------

validate_cool_option_resources <- function(cool_options, records, resources_cdta, cx) {
  fail <- function(...) stop("Cool Options: ", ..., call. = FALSE)
  raw <- sf::st_drop_geometry(cool_options)

  # 1. The id is OEM's, so it must be present and unique citywide. A duplicate
  #    would put two sites on one resource page.
  if (any(is.na(raw$NYCEM_ID) | !nzchar(raw$NYCEM_ID))) fail("a site with no NYCEM_ID")
  assert_unique(raw, "NYCEM_ID")

  # 2. The fetch is whole. See COOL_MIN_QUEENS.
  n <- sum(raw$Borough_name == "Queens")
  if (n < COOL_MIN_QUEENS || n > COOL_MAX_QUEENS) {
    fail(n, " Queens sites, expected ", COOL_MIN_QUEENS, "-", COOL_MAX_QUEENS,
         ". A truncated fetch, or OEM has really changed the list - check ",
         "Cool_Options before widening the range.")
  }

  # 3. Every field the resource page shows is present, and the ids are
  #    route-safe: the frontend builds /q{NN}/resource/cool/<slug>.
  for (col in c("name", "address", "canonical_category", "verified_on")) {
    blank <- sum(is.na(records[[col]]) | !nzchar(records[[col]]))
    if (blank > 0) fail(blank, " record(s) with no ", col)
  }
  bad_id <- records |> filter(!grepl("^cool:[a-z0-9-]{1,60}$", resource_id))
  if (nrow(bad_id) > 0) fail("bad resource_id ", paste(bad_id$resource_id, collapse = ", "))
  vocab <- cx$canonical_category[!cx$canonical_category %in% CATEGORY_NON_DISPLAY]
  if (!all(records$canonical_category %in% vocab)) {
    fail("Space_type maps to no display category in the resource crosswalk")
  }

  # 4. Located, inside the NYC box.
  off <- records |>
    filter(is.na(lon) | is.na(lat) | lon < -74.3 | lon > -73.6 |
             lat < 40.4 | lat > 41.0)
  if (nrow(off) > 0) fail("unlocated or off-map: ", paste(off$name, collapse = ", "))

  # 5. Every Queens site is published in a district. Two ways on resource_id,
  #    so a site the point-in-polygon join drops - a park, an airport - fails
  #    here by name rather than vanishing from the map.
  published <- resources_cdta |> filter(source == COOL_SOURCE, !is.na(cdta2020))
  assert_keys_match(select(records, resource_id), select(published, resource_id),
                    by = "resource_id", label_x = "Queens Cool Options",
                    label_y = "published resources")
  outside <- published |> filter(!grepl("^QN", cdta2020))
  if (nrow(outside) > 0) {
    fail("Queens site(s) placed outside Queens: ",
         paste(head(outside$name, 3), collapse = ", "))
  }
  TRUE
}
