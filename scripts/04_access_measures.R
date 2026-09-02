# scripts/04_access_measures.R
#
# Walk-time access measures. Tier-2: runs LOCALLY, once, and publishes a file.
# The DAG never routes anything - it reads data/prepared/access_stats.csv as a
# `format = "file"` target. See ACCESS_MEASURES.md.
#
# Usage:  Rscript scripts/04_access_measures.R
#
# Deliberately plain `Rscript`, NOT `uvr run`. r5r, rJava and a JDK must stay
# out of uvr.toml/uvr.lock, because `uvr sync --frozen` is what CI installs and
# putting them there would drag a JVM and a multi-hundred-MB OSM extract into
# every build.
#
# PREREQUISITES, none of which touch the project library:
#
#   brew install openjdk@21 osmium-tool
#   mkdir -p ~/Library/R/arm64/4.6/library
#   Rscript -e 'install.packages("r5r", lib="~/Library/R/arm64/4.6/library",
#                                repos="https://cloud.r-project.org")'
#
#   data/source/osm/nyc.osm.pbf     Geofabrik NY state, clipped (see below)
#   data/source/census/…            TIGER 2020 blocks + PL population
#
# All of data/source/ is gitignored. Nothing here is committed except this
# script and the CSV it writes.

# --- environment -------------------------------------------------------------

# .Rprofile PREPENDS the uvr library rather than replacing .libPaths(), so the
# personal library is reachable as long as it exists. r5r lives there; the
# project library stays clean and CI never sees it.
.libPaths(c(file.path(Sys.getenv("HOME"), "Library/R/arm64/4.6/library"),
            .libPaths()))

# r5r 2.4.0 requires EXACTLY JDK 21. Its DESCRIPTION says "Java JDK (>= 21.0)"
# and the runtime check in start_r5r_java() rejects anything else - Java 26 was
# refused outright. openjdk@21 is installed keg-only so the system default is
# untouched; this pins JAVA_HOME for this process only, and must run BEFORE
# rJava loads, which is when the JVM location resolves.
JAVA21 <- "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
if (!dir.exists(JAVA21)) {
  stop("JDK 21 not found at ", JAVA21, "\n  brew install openjdk@21")
}
Sys.setenv(JAVA_HOME = JAVA21)
options(java.parameters = "-Xmx16G")   # before the JVM starts; R5 is hungry

suppressMessages({
  library(r5r); library(sf); library(dplyr); library(data.table)
  library(jsonlite)
})

ROOT      <- normalizePath(".")
R5_DIR    <- file.path(ROOT, "data/source/r5")
BLOCKS    <- file.path(ROOT, "data/source/census/nyc_block_origins.rds")
OUT       <- file.path(ROOT, "data/prepared/access_stats.csv")

# A SECOND deliverable the brief does not specify, and without which the first
# cannot be consumed.
#
# access_stats.csv keys on block GEOID and gives walk times. The DAG has no way
# to turn that into a district figure: it needs each block's POPULATION to
# weight by, and its LOCATION to assign to a CDTA. Neither is in the pipeline -
# nothing upstream has ever fetched census blocks.
#
# Emitted as a companion rather than as extra columns on access_stats.csv,
# which would repeat both values four times over (once per facility set) and
# would put the brief's schema out of date.
#
# The spatial assignment itself stays in the DAG, not here: it needs the
# UNSIMPLIFIED CDTA boundaries, and this script deliberately does not depend on
# {targets}.
OUT_BLOCKS <- file.path(ROOT, "data/prepared/block_weights.csv")

WALK_SPEED  <- 3.6    # km/h, r5r default. Changing this changes every number.
THRESHOLDS  <- c(10, 15, 20, 30)
CAP_NEAR    <- 30     # first pass: covers every threshold
CAP_FAR     <- 180    # second pass, only for origins the first pass missed

