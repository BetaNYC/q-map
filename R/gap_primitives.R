# R/gap_primitives.R
#
# The five primitives the 33 gaps collapse to. Each returns one row per CDTA
# with a `value` plus the `facts` the sentence template interpolates.
#
# Two are implemented here - supply_ratio and exposure_overlay - which between
# them cover every gap that is computable without walk times. access_threshold
# and access_mean both need a routed pedestrian network (section 11 step 8) and
# are stubbed so the shape is fixed before r5r lands.

ANALYSIS_CRS_GAPS <- 2263
FEET_PER_MILE <- 5280

# Population apportioned into a hazard polygon.
#
# Tracts are split by the polygon and population is apportioned by the share of
# tract area inside it - the areal apportionment rule of PIPELINE_DESIGN.md 2
# for anything finer than a tract. It assumes population is spread evenly
# within a tract, which is the standard assumption and the reason census blocks
# would be better here if the block file were already in the pipeline.
exposure_overlay_population <- function(tracts, tract_pop, tract_cdta,
                                        hazard_polygon, districts) {
  t2 <- st_transform(tracts, ANALYSIS_CRS_GAPS)
  hz <- st_union(st_transform(hazard_polygon, ANALYSIS_CRS_GAPS))

  t2$tract_area <- as.numeric(st_area(t2))
  inter <- suppressWarnings(st_intersection(t2, hz))
  inter$hit_area <- as.numeric(st_area(inter))

  share <- inter |>
    st_drop_geometry() |>
    group_by(geoid) |>
    summarise(hit_area = sum(hit_area), .groups = "drop")

  t2 |>
    st_drop_geometry() |>
    select(geoid, tract_area) |>
    left_join(share, by = "geoid") |>
    mutate(area_share = pmin(coalesce(hit_area, 0) / tract_area, 1)) |>
    inner_join(tract_pop, by = "geoid") |>
    inner_join(tract_cdta, by = "geoid") |>
    filter(!is.na(cdta2020)) |>
    group_by(cdta2020) |>
    summarise(
      pop_total = sum(pop, na.rm = TRUE),
      pop_exposed = sum(pop * area_share, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(value = ifelse(pop_total > 0, pop_exposed / pop_total * 100, 0)) |>
    right_join(select(districts, cdta2020), by = "cdta2020") |>
    mutate(across(c(pop_total, pop_exposed, value), ~ coalesce(.x, 0)))
}

# Facilities falling inside a hazard polygon, as a share of that district's
# facilities of the same kind.
#
# Districts with no facilities of that kind get NA rather than 0: "0% of your
# hospitals are in a flood zone" is a very different statement when you have no
# hospitals, and rendering it as 0 would read as reassurance.
exposure_overlay_facilities <- function(facilities, hazard_polygon, districts,
                                        cdta_col = "cdta2020") {
  f2 <- st_transform(facilities, ANALYSIS_CRS_GAPS)
  hz <- st_union(st_transform(hazard_polygon, ANALYSIS_CRS_GAPS))
  f2$in_hazard <- lengths(st_intersects(f2, hz)) > 0

  f2 |>
    st_drop_geometry() |>
    filter(!is.na(.data[[cdta_col]])) |>
    group_by(cdta2020 = .data[[cdta_col]]) |>
    summarise(
      n_total = dplyr::n(),
      n_exposed = sum(in_hazard),
      .groups = "drop"
    ) |>
    mutate(value = ifelse(n_total > 0, n_exposed / n_total * 100, NA_real_)) |>
    right_join(select(districts, cdta2020), by = "cdta2020") |>
    mutate(across(c(n_total, n_exposed), ~ coalesce(.x, 0L)))
}

# Facility count per 10,000 of a denominator.
supply_ratio <- function(facilities, districts, denominator,
                         cdta_col = "cdta2020", per = 10000) {
  counts <- facilities |>
    st_drop_geometry() |>
    filter(!is.na(.data[[cdta_col]])) |>
    count(cdta2020 = .data[[cdta_col]], name = "n_facilities")

  districts |>
    select(cdta2020) |>
    left_join(counts, by = "cdta2020") |>
    left_join(denominator, by = "cdta2020") |>
    mutate(
      n_facilities = coalesce(n_facilities, 0L),
      value = ifelse(!is.na(denom) & denom > 0,
                     n_facilities / denom * per, NA_real_)
    )
}

# A Euclidean buffer, for the gaps that say "within X miles".
#
# Section 8b is explicit that these are straight-line buffers, not network
# walks: proximity to a solid-waste facility is about airborne and truck-traffic
# exposure, which does not follow the pedestrian network.
buffer_miles <- function(facilities, miles) {
  facilities |>
    st_transform(ANALYSIS_CRS_GAPS) |>
    st_buffer(miles * FEET_PER_MILE) |>
    st_union()
}

# Assign point facilities to districts.
facilities_to_cdta <- function(facilities, cdta) {
  f2 <- st_transform(facilities, ANALYSIS_CRS_GAPS)
  c2 <- select(st_transform(cdta, ANALYSIS_CRS_GAPS), CDTA2020)
  suppressWarnings(st_join(f2, c2, join = st_within)) |>
    rename(cdta2020 = CDTA2020)
}

# --- not yet implemented ----------------------------------------------------
#
# Both need a routed pedestrian network. Section 8b keeps r5r out of CI: the
# DAG will read a published access_stats.csv as a file target rather than
# routing at build time. Stubbed so the return shape is settled first.

access_threshold <- function(...) {
  stop("access_threshold needs the r5r access measures (step 8). ",
       "9 of the 12 blocked gaps wait only on this.")
}

access_mean <- function(...) {
  stop("access_mean needs the r5r access measures (step 8).")
}

# --- the computable gaps ----------------------------------------------------
#
# One function per gap, each returning cdta2020 + value + a `facts` list the
# registry's sentence_template interpolates. Section 8e: the registry holds the
# template, the pipeline emits the facts, the frontend writes the sentence.

# Gap 18 - emergency alerts not published in local languages.
#
# The quick win of section 8f, and it holds up: Greek is Astoria-Queensbridge's
# second-largest limited-English group at 3,041 speakers, and Notify NYC does
# not publish in Greek.
#
# SCOPE CORRECTION. Section 8f frames this as "LEP population WITHIN EVACUATION
# ZONES vs Notify NYC coverage", but the DCP workbook is PUMA-level, which is
# the whole district. There is no way to say how many Greek speakers live in an
# evacuation zone specifically. Multiplying the district count by the district's
# evacuation-zone population share would assume language groups are spread
# evenly across the district, which is precisely what they are not.
#
# So this reports the district-level fact and carries the district's
# evacuation-zone exposure separately, rather than inventing a joint number.
gap_18_language_coverage <- function(lep, languages, crosswalk) {
  uncovered <- languages |> filter(!is_covered, !is_aggregate) |> pull(lep_language)

  lep |>
    filter(language %in% uncovered) |>
    # Explicitly many-to-many: four PUMAs cover two community districts each
    # (all Manhattan/Bronx), so those districts legitimately share language
    # figures. Declared rather than silenced, so a NEW many-to-many would still
    # be a surprise worth investigating.
    inner_join(select(crosswalk, cdta2020, puma2020), by = "puma2020",
               relationship = "many-to-many") |>
    group_by(cdta2020) |>
    slice_max(estimate, n = 1, with_ties = FALSE) |>
    ungroup() |>
    transmute(
      cdta2020,
      value = as.numeric(estimate),
      facts_language = language,
      facts_speakers = as.integer(estimate),
      facts_cv = round(cv, 1),
      # DCP greys out estimates with a coefficient of variation above 30 in the
      # published workbook ("data shown in gray have poor statistical
      # reliability"). Carried through rather than filtered: QN14's top
      # uncovered language is Tagalog at 173 speakers with a CV of 49, which is
      # a real finding about a small population and a bad number to state
      # flatly. The frontend decides how to present it.
      facts_reliable = !is.na(cv) & cv <= 30
    )
}

# Gap 2 - indoor cool options per 10,000 residents.
gap_02_cool_options <- function(cool_options, cdta, districts, chp) {
  denom <- chp_districts(chp) |>
    inner_join(select(districts, cdta2020, borocd), by = "borocd") |>
    transmute(cdta2020, denom = as.numeric(Overall_Pop))

  facilities_to_cdta(cool_options, cdta) |>
    supply_ratio(districts, denom) |>
    transmute(cdta2020, value,
              facts_count = n_facilities,
              facts_per_10k = round(value, 2))
}

# Gaps 7, 27, 28, 31 - population inside a hazard area.
gap_population_exposure <- function(tracts, tract_pop, tract_cdta,
                                    hazard_polygon, districts) {
  exposure_overlay_population(tracts, tract_pop, tract_cdta,
                              hazard_polygon, districts) |>
    transmute(cdta2020, value,
              facts_pct = round(value, 1),
              facts_people = round(pop_exposed))
}

# Gaps 11, 12, 17 - facilities inside a hazard area.
gap_facility_exposure <- function(facilities, hazard_polygon, districts) {
  exposure_overlay_facilities(facilities, hazard_polygon, districts) |>
    transmute(cdta2020, value,
              facts_pct = round(value, 1),
              facts_exposed = n_exposed,
              facts_total = n_total)
}

# Gap 33 - few places to reach people in a hazard area.
#
# Communication resources are libraries, community organisations and cultural
# institutions - the places that actually pass word along when the power is
# out. Expressed as flood-exposed population per communication resource, so a
# district with many exposed residents and few such places scores high.
COMMUNICATION_CATEGORIES <- c("libraries-and-community", "government-offices")

gap_33_communication <- function(res_cdta, flood_exposure, districts) {
  counts <- res_cdta |>
    filter(canonical_category %in% COMMUNICATION_CATEGORIES, !is.na(cdta2020)) |>
    count(cdta2020, name = "n_comms")

  flood_exposure |>
    # gap_population_exposure() renames pop_exposed to facts_people on its way
    # out, so take the fact rather than the intermediate.
    select(cdta2020, pop_exposed = facts_people) |>
    left_join(counts, by = "cdta2020") |>
    mutate(
      n_comms = coalesce(n_comms, 0L),
      value = ifelse(n_comms > 0, pop_exposed / n_comms, NA_real_)
    ) |>
    transmute(cdta2020, value,
              facts_people = round(pop_exposed),
              facts_resources = n_comms,
              facts_per_resource = round(value))
}

# --- orchestration ----------------------------------------------------------

# Compute every gap the registry marks available, for all 59 CDTAs.
#
# Section 8c: compute the full matrix, not just the three a district displays.
# The marginal cost is near zero once the primitives exist, and the display
# rule WILL change - computing only the selected three would make a rule change
# a pipeline redesign instead of a re-render.
#
# One caveat the design doc did not anticipate: the resource-based gaps (11, 33)
# can only be computed where canonical resources exist, which is Queens. Their
# "citywide" values cover 14 districts, not 59, so a citywide percentile of
# those two would be meaningless.
compute_available_gaps <- function(reg, inputs) {
  d <- inputs$districts
  out <- list()
  add <- function(id, tbl) {
    out[[as.character(id)]] <<- tbl |> mutate(gap_id = as.integer(id))
  }

  add(2,  gap_02_cool_options(inputs$cool_options, inputs$cdta, inputs$crosswalk,
                              inputs$chp))
  add(7,  gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$stormwater, d))
  add(11, gap_facility_exposure(inputs$critical_resources, inputs$stormwater, d))
  add(12, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$flood_x_wastewater, d))
  add(17, gap_facility_exposure(inputs$evac_centers_cdta, inputs$evac_zones, d))
  add(18, gap_18_language_coverage(inputs$lep, inputs$languages, inputs$crosswalk))
  add(27, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$solid_waste_buffer, d))
  add(28, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$wastewater_buffer, d))
  add(31, gap_facility_exposure(inputs$hazard_facilities_cdta, inputs$stormwater, d))
  add(33, gap_33_communication(inputs$resources_cdta, out[["7"]], d))

  bind_rows(out) |>
    left_join(select(reg, gap_id, hazard_slug, priority, label, unit, polarity,
                     sentence_template, status),
              by = "gap_id") |>
    relocate(gap_id, hazard_slug, priority, cdta2020, value)
}

