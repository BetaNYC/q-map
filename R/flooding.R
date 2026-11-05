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

# --- FEMA flood zones -------------------------------------------------------
#
# The FEMA National Flood Hazard Layer (NFHL), flood hazard areas (MapServer
# layer 28), for the display layer `fema_flood_zones`. Display only: nothing
# ranks or scores on it.
#
# WHICH MAP. NYC's EFFECTIVE flood insurance rate map, dated 2007-09-05 on
# every panel (DFIRM 360497, checked 2026-11-05), plus the Letters of Map
# Revision since. NOT the 2015 Preliminary FIRM the city's building code
# uses. Anything that labels this layer must say "2007", or a reader takes a
# 19-year-old map as current. See METHODOLOGY.md.
#
# TIER 2. FEMA's service reset the connection five times in one Queens fetch
# (2026-11-05). scripts/10_mirror_fema.R fetches it once, with retries, and
# publishes two assets in the data-v* release:
#
#   fema_nfhl_queens.geojson   the raw download, checked here in the DAG
#   fema_flood_zones.pmtiles   the map layer, copied through like stormwater
#
# The script and this check share NFHL_ZONE_CLASSES below, so the tiles
# cannot classify a zone the check does not know.

# Every (FLD_ZONE, ZONE_SUBTY) pair the Queens download carries, and the
# display class it becomes. NA means dropped: unshaded X is "minimal flood
# hazard" (most of the borough), and open water is not land anyone lives on.
#
#   VE      1% annual chance, coastal high hazard (wave action over 3 ft)
#   AE      1% annual chance. A (no base flood elevation, 2 features) and the
#           AE floodway (7) are folded in: both are inside the 1% floodplain
#           and neither is a coastal distinction a resident needs.
#   0.2PCT  0.2% annual chance ("500-year"), FEMA's shaded X
#
# The pairs are listed exactly so validate_nfhl() can compare them both ways
# (d26's validate_nfhl idiom). A zone type FEMA adds in a future re-mirror -
# AO, AH, a new subtype - fails the check instead of silently vanishing from
# the map.
NFHL_ZONE_CLASSES <- tibble::tribble(
  ~FLD_ZONE,    ~ZONE_SUBTY,                          ~zone,
  "VE",         NA,                                   "VE",
  "AE",         NA,                                   "AE",
  "AE",         "FLOODWAY",                           "AE",
  "A",          NA,                                   "AE",
  "X",          "0.2 PCT ANNUAL CHANCE FLOOD HAZARD", "0.2PCT",
  "X",          "AREA OF MINIMAL FLOOD HAZARD",       NA,
  "OPEN WATER", NA,                                   NA
)

# The display order, most to least severe. The legend and the paint
# expression read the same order.
NFHL_ZONES <- c("VE", "AE", "0.2PCT")

# NYC's DFIRM. The download's bounding box also catches Nassau County
# (36059C), which the mirror drops before tiling.
NFHL_NYC_DFIRM <- "360497"

# Add the display class. Empty-string subtypes are read as NA first: ArcGIS
# serves a missing ZONE_SUBTY as either, depending on the format.
classify_nfhl <- function(x) {
  x |>
    dplyr::mutate(ZONE_SUBTY = dplyr::na_if(trimws(ZONE_SUBTY), "")) |>
    dplyr::left_join(NFHL_ZONE_CLASSES, by = c("FLD_ZONE", "ZONE_SUBTY"))
}

validate_nfhl <- function(x) {
  required <- c("DFIRM_ID", "FLD_ZONE", "ZONE_SUBTY")
  missing <- setdiff(required, names(x))
  if (length(missing) > 0) {
    stop("NFHL mirror: missing column(s) ", paste(missing, collapse = ", "))
  }

  # Two-way: a pair in the data with no class, or a class that no longer
  # occurs. The second direction is the one that notices FEMA restructuring
  # the layer.
  observed <- x |>
    sf::st_drop_geometry() |>
    dplyr::mutate(ZONE_SUBTY = dplyr::na_if(trimws(ZONE_SUBTY), "")) |>
    dplyr::distinct(FLD_ZONE, ZONE_SUBTY)
  assert_keys_match(observed, dplyr::select(NFHL_ZONE_CLASSES, -zone),
                    by = c("FLD_ZONE", "ZONE_SUBTY"),
                    label_x = "fema_nfhl_queens.geojson",
                    label_y = "NFHL_ZONE_CLASSES")

  if (!NFHL_NYC_DFIRM %in% x$DFIRM_ID) {
    stop("NFHL mirror: no features from NYC's DFIRM ", NFHL_NYC_DFIRM,
         ". The bounding box or the service has changed.")
  }

  # Every display class must be present in NYC's part, or the legend shows a
  # class the map never draws.
  nyc <- classify_nfhl(sf::st_drop_geometry(x)) |>
    dplyr::filter(DFIRM_ID == NFHL_NYC_DFIRM, !is.na(zone))
  absent <- setdiff(NFHL_ZONES, nyc$zone)
  if (length(absent) > 0) {
    stop("NFHL mirror: no NYC features in class(es) ",
         paste(absent, collapse = ", "))
  }
  TRUE
}
