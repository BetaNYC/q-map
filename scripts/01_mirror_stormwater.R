# scripts/01_mirror_stormwater.R
#
# Tier-2 mirror: NYC DEP stormwater flood maps.
#
# The DEP publishes these as an ESRI geodatabase with no API. They arrive as
# GeoJSON in EPSG:2263 (converted from the geodatabase in the d26 project) and
# are passed through to data/prepared/ unchanged.
#
# Kept as GeoJSON rather than converted. GeoPackage would be 2.3x smaller and
# 11x faster to read, but at 0.88s and 40MB neither matters here. Revisit only
# if the release payload grows.
#
# One transformation IS applied: st_zm(). The source carries Z coordinates
# inherited from the ESRI geodatabase, which are meaningless for a 2D flood
# extent. d26's scripts/04_mirror_stormwater_flooding_d26_zctas.R strips them
# for the same reason ("Have to strip Z,M values from geometry").
#
# Verified lossless before adopting: total area is identical to the digit
# (118,204,172 sq ft) and every Queens district's flood percentage differs by
# exactly 0. It also drops ~8.6% of the file size.
#
# st_make_valid() is deliberately NOT applied here. Both layers arrive with
# invalid geometry, and unlike stripping Z that is a repair which can move
# vertices. Repairs belong in the DAG where they are attributable to a target,
# not baked into an immutable Release asset. The mirror warns instead.
#
# Only the CURRENT sea-level scenarios are mirrored. The 2050s and 2080s
# scenarios exist but no screen renders them, and the coastal-storm ranking
# uses present-day exposure by the same reasoning (see METHODOLOGY.md).
#
# Usage:  uvr run scripts/01_mirror_stormwater.R
#
# Inputs:  data/source/flood_geojson/{limited_1_77,moderate_2_13}.geojson
# Outputs: data/prepared/stormwater_{limited_1_77,moderate_2_13}.geojson
#
# The outputs are published as assets of the data-v* GitHub Release. See
# DATA_SOURCES.md.

library(sf)
library(dplyr)

sf_use_s2(FALSE)

source("R/validate.R")

SRC <- "data/source/flood_geojson"
OUT <- "data/prepared"

# Flooding_C is the flood-depth category, and the values are not self-
# describing. From the QGIS metadata sidecar shipped with the source:
#   1 = Nuisance flooding            ponding >= 4 in and < 1 ft
#   2 = Deep and contiguous flooding ponding >= 1 ft
#
# q-map's heavy-rain measure unions BOTH categories, so the published
# percentage includes nuisance ponding. That is a deliberate choice; anyone
# quoting the number should know what it covers.
FLOODING_CATEGORIES <- c(`1` = "nuisance", `2` = "deep_contiguous")

LAYERS <- c(
  limited_1_77  = "Limited flood, 1.77 in/hr, current sea levels",
  moderate_2_13 = "Moderate flood, 2.13 in/hr, current sea levels"
)

dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

for (nm in names(LAYERS)) {
  src <- file.path(SRC, paste0(nm, ".geojson"))
  dst <- file.path(OUT, paste0("stormwater_", nm, ".geojson"))

  if (!file.exists(src)) stop("Missing source: ", src)

  x <- st_read(src, quiet = TRUE) |> st_zm()

  # Validate before publishing. A Release asset is immutable in practice - it
  # is easier to assert here than to discover a bad mirror in CI three weeks on.
  assert_crs(x, 2263)
  # st_z_range() returns a bare NA on 2D geometry, so is.na()-based guards
  # evaluate to NA rather than FALSE. Check the coordinate matrix instead.
  dims <- colnames(st_coordinates(x))
  if (any(c("Z", "M") %in% dims)) {
    stop(nm, ": Z or M values survived st_zm() - dims are ",
         paste(dims, collapse = ","))
  }
  assert_row_count(x, min = 2, max = 2)
  assert_no_na(x, "Flooding_C")
  unexpected <- setdiff(as.character(x$Flooding_C), names(FLOODING_CATEGORIES))
  if (length(unexpected) > 0) {
    stop("Unexpected Flooding_C value(s) in ", nm, ": ",
         paste(unexpected, collapse = ", "))
  }
  if (!all(st_is_valid(x))) {
    # Do not silently repair. A geometry that arrives invalid is a fact about
    # the source and the DAG should decide what to do with it.
    warning(nm, ": ", sum(!st_is_valid(x)), " invalid geometry(ies) in source")
  }

  if (file.exists(dst)) file.remove(dst)
  st_write(x, dst, driver = "GeoJSON", quiet = TRUE)

  message(sprintf("%-16s %5.1f MB -> %5.1f MB  %s", nm,
                  file.info(src)$size / 1024^2,
                  file.info(dst)$size / 1024^2,
                  basename(dst)))
}

message("\nMirrored ", length(LAYERS), " stormwater layers to ", OUT)
