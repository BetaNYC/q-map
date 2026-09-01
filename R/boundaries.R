# R/boundaries.R
#
# District boundaries and the entry-screen index.
#
# Produces two artifacts:
#   data/processed/cdta.geojson   59 simplified polygons, minimal properties
#   data/processed/districts.json 59-row index - picker, map, point-in-polygon
#
# Analysis happens in EPSG:2263 (NY Long Island, ftUS); everything is
# reprojected to EPSG:4326 at the delivery boundary only.

ANALYSIS_CRS <- 2263
DELIVERY_CRS <- 4326

# The unsimplified citywide CDTA layer is ~5.3 MB, which is unshippable for a
# file the entry screen blocks on. keep = 0.05 retains 5% of vertices.
#
# rmapshaper builds topology before simplifying, so shared borders between
# adjacent districts are simplified identically and do not pull apart. That is
# the property validate_cdta_simplified() checks rather than assumes.
SIMPLIFY_KEEP <- 0.05

# Hard ceiling on the delivered GeoJSON. Asserted so a future keep= change, or
# an upstream boundary revision, cannot silently reintroduce a multi-megabyte
# download on the entry screen.
GEOJSON_MAX_BYTES <- 600 * 1024

simplify_cdta <- function(cdta, keep = SIMPLIFY_KEEP) {
  cdta |>
    st_transform(ANALYSIS_CRS) |>
    # keep_shapes = TRUE guarantees no polygon is dropped entirely; explode =
    # FALSE keeps multipart districts (the Rockaways, Broad Channel) as one
    # feature so the count stays at 59.
    rmapshaper::ms_simplify(keep = keep, keep_shapes = TRUE, explode = FALSE) |>
    st_make_valid()
}

# Minimum shared border, in feet, for two districts to count as real
# neighbours whose adjacency simplification must preserve.
#
# Measured on the real citywide layer: of 104 touching pairs, the median shares
# 5,977 ft of border and the 10th percentile shares 330 ft. Eight pairs share
# under 100 ft. Those short ones are all cross-river - BX08-MN12 (11 ft),
# MN08-QN01 (12 ft), BK01-MN03 (143 ft) - artifacts of where the borough line
# falls in the East and Harlem Rivers, not borders anyone can walk across.
# Simplification legitimately pulls those apart and nobody will ever see it.
# 250 ft sits in the empty band between the artifacts (<=143) and the real
# borders (>=330).
MIN_SHARED_BORDER_FT <- 250

# Which districts share a border, as a comparable set of pairs.
#
# ids is passed explicitly rather than read off a column. An earlier version
# took x$cdta2020 from the sf object, which silently resolved to NULL because
# the DCP layer spells it CDTA2020 - so the whole check compared empty sets and
# passed no matter what simplification did to the geometry.
adjacency_pairs <- function(x, ids) {
  stopifnot(length(ids) == nrow(x), !anyNA(ids))
  touches <- st_touches(x)
  pairs <- unlist(lapply(seq_along(touches), function(i) {
    if (length(touches[[i]]) == 0) return(character(0))
    paste(pmin(ids[i], ids[touches[[i]]]),
          pmax(ids[i], ids[touches[[i]]]),
          sep = "-")
  }))
  sort(unique(pairs))
}

# Adjacent pairs sharing a border long enough to be worth defending. Requires a
# projected CRS - lengths are in the CRS's units.
substantial_adjacency <- function(x, ids, min_ft = MIN_SHARED_BORDER_FT) {
  stopifnot(length(ids) == nrow(x), !anyNA(ids))
  touches <- st_touches(x)
  geom <- st_geometry(x)
  out <- character(0)
  for (i in seq_along(touches)) {
    for (j in touches[[i]]) {
      if (i >= j) next
      shared <- suppressWarnings(st_intersection(geom[i], geom[j]))
      len <- if (length(shared) == 0) 0 else sum(as.numeric(st_length(shared)))
      if (isTRUE(len >= min_ft)) {
        out <- c(out, paste(pmin(ids[i], ids[j]), pmax(ids[i], ids[j]), sep = "-"))
      }
    }
  }
  sort(unique(out))
}

