# R/layers.R
#
# Delivery geometry for the hazard-page and district map overlays.
#
# WHY GEOJSON AND NOT PMTILES
#
# The registry marked four of these `blocked_on_data` while their data sat
# built in the target store, and the obvious fix looked like "tile them the way
# stormwater is tiled". Measured first, and tiling is the wrong answer for
# every one of them:
#
#   surge_current        361 exposed tracts      111 KB simplified
#   hurricane_evac_zones 6 polygons, Queens      157 KB simplified
#   evacuation_centers   60 points                12 KB
#   cooling_centers      476 points              102 KB
#   resources          3,905 points              ~350 KB
#
# All are smaller than cdta.geojson, which the entry screen already blocks on
# at 129 KB. PMTiles earns its keep on the stormwater layers because they are
# 20 MB and 38 MB of source geometry; here it would add a tippecanoe step, a
# data-v* release round trip and a second delivery mechanism to save nothing.
#
# The stormwater separation stands and is unaffected: the DAG still never runs
# tippecanoe. These are written directly because they are small enough to be.
#
# DISPLAY LAYERS ARE QUEENS-SCOPED
#
# "Compute citywide, display Queens" governs computation - every index and
# every gap is computed across all 59 CDTAs so comparisons are citywide. These
# are delivery geometry for a Queens map, so they ship Queens-only. Clipping
# the evacuation zones takes them from 876 KB to 157 KB.
#
# cdta.geojson is the deliberate exception and stays citywide, because it backs
# the client-side point-in-polygon after geocoding and a user can geocode an
# address outside Queens.

LAYER_SIMPLIFY_KEEP <- 0.10

# No single overlay should cost more than the boundary file the entry screen
# already waits on. Asserted per layer so a future upstream revision cannot
# quietly ship a multi-megabyte overlay.
LAYER_MAX_BYTES <- 600 * 1024

# The one writer. Every layer goes through it so precision, winding, the
# RFC 7946 crs rule and the size ceiling are decided once.
write_layer_geojson <- function(x, path, keep = NULL, clip = NULL) {
  x <- sf::st_transform(x, 4326)

  if (!is.null(clip)) {
    x <- suppressWarnings(sf::st_intersection(sf::st_make_valid(x), clip))
    x <- x[!sf::st_is_empty(sf::st_geometry(x)), , drop = FALSE]
  }
  if (!is.null(keep)) {
    x <- rmapshaper::ms_simplify(x, keep = keep, keep_shapes = TRUE)
  }

  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  if (file.exists(path)) file.remove(path)
  sf::st_write(x, path, driver = "GeoJSON", quiet = TRUE,
               layer_options = c("COORDINATE_PRECISION=6", "RFC7946=YES"))
  path
}

# The Queens outline every display layer is clipped to.
queens_outline <- function(cdta_boundaries) {
  cdta_boundaries |>
    dplyr::filter(grepl("^QN", CDTA2020)) |>
    sf::st_transform(4326) |>
    sf::st_union()
}

# --- context layers ---------------------------------------------------------

# Hurricane evacuation zones 1-6. Clipped to Queens: citywide these are 3 MB of
# coastal detail for six polygons.
layer_hurricane_evac_zones <- function(evac_zones, qn, path) {
  evac_zones |>
    dplyr::transmute(zone = as.integer(zone)) |>
    write_layer_geojson(path, keep = LAYER_SIMPLIFY_KEEP, clip = qn)
}

# Present-day storm surge, from the Flood Vulnerability Index's ss_cur column.
#
# NULL means "not exposed", not "missing" - only 361 of 2,208 tracts carry a
# value, and the layer is the exposed set. Dropping the NULLs is what makes
# this a 111 KB overlay rather than a citywide choropleth of mostly-absent
# data, and it is also the correct reading of the column.
layer_surge_current <- function(fvi, qn, path) {
  fvi |>
    dplyr::filter(!is.na(ss_cur)) |>
    dplyr::transmute(geoid, ss_cur = as.integer(ss_cur)) |>
    write_layer_geojson(path, keep = LAYER_SIMPLIFY_KEEP, clip = qn)
}

# --- resource layers --------------------------------------------------------

# Hurricane evacuation centres. `accessible` is carried because it is the one
# attribute that changes whether a given person can use one.
layer_evacuation_centers <- function(evac_centers, qn, path) {
  evac_centers |>
    dplyr::transmute(name = display_case(bldg_name),
                     address = display_case(bldg_add),
                     accessible = accessible) |>
    write_layer_geojson(path, clip = qn)
}

