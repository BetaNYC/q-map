# scripts/07_mirror_franc.R
#
# Tier-2 mirror: the FRANC Resource Map, a Google MyMap maintained by the
# Rockaway COAD.
#
# Numbered 07 because 04 is reserved for the access measures (ACCESS_MEASURES.md)
# and 05/06 are taken. The number is run order, not grouping.
#
# Unlike the DEP shapefiles this source IS fetchable programmatically - but it
# is a community-maintained Google map that can be edited or deleted without
# notice, which is exactly what a dated snapshot is for. The KML is the mirror;
# the GeoJSON is derived from it here.
#
# Usage:  uvr run scripts/07_mirror_franc.R
#
# Outputs: data/source/franc_mymap.kml               the snapshot
#          data/prepared/franc_resource_map.geojson  what the seed reads

library(sf)
library(dplyr)
library(purrr)

MYMAP_URL <- paste0("https://www.google.com/maps/d/kml",
                    "?mid=1aFJJyecLErzB0xyf57YsUUBUzJsKnXlL&forcekml=1")
KML  <- "data/source/franc_mymap.kml"
GEOJSON <- "data/prepared/franc_resource_map.geojson"

dir.create(dirname(KML), showWarnings = FALSE, recursive = TRUE)
dir.create(dirname(GEOJSON), showWarnings = FALSE, recursive = TRUE)

# The original version of this script had three bugs, all fixed here:
#
#   It downloaded to "mymap.kml" in the working directory but wrote its output
#   to "test/", so the two paths could not both be correct from any single cwd.
#   Both are now absolute within the project.
#
#   st_write() had no delete_dsn, so a second run failed with "Dataset already
#   exists" rather than overwriting.
#
#   No timeout bump. 60 KB is small but Google's KML export can stall.
old_timeout <- getOption("timeout")
options(timeout = 120)
on.exit(options(timeout = old_timeout), add = TRUE)

message("Downloading the FRANC MyMap KML ...")
download.file(MYMAP_URL, KML, mode = "wb", quiet = TRUE)
message("  ", KML, " (", round(file.info(KML)$size / 1024), " KB)")

# Read via LIBKML if it is available, otherwise the plain KML driver.
#
# This matters for one field. The KML carries <styleUrl> on every placemark -
# 68 distinct icon values across 82 features - which LIBKML surfaces as `icon`
# and the plain KML driver drops entirely. That is a second, independent
# category signal: source_layer conflates membership ("FRANC Members"),
# category ("Food Pantry Services") and population served ("DAFN"), which is
# why 34 records needed hand-recategorising. icon is the one other clue.
#
# sf's bundled GDAL has no LIBKML driver, but the system GDAL usually does, so
# convert through it into a GeoPackage first. Falls back rather than failing:
# losing `icon` degrades the review signal, it does not break the mirror.
read_mymap <- function(kml) {
  gpkg <- tempfile(fileext = ".gpkg")
  ok <- nchar(Sys.which("ogr2ogr")) > 0 &&
    system2("ogr2ogr", c("-f", "GPKG", shQuote(gpkg), shQuote(kml)),
            stdout = FALSE, stderr = FALSE) == 0 && file.exists(gpkg)

  src <- if (ok) gpkg else kml
  if (!ok) {
    warning("ogr2ogr unavailable or failed - reading with sf's KML driver. ",
            "The `icon` field will be missing.")
  }
  layers <- st_layers(src)$name
  message("Reading ", length(layers), " layers", if (ok) " via LIBKML" else "", " ...")
  purrr::map(layers, function(l) {
    st_read(src, layer = l, quiet = TRUE) |> mutate(source_layer = l)
  }) |> bind_rows()
}

combined <- read_mymap(KML)

# Column names differ between the two drivers - LIBKML gives `description`,
# the KML driver gives `Description`. Normalise rather than assume.
names(combined) <- sub("^Description$", "description", names(combined))

keep <- intersect(c("Name", "description", "icon"), names(combined))
out <- combined |>
  st_zm() |>
  select(all_of(keep), source_layer)

if (file.exists(GEOJSON)) invisible(file.remove(GEOJSON))
st_write(out, GEOJSON, driver = "GeoJSON", quiet = TRUE)

geom <- table(as.character(st_geometry_type(out)))
message("\nWrote ", GEOJSON, " (", nrow(out), " features)")
message("  geometry: ", paste(names(geom), geom, collapse = ", "))
message("  fields:   ", paste(setdiff(names(out), attr(out, "sf_column")),
                              collapse = ", "))
if (!"icon" %in% names(out)) {
  message("  NOTE: `icon` is absent - the styleUrl category signal was not captured")
}
