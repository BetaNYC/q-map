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
  # Gaps 11 and 17 were retired - see BLOCKERS in R/registry.R for why. Their
  # registry rows survive with gap_id and a reason, per section 8c; only the
  # computation goes.
  add(12, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$flood_x_wastewater, d))
  add(18, gap_18_language_coverage(inputs$lep, inputs$languages, inputs$crosswalk))
  add(27, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$solid_waste_buffer, d))
  add(28, gap_population_exposure(inputs$tracts, inputs$tract_pop,
                                  inputs$tract_cdta, inputs$wastewater_buffer, d))
  add(31, gap_facility_exposure(inputs$hazard_facilities_cdta, inputs$stormwater, d))
  add(33, gap_33_communication(inputs$resources_cdta, out[["7"]], d))

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
    left_join(select(reg, gap_id, hazard_slug, priority, label, unit, polarity,
                     sentence_template, sentence_template_zero,
                     sentence_template_unreliable, status),
              by = "gap_id") |>
    left_join(select(crosswalk_display_names(inputs$crosswalk),
                     cdta2020, facts_district),
              by = "cdta2020") |>
    relocate(gap_id, hazard_slug, priority, cdta2020, value)
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
#
# WITHIN a hazard, the pick is the most extreme value for this district rather
# than the lowest registry priority - see gap_extremeness(). The walk order
# across hazards is unchanged: it still follows the district's risk ranking,
# because which hazard matters here is not a question about gap values.
select_district_gaps <- function(gaps, hazards, crosswalk, n_target = 3) {
  ranked <- hazards |> filter(ranked) |> arrange(cdta2020, rank)
  shipped <- crosswalk |> filter(boro_code == 4) |> pull(cdta2020)
  scored <- gap_extremeness(gaps, shipped)

  lapply(split(ranked, ranked$cdta2020), function(hz) {
    district <- hz$cdta2020[1]
    pool <- scored |> filter(cdta2020 == district)

    top3 <- hz$slug[hz$rank <= n_target]
    chosen <- list()

    take_from <- function(slug, risk_rank, fallback_from = NA_character_) {
      cand <- pool |>
        filter(hazard_slug == slug,
               !gap_id %in% vapply(chosen, function(c) c$gap_id, integer(1))) |>
        # THE NON-FINDING FLOOR, then extremeness, then priority as a
        # deterministic tiebreak.
        #
        # Extremeness alone can surface a zero. Where most districts sit at
        # zero the midrank puts the zeros mid-scale, so a zero can win its
        # hazard even though it says nothing - QN11 drew two such sentences of
        # three, under a heading that reads "Neighborhood Resource Gaps".
        #
        # A gap that found nothing therefore sorts last within its hazard: it
        # is used only when the hazard has nothing else to offer, rather than
        # never, because a district with genuinely nothing to report should
        # still get a sentence rather than a gap in the list. When it is used,
        # sentence_template_zero states it as a finding of absence.
        arrange(is_non_finding, desc(extremeness), priority)
      if (nrow(cand) == 0) return(NULL)
      row <- cand[1, ]
      row$risk_rank <- risk_rank
      row$fallback_from <- fallback_from
      row
    }

    # The highest-ranked top-three slot nothing has filled yet.
    #
    # A slot is filled two ways, and BOTH have to count: by a gap drawn from
    # that hazard directly, or by a fallback that already claimed it. Counting
    # only the first hands the same slot to two different fallbacks - with
    # heat, rain and hazmat all barren, coastal-storm and cross-cutting both
    # came back `fallback_from: extreme-heat` while heavy-rain and hazmat went
    # unclaimed.
    unfilled <- function() {
      taken   <- vapply(chosen, function(c) c$hazard_slug, character(1))
      claimed <- vapply(chosen, function(c) {
        v <- c$fallback_from
        if (length(v) == 0 || is.na(v)) NA_character_ else as.character(v)
      }, character(1))
      setdiff(top3, c(taken, claimed[!is.na(claimed)]))[1]
    }
    rank_of <- function(slug) {
      if (is.na(slug)) return(NA_integer_)
      as.integer(hz$rank[match(slug, hz$slug)])
    }

    # First pass: one gap per top-three hazard, in rank order. Not a fallback -
    # the gap is about the hazard it was drawn from.
    for (i in seq_len(min(n_target, nrow(hz)))) {
      got <- take_from(hz$slug[i], hz$rank[i])
      if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
    }

    # Fall-through: continue down the ranked hazards, then cross-cutting.
    if (length(chosen) < n_target && nrow(hz) > n_target) {
      for (i in seq(n_target + 1, nrow(hz))) {
        if (length(chosen) >= n_target) break
        got <- take_from(hz$slug[i], hz$rank[i],
                         fallback_from = unfilled())
        if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
      }
    }

    # Cross-cutting, last resort.
    #
    # This branch carried two latent defects, neither reachable while all 14
    # districts fill three sentences from their top three - which they do
    # today, so nothing had ever executed it:
    #
    #   1. It passed risk_rank = NA_integer_ into `if (risk_rank > n_target)`,
    #      which is `if (NA)` and ERRORS - "missing value where TRUE/FALSE
    #      needed". The fall-through path crashed the build rather than
    #      degrading.
    #   2. gap_entry() then dropped risk_rank on NA, so the payload would have
    #      broken DATA_CONTRACT.md's unconditional promise that every displayed
    #      gap carries one.
    #
    # A cross-cutting gap now takes the rank of the hazard it STANDS IN FOR.
    #
    # Be precise about what that does to the field, because it is not uniform.
    # `risk_rank` is normally the rank of the hazard the gap MEASURES - a
    # coastal-storm gap standing in for slot 1 still carries rank 4, which is
    # section 8d's original intent and stays unchanged. Cross-cutting measures
    # no ranked hazard and has no rank of its own, so it borrows the slot's.
    #
    # That is the single case where the two readings differ, and
    # `hazard_slug: "cross-cutting"` is what tells a consumer which applies -
    # it is a registry-only pseudo-hazard with no page, so a UI already has to
    # treat it separately. Together with `fallback_from` the row is fully
    # legible: fills slot 2, stands in for heavy rain, measures something
    # cross-cutting.
    #
    # The alternative was NA, which is what broke the contract in the first
    # place. A separate `slot` field would be cleaner still if this ever needs
    # to be uniform.
    if (length(chosen) < n_target) {
      stands_for <- unfilled()
      # Nothing to stand in for means fewer than three ranked hazards exist,
      # and a gap with no slot has no business on the screen.
      if (!is.na(stands_for)) {
        got <- take_from("cross-cutting",
                         risk_rank = rank_of(stands_for),
                         fallback_from = stands_for)
        if (!is.null(got)) chosen[[length(chosen) + 1]] <- got
      }
    }
    if (length(chosen) == 0) return(NULL)
    bind_rows(chosen) |> mutate(display_order = row_number())
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
  people_per_resource = c("people", "resources", "per_resource")
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
  per_10k             = "per_10k"
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
          hazard_label = gap_hazard_label(reg$hazard_slug),
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
