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
    "rmapshaper", "jsonlite", "tibble", "purrr", "stats", "yaml"
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

  tar_target(
    cdta_crosswalk_checks,
    validate_cdta_crosswalk(cdta_crosswalk, hvi)
  ),

  ## Heat --------------------------------------------------------------------
  # DOHMH Heat Vulnerability Index, keyed on CommDist. Tier 1 - fetched, not
  # mirrored, since DOHMH publishes it as a feature service. Static in
  # practice: the 2023 vintage has been current since publication, so a plain
  # tar_target rather than tar_age().
  #
  # get_hvi() filters out Joint Interest Areas by name and asserts 59 rows.
  # Filtering on "has an HVI score" instead would return 60 - BX28 Pelham Bay
  # Park is a JIA that carries a score - so a park would enter the district set.

  tar_target(
    hvi,
    get_hvi()
  ),

  ## Heavy rain --------------------------------------------------------------
  # DEP stormwater flood extents. Tier 2: no API, so they are mirrored to
  # data/prepared/ by scripts/01_mirror_stormwater.R and published in the
  # data-v* Release. In CI the Release is rehydrated into data/prepared/ before
  # tar_make(); locally the mirror script puts them there. Either way the DAG
  # sees a plain file path whose hash it tracks.

  tar_target(
    stormwater_limited_path,
    "data/prepared/stormwater_limited_1_77.geojson",
    format = "file"
  ),

  tar_target(
    stormwater_moderate_path,
    "data/prepared/stormwater_moderate_2_13.geojson",
    format = "file"
  ),

  tar_target(
    stormwater_limited,
    get_stormwater(stormwater_limited_path)
  ),

  tar_target(
    stormwater_moderate,
    get_stormwater(stormwater_moderate_path)
  ),

  tar_target(
    stormwater_limited_checks,
    validate_stormwater(stormwater_limited, "stormwater_limited_1_77")
  ),

  tar_target(
    stormwater_moderate_checks,
    validate_stormwater(stormwater_moderate, "stormwater_moderate_2_13")
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
  ),

  ## Hazard inputs -----------------------------------------------------------
  # All Tier-1 feature services. Static in practice - PIVI and the chemical
  # business counts are published per JRA cycle, the FVI per climate
  # assessment - so plain targets, invalidated by hand.

  tar_target(pivi, get_pivi()),
  tar_target(chem_businesses, get_chem_businesses()),
  tar_target(fvi, get_fvi()),

  # Census tract population, used only to population-weight the FVI onto
  # districts per PIPELINE_DESIGN.md 2. Requires CENSUS_API_KEY.
  tar_target(tract_pop, get_tract_population()),

  tar_target(tract_cdta, tract_to_cdta(fvi, cdta_boundaries)),

  tar_target(
    tract_cdta_checks,
    validate_tract_cdta(tract_cdta, tract_pop)
  ),

  tar_target(
    coastal_exposure,
    coastal_per_cdta(st_drop_geometry(fvi),
                     filter(tract_cdta, !is.na(cdta2020)), tract_pop)
  ),

  tar_target(
    stormwater_pct,
    stormwater_pct_per_cdta(cdta_boundaries, stormwater_moderate)
  ),

  ## Hazard ranking ----------------------------------------------------------

  tar_target(
    hazard_measures,
    build_hazard_measures(cdta_crosswalk, hvi, pivi, chem_businesses,
                          stormwater_pct, coastal_exposure)
  ),

  tar_target(
    hazard_measures_checks,
    validate_hazard_measures(hazard_measures)
  ),

  tar_target(
    hazards,
    build_hazards(hazard_measures)
  ),

  ## District payloads -------------------------------------------------------

  tar_target(chp_path, "data/prepared/chp_by_cd.csv", format = "file"),
  tar_target(lep_path, "data/prepared/lep_languages_puma.csv", format = "file"),

  tar_target(chp, read_chp(chp_path)),
  tar_target(lep, read_lep(lep_path)),
  tar_target(chp_checks, validate_chp(chp)),
  tar_target(lep_checks, validate_lep(lep)),

  tar_target(
    district_payloads,
    build_district_payloads(cdta_crosswalk, hazards, hazard_measures, chp, lep,
                            overlay_index = hazard_override_index(hazard_overlays),
                            resource_categories = district_resource_categories)
  ),

  tar_target(
    district_payloads_checks,
    validate_district_payloads(district_payloads, cdta_crosswalk)
  ),

  tar_target(
    district_output_checks,
    validate_district_output(district_payload_paths)
  ),

  tar_target(
    hazard_calibration_checks,
    validate_hazard_calibration(district_payloads)
  ),

  tar_target(
    district_payload_paths,
    write_district_payloads(district_payloads, "data/processed/districts"),
    format = "file"
  ),

  ## Hazard content ----------------------------------------------------------
  # Authored YAML, validated and copied - never generated. Tracked as a
  # directory-level file target so editing any file invalidates the check.

  tar_target(
    hazard_content_dir,
    HAZARD_CONTENT_DIR,
    format = "file"
  ),

  tar_target(
    hazard_content,
    read_hazard_content(hazard_content_dir)
  ),

  tar_target(map_layer_registry_path, "data/registry/map_layers.csv", format = "file"),
  tar_target(map_layer_registry, read_layer_registry(map_layer_registry_path)),
  tar_target(map_layer_registry_checks, validate_layer_registry(map_layer_registry)),

  tar_target(
    hazard_content_checks,
    validate_hazard_content(
      hazard_content,
      model_slugs = c(names(HAZARD_SEVERITY), HAZARD_PINNED),
      registry_ids = map_layer_registry$layer_id
    )
  ),

  ## Per-district hazard overrides -------------------------------------------
  # Rare by design: only where citywide guidance is genuinely wrong for a
  # district. Everything that varies numerically is templated instead.

  tar_target(hazard_overlays, read_hazard_overlays(hazard_content_dir)),

  tar_target(
    hazard_overlay_checks,
    validate_hazard_overlays(
      hazard_overlays, hazard_content,
      district_slugs = filter(cdta_crosswalk, boro_code == 4)$slug
    )
  ),

  tar_target(
    hazard_overlay_paths,
    write_hazard_overlays(hazard_content, hazard_overlays,
                          "data/processed/districts"),
    format = "file"
  ),

  # Separate from the schema check: it is the only target that needs the
  # network, and it is the one most likely to fail for reasons unrelated to the
  # content. Keeping it its own node makes that attributable.
  tar_target(
    hazard_link_checks,
    validate_hazard_links(hazard_content, hazard_overlays)
  ),

  tar_target(
    hazard_content_paths,
    write_hazard_content(hazard_content, "data/processed/hazards"),
    format = "file"
  ),

  tar_target(
    hazard_output_checks,
    validate_hazard_output(hazard_content_paths)
  ),

  ## Resources ---------------------------------------------------------------
  # The canonical file is hand-maintained and committed; the pipeline reads it
  # and never writes it. scripts/03_seed_resources.R proposes changes as a diff.

  tar_target(resource_categories_path, "data/crosswalk/resource_categories.csv",
             format = "file"),
  tar_target(resource_categories, read_resource_categories(resource_categories_path)),
  tar_target(resource_categories_checks, validate_resource_categories(resource_categories)),

  tar_target(canonical_resources_path, "data/canonical/resources.csv",
             format = "file"),
  tar_target(canonical_resources, read_canonical_resources(canonical_resources_path)),
  tar_target(
    canonical_resources_checks,
    validate_canonical_resources(canonical_resources, resource_categories)
  ),

  tar_target(
    resources_cdta,
    resources_to_cdta(canonical_resources, cdta_boundaries)
  ),

  tar_target(
    district_resource_categories,
    resource_categories_per_district(resources_cdta, resource_categories)
  ),

  tar_target(
    resource_payload_paths,
    write_resource_payloads(resources_cdta, cdta_crosswalk,
                            "data/processed/resources"),
    format = "file"
  ),

  tar_target(
    resource_payloads_checks,
    validate_resource_payloads(resource_payload_paths, resources_cdta)
  ),

  ## Resource gap registry ---------------------------------------------------
  # Config, documentation and acquisition backlog in one committed CSV. All 33
  # candidates keep a row; eight are retired with a reason.

  tar_target(gap_registry_path, "data/registry/resource_gaps.csv", format = "file"),
  tar_target(gap_registry, read_gap_registry(gap_registry_path)),

  tar_target(
    gap_registry_checks,
    validate_gap_registry(
      gap_registry,
      ranked_slugs = names(HAZARD_SEVERITY),
      pinned_slugs = HAZARD_PINNED
    )
  )
)
