# scripts/03_seed_resources.R
#
# Seeds data/canonical/resources.csv from the three sources.
#
# Run ONCE to create the canonical file. After that it becomes a reconcile
# step: a re-run proposes data/review/resources_diff.csv for a human to review
# rather than overwriting hand corrections. See section 4c of PIPELINE_DESIGN.md.
#
# Standalone and not part of the DAG, for two reasons: it geocodes 232 addresses
# against an external service, and its output is a file a person edits. The
# pipeline reads only the committed canonical CSV.
#
# Usage:
#   uvr run scripts/03_seed_resources.R          # seed, or propose a diff
#   uvr run scripts/03_seed_resources.R -- --force   # overwrite the canonical file
#
# Inputs:
#   DCP Facilities Database (Socrata, fetched)
#   data/prepared/qnpd_nonprofits.csv
#   data/prepared/franc_resource_map.geojson
#   data/crosswalk/resource_categories.csv

library(sf)
library(dplyr)
library(readr)
library(httr)
library(jsonlite)
library(tibble)

source("R/validate.R")
source("R/content.R")     # for %||%
source("R/resources.R")

CANONICAL <- "data/canonical/resources.csv"
DIFF_OUT  <- "data/review/resources_diff.csv"
force <- "--force" %in% commandArgs(trailingOnly = TRUE)

cx <- read_resource_categories("data/crosswalk/resource_categories.csv")
invisible(validate_resource_categories(cx))
message("Category crosswalk: ", nrow(cx), " mappings, ",
        dplyr::n_distinct(cx$canonical_category[cx$canonical_category != "exclude"]),
        " canonical categories")

message("Fetching DCP Facilities Database (Queens, scoped by crosswalk) ...")
facdb <- get_facdb(cx)
message("  ", nrow(facdb), " facilities")

message("Reading Queens Nonprofit Directory ...")
qnpd <- read_qnpd("data/prepared/qnpd_nonprofits.csv")
message("  ", nrow(qnpd), " organisations")

message("Geocoding nonprofit addresses via NYC GeoSearch ...")
qnpd_geo <- geocode_addresses(qnpd$address)
message("  ", sum(!is.na(qnpd_geo$lon)), " of ", nrow(qnpd), " geocoded; ",
        sum(qnpd_geo$geocode_boro == "Queens", na.rm = TRUE), " in Queens")

message("Reading FRANC resource map ...")
franc <- read_franc("data/prepared/franc_resource_map.geojson")
message("  ", nrow(franc), " features")

# FacDB publishes 0/0 for records it could not place. Geocode those from their
# address rather than losing them - it recovers ~89 Queens resources, most of
# them cultural institutions.
facdb_missing <- is.na(na_if_zero(suppressWarnings(as.numeric(facdb$longitude))))
if (any(facdb_missing)) {
  message("Geocoding ", sum(facdb_missing), " FacDB records with 0/0 coordinates ...")
  addr <- paste_na(facdb$address[facdb_missing], facdb$city[facdb_missing],
                   facdb$zipcode[facdb_missing])
  fg <- geocode_addresses(addr)
  facdb$longitude[facdb_missing] <- fg$lon
  facdb$latitude[facdb_missing] <- fg$lat
  message("  recovered ", sum(!is.na(fg$lon)), " of ", sum(facdb_missing))
}

candidates <- build_resource_candidates(facdb, qnpd, qnpd_geo, franc, cx)
message("\nCandidates: ", nrow(candidates), " records")
print(candidates |> count(source, name = "n") |> as.data.frame(), row.names = FALSE)

dir.create(dirname(CANONICAL), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(CANONICAL) || force) {
  write_csv(candidates, CANONICAL, na = "")
  message("\nSeeded ", CANONICAL, " (", nrow(candidates), " rows)")
  message("This file is now hand-maintained. Re-running proposes a diff ",
          "instead of overwriting it.")
} else {
  # Reconcile by resource_id. Fuzzy name+address matching for records whose id
  # changed is the next increment; for now an id change surfaces as an
  # add/remove pair, which a reviewer can spot.
  existing <- read_csv(CANONICAL, show_col_types = FALSE,
                       col_types = cols(.default = col_character()))
  cand_chr <- candidates |> mutate(across(everything(), as.character))

  added <- anti_join(cand_chr, existing, by = "resource_id") |>
    mutate(.change = "added")
  removed <- anti_join(existing, cand_chr, by = "resource_id") |>
    mutate(.change = "removed")

  # Changed: compare only source-derived fields. Anything a human may have
  # edited by hand must not be reported as drift, or every review cycle
  # re-proposes undoing the last one. canonical_category is deliberately NOT in
  # this list - recategorising is exactly the hand edit the loop exists to
  # protect, and reporting it would ask the reviewer to undo their own work.
  source_fields <- c("name", "subcategory", "address", "lon", "lat", "capacity")

  joined <- inner_join(
    select(cand_chr, resource_id, all_of(source_fields)),
    select(existing, resource_id, all_of(source_fields)),
    by = "resource_id", suffix = c(".new", ".old")
  )

  # Compared pairwise rather than with if_any(): cur_column() is only defined
  # inside across(), and using it in if_any() aborts.
  #
  # Numeric fields are compared with a tolerance. A CSV round-trip can change
  # the printed form of a coordinate without changing the value, and reporting
  # that as drift would fill the review file with noise.
  differs <- function(a, b, numeric = FALSE) {
    na_a <- is.na(a); na_b <- is.na(b)
    if (numeric) {
      an <- suppressWarnings(as.numeric(a)); bn <- suppressWarnings(as.numeric(b))
      (na_a != na_b) | (!na_a & !na_b & abs(an - bn) > 1e-6)
    } else {
      (na_a != na_b) | (!na_a & !na_b & as.character(a) != as.character(b))
    }
  }
  numeric_fields <- c("lon", "lat", "capacity")
  flags <- lapply(source_fields, function(f) {
    differs(joined[[paste0(f, ".new")]], joined[[paste0(f, ".old")]],
            numeric = f %in% numeric_fields)
  })
  changed <- joined[Reduce(`|`, flags), ] |> mutate(.change = "changed")

  diff <- bind_rows(added, removed, changed)
  dir.create(dirname(DIFF_OUT), showWarnings = FALSE, recursive = TRUE)
  write_csv(diff, DIFF_OUT, na = "")
  message("\n", CANONICAL, " exists and was NOT modified.")
  message("Wrote ", DIFF_OUT, ": ", sum(diff$.change == "added"), " added, ",
          sum(diff$.change == "removed"), " removed, ",
          sum(diff$.change == "changed"), " changed")
  message("Review, then merge by hand. --force overwrites instead.")
}