# --- facility sets ------------------------------------------------------------
#
# Reproduced here rather than referenced, per the brief: this script must be
# runnable without reading pipeline code.
#
# Three traps, each already paid for once:
#   - `ayer-cga7` is NOT the evacuation centres dataset. It is a visualisation
#     asset with zero columns returning 60 empty objects. Use `p5md-weyf`.
#   - Cooling CENTERS open only in a declared heat emergency and cannot be a
#     standing measure. Cool Options is the year-round list.
#   - Cooling TOWERS (y4fw-iqfr) are HVAC equipment tracked for Legionella.
#     Never a facility set here; a pipeline validator fails the build on them.

FACDB <- "https://data.cityofnewyork.us/resource/ji82-xba5.json"
COOL  <- paste0("https://services6.arcgis.com/yG5s3afENB5iO9fj/arcgis/rest/",
                "services/Cool_Options/FeatureServer/0/query")

socrata <- function(where) {
  fromJSON(URLencode(paste0(
    FACDB, "?$select=uid,latitude,longitude&$where=", where, "&$limit=50000")))
}

# FacDB uses 0/0 as a null-coordinate sentinel rather than leaving the field
# empty - 89 Queens records. Routed as-is they land in the Gulf of Guinea.
clean_points <- function(df, id, lon, lat) {
  tibble::tibble(id = as.character(df[[id]]),
                 lon = as.numeric(df[[lon]]),
                 lat = as.numeric(df[[lat]])) |>
    filter(!is.na(lon), !is.na(lat), lon != 0, lat != 0)
}

get_facilities <- function(set) {
  switch(set,
    cool_options_indoor = {
      u <- paste0(COOL, "?where=", URLencode("Space_type='Cooling Center'",
                                             reserved = TRUE),
                  "&outFields=*&f=geojson&outSR=4326&resultRecordCount=5000")
      g <- st_read(u, quiet = TRUE)
      xy <- st_coordinates(st_geometry(g))
      tibble::tibble(id = as.character(seq_len(nrow(g))),
                     lon = xy[, 1], lat = xy[, 2]) |>
        filter(!is.na(lon), !is.na(lat), lon != 0, lat != 0)
    },
    parks      = clean_points(socrata("facgroup='PARKS AND PLAZAS'"),
                              "uid", "longitude", "latitude"),
    hospitals  = clean_points(socrata("facsubgrp='HOSPITALS AND CLINICS'"),
                              "uid", "longitude", "latitude"),
    evacuation_centers = {
      # Geometry arrives as `the_geom`, a GeoJSON Point object per row - not a
      # flat lat/lon pair like FacDB.
      d <- fromJSON("https://data.cityofnewyork.us/resource/p5md-weyf.json?$limit=5000",
                    simplifyVector = FALSE)
      clean_points(
        data.frame(
          id  = seq_along(d),
          lon = vapply(d, function(r) as.numeric(r$the_geom$coordinates[[1]]), numeric(1)),
          lat = vapply(d, function(r) as.numeric(r$the_geom$coordinates[[2]]), numeric(1))),
        "id", "lon", "lat")
    },
    stop("unknown facility set: ", set))
}

SETS <- c("cool_options_indoor", "parks", "evacuation_centers", "hospitals")

# --- routing ------------------------------------------------------------------

# r5r 2.4.0's travel_time_matrix() returns from_id = the DESTINATION and
# to_id = the ORIGIN. The columns are swapped relative to the argument names.
#
# This is the highest-consequence trap in the whole step. Grouping by `from_id`
# and taking a minimum - the obvious reading - computes minutes to the nearest
# BLOCK for each facility instead of minutes to the nearest facility for each
# block. Right column names, right value range, right row count, entirely wrong
# file. Nothing errors.
#
# So the origin column is identified by CONTENT, never by name, and asserted.
# A future r5r that fixes or re-reverses this cannot silently flip the result.
origin_column <- function(ttm, origin_ids) {
  hits <- vapply(c("from_id", "to_id"),
                 function(cl) mean(as.character(ttm[[cl]]) %in% origin_ids),
                 numeric(1))
  if (max(hits) < 0.99) {
    stop("neither travel_time_matrix column holds the origin ids ",
         "(from_id ", round(100 * hits[1]), "%, to_id ", round(100 * hits[2]),
         "%). The output shape has changed; do not trust the column names.")
  }
  if (min(hits) > 0.99) {
    stop("both columns look like origin ids - cannot disambiguate.")
  }
  names(hits)[which.max(hits)]
}