# Shipped geometry carries only what the map needs to join on. Every other
# attribute lives in districts.json and is attached client-side via
# setFeatureState, which keeps the tile payload small.
write_cdta_geojson <- function(cdta_simplified, crosswalk, path) {
  out <- cdta_simplified |>
    st_transform(DELIVERY_CRS) |>
    select(cdta2020 = CDTA2020) |>
    left_join(select(crosswalk, cdta2020, slug), by = "cdta2020") |>
    select(cdta2020, slug) |>
    arrange(cdta2020)

  if (file.exists(path)) file.remove(path)
  # RFC7946=YES drops the `crs` member GDAL otherwise writes. RFC 7946 removed
  # crs entirely - GeoJSON is WGS84 lon/lat by definition - so publishing one is
  # a pre-2016 artifact that MapLibre ignores and some validators warn on. The
  # flag also enforces right-hand-rule winding, which is what tippecanoe and
  # MapLibre want anyway. The explicit COORDINATE_PRECISION still wins.
  st_write(out, path, driver = "GeoJSON", quiet = TRUE,
           layer_options = c("COORDINATE_PRECISION=6", "RFC7946=YES"))
  path
}

# Build the entry-screen index.
#
# All 59 CDTAs, not just Queens: the index drives the citywide map and the
# client-side point-in-polygon that runs after geocoding, and a user can
# geocode an address outside Queens. Districts outside Queens resolve to a row
# that the app can then decline to route to, which is a better failure than no
# match at all.
build_districts_index <- function(cdta_simplified, crosswalk) {
  geom <- cdta_simplified |> st_transform(DELIVERY_CRS)

  # point_on_surface, not centroid. QN14 (the Rockaways) is a long curved
  # peninsula and QN07 wraps around water; a true centroid falls outside the
  # polygon for both, which would put the map marker and the "zoom to district"
  # target in Jamaica Bay. point_on_surface is guaranteed inside.
  pos <- suppressWarnings(st_point_on_surface(geom))
  coords <- st_coordinates(pos)

  bboxes <- lapply(st_geometry(geom), function(g) {
    b <- st_bbox(g)
    unname(round(as.numeric(b[c("xmin", "ymin", "xmax", "ymax")]), 6))
  })

  tibble::tibble(
    cdta2020 = geom$CDTA2020,
    point_on_surface = lapply(seq_len(nrow(coords)), function(i) {
      unname(round(as.numeric(coords[i, c("X", "Y")]), 6))
    }),
    bbox = bboxes
  ) |>
    left_join(crosswalk, by = "cdta2020") |>
    transmute(
      cdta2020, slug, display_name, cd_label,
      boro = boro_name,
      point_on_surface, bbox,
      coad
    ) |>
    arrange(cdta2020)
}

write_districts_json <- function(districts, path) {
  jsonlite::write_json(
    districts, path,
    auto_unbox = TRUE,   # scalars as values, not 1-element arrays
    digits = NA,         # coordinates already rounded; do not re-round
    null = "null",
    na = "null"          # coad is null for 58 of 59 - emit null, not absent
  )
  path
}

# --- validation ------------------------------------------------------------

validate_cdta_boundaries <- function(cdta) {
  assert_row_count(cdta, min = 59, max = 59)
  assert_crs(cdta, DELIVERY_CRS)
  assert_valid_geom(cdta)
  assert_no_na(cdta, "CDTA2020")
  TRUE
}

validate_cdta_simplified <- function(cdta_simplified, cdta) {
  assert_row_count(cdta_simplified, min = 59, max = 59)
  assert_crs(cdta_simplified, ANALYSIS_CRS)
  assert_valid_geom(cdta_simplified)

  # keep_shapes should make this impossible, but an empty geometry here would
  # produce a district with no map presence and no obvious error downstream.
  empty <- cdta_simplified$CDTA2020[st_is_empty(cdta_simplified)]
  if (length(empty) > 0) {
    stop(paste0(
      length(empty), " district(s) simplified to empty geometry: ",
      paste(empty, collapse = ", ")
    ))
  }

  # The failure mode that matters: simplification pulling shared borders apart,
  # leaving hairline gaps between neighbours. Invisible in a row count and easy
  # to miss by eye at low zoom. Every pair of districts that touched before must
  # still touch.
  # Pairs with a real shared border before; any remaining contact after.
  before <- substantial_adjacency(st_transform(cdta, ANALYSIS_CRS), cdta$CDTA2020)
  after <- adjacency_pairs(cdta_simplified, cdta_simplified$CDTA2020)

  # A vacuous comparison is the failure this check is most likely to suffer, so
  # assert it found something before trusting that it found nothing wrong.
  if (length(before) < 90) {
    stop(paste0(
      "Adjacency check found only ", length(before),
      " substantially-bordering district pairs, expected ~94 - the check is not working"
    ))
  }

  lost <- setdiff(before, after)
  if (length(lost) > 0) {
    stop(paste0(
      length(lost), " of ", length(before),
      " adjacent district pair(s) separated by simplification: ",
      paste(head(lost, 5), collapse = ", "),
      if (length(lost) > 5) ", ..." else ""
    ))
  }

  # Area is not preserved exactly by Visvalingam simplification, but a large
  # move means keep= is too aggressive for this geometry.
  area_before <- as.numeric(sum(st_area(st_transform(cdta, ANALYSIS_CRS))))
  area_after <- as.numeric(sum(st_area(cdta_simplified)))
  drift <- abs(area_after - area_before) / area_before
  if (drift > 0.02) {
    stop(paste0(
      "Total area moved ", round(drift * 100, 2),
      "% under simplification, expected under 2%"
    ))
  }

  TRUE
}

