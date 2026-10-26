# R/gap_primitives.R
#
# The five primitives the 33 gaps collapse to. Each returns one row per CDTA
# with a `value` plus the `facts` the sentence template interpolates.
#
# supply_ratio and exposure_overlay live here. access_threshold and access_mean
# live in R/access.R, because they read the locally-produced walk-time table
# rather than computing anything spatial - see ACCESS_MEASURES.md.

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

# access_threshold() and access_mean() now live in R/access.R, implemented
# against data/prepared/access_stats.csv.

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
#
# CROSS-CUTTING SINCE 2026-10-20. The scope correction above left nothing
# coastal in the measure, and Notify NYC is an all-hazard channel (the alert
# archive carries flood advisories, power outages and fire alongside coastal
# flood statements). It moved off coastal-storm so it can fill the third slot
# in the five districts that rank two hazards. QN01, QN02, QN03 and QN06 had
# shown it for coastal storm; they now show gap 13 or 21 there. The QN14
# reasoning below predates that move - QN14 shows gap 21.
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
    # RELIABLE FIRST, THEN THE HONEST FALLBACK.
    #
    # DCP greys out estimates with a coefficient of variation above 30 in the
    # published workbook ("data shown in gray have poor statistical
    # reliability"), so the largest uncovered language is not always the one
    # worth naming. Prefer the largest that clears the threshold.
    #
    # Measured across the 14 Queens districts: 11 have a reliable uncovered
    # language, and for every one of them it is ALSO the largest overall - so
    # this changes no district's answer where a reliable answer exists. Three
    # have none at all: q08 Tagalog (CV 30.5), q12 Punjabi (33.5) and q14
    # Tagalog (49.2).
    #
    # Dropping the gap in those three was the alternative and is worse. It
    # would take gap 18 away from QN14, whose only other coastal-storm gap was
    # retired - so the one district that leads with coastal storm would fall
    # through to the same three sentences as the other twelve. The district
    # that is genuinely different would stop looking different.
    #
    # So: keep the number, and hedge the sentence. The unreliable variant is
    # `sentence_template_unreliable` in the registry, selected by gap_entry()
    # on facts$reliable. Copy stays in a CSV a non-engineer can edit.
    arrange(desc(!is.na(cv) & cv <= 30), desc(estimate), .by_group = TRUE) |>
    slice_head(n = 1) |>
    ungroup() |>
    transmute(
      cdta2020,
      value = as.numeric(estimate),
      facts_language = language,
      facts_speakers = as.integer(estimate),
      facts_cv = round(cv, 1),
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
# those two would be meaningless. Both are now retired, so no live gap reads
# canonical resources.
compute_available_gaps <- function(reg, inputs) {
  d <- inputs$districts
  out <- list()
  add <- function(id, tbl) {
    out[[as.character(id)]] <<- tbl |> mutate(gap_id = as.integer(id))
  }

  add(1,  access_threshold(inputs$access, inputs$block_cdta,
                           "cool_options_indoor", 15, "all_residents"))
  add(2,  gap_02_cool_options(inputs$cool_options, inputs$cdta, inputs$crosswalk,
                              inputs$chp))
  add(7,  gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$stormwater, d))
  # Gaps 11 and 17 were retired - see BLOCKERS in R/registry.R for why. Their
  # registry rows survive with gap_id and a reason, per section 8c; only the
  # computation goes.
  add(12, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$flood_x_wastewater, d))
  add(13, access_mean(inputs$access, inputs$block_cdta,
                      "evacuation_centers", "all_residents"))
  add(18, gap_18_language_coverage(inputs$lep, inputs$languages, inputs$crosswalk))
  add(21, access_mean(inputs$access, inputs$block_cdta,
                      "hospitals", "all_residents"))
  # Gaps 27 and 28 were retired 2026-09-22 (hazard_pinned) when the reviewed
  # ranking pinned hazmat - same rule as 11 and 17 above: the registry rows
  # stay, the computation goes. Leaving the add() in place shipped a retired
  # row carrying a value, which is what validate_gap_values() now refuses.
  add(31, gap_facility_exposure(inputs$hazard_facilities_cdta, inputs$stormwater, d))
  # Gap 33 was retired 2026-10-20 (not_cross_cutting): filed cross-cutting, it
  # counted stormwater-exposed residents per library, community centre or
  # government office, so it measured heavy rain. Same rule as 27 and 28. Its
  # computation is in git history if it is ever re-filed to heavy-rain.

  # Every sentence_template opens with {district}, and it was the one
  # placeholder that could never resolve from `facts` - it comes from the
  # payload root, so a frontend following the contract's "interpolate facts
  # into this" literally rendered the token. Injecting it here makes the rule
  # absolute rather than a documented exception: EVERY placeholder resolves
  # inside facts, and validate_gap_values() enforces exactly that.
  #
  # It costs one join and one column repeated across 59 rows per gap. The
  # alternative - a named set of payload-root fields the frontend must know
  # about - is a second lookup table living in prose, which is the kind of
  # thing DATA_CONTRACT.md exists to avoid.
  bind_rows(out) |>
    left_join(select(reg, gap_id, hazard_slug, part, priority, label, unit, polarity,
                     sentence_template, sentence_template_zero,
                     sentence_template_unreliable, status),
              by = "gap_id") |>
    left_join(select(crosswalk_display_names(inputs$crosswalk),
                     cdta2020, facts_district),
              by = "cdta2020") |>
    # A district a primitive could not answer for is `not_applicable` HERE,
    # not `available` with a hole. Selection skips it and falls through, and
    # the full matrix still ships the row so the absence is legible.
    #
    # Demotion requires an explicit reason: a primitive that returns NA without
    # saying why is still a defect, and validate_gap_values() fails on it.
    mutate(status = ifelse(
      status == "available" & is.na(value) &
        !is.na(dplyr::coalesce(facts_unavailable_reason, NA_character_)),
      "not_applicable", status)) |>
    relocate(gap_id, hazard_slug, part, priority, cdta2020, value)
}

