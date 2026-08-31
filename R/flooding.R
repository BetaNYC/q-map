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
  # Boundaries arrive in EPSG:4326 for delivery; area and intersection work
  # happens in the analysis CRS, per d26's "analytical work in EPSG:2263,
  # reproject only at the delivery boundary" agreement.
  cdta <- st_transform(cdta, 2263)
  stormwater <- st_transform(stormwater, 2263)

  u <- st_union(stormwater)
  area <- as.numeric(st_area(cdta))

  pct <- vapply(seq_len(nrow(cdta)), function(i) {
    g <- suppressWarnings(st_intersection(st_geometry(cdta)[i], u))
    if (length(g) == 0) 0 else as.numeric(sum(st_area(g))) / area[i] * 100
  }, numeric(1))

  tibble::tibble(cdta2020 = cdta$CDTA2020, pct_area = pct)
}

# Copy a mirrored tile set into the deployable output directory.
#
# The tiles are built by scripts/01_mirror_stormwater.R and published in the
# data-v* release; the DAG only moves them into data/processed/ so everything
# the frontend needs sits under one root. Same reason d26 copied its COGs
# through rather than serving them from the release: release asset URLs
# redirect, which breaks the range requests a tiled format depends on.
copy_layer <- function(src, dest_dir) {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  dst <- file.path(dest_dir, basename(src))
  file.copy(src, dst, overwrite = TRUE)
  dst
}

validate_layer_tiles <- function(paths, registry) {
  for (p in paths) {
    if (!file.exists(p)) stop("Layer tile missing: ", p)
    # PMTiles v3 files begin with the ASCII magic "PMTiles". A truncated or
    # half-written file is otherwise indistinguishable from a valid one until
    # MapLibre fails at runtime.
    magic <- readBin(p, "raw", n = 7)
    if (!identical(rawToChar(magic), "PMTiles")) {
      stop(basename(p), " is not a PMTiles file - magic bytes are ",
           paste(magic, collapse = " "))
    }
    if (file.info(p)$size < 1024) {
      stop(basename(p), " is suspiciously small (", file.info(p)$size, " bytes)")
    }
  }

  # Every layer the registry marks available with pmtiles delivery must have a
  # file, or the hazard pages reference a layer that cannot load.
  expected <- registry |>
    filter(status == "available", delivery == "pmtiles") |>
    pull(layer_id)
  produced <- sub("\\.pmtiles$", "", basename(paths))
  missing <- setdiff(expected, produced)
  if (length(missing) > 0) {
    stop("Registry marks these pmtiles layers available but no tile exists: ",
         paste(missing, collapse = ", "))
  }
  TRUE
}