# Select up to three gaps per district by walking its hazard ranking.
#
# Section 8d: the guarantee is three sentences, achieved by descending the
# ranking until three resolve. That creates a specific hazard the data must
# defend against - the three gaps shown may not correspond to the three risks
# listed above them on the same screen. So every selected gap carries
# risk_rank, and one drawn from outside the top three carries fallback_from
# naming the risk it stands in for.
#
# The walk stops at the last RANKED hazard. A pinned hazard has no
# district-specific measure, so a gap attached to one has no district-specific
# justification either. cross-cutting is eligible as a final fallback because it
# is by definition not tied to any single hazard.
select_district_gaps <- function(gaps, hazards, n_target = 3) {
  ranked <- hazards |> filter(ranked) |> arrange(cdta2020, rank)

  lapply(split(ranked, ranked$cdta2020), function(hz) {
    district <- hz$cdta2020[1]
    pool <- gaps |>
      filter(cdta2020 == district, status == "available", !is.na(value))

    top3 <- hz$slug[hz$rank <= n_target]
    chosen <- list()

    take_from <- function(slug, risk_rank) {
      cand <- pool |>
        filter(hazard_slug == slug,
               !gap_id %in% vapply(chosen, function(c) c$gap_id, integer(1))) |>
        arrange(priority)
      if (nrow(cand) == 0) return(NULL)
      row <- cand[1, ]
      row$risk_rank <- risk_rank
      row$fallback_from <- if (risk_rank > n_target) {
        setdiff(top3, vapply(chosen, function(c) c$hazard_slug, character(1)))[1]
      } else NA_character_
      row
    }

    # First pass: one gap per top-three hazard, in rank order.
    for (i in seq_len(min(n_target, nrow(hz)))) {
      got <- take_from(hz$slug[i], hz$rank[i])
      if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
    }
    # Fall-through: continue down the ranked hazards, then cross-cutting.
    if (length(chosen) < n_target && nrow(hz) > n_target) {
      for (i in seq(n_target + 1, nrow(hz))) {
        if (length(chosen) >= n_target) break
        got <- take_from(hz$slug[i], hz$rank[i])
        if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
      }
    }
    if (length(chosen) < n_target) {
      got <- take_from("cross-cutting", NA_integer_)
      if (!is.null(got)) {
        got$fallback_from <- setdiff(
          top3, vapply(chosen, function(c) c$hazard_slug, character(1)))[1]
        chosen[[length(chosen) + 1]] <- got
      }
    }
    if (length(chosen) == 0) return(NULL)
    bind_rows(chosen) |> mutate(display_order = row_number())
  }) |> bind_rows()
}

