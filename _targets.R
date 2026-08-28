# _targets.R
#
# The q-map pipeline. See PIPELINE_DESIGN.md for the shape of the outputs and
# DATA_CONTRACT.md for what the frontend is promised.
#
# Conventions, carried over from d26-gi-web-map:
#   <artifact>_path    a format = "file" target - either a committed input
#                      whose hash we track, or a writer that returns its path
#   <artifact>         the in-memory object
#   <name>_checks      a validation target that returns TRUE or stop()s
#
# Validation lives in its own target rather than inside the data target's
# command, so failures are attributable in tar_visnetwork() and a bad asset
# blocks the build instead of silently shipping.

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c(
    "sf", "dplyr", "httr", "readr", "readxl", "tidyr",
    "rmapshaper", "jsonlite", "tibble"
  ),
  format = "qs"
)

tar_source()

list(

  ## Crosswalk -------------------------------------------------------------
  # The geography spine. Built by scripts/00_build_crosswalk.R and committed;
  # the DAG only reads it. Tracked as a file target so that editing the CSV by
  # hand - which is the intended way to correct it - invalidates everything
  # downstream.

  tar_target(
    cdta_crosswalk_path,
    "data/crosswalk/cdta_crosswalk.csv",
    format = "file"
  ),

  tar_target(
    cdta_crosswalk,
    read_cdta_crosswalk(cdta_crosswalk_path)
  ),

  # The HVI export is one of the crosswalk's two-way key checks, so the
  # validator needs it. Tracked as a file target for the same reason.
  tar_target(
    hvi_cdta_path,
    "data/source/hvi_cdta2020.csv",
    format = "file"
  ),

  tar_target(
    cdta_crosswalk_checks,
    validate_cdta_crosswalk(cdta_crosswalk, hvi_path = hvi_cdta_path)
  ),

  ## Boundaries ------------------------------------------------------------
  # Static tier: CDTA boundaries change on the decennial cycle. Fetched with a
  # plain tar_target rather than tar_age() - invalidate by hand when DCP
  # revises the layer, the same treatment d26 gave the FEMA NFHL fetch.

  tar_target(
    cdta_boundaries,
    get_cdta()
  ),

  tar_target(
    cdta_boundaries_checks,
    validate_cdta_boundaries(cdta_boundaries)
  ),

  tar_target(
    cdta_simplified,
    simplify_cdta(cdta_boundaries)
  ),

  tar_target(
    cdta_simplified_checks,
    validate_cdta_simplified(cdta_simplified, cdta_boundaries)
  ),

  ## Output ----------------------------------------------------------------

  tar_target(
    cdta_geojson_path,
    write_cdta_geojson(cdta_simplified, cdta_crosswalk,
                       "data/processed/cdta.geojson"),
    format = "file"
  ),

  tar_target(
    cdta_geojson_checks,
    validate_cdta_geojson(cdta_geojson_path)
  ),

  tar_target(
    districts,
    build_districts_index(cdta_simplified, cdta_crosswalk)
  ),

  tar_target(
    districts_checks,
    validate_districts(districts, cdta_crosswalk, cdta_simplified)
  ),

  tar_target(
    districts_json_path,
    write_districts_json(districts, "data/processed/districts.json"),
    format = "file"
  )
)
