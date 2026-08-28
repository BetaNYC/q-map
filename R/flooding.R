# R/flooding.R
#
# NYC DEP stormwater flood extents - the "heavy rain" hazard measure.
#
# The layers arrive as Tier-2 mirrors in data/prepared/, published in the
# data-v* Release and rehydrated in CI. The mirror strips Z values but
# deliberately leaves invalid geometry alone, so the repair happens here where
# it is attributable to a target.

# Flooding_C is the flood-depth category. The values are not self-describing;
# these definitions come from the QGIS metadata sidecar shipped with the DEP
# source.
#
# q-map's heavy-rain measure unions BOTH categories, so the published
# percentage includes nuisance ponding as well as deep flooding. Decided
# 2026-08-28; see METHODOLOGY.md.
FLOODING_CATEGORIES <- c(
  `1` = "nuisance",         # ponding >= 4 in and < 1 ft
  `2` = "deep_contiguous"   # ponding >= 1 ft
)

# Read a mirrored stormwater layer and repair its geometry.
#
# Both DEP layers arrive invalid - two enormous multipart polygons each, with
# self-intersections inherited from the geodatabase. st_make_valid() is applied
# here rather than in the mirror because it is a repair that can move vertices,
# and that should be visible as a pipeline step rather than baked into an
# immutable Release asset.
get_stormwater <- function(path) {
  read_sf(path) |> st_make_valid()
}

validate_stormwater <- function(x, label) {
  assert_crs(x, 2263)
  assert_row_count(x, min = 2, max = 2)
  assert_no_na(x, "Flooding_C")
  assert_valid_geom(x)

  # An upstream change to the category scheme would silently redefine what the
  # heavy-rain percentage measures. Fail instead.
  unexpected <- setdiff(as.character(x$Flooding_C), names(FLOODING_CATEGORIES))
  if (length(unexpected) > 0) {
    stop(paste0(
      label, ": unexpected Flooding_C value(s) ",
      paste(unexpected, collapse = ", "),
      " - expected only ", paste(names(FLOODING_CATEGORIES), collapse = ", ")
    ))
  }

  # The mirror strips Z; if it reappears the mirror was bypassed.
  dims <- colnames(st_coordinates(x))
  if (any(c("Z", "M") %in% dims)) {
    stop(label, ": Z or M values present - was the mirror script skipped?")
  }

  TRUE
}

# Percent of each CDTA's area covered by a flood layer.
#
# Unions the layer first so overlapping categories are not double-counted, then
# intersects per district. Returns one row per CDTA including explicit zeros:
# a district with no flooding must appear as 0, not be dropped, or it silently
# becomes NA in the district payload. Same reasoning as d26's swf_per_zcta().
stormwater_pct_per_cdta <- function(cdta, stormwater) {
  u <- st_union(stormwater)
  area <- as.numeric(st_area(cdta))

  pct <- vapply(seq_len(nrow(cdta)), function(i) {
    g <- suppressWarnings(st_intersection(st_geometry(cdta)[i], u))
    if (length(g) == 0) 0 else as.numeric(sum(st_area(g))) / area[i] * 100
  }, numeric(1))

  tibble::tibble(cdta2020 = cdta$CDTA2020, pct_area = pct)
}