# The district name as the sentence templates spell it. Kept as its own
# function so the "which name goes in the sentence" decision has one home -
# display_name, not cd_label and not the CDTA code.
crosswalk_display_names <- function(crosswalk) {
  crosswalk |> transmute(cdta2020, facts_district = display_name)
}

# How unusual a district's value is for a gap, among the districts that ship.
#
# WHY THIS REPLACED `priority`
#
# Selection used to take each hazard's lowest-`priority` available gap, and
# priority is a fixed property of the registry row. The result was that twelve
# of fourteen districts received the identical three gaps - 2, 7, 31 - and only
# QN14 and QN10 differed, and only because coastal storm reached their top
# three. The values differed per district; the indicators did not. Section F
# read as a template with the numbers swapped.
#
# Ranking by extremeness asks a different question: of the gaps available for
# this hazard, which one is this district most unusual on? That makes the
# sentence say something true about THIS district rather than something true
# everywhere, and it costs nothing - section 8c already computes the full
# matrix, so the comparison data is sitting there.
#
# THREE DECISIONS INSIDE IT
#
# 1. The frame is the 14 shipped districts, not all 59. Gaps 31 and 33 are
#    Queens-scoped by construction (see validate_gap_values), so a citywide
#    percentile does not exist for them - and "notable here relative to the
#    rest of Queens" is the claim the screen actually makes. One frame for
#    every gap beats two frames in one list.
#
# 2. Midrank percentile, tie-averaged. Same convention the hazard model uses,
#    and these measures tie heavily - eight districts share a value of 0 on
#    gap 31.
#
# 3. Polarity inverts it. `higher_is_worse` makes a high value extreme;
#    `higher_is_better` makes a LOW value extreme. Gap 2 is
#    higher_is_better, so the district with the fewest cool options per 10k is
#    the one worth a sentence - not the best-served one. Getting this backwards
#    would put each district's best news in its resource-gap section.
#
# Ties in extremeness fall back to `priority`, which validate_gap_registry()
# already asserts is unique within a hazard - so selection stays deterministic
# and cannot change between rebuilds without a data change.
gap_extremeness <- function(gaps, shipped) {
  gaps |>
    filter(cdta2020 %in% shipped, status == "available", !is.na(value)) |>
    group_by(gap_id) |>
    mutate(
      # rank() with ties.method = "average" is the midrank; dividing by n gives
      # a 0-1 standing. A gap with one distinct value lands everyone at the
      # same midrank, so extremeness cannot manufacture a difference that the
      # data does not contain - the priority tiebreak decides those.
      .pct = rank(value, ties.method = "average") / dplyr::n(),
      extremeness = if_else(polarity == "higher_is_better", 1 - .pct, .pct)
    ) |>
    ungroup() |>
    select(-.pct) |>
    # Computed here rather than in the arrange() so the flag travels with the
    # scored pool and can be inspected.
    (\(x) { x$is_non_finding <- gap_non_finding_flags(x); x })()
}