nearest_minutes <- function(core, origins, dests, cap) {
  ttm <- travel_time_matrix(core, origins = origins, destinations = dests,
                            mode = "WALK", max_trip_duration = cap,
                            walk_speed = WALK_SPEED, progress = FALSE)
  if (nrow(ttm) == 0) {
    return(tibble::tibble(geoid = character(), minutes = numeric(),
                          nearest_id = character()))
  }
  ocol <- origin_column(ttm, origins$id)
  dcol <- setdiff(c("from_id", "to_id"), ocol)

  setDT(ttm)
  ttm[, .SD[which.min(travel_time_p50)], by = c(ocol)] |>
    as_tibble() |>
    transmute(geoid = as.character(.data[[ocol]]),
              minutes = as.numeric(travel_time_p50),
              nearest_id = as.character(.data[[dcol]]))
}

# --- run ----------------------------------------------------------------------

blocks <- readRDS(BLOCKS)
origins <- blocks |> transmute(id = geoid, lon, lat)
cat(sprintf("origins: %s populated blocks, %s residents\n\n",
            format(nrow(origins), big.mark = ","),
            format(sum(blocks$pop), big.mark = ",")))

core <- build_network(R5_DIR, verbose = FALSE)

results <- list()
checks  <- list()

for (set in SETS) {
  f <- get_facilities(set)
  cat(sprintf("%-20s %5d facilities  ", set, nrow(f)))

  t0 <- Sys.time()
  near <- nearest_minutes(core, origins, f, CAP_NEAR)

  # Second pass, bounded: only the origins with nothing inside CAP_NEAR. For a
  # 60-centre citywide set that is most of the city, and leaving them NA would
  # bias access_mean downward by dropping exactly the worst-served blocks.
  missed <- setdiff(origins$id, near$geoid)
  if (length(missed) > 0) {
    far <- nearest_minutes(core, filter(origins, id %in% missed), f, CAP_FAR)
    near <- bind_rows(near, far)
  }

  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("%6.1fs  resolved %s of %s\n", el,
              format(nrow(near), big.mark = ","),
              format(nrow(origins), big.mark = ",")))

  results[[set]] <- origins |>
    transmute(geoid = id) |>
    left_join(near, by = "geoid") |>
    transmute(
      geoid, facility_set = set,
      minutes_to_nearest = minutes,
      within_10 = !is.na(minutes) & minutes <= 10,
      within_15 = !is.na(minutes) & minutes <= 15,
      within_20 = !is.na(minutes) & minutes <= 20,
      within_30 = !is.na(minutes) & minutes <= 30,
      nearest_id = nearest_id
    )
  checks[[set]] <- f
}

stop_r5(core)

# --- the sanity check the brief requires --------------------------------------
#
# A network walk must be LONGER than the straight line to the same facility,
# typically by 20-40%. At or below 1.0x means a broken graph - usually a CRS
# mismatch or an extract that does not cover the study area - and it fails by
# producing plausible small numbers rather than an error.

