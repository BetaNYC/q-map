# scripts/10_mirror_fema.R
#
# Tier-2 mirror: FEMA flood zones for Queens (the `fema_flood_zones` layer).
#
# WHY A MIRROR AND NOT A TARGET
#
# FEMA's NFHL service reset the connection five times during one Queens fetch
# on 2026-11-05. As a target, a cold CI cache would refetch it and one bad
# afternoon at FEMA would fail the pipeline and hold every deploy. The map it
# serves (NYC's 2007 effective FIRM) changes only when FEMA adopts a new one or
# issues a map revision, so a mirror refreshed by hand loses nothing.
#
# WHAT IT WRITES (both published as data-v* release assets)
#
#   data/prepared/fema_nfhl_queens.geojson
#       The download as served: every flood hazard area intersecting Queens's
#       bounding box (which also catches Nassau County and parts of Brooklyn),
#       a handful of fields, EPSG:4326, NOT repaired. The DAG reads it for
#       fema_nfhl_checks, the same way it reads the stormwater mirrors.
#
#   data/prepared/fema_flood_zones.pmtiles
#       The map layer. NYC's DFIRM only, classed VE / AE / 0.2PCT
#       (NFHL_ZONE_CLASSES in R/flooding.R), dissolved per class, clipped to
#       Queens. One attribute: `zone`.
#
# WHY PMTILES (Andrew, 2026-11-05). As GeoJSON this layer is 387 KB at the
# project's 10% simplification. Every GeoJSON overlay is fetched when the map
# starts, switched on or not, so it would have cost every map load 387 KB.
# PMTiles fetches only the tiles in view, and only once the layer is on.
#
# Built here rather than in the DAG for the stormwater reason: it keeps
# tippecanoe out of CI. See scripts/01_mirror_stormwater.R for the two tiling
# rules applied below (explode to POLYGON, transform to 4326).
#
# Usage:  uvr run scripts/10_mirror_fema.R
#         Needs the targets store (for the Queens outline) and tippecanoe.
#         Then publish both files in a new data-v* release - see
#         DATA_SOURCES.md.

library(sf)
library(dplyr)

sf_use_s2(FALSE)

source("R/validate.R")
source("R/flooding.R")
source("R/layers.R")

NFHL_URL <- paste0("https://hazards.fema.gov/arcgis/rest/services/public/",
                   "NFHLWMS/MapServer/28/query")
NFHL_FIELDS <- c("DFIRM_ID", "VERSION_ID", "FLD_ZONE", "ZONE_SUBTY",
                 "SFHA_TF", "SOURCE_CIT")

OUT_RAW   <- "data/prepared/fema_nfhl_queens.geojson"
OUT_TILES <- "data/prepared/fema_flood_zones.pmtiles"

# Small pages and patient retries. 500-record pages failed outright; 250 with
# backoff completed with five resets along the way.
PAGE_SIZE   <- 250
MAX_TRIES   <- 6

# Same zooms as stormwater, for the same reason: below z8 MapLibre draws
# nothing and says nothing, and z16 is block level.
TILE_MIN_ZOOM <- 8
TILE_MAX_ZOOM <- 16

if (nchar(Sys.which("tippecanoe")) == 0) {
  stop("tippecanoe not found. It is needed for ", OUT_TILES, ".")
}

# --- the Queens frame -------------------------------------------------------

qn <- queens_outline(targets::tar_read(cdta_boundaries))
bb <- st_bbox(qn)
envelope <- paste(round(bb[c("xmin", "ymin", "xmax", "ymax")], 6), collapse = ",")

query_url <- function(extra) {
  paste0(NFHL_URL, "?where=1%3D1",
         "&geometry=", envelope,
         "&geometryType=esriGeometryEnvelope&inSR=4326",
         "&spatialRel=esriSpatialRelIntersects", extra)
}

with_retries <- function(what, f) {
  for (attempt in seq_len(MAX_TRIES)) {
    out <- tryCatch(f(), error = function(e) {
      message("  ", what, ": attempt ", attempt, " failed (", conditionMessage(e), ")")
      NULL
    })
    if (!is.null(out)) return(out)
    Sys.sleep(5 * attempt)
  }
  stop(what, ": gave up after ", MAX_TRIES, " attempts")
}