# The slots a district's gap sentences fill, in order (2026-10-26).
#
# A SLOT IS A MEASURED PART OF A RANKED CATEGORY. Gaps were drawn one per
# ranked hazard until the SME categories merged coastal storm and heavy rain
# into Flooding. One gap per category would have cut a surge-exposed
# district's two flood sentences to one, so selection draws one per part
# instead (Andrew, 2026-10-26). A category with no parts is one slot.
#
# Ordered by category rank, then within a category by part score descending,
# with CATEGORY_PARTS order (coastal before rain, the review's specificity
# order) breaking ties.
#
# A PART SCORING 0 GETS NO SLOT. Coastal storm scores 0 in five districts
# (QN04, QN05, QN08, QN09, QN12). From 2026-10-14 it was unranked there and
# drew no gap; this keeps that. Those districts have two slots, and the third
# sentence comes from cross-cutting.
#
# `risk_rank` is the CATEGORY's rank, so both flooding slots carry rank 1.
# `slot` is the sentence position.
district_gap_slots <- function(hazards, measures) {
  ranked <- hazards |> filter(ranked) |> select(cdta2020, slug, rank)
  rows <- lapply(seq_len(nrow(ranked)), function(i) {
    h <- ranked[i, ]
    parts <- CATEGORY_PARTS[[h$slug]]
    if (is.null(parts)) {
      return(tibble::tibble(cdta2020 = h$cdta2020, hazard_slug = h$slug,
                            part = NA_character_, risk_rank = h$rank,
                            part_score = NA_integer_, part_order = 1L))
    }
    m <- measures[measures$cdta2020 == h$cdta2020, ]
    tibble::tibble(
      cdta2020 = h$cdta2020, hazard_slug = h$slug, part = parts,
      risk_rank = h$rank,
      part_score = vapply(parts, function(p) as.integer(m[[PART_SCORE_COL[[p]]]]),
                          integer(1)),
      part_order = seq_along(parts)
    )
  })
  bind_rows(rows) |>
    filter(is.na(part_score) | part_score > 0) |>
    arrange(cdta2020, risk_rank, desc(part_score), part_order) |>
    group_by(cdta2020) |>
    mutate(slot = row_number()) |>
    ungroup() |>
    select(cdta2020, slot, hazard_slug, part, risk_rank)
}

# Select three gaps per district by walking its slots.
#
# Section 8d: the guarantee is three sentences. That creates a specific hazard
# the data must defend against - the gaps shown may not correspond to the
# risks listed above them on the same screen. So every selected gap carries
# risk_rank, and a cross-cutting gap standing in for a slot carries
# fallback_from (and fallback_part) naming what it stands in for.
#
# The walk stops at the last slot. A pinned hazard has no district-specific
# measure, so a gap attached to one has no district-specific justification
# either. cross-cutting is eligible because it is by definition not tied to
# any single hazard.
#
# Where a district has fewer than three slots, the sentences after its last
# slot come from cross-cutting too, with risk_rank set to the sentence number
# and NO fallback_from: nothing is being stood in for.
#
# WITHIN a slot, the pick is the most extreme value for this district rather
# than the lowest registry priority - see gap_extremeness(). The walk order is
# the district's risk ranking, because which hazard matters here is not a
# question about gap values.
select_district_gaps <- function(gaps, slots, crosswalk, n_target = 3) {
  shipped <- crosswalk |> filter(boro_code == 4) |> pull(cdta2020)
  scored <- gap_extremeness(gaps, shipped)
  slot_key <- function(h, p) ifelse(is.na(p) | !nzchar(p), h, paste0(h, "/", p))
  scored$slot_key <- slot_key(scored$hazard_slug, scored$part)

  lapply(split(slots, slots$cdta2020), function(sl) {
    district <- sl$cdta2020[1]
    pool <- scored |> filter(cdta2020 == district)
    sl$key <- slot_key(sl$hazard_slug, sl$part)
    top <- sl[sl$slot <= n_target, ]
    chosen <- list()

    take_from <- function(key, slot, risk_rank, fallback = NULL) {
      cand <- pool |>
        filter(slot_key == key,
               !gap_id %in% vapply(chosen, function(c) c$gap_id, integer(1))) |>
        # THE NON-FINDING FLOOR, then extremeness, then priority as a
        # deterministic tiebreak.
        #
        # Extremeness alone can surface a zero. Where most districts sit at
        # zero the midrank puts the zeros mid-scale, so a zero can win its
        # hazard even though it says nothing - QN11 drew two such sentences of
        # three, under a heading that reads "Neighborhood Resource Gaps".
        #
        # A gap that found nothing therefore sorts last within its slot: it is
        # used only when the slot has nothing else to offer, rather than never,
        # because a district with genuinely nothing to report should still get
        # a sentence rather than a gap in the list. When it is used,
        # sentence_template_zero states it as a finding of absence.
        arrange(is_non_finding, desc(extremeness), priority)
      if (nrow(cand) == 0) return(NULL)
      row <- cand[1, ]
      row$slot <- as.integer(slot)
      row$risk_rank <- as.integer(risk_rank)
      row$fallback_from <- if (is.null(fallback)) NA_character_ else fallback$hazard_slug
      row$fallback_part <- if (is.null(fallback)) NA_character_ else fallback$part
      row
    }

    # First pass: one gap per slot, in order. Not a fallback - the gap is
    # about the slot it was drawn from.
    for (i in seq_len(nrow(top))) {
      got <- take_from(top$key[i], top$slot[i], top$risk_rank[i])
      if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
    }

    # A slot that drew nothing gets a cross-cutting stand-in, at that slot's
    # position and rank, naming what it stands in for.
    #
    # `risk_rank` is normally the rank of the hazard the gap MEASURES.
    # Cross-cutting measures no ranked hazard and has no rank of its own, so
    # it borrows the slot's; `hazard_slug: "cross-cutting"` tells a consumer
    # which reading applies.
    filled <- vapply(chosen, function(c) c$slot, integer(1))
    for (i in which(!top$slot %in% filled)) {
      got <- take_from("cross-cutting", top$slot[i], top$risk_rank[i],
                       fallback = top[i, ])
      if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
    }

    # Sentences after the last slot (2026-10-20). Five districts have two
    # slots: coastal storm scores 0 there. Sentence 3 belongs to no hazard, so
    # it takes a cross-cutting gap, risk_rank = 3, and no fallback_from.
    for (s in seq_len(max(0L, n_target - nrow(sl))) + nrow(sl)) {
      got <- take_from("cross-cutting", s, s)
      if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
    }

    if (length(chosen) == 0) return(NULL)
    bind_rows(chosen) |>
      arrange(slot) |>
      mutate(display_order = row_number()) |>
      select(-slot_key)
  }) |> bind_rows()
}