# --- payloads ---------------------------------------------------------------

# Turn a computed row into the facts the sentence template interpolates.
gap_facts <- function(row) {
  fc <- names(row)[startsWith(names(row), "facts_")]
  out <- lapply(fc, function(f) row[[f]])
  names(out) <- sub("^facts_", "", fc)
  out[!vapply(out, function(v) length(v) == 0 || all(is.na(v)), logical(1))]
}

gap_entry <- function(row, include_selection = TRUE) {
  e <- list(
    gap_id = as.integer(row$gap_id),
    hazard_slug = row$hazard_slug,
    label = row$label,
    value = if (is.na(row$value)) NULL else round(as.numeric(row$value), 3),
    unit = row$unit,
    polarity = row$polarity,
    status = row$status,
    sentence_template = if (is.na(row$sentence_template) ||
                            !nzchar(row$sentence_template)) NULL else row$sentence_template,
    facts = gap_facts(row)
  )
  if (include_selection) {
    e$risk_rank <- if (is.na(row$risk_rank)) NULL else as.integer(row$risk_rank)
    # Section 8d: without this the screen is quietly misleading. A gap drawn
    # from outside the top three is about a different hazard than the risk
    # listed above it, and only this field lets the UI say so.
    e$fallback_from <- if (is.na(row$fallback_from)) NULL else row$fallback_from
  }
  compact_list(e)
}