# Year-round indoor cool options, NOT emergency cooling centres - those open
# only during a declared heat emergency and cannot be a standing layer. See
# METHODOLOGY.md.
layer_cooling_centers <- function(cool_options, qn, path) {
  cool_options |>
    dplyr::transmute(name = display_case(Facility_name),
                     location_type = Location_type,
                     accessible = Accessible) |>
    write_layer_geojson(path, clip = qn)
}

# Every resource as a map point, with MINIMAL properties.
#
# This is the file PIPELINE_DESIGN.md section 3 called resources.pmtiles. It was
# dropped without a decision record, and the consequence was that screen 04 had
# to load resources/<slug>.json - up to 248 KB of mission statements, referral
# policies and contact details - to draw dots on a map.
#
# ONE FILE PER DISTRICT, not one for Queens.
#
# A Queens-wide file was written first and measured 1,190 KB - the per-layer
# ceiling caught it. The size is structural rather than fixable by trimming
# properties: 3,905 features carry ~390 KB of GeoJSON scaffolding before any
# attribute, and the resource_id alone is 38 characters x 3,905.
#
# Per-district is also simply the right shape. Screen 04 is a DISTRICT map; it
# never needs another district's points, and the largest district file is
# around 85 KB against 1.19 MB for the lot. The earlier argument for one cached
# file assumed people move between districts often enough to amortise it, which
# is a guess, against a cost that is measured.
#
# `category` is the toggle key per B4; `source` and `is_coad_member` ride along
# as secondary filters so FRANC and directory records stay distinguishable
# without a second file.
layer_resources <- function(res_cdta, crosswalk, dir) {
  shipped <- crosswalk |> dplyr::filter(boro_code == 4)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  vapply(seq_len(nrow(shipped)), function(i) {
    row <- shipped[i, ]
    res_cdta |>
      dplyr::filter(cdta2020 == row$cdta2020, !is.na(lon), !is.na(lat)) |>
      dplyr::transmute(
        resource_id, name,
        category = canonical_category,
        source,
        is_coad_member = as.logical(is_coad_member),
        lon, lat
      ) |>
      sf::st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE) |>
      dplyr::select(-lon, -lat) |>
      write_layer_geojson(file.path(dir, paste0(row$slug, ".geojson")))
  }, character(1))
}

# --- validation -------------------------------------------------------------

validate_layer_geojson <- function(paths, registry) {
  for (p in paths) {
    if (!file.exists(p)) stop("Layer GeoJSON missing: ", p)

    size <- file.info(p)$size
    if (size > LAYER_MAX_BYTES) {
      stop(basename(p), " is ", round(size / 1024), " KB, over the ",
           round(LAYER_MAX_BYTES / 1024), " KB per-layer ceiling. Simplify ",
           "further, clip tighter, or move it to PMTiles - but decide, rather ",
           "than shipping an overlay heavier than the basemap.")
    }

    # An empty FeatureCollection is the failure that looks like success: the
    # file exists, the fetch succeeds, and the map renders nothing. Most likely
    # cause is a clip against the wrong CRS.
    txt <- paste(readLines(p, n = 40, warn = FALSE), collapse = " ")
    if (!grepl('"features"', txt, fixed = TRUE) ||
        grepl('"features"\\s*:\\s*\\[\\s*\\]', txt)) {
      stop(basename(p), " has no features. A layer that fetches cleanly and ",
           "draws nothing is worse than one that 404s.")
    }
    if (grepl('"crs"', txt, fixed = TRUE)) {
      stop(basename(p), " carries a `crs` member - RFC 7946 removed it.")
    }
  }

  # Every registry row marked available with geojson delivery must have a file,
  # the same assertion validate_layer_tiles() makes for pmtiles.
  expected <- registry |>
    dplyr::filter(status == "available", delivery == "geojson") |>
    dplyr::pull(layer_id)

  # A per-district layer lives in layers/<layer_id>/<slug>.geojson, so its id
  # is the parent directory. A citywide one is layers/<layer_id>.geojson.
  produced <- unique(ifelse(
    basename(dirname(paths)) == "layers",
    sub("\\.geojson$", "", basename(paths)),
    basename(dirname(paths))
  ))
  missing <- setdiff(expected, produced)
  if (length(missing) > 0) {
    stop("Registry marks these geojson layers available but no file exists: ",
         paste(missing, collapse = ", "))
  }
  TRUE
}