# --- validating the computed matrix -----------------------------------------
#
# validate_gap_registry() checks the registry as config. This checks the
# NUMBERS, and it exists because three defects got past the registry check by
# being perfectly well-formed config over a computation that did something
# else:
#
#   1. Gap 31 declared unit `pct_population` with `denominator
#      district_population`, and was wired to gap_facility_exposure(). Both
#      numerator and denominator were facilities. Config was self-consistent;
#      config and computation were not. DATA_CONTRACT.md tells the frontend
#      `unit` is authoritative, so this rendered a facility share as a
#      population share on 12 of 14 district pages.
#   2. Gap 17 hit a zero denominator in 3 districts. NaN was dropped by
#      gap_entry()'s is.na() guard and NaN facts by gap_facts()'s NA filter, so
#      a divide-by-zero became a well-formed `available` row with no value and
#      a template that could not interpolate. No error anywhere.
#   3. Gap 2's template named {value}, which is not a facts key.
#
# All three are mechanically detectable once the values exist, and none is
# detectable from the registry alone. Hence a separate check, downstream.

# Which facts a unit obliges a gap to emit. The point is to tie the declared
# unit to the shape of the computation that produced it, so the two cannot
# disagree silently again.
GAP_UNIT_REQUIRED_FACTS <- list(
  pct_population = "people",   # a population share must say how many people
  pct_facilities = c("exposed", "total"),  # a facility share must show the ratio
  # Gap 33 declared pct_population while computing people-per-resource, so its
  # values ran 62 to 403 and would have rendered as "207%". It never displayed
  # - cross-cutting is only reachable through fall-through, which has never
  # fired - so nothing surfaced it until the placeholder check did.
  people_per_resource = c("people", "resources", "per_resource"),
  # access_mean gaps: the sentence states a duration, so the duration must be
  # a fact rather than the rounded root `value`.
  minutes = "minutes"
)