# The full 33-gap matrix per district, so absence is legible rather than silent.
write_gap_matrices <- function(gap_values, registry, crosswalk, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  shipped <- crosswalk |> filter(boro_code == 4)

  paths <- vapply(seq_len(nrow(shipped)), function(i) {
    row <- shipped[i, ]
    computed <- gap_values |> filter(cdta2020 == row$cdta2020)

    # Every registry row appears, computed or not. A gap that is blocked,
    # deferred or retired ships with its status and its reason, so a reader can
    # see what is missing and why rather than inferring it from an absence.
    entries <- lapply(seq_len(nrow(registry)), function(j) {
      reg <- registry[j, ]
      hit <- computed |> filter(gap_id == reg$gap_id)
      if (nrow(hit) == 1) {
        gap_entry(hit, include_selection = FALSE)
      } else {
        compact_list(list(
          gap_id = as.integer(reg$gap_id),
          hazard_slug = reg$hazard_slug,
          label = reg$label,
          value = NULL,
          unit = reg$unit,
          polarity = reg$polarity,
          status = reg$status,
          blocked_on = if (is.na(reg$blocked_on) || !nzchar(reg$blocked_on)) NULL
                       else reg$blocked_on
        ))
      }
    })

    payload <- list(cdta2020 = row$cdta2020, slug = row$slug,
                    computed = nrow(computed), total = nrow(registry),
                    gaps = entries)
    p <- file.path(dir, paste0(row$slug, ".json"))
    jsonlite::write_json(force_arrays(payload, c("gaps")), p,
                         auto_unbox = TRUE, digits = NA, null = "null", na = "null")
    p
  }, character(1))
  unname(paths)
}