cat("\n--- network vs straight line, to the SAME nearest facility ---\n")
ratio_rows <- list()
for (set in SETS) {
  r <- results[[set]] |> filter(!is.na(minutes_to_nearest), minutes_to_nearest > 0)
  f <- checks[[set]]
  o <- blocks |> transmute(geoid, lon, lat) |> inner_join(r, by = "geoid")

  po <- st_as_sf(o, coords = c("lon", "lat"), crs = 4326) |> st_transform(2263)
  pf <- st_as_sf(f, coords = c("lon", "lat"), crs = 4326) |> st_transform(2263)
  idx <- match(o$nearest_id, f$id)
  d_ft <- as.numeric(st_distance(po, pf[idx, ], by_element = TRUE))
  euclid_min <- (d_ft * 0.0003048) / WALK_SPEED * 60      # ft -> km -> minutes

  # r5r returns INTEGER minutes, so at short distances rounding dominates the
  # comparison: a 140 m walk is 2.3 min but reports as 2, and against a 2.3 min
  # straight line it looks faster. Measured on parks, the sub-1x rate falls
  # monotonically with distance - 36% at 1 min, 4% at 3 min, 0.05% at 11-20,
  # zero above 20 - which is the signature of rounding. A broken graph would be
  # distance-independent.
  #
  # So the distribution is reported over everything, but the PASS/FAIL band is
  # the rounding-immune one: beyond 5 minutes, one minute of granularity is
  # under 20% of the value and cannot flip the comparison.
  ok <- euclid_min > 0
  ratio <- o$minutes_to_nearest[ok] / euclid_min[ok]
  far <- ok & o$minutes_to_nearest > 5
  ratio_far <- o$minutes_to_nearest[far] / euclid_min[far]

  q <- quantile(ratio, c(0.25, 0.5, 0.75), na.rm = TRUE)
  ratio_rows[[set]] <- data.frame(
    set = set, n = length(ratio),
    p25 = round(q[[1]], 2), median = round(q[[2]], 2), p75 = round(q[[3]], 2),
    below_1x_all = sprintf("%.2f%%", 100 * mean(ratio < 1)),
    below_1x_over5min = sprintf("%.2f%%", 100 * mean(ratio_far < 1)))
}
print(do.call(rbind, ratio_rows), row.names = FALSE)
cat("\nPASS band is `below_1x_over5min`; the all-distance column is inflated\n",
    "by one-minute rounding at short range and is reported for completeness.\n")

worst <- max(vapply(ratio_rows,
                    function(x) as.numeric(sub("%", "", x$below_1x_over5min)),
                    numeric(1)))
if (worst > 1) {
  stop("more than 1% of blocks beyond 5 minutes route FASTER than the straight ",
       "line. That is not rounding - check the OSM extract covers the study ",
       "area and that no CRS was mixed.")
}
cat(sprintf("sanity check PASSED - worst set has %.2f%% sub-1x beyond 5 min\n", worst))

# --- write --------------------------------------------------------------------

out <- bind_rows(results) |> select(-nearest_id)
stopifnot(all(nchar(out$geoid) == 15),
          nrow(out) == nrow(origins) * length(SETS))

dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
# geoid is a 15-digit identifier and MUST be read back as character. A naive
# fread()/read.csv() parses it as a number - at 15 significant digits that is
# at the edge of double precision, and any leading zero would be lost outright.
# ACCESS_MEASURES.md specifies `character`; the pipeline side must say so.
data.table::fwrite(out, OUT)
cat(sprintf("\nwrote %s\n  %s rows, %s blocks x %d facility sets\n",
            OUT, format(nrow(out), big.mark = ","),
            format(nrow(origins), big.mark = ","), length(SETS)))

data.table::fwrite(
  blocks |> transmute(geoid, pop, lon, lat), OUT_BLOCKS)
cat(sprintf("wrote %s\n  %s blocks, %s residents\n",
            OUT_BLOCKS, format(nrow(blocks), big.mark = ","),
            format(sum(blocks$pop), big.mark = ",")))

print(out |> group_by(facility_set) |>
        summarise(median_min = round(median(minutes_to_nearest, na.rm = TRUE), 1),
                  within_15 = sprintf("%.1f%%", 100 * mean(within_15)),
                  unreachable = sum(is.na(minutes_to_nearest)),
                  .groups = "drop") |> as.data.frame())