# Scoped to the districts that actually ship, and that scoping is not laziness.
#
# Section 8c computes the full 59-CDTA matrix so composites can normalise
# against other districts. But three gaps cannot be computed citywide at all:
# 33 and the retired 11 read the canonical resource file, and 31 reads FacDB
# hazard facilities fetched with boro = "QUEENS". All three are Queens-scoped
# by construction, so a citywide null is correct data, not a defect.
# (METHODOLOGY.md named 11 and 33; 31 belongs on that list and this check is
# what surfaced it.)
#
# The promise the contract makes is about the 14 payloads that ship. Asserting
# over those is asserting over the thing that can actually break a screen.
validate_gap_values <- function(gap_values, crosswalk) {
  fail <- function(...) stop("gap values: ", ..., call. = FALSE)

  shipped <- crosswalk |> filter(boro_code == 4) |> pull(cdta2020)

  # 0. Computed means available. The converse of check 1, and the one that
  #    was missing: compute_available_gaps() is a hand-kept list of add()
  #    calls that never reads registry status, so retiring a gap in the
  #    registry without deleting its add() shipped a `retired` row still
  #    carrying a value - breaking the contract's "only `available` has a
  #    value". Found 2026-09-22 when gaps 27 and 28 were retired that way.
  #    `not_applicable` is the one legitimate non-available status here: it is
  #    assigned per district downstream of the registry, not by it.
  stale <- gap_values |>
    filter(!status %in% c("available", "not_applicable")) |>
    distinct(gap_id, status)
  if (nrow(stale) > 0) {
    fail("gap(s) ", paste(sprintf("%s (%s)", stale$gap_id, stale$status),
                          collapse = ", "),
         " are still computed but not `available` in resource_gaps.csv. ",
         "Retiring or blocking a gap is two steps: the registry row, AND ",
         "removing its add() from compute_available_gaps(). Otherwise the ",
         "row ships with a value the contract says it cannot have.")
  }

  live <- gap_values |>
    filter(status == "available", cdta2020 %in% shipped)

  # 1. Available means displayable. The contract says so, and a null value with
  #    an `available` status is a promise the payload does not keep.
  novalue <- live |> filter(is.na(value))
  if (nrow(novalue) > 0) {
    bad <- novalue |> distinct(gap_id, cdta2020)
    fail("gap(s) marked `available` produced no value for ",
         paste(sprintf("gap %s/%s", bad$gap_id, bad$cdta2020),
               collapse = ", "),
         ". A zero denominator is not availability - either give the gap a ",
         "not_applicable status with a reason, or define the empty case ",
         "explicitly. Shipping `available` with no value means the sentence ",
         "cannot render and nothing says why.")
  }

  # 2. The declared unit must match the facts the computation actually emitted.
  #    This is the gap-31 check.
  for (u in names(GAP_UNIT_REQUIRED_FACTS)) {
    need <- GAP_UNIT_REQUIRED_FACTS[[u]]
    rows <- live |> filter(unit == u)
    if (nrow(rows) == 0) next
    for (f in need) {
      col <- paste0("facts_", f)
      if (!col %in% names(rows) || all(is.na(rows[[col]]))) {
        fail("gap(s) ", paste(unique(rows$gap_id), collapse = ", "),
             " declare unit `", u, "` but emit no `", f, "` fact. ",
             "A unit is a claim about what the denominator was; if the ",
             "computation cannot supply ", f, ", the unit is wrong.")
      }
    }
  }

  # 3. A gap that can report an unreliable number must have copy for it.
  #    Without this, a CV-49 estimate silently renders in the flat sentence,
  #    which is the exact failure the hedged variant exists to prevent - and it
  #    fails on the district where the number is worst, not on all of them, so
  #    it would not show up in a spot check.
  if ("facts_reliable" %in% names(live)) {
    unhedged <- live |>
      filter(!is.na(facts_reliable), !facts_reliable,
             is.na(sentence_template_unreliable) |
               !nzchar(sentence_template_unreliable))
    if (nrow(unhedged) > 0) {
      fail("gap(s) ", paste(unique(unhedged$gap_id), collapse = ", "),
           " report an estimate DCP would grey out (CV > 30) in ",
           paste(unhedged$cdta2020, collapse = ", "),
           " but have no `sentence_template_unreliable`. Either author the ",
           "hedged copy or stop selecting unreliable values.")
    }
  }

  # 4. A gap that can report nothing must have copy for it. Without this, a
  #    zero renders through the flat template as "0 of X's 12 hazardous
  #    facilities sit..." - wrong English, and it frames an absence as a
  #    quantity. Checked over the whole shipped matrix, not just what gets
  #    selected, because gaps/<slug>.json ships every row.
  zeroed <- live |>
    filter(polarity == "higher_is_worse", !is.na(value), value == 0,
           is.na(sentence_template_zero) | !nzchar(sentence_template_zero))
  if (nrow(zeroed) > 0) {
    bad <- zeroed |> distinct(gap_id)
    fail("gap(s) ", paste(bad$gap_id, collapse = ", "),
         " report a value of zero in ",
         paste(unique(zeroed$cdta2020), collapse = ", "),
         " but have no `sentence_template_zero`. A higher_is_worse zero is a ",
         "finding of absence and needs its own sentence - the flat template ",
         "renders it as a quantity.")
  }

  # 5. Every placeholder resolves inside facts. Failure is otherwise silent -
  #    a missing key renders as a literal "{district}", not an error.
  for (i in seq_len(nrow(live))) {
    # The variant that will actually ship, not the flat one - a hedged template
    # can name a placeholder the flat one does not.
    tmpl <- gap_sentence_template(live[i, ])
    if (is.null(tmpl) || is.na(tmpl) || !nzchar(tmpl)) next
    ph <- unique(regmatches(tmpl, gregexpr("\\{([a-z0-9_]+)\\}", tmpl))[[1]])
    ph <- gsub("[{}]", "", ph)
    have <- names(gap_facts(live[i, ]))
    missing <- setdiff(ph, have)
    if (length(missing) > 0) {
      fail("gap ", live$gap_id[i], " (", live$cdta2020[i],
           ") has template placeholder(s) {", paste(missing, collapse = "}, {"),
           "} with no matching fact. Every placeholder must resolve inside ",
           "`facts` - the frontend interpolates that object and nothing else.")
    }
  }

  TRUE
}

# --- payloads ---------------------------------------------------------------

# The fact each unit puts in front of the reader. The headline number is what
# the sentence is about, and it is the ROUNDED one - `facts` carries display
# values, `value` carries full precision.
GAP_UNIT_HEADLINE_FACT <- c(
  pct_population      = "pct",
  pct_facilities      = "exposed",
  people_per_resource = "per_resource",
  count_speakers      = "speakers",
  per_10k             = "per_10k",
  minutes             = "minutes"
)

gap_headline_value <- function(row) {
  h <- unname(GAP_UNIT_HEADLINE_FACT[row$unit])
  if (length(h) == 0 || is.na(h)) return(NA_real_)
  col <- paste0("facts_", h)
  if (!col %in% names(row)) return(NA_real_)
  v <- row[[col]]
  if (length(v) == 0) return(NA_real_)
  as.numeric(v[[1]])
}