validate_gap_selection <- function(sel, hazards, crosswalk, n_target = 3) {
  shipped <- crosswalk |> filter(boro_code == 4)
  missing <- setdiff(shipped$cdta2020, sel$cdta2020)
  if (length(missing) > 0) {
    stop("No gap selected at all for: ", paste(missing, collapse = ", "))
  }

  counts <- sel |> filter(cdta2020 %in% shipped$cdta2020) |> count(cdta2020)
  if (any(counts$n > n_target)) {
    stop("More than ", n_target, " gaps selected for ",
         paste(counts$cdta2020[counts$n > n_target], collapse = ", "))
  }

  # Section 8d. A gap whose hazard is not in the district's top three MUST name
  # the risk it stands in for, or the reader sees a sentence about hazard B
  # sitting under a heading for hazard A.
  bad <- sel |> filter(is.na(risk_rank) | risk_rank > n_target,
                       is.na(fallback_from))
  if (nrow(bad) > 0) {
    stop(nrow(bad), " selected gap(s) come from outside the top ", n_target,
         " but carry no fallback_from: ",
         paste(unique(bad$cdta2020), collapse = ", "))
  }

  # A district must never show the same indicator twice.
  dupes <- sel |> count(cdta2020, gap_id) |> filter(n > 1)
  if (nrow(dupes) > 0) {
    stop("Duplicate gap in one district: ",
         paste(dupes$cdta2020, collapse = ", "))
  }
  TRUE
}