# --- download ---------------------------------------------------------------

# The server's own count, so the download can be checked for completeness. A
# page that silently comes back short is the failure a retry loop does not see.
expected_n <- with_retries("count", function() {
  jsonlite::fromJSON(query_url("&returnCountOnly=true&f=json"))$count
})
message("NFHL reports ", expected_n, " features in the Queens frame")

pages <- list()
offset <- 0
repeat {
  page <- with_retries(paste("page at", offset), function() {
    read_sf(query_url(paste0(
      "&outFields=", paste(NFHL_FIELDS, collapse = ","),
      "&outSR=4326&f=geojson",
      "&resultOffset=", offset, "&resultRecordCount=", PAGE_SIZE
    )), quiet = TRUE)
  })
  if (nrow(page) == 0) break
  pages[[length(pages) + 1]] <- page
  offset <- offset + nrow(page)
  if (nrow(page) < PAGE_SIZE) break
}
raw <- bind_rows(pages)

if (nrow(raw) != expected_n) {
  stop("Downloaded ", nrow(raw), " features; the service reported ", expected_n)
}

# Validate before publishing: a release asset is immutable in practice.
invisible(validate_nfhl(raw))

if (file.exists(OUT_RAW)) file.remove(OUT_RAW)
st_write(raw, OUT_RAW, driver = "GeoJSON", quiet = TRUE)
message(sprintf("%s: %d features, %.1f MB", OUT_RAW, nrow(raw),
                file.info(OUT_RAW)$size / 1024^2))

# --- tiles ------------------------------------------------------------------

zones <- raw |>
  filter(DFIRM_ID == NFHL_NYC_DFIRM) |>
  classify_nfhl() |>
  filter(!is.na(zone)) |>
  st_make_valid() |>
  group_by(zone) |>
  summarise(.groups = "drop") |>
  st_make_valid()

# Intersection can return GEOMETRYCOLLECTIONs where a zone meets the outline
# along a line; keep only the polygon parts.
zones <- suppressWarnings(st_intersection(zones, qn) |> st_collection_extract("POLYGON")) |>
  group_by(zone) |>
  summarise(.groups = "drop")

if (!setequal(zones$zone, NFHL_ZONES)) {
  stop("Queens tiles carry zone(s) ", paste(sort(zones$zone), collapse = ", "),
       "; expected ", paste(NFHL_ZONES, collapse = ", "))
}

area_km2 <- as.numeric(st_area(st_transform(zones, 2263))) / 10763910.4
message("Queens area by zone (km2): ",
        paste(sprintf("%s %.2f", zones$zone, area_km2), collapse = ", "))

# `zone` is constant within each dissolved feature, so st_cast's "repeating
# attributes" warning is expected and silenced.
parts <- suppressWarnings(zones |>
  st_cast("MULTIPOLYGON") |>
  st_cast("POLYGON")) |>      # see 01_mirror_stormwater.R - not cosmetic
  st_transform(4326)

tmp <- tempfile(fileext = ".geojson")
st_write(parts, tmp, driver = "GeoJSON", quiet = TRUE)

if (file.exists(OUT_TILES)) file.remove(OUT_TILES)
status <- system2("tippecanoe", c(
  "-o", shQuote(OUT_TILES),
  "-Z", TILE_MIN_ZOOM, "-z", TILE_MAX_ZOOM,
  "-l", "fema_flood_zones",
  "-n", "fema_flood_zones",
  # A flood zone is the data. Dropping or shrinking small polygons would
  # remove real floodplain.
  "--no-feature-limit", "--no-tile-size-limit",
  "--no-tiny-polygon-reduction",
  shQuote(tmp)
), stdout = FALSE, stderr = FALSE)

if (status != 0 || !file.exists(OUT_TILES)) stop("tippecanoe failed")
message(sprintf("%s: %d parts, %.2f MB", OUT_TILES, nrow(parts),
                file.info(OUT_TILES)$size / 1024^2))