# Is this row a non-finding - a measure that found nothing worth a sentence?
#
# TESTED ON THE DISPLAYED NUMBER, NOT THE RAW VALUE. QN11's gap 12 is
# 0.023%, which is not zero and passed an exact-zero test, but `facts_pct`
# rounds it to 0.0 and the sentence reads "0% of people in
# Auburndale-Bayside-Douglaston live where flooding overlaps a wastewater
# facility." The reader sees a zero, so the floor has to see one too.
#
# Only meaningful for `higher_is_worse`, where zero means "none of the bad
# thing". For `higher_is_better` a zero is the OPPOSITE - zero cool options per
# 10,000 residents is the worst possible result, not a non-finding. The same
# number means opposite things depending on polarity, so this deliberately
# claims only the case it can defend.
gap_is_non_finding <- function(row) {
  pol <- row$polarity
  if (length(pol) == 0 || is.na(pol) || pol != "higher_is_worse") return(FALSE)
  hv <- gap_headline_value(row)
  !is.na(hv) && hv == 0
}

# Vectorised over a table of computed gap rows.
gap_non_finding_flags <- function(tbl) {
  if (nrow(tbl) == 0) return(logical(0))
  vapply(seq_len(nrow(tbl)), function(i) gap_is_non_finding(tbl[i, ]),
         logical(1))
}

# Which copy variant this row renders with.
#
# PRECEDENCE: zero, then unreliable, then flat.
#
# Zero wins because it changes the sentence's subject rather than its
# confidence. "An estimated 0 people" is not a hedge, it is nonsense - if the
# measure found nothing, the uncertainty of the magnitude is moot. The two
# cannot currently co-occur (gap 18 is the only unreliable gap and its value is
# a speaker count that cannot be zero, since a district with no uncovered
# language produces no row), but the order is fixed here rather than left to
# whichever branch happens to run first.
#
# Each variant falls back to the flat template when not authored.
# validate_gap_values() fails on exactly those cases, so these are
# belt-and-braces defaults rather than silent degrades.
gap_sentence_template <- function(row) {
  flat <- row$sentence_template
  if (is.na(flat) || !nzchar(flat)) return(NULL)

  usable <- function(x) {
    !is.null(x) && length(x) > 0 && !is.na(x) && nzchar(x)
  }

  # Copy uses an EXACT zero, not the rounded one the selection floor uses.
  # "No one in Auburndale-Bayside-Douglaston lives where flooding overlaps a
  # wastewater facility" would be false at 0.023% - that is roughly 41 people.
  # A rounding-zero is demoted by the floor and so almost never displays; if it
  # ever does, it renders the flat sentence and reads "0%", which is imprecise
  # rather than untrue. Erring toward imprecise is the right way round here.
  exact_zero <- !is.na(row$value) && row$polarity == "higher_is_worse" &&
    row$value == 0
  if (exact_zero && usable(row[["sentence_template_zero"]])) {
    return(row[["sentence_template_zero"]])
  }

  reliable <- row[["facts_reliable"]]
  unreliable <- !is.null(reliable) && length(reliable) > 0 &&
    !is.na(reliable) && !isTRUE(reliable)
  if (unreliable && usable(row[["sentence_template_unreliable"]])) {
    return(row[["sentence_template_unreliable"]])
  }

  flat
}

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
    # Present on every gap so a grouped view never renders a raw slug. Two
    # slugs have no hazard page behind them - see GAP_ORPHAN_HAZARD_LABELS.
    hazard_label = gap_hazard_label(row$hazard_slug),
    # The part of the hazard the gap measures (heavy-rain, coastal-storm,
    # extreme-heat): the hazard page anchor. Absent on gaps whose hazard has
    # no parts.
    part = gap_part(row$part),
    label = row$label,
    value = if (is.na(row$value)) NULL else round(as.numeric(row$value), 3),
    unit = row$unit,
    polarity = row$polarity,
    status = row$status,
    # The pipeline picks the copy variant, not the frontend.
    #
    # A gap whose facts carry `reliable = FALSE` ships the hedged sentence
    # instead of the flat one. Doing it here keeps the frontend contract to a
    # single rule - interpolate `sentence_template` with `facts` - rather than
    # asking every consumer to know that one gap has two templates and which
    # field switches between them. `facts$reliable` still ships, so the UI can
    # also style the number if it wants to.
    #
    # The threshold is DCP's (CV > 30), so it belongs with the data. Letting a
    # component decide when to hedge would put a statistical standard in a
    # Svelte file, where it goes stale and nobody reviews it.
    sentence_template = gap_sentence_template(row),
    facts = gap_facts(row)
  )
  if (include_selection) {
    e$risk_rank <- if (is.na(row$risk_rank)) NULL else as.integer(row$risk_rank)
    # Section 8d: without this the screen is quietly misleading. A gap drawn
    # from outside the top three is about a different hazard than the risk
    # listed above it, and only this field lets the UI say so.
    e$fallback_from <- if (is.na(row$fallback_from)) NULL else row$fallback_from
    # Which part of fallback_from the stand-in fills, where that hazard has
    # parts: "stands in for Flooding's coastal-storm slot".
    e$fallback_part <- gap_part(row$fallback_part)
  }
  compact_list(e)
}