validate_cdta_geojson <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) stop(paste0("GeoJSON not written: ", path))

  # RFC 7946 has no `crs` member. Asserted rather than trusted because it comes
  # back the moment someone drops RFC7946=YES from the layer_options, and it is
  # invisible in every other check.
  if (any(grepl('"crs"', readLines(path, n = 3, warn = FALSE), fixed = TRUE))) {
    stop("cdta.geojson carries a `crs` member - RFC 7946 removed it. ",
         "Check RFC7946=YES is still in write_cdta_geojson()'s layer_options.")
  }
  if (size > GEOJSON_MAX_BYTES) {
    stop(paste0(
      "cdta.geojson is ", round(size / 1024), " KB, over the ",
      round(GEOJSON_MAX_BYTES / 1024), " KB ceiling - ",
      "the entry screen blocks on this file"
    ))
  }
  g <- read_sf(path)
  assert_row_count(g, min = 59, max = 59)
  assert_crs(g, DELIVERY_CRS)
  assert_no_na(g, c("cdta2020", "slug"))
  assert_unique(g, "cdta2020")
  TRUE
}

validate_districts <- function(districts, crosswalk, cdta_simplified) {
  assert_row_count(districts, min = 59, max = 59)

  # Every field the wireframe renders unconditionally must be non-null. coad is
  # deliberately excluded: null is its normal value in 58 of 59 districts.
  assert_no_na(districts, c(
    "cdta2020", "slug", "display_name", "cd_label", "boro"
  ))
  assert_unique(districts, "cdta2020")
  assert_unique(districts, "slug")

  # The index must cover exactly the crosswalk, both directions.
  assert_keys_match(
    districts, crosswalk, by = "cdta2020",
    label_x = "districts index", label_y = "crosswalk"
  )

  # Every point_on_surface must actually be inside its own district.
  #
  # A bbox containment test is not enough and would give false confidence: the
  # case this defends against is QN14, whose bounding box encloses most of
  # Jamaica Bay. A point in open water there passes a bbox check and still puts
  # the map marker offshore. So test the real geometry.
  poly <- cdta_simplified |>
    st_transform(DELIVERY_CRS) |>
    select(cdta2020 = CDTA2020)
  ord <- match(districts$cdta2020, poly$cdta2020)
  if (anyNA(ord)) {
    stop("districts index references a CDTA absent from the simplified geometry")
  }

  pts <- st_sfc(
    lapply(districts$point_on_surface, function(p) st_point(as.numeric(p))),
    crs = DELIVERY_CRS
  )
  inside <- suppressMessages(
    mapply(function(pt, i) {
      length(st_within(pt, st_geometry(poly)[i])[[1]]) > 0
    }, pts, ord)
  )
  if (!all(inside)) {
    stop(paste0(
      sum(!inside), " district(s) have a point_on_surface outside their own polygon: ",
      paste(districts$cdta2020[!inside], collapse = ", ")
    ))
  }

  # bbox must still be well-formed and contain the point.
  bad_bbox <- vapply(seq_len(nrow(districts)), function(i) {
    b <- districts$bbox[[i]]
    length(b) != 4 || b[1] >= b[3] || b[2] >= b[4]
  }, logical(1))
  if (any(bad_bbox)) {
    stop(paste0(
      sum(bad_bbox), " district(s) have a degenerate bbox: ",
      paste(districts$cdta2020[bad_bbox], collapse = ", ")
    ))
  }

  # FRANC serves the Rockaways and nowhere else, for now. If a second COAD is
  # added this assertion is the reminder to update 4d and the 02 screen.
  coads <- districts$cdta2020[!is.na(districts$coad)]
  if (!identical(coads, "QN14")) {
    stop(paste0(
      "Expected COAD on QN14 only, got: ",
      if (length(coads) == 0) "none" else paste(coads, collapse = ", ")
    ))
  }

  TRUE
}
