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
                            resource_categories = district_resource_categories,
                            gap_selection = gap_selection)
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

  # Availability of every blocker named by either registry, gathered once from
  # the real upstream objects. Both freshness checks read this, so a dataset
  # landing invalidates them together. See R/registry.R.
  tar_target(
    blocker_facts_now,
    blocker_facts(
      fvi                 = fvi,
      evac_zones          = evac_zones,
      cool_options        = cool_options,
      evac_centers        = evac_centers,
      canonical_resources = canonical_resources
    )
  ),

  tar_target(
    map_layer_registry_checks,
    validate_layer_registry(map_layer_registry) &&
      validate_registry_freshness(map_layer_registry, blocker_facts_now,
                                  "map_layers.csv", id_col = "layer_id")
  ),

  tar_target(
    hazard_content_checks,
    validate_hazard_content(
      hazard_content,
      model_slugs = c(names(HAZARD_SEVERITY), HAZARD_PINNED),
      registry_ids = map_layer_registry$layer_id,
      available_ids = map_layer_registry$layer_id[
        map_layer_registry$status == "available"]
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
    ) &&
      validate_registry_freshness(gap_registry, blocker_facts_now,
                                  "resource_gaps.csv", id_col = "gap_id")
  ),

  ## Gap inputs --------------------------------------------------------------

  tar_target(language_crosswalk_path, "data/crosswalk/languages.csv", format = "file"),
  tar_target(language_crosswalk, read_language_crosswalk(language_crosswalk_path)),
  tar_target(language_crosswalk_checks, validate_language_crosswalk(language_crosswalk, lep)),

  tar_target(cool_options, get_cool_options()),
  tar_target(evac_zones, get_evac_zones()),
  tar_target(evac_centers, get_evac_centers()),
  tar_target(solid_waste_facilities, get_hazard_facilities("SOLID WASTE")),
  tar_target(wastewater_facilities, get_hazard_facilities("WATER AND WASTEWATER")),

  ## Access measures ---------------------------------------------------------
  # Published by scripts/04_access_measures.R, which runs LOCALLY with r5r and
  # a JVM and is never part of this DAG. Read as files, exactly as section 8b
  # requires - the pipeline consumes walk times and never routes.

  tar_target(access_stats_path, "data/prepared/access_stats.csv", format = "file"),
  tar_target(access_stats, read_access_stats(access_stats_path)),

  tar_target(block_weights_path, "data/prepared/block_weights.csv", format = "file"),
  tar_target(block_weights, read_block_weights(block_weights_path)),

  # The spatial half stays here rather than in the local script, because it
  # needs the UNSIMPLIFIED boundaries the DAG already holds.
  tar_target(block_cdta, blocks_to_cdta(block_weights, cdta_boundaries)),
  tar_target(block_cdta_checks, validate_block_cdta(block_cdta)),

  ## Gap computation ---------------------------------------------------------

  tar_target(
    gap_values,
    compute_available_gaps(gap_registry, list(
      districts = select(sf::st_drop_geometry(cdta_boundaries), cdta2020 = CDTA2020),
      cdta = cdta_boundaries, crosswalk = cdta_crosswalk, chp = chp, lep = lep,
      languages = language_crosswalk,
      tracts = fvi, tract_pop = tract_pop,
      tract_cdta = filter(tract_cdta, !is.na(cdta2020)),
      stormwater = stormwater_moderate,
      cool_options = cool_options,
      solid_waste_buffer = sf::st_sfc(buffer_miles(solid_waste_facilities, 0.5), crs = 2263),
      wastewater_buffer = sf::st_sfc(buffer_miles(wastewater_facilities, 0.5), crs = 2263),
      flood_x_wastewater = sf::st_sfc(sf::st_intersection(
        sf::st_union(sf::st_transform(stormwater_moderate, 2263)),
        buffer_miles(wastewater_facilities, 0.5)), crs = 2263),
      hazard_facilities_cdta = facilities_to_cdta(
        rbind(select(solid_waste_facilities, uid, facname, geometry),
              select(wastewater_facilities, uid, facname, geometry)),
        cdta_boundaries),
      resources_cdta = resources_cdta,
      access = access_stats,
      block_cdta = block_cdta
    ))
  ),

  # The numbers, not the config. Catches a unit that disagrees with the
  # computation that produced it, an `available` gap with no value, and a
  # template placeholder with no matching fact - three failure modes that are
  # invisible to validate_gap_registry() because the config is well-formed.
  tar_target(gap_values_checks, validate_gap_values(gap_values, cdta_crosswalk)),

  tar_target(gap_selection, select_district_gaps(gap_values, hazards, cdta_crosswalk)),

  tar_target(gap_selection_checks, validate_gap_selection(gap_selection, hazards, cdta_crosswalk)),

  tar_target(
    gap_matrix_paths,
    write_gap_matrices(gap_values, gap_registry, cdta_crosswalk, "data/processed/gaps"),
    format = "file"
  ),

  ## Current conditions ------------------------------------------------------
  # Computed from the committed ARCHIVE, not the live feed. DOHMH publishes a
  # 12-week rolling window; scripts/06_archive_respiratory.R appends to the
  # archive weekly, and the archive is the only record of anything older.

  tar_target(respiratory_archive_path, ARCHIVE_PATH, format = "file"),
  tar_target(respiratory_archive, read_respiratory_archive(respiratory_archive_path)),
  tar_target(respiratory_checks, validate_respiratory(respiratory_archive)),

  tar_target(conditions, build_conditions(respiratory_archive)),
  tar_target(
    conditions_path,
    write_conditions(conditions, "data/processed/conditions.json"),
    format = "file"
  ),

  ## Map layers --------------------------------------------------------------
  # Vector tiles built by scripts/01_mirror_stormwater.R and published in the
  # data-v* release. The DAG copies them through; it never runs tippecanoe.

  tar_target(stormwater_moderate_tiles_src,
             "data/prepared/stormwater_moderate_2_13.pmtiles", format = "file"),
  tar_target(stormwater_limited_tiles_src,
             "data/prepared/stormwater_limited_1_77.pmtiles", format = "file"),

  tar_target(
    layer_tile_paths,
    c(copy_layer(stormwater_moderate_tiles_src, "data/processed/layers"),
      copy_layer(stormwater_limited_tiles_src, "data/processed/layers")),
    format = "file"
  ),

  tar_target(layer_tile_checks, validate_layer_tiles(layer_tile_paths, map_layer_registry)),

  # GeoJSON overlays. Written directly rather than tiled: measured, every one is
  # smaller than cdta.geojson, so tippecanoe would add a build step and a
  # data-v* round trip to save nothing. See R/layers.R.
  tar_target(queens_shape, queens_outline(cdta_boundaries)),

  tar_target(
    layer_geojson_paths,
    c(
      layer_hurricane_evac_zones(evac_zones, queens_shape,
                                 "data/processed/layers/hurricane_evac_zones.geojson"),
      layer_surge_current(fvi, queens_shape,
                          "data/processed/layers/surge_current.geojson"),
      layer_evacuation_centers(evac_centers, queens_shape,
                               "data/processed/layers/evacuation_centers.geojson"),
      layer_cooling_centers(cool_options, queens_shape,
                            "data/processed/layers/cooling_centers.geojson"),
      layer_resources(resources_cdta, cdta_crosswalk,
                      "data/processed/layers/resources")
    ),
    format = "file"
  ),

  tar_target(layer_geojson_checks,
             validate_layer_geojson(layer_geojson_paths, map_layer_registry))
)