# A registry `part` as the payload carries it: the id, or absent.
gap_part <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) NULL else x
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
          hazard_label = gap_hazard_label(reg$hazard_slug),
          part = gap_part(reg$part),
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

validate_gap_selection <- function(sel, slots, crosswalk, n_target = 3) {
  shipped <- crosswalk |> filter(boro_code == 4)
  missing <- setdiff(shipped$cdta2020, sel$cdta2020)
  if (length(missing) > 0) {
    stop("No gap selected at all for: ", paste(missing, collapse = ", "))
  }

  # Exactly three, not "up to". Since 2026-10-20 the guarantee holds in every
  # district - those with two slots fill the third from cross-cutting - so a
  # short district is a regression to catch, not a state to allow.
  counts <- sel |> filter(cdta2020 %in% shipped$cdta2020) |> count(cdta2020)
  short <- counts$cdta2020[counts$n != n_target]
  if (length(short) > 0) {
    stop("Not exactly ", n_target, " gaps selected for ",
         paste(short, collapse = ", "),
         ". If a district has fewer than ", n_target, " slots, the rest need ",
         "an available cross-cutting gap.")
  }

  if (any(is.na(sel$risk_rank))) {
    stop("Selected gap(s) with no risk_rank: ",
         paste(unique(sel$cdta2020[is.na(sel$risk_rank)]), collapse = ", "))
  }

  # Every non-cross-cutting gap must sit in one of THIS district's slots, at
  # that slot's position and rank. Joined to the district's own slots, not the
  # registry's list of parts: coastal storm is a measured part citywide but
  # has no slot in the five districts where it scores 0, and before 2026-10-14
  # those five each showed a coastal-storm gap. This is the check that keeps
  # it off. Keyed on part as well as hazard, so a heavy-rain gap cannot fill
  # the coastal slot.
  key <- function(h, p) {
    as.character(ifelse(is.na(p) | !nzchar(p), h, paste0(h, "/", p)))
  }
  slot_tbl <- slots |>
    mutate(key = key(hazard_slug, part)) |>
    select(cdta2020, key, slot_pos = slot, slot_rank = risk_rank)
  n_slots <- slots |> count(cdta2020, name = "n_slots")
  chk <- sel |>
    mutate(key = key(hazard_slug, part)) |>
    left_join(slot_tbl, by = c("cdta2020", "key")) |>
    left_join(n_slots, by = "cdta2020") |>
    mutate(n_slots = coalesce(n_slots, 0L))

  own <- chk |> filter(!hazard_slug %in% GAP_PSEUDO_HAZARDS)
  stray <- own |> filter(is.na(slot_pos))
  if (nrow(stray) > 0) {
    stop("Gap(s) from a hazard part with no slot in that district: ",
         paste(sprintf("%s gap %s (%s)", stray$cdta2020, stray$gap_id,
                       stray$key), collapse = ", "))
  }
  misplaced <- own |> filter(slot != slot_pos | risk_rank != slot_rank)
  if (nrow(misplaced) > 0) {
    stop("Gap(s) not at their slot's position and rank: ",
         paste(sprintf("%s gap %s", misplaced$cdta2020, misplaced$gap_id),
               collapse = ", "))
  }

  # A cross-cutting gap is in one of exactly two positions, and the presence
  # of fallback_from says which. With it: standing in for a slot of this
  # district that drew no gap of its own, at that slot's position and rank.
  # Without it: after the district's last slot. Anything else is a sentence
  # placed where nothing put it.
  cc <- chk |> filter(hazard_slug %in% GAP_PSEUDO_HAZARDS)
  stand_in <- cc |>
    filter(!is.na(fallback_from)) |>
    mutate(fb_key = key(fallback_from, fallback_part)) |>
    left_join(rename(slot_tbl, fb_key = key, fb_pos = slot_pos, fb_rank = slot_rank),
              by = c("cdta2020", "fb_key"))
  own_keys <- paste(own$cdta2020, own$key)
  bad_stand_in <- stand_in |>
    filter(is.na(fb_pos) | slot != fb_pos | risk_rank != fb_rank |
             paste(cdta2020, fb_key) %in% own_keys)
  bad_slot <- cc |> filter(is.na(fallback_from),
                           slot <= n_slots | slot > n_target | risk_rank != slot)
  if (nrow(bad_stand_in) + nrow(bad_slot) > 0) {
    stop("Cross-cutting gap(s) in no legitimate slot: ",
         paste(sprintf("%s gap %s (slot %s, fallback_from %s)",
                       c(bad_stand_in$cdta2020, bad_slot$cdta2020),
                       c(bad_stand_in$gap_id, bad_slot$gap_id),
                       c(bad_stand_in$slot, bad_slot$slot),
                       c(bad_stand_in$fallback_from, bad_slot$fallback_from)),
               collapse = ", "))
  }

  # A district must never show the same indicator twice, or fill one slot
  # twice.
  dupes <- sel |> count(cdta2020, gap_id) |> filter(n > 1)
  dup_slots <- sel |> count(cdta2020, slot) |> filter(n > 1)
  if (nrow(dupes) + nrow(dup_slots) > 0) {
    stop("Duplicate gap or slot in one district: ",
         paste(unique(c(dupes$cdta2020, dup_slots$cdta2020)), collapse = ", "))
  }
  TRUE
}

# --- access measures contract -----------------------------------------------
#
# Produced OUTSIDE the DAG by scripts/04_access_measures.R and published in a
# data-v* release. See ACCESS_MEASURES.md for the full brief.
#
# The DAG never routes. It reads this file as a format = "file" target, exactly
# as d26 read its zonal statistics, which keeps r5r, a JVM and a
# multi-hundred-MB OSM extract out of CI.

ACCESS_FACILITY_SETS <- c("cool_options_indoor", "parks",
                          "evacuation_centers", "hospitals")
ACCESS_THRESHOLDS <- c(10, 15, 20, 30)
# Only the small sets get a full travel-time matrix; the large ones are
# isochrone unions, so minutes_to_nearest is legitimately absent for them.
ACCESS_SETS_WITH_MINUTES <- c("evacuation_centers", "hospitals")

read_access_stats <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    geoid = readr::col_character(),
    facility_set = readr::col_character(),
    minutes_to_nearest = readr::col_double(),
    .default = readr::col_logical()
  ))
}

validate_access_stats <- function(acc) {
  within_cols <- paste0("within_", ACCESS_THRESHOLDS)
  required <- c("geoid", "facility_set", "minutes_to_nearest", within_cols)
  missing <- setdiff(required, names(acc))
  if (length(missing) > 0) {
    stop("access_stats.csv: missing column(s) ", paste(missing, collapse = ", "),
         " - see ACCESS_MEASURES.md")
  }
  assert_no_na(acc, c("geoid", "facility_set"))

  bad_set <- setdiff(acc$facility_set, ACCESS_FACILITY_SETS)
  if (length(bad_set) > 0) {
    stop("access_stats.csv: unknown facility_set(s) ",
         paste(bad_set, collapse = ", "))
  }
  absent <- setdiff(ACCESS_FACILITY_SETS, acc$facility_set)
  if (length(absent) > 0) {
    stop("access_stats.csv: no rows for facility_set(s) ",
         paste(absent, collapse = ", "), " - all four are needed")
  }

  # 15-digit 2020 block GEOIDs. A tract geoid is 11 digits, and silently
  # accepting one would collapse ~40 blocks into a single origin.
  bad_geoid <- unique(acc$geoid[nchar(acc$geoid) != 15])
  if (length(bad_geoid) > 0) {
    stop("access_stats.csv: ", length(bad_geoid), " geoid(s) are not 15-digit ",
         "block ids - a tract geoid is 11 digits. e.g. ", bad_geoid[1])
  }
  dupes <- acc |> count(geoid, facility_set) |> filter(n > 1)
  if (nrow(dupes) > 0) {
    stop("access_stats.csv: ", nrow(dupes), " duplicate (geoid, facility_set) rows")
  }

  # The sets that feed access_mean must actually carry minutes.
  for (fs in ACCESS_SETS_WITH_MINUTES) {
    rows <- acc |> filter(facility_set == fs)
    if (all(is.na(rows$minutes_to_nearest))) {
      stop("access_stats.csv: facility_set '", fs, "' has no ",
           "minutes_to_nearest, but access_mean gaps need it")
    }
  }

  # Monotonicity. A block within 10 minutes must be within 15, 20 and 30. A
  # violation means the isochrones were unioned inconsistently, which produces
  # plausible numbers rather than an error.
  for (i in seq_len(length(ACCESS_THRESHOLDS) - 1)) {
    lo <- within_cols[i]; hi <- within_cols[i + 1]
    bad <- sum(acc[[lo]] & !acc[[hi]], na.rm = TRUE)
    if (bad > 0) {
      stop("access_stats.csv: ", bad, " row(s) are ", lo, " but not ", hi,
           " - the isochrone unions are inconsistent")
    }
  }

  # A walk time at or below the straight-line equivalent means a broken network
  # graph, which is the failure mode ACCESS_MEASURES.md calls out as most likely
  # to pass unnoticed. Only checkable where minutes are present.
  neg <- acc |> filter(!is.na(minutes_to_nearest), minutes_to_nearest < 0)
  if (nrow(neg) > 0) {
    stop("access_stats.csv: ", nrow(neg), " negative walk time(s)")
  }
  TRUE
}
