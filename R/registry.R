# R/registry.R
#
# Registry freshness: a blocked row must still be blocked.
#
# WHY THIS EXISTS
#
# map_layers.csv and resource_gaps.csv both carry `status` and `blocked_on`,
# hand-edited, and both double as an acquisition backlog. That works while
# somebody remembers to revisit a row when its dataset lands. Nobody did:
# seven of seventeen map layers claimed `blocked_on_data` while the data was
# already sitting in the target store - `evac_zones` was marked "not yet
# fetched" with six features built, and `surge_current` was blocked on
# `fvi_tract_geometry` with 2,208 tract polygons built.
#
# The existing check runs one direction only. validate_layer_tiles() asserts
# available => the artifact exists, and never asks whether a blocked row is
# still blocked. That is the same asymmetry METHODOLOGY.md already records for
# the vacuous adjacency check: a one-way comparison passes for the wrong
# reason. assert_keys_match() answers it for join keys by anti_joining both
# ways. This is the equivalent for status.
#
# THE SHAPE
#
# Three pieces, deliberately separated so the predicate stays testable and the
# registry stays declarative:
#
#   BLOCKERS         the vocabulary. One entry per token that may appear in a
#                    `blocked_on` column, with what kind of thing it is and how
#                    to tell whether it has been resolved.
#   blocker_facts()  gathers availability from the real upstream targets, once,
#                    into a plain list. Keeps BLOCKERS free of DAG references.
#   validate_registry_freshness()
#                    the assertion. Vocabulary first, then freshness.
#
# The vocabulary lives in R rather than a third CSV on purpose. A committed
# blockers.csv would be one more hand-maintained status file to drift - which
# is the problem, not the fix. A predicate is code; it belongs in code.

# --- the vocabulary ---------------------------------------------------------
#
# `kind` decides whether a resolved blocker is an error:
#
#   "data"    waiting on a dataset or a computed input. If this resolves, the
#             row is stale and the build must fail - that is the whole point.
#   "scope"   a deliberate decision not to build something yet. Tree canopy is
#             blocked on `land_cover_processing` because 121 GB of LiDAR is out
#             of scope, not because the file is missing. Resolving it does not
#             oblige us to build it, so it never fails.
#   "reason"  not a blocker at all - the retired gaps reuse this column to say
#             why they were retired. Listed so a typo on a retired row is still
#             caught, never checked for freshness.
#
# `resolved` returns TRUE when the blocker no longer applies. It reads only
# from the facts list, never from targets directly.

BLOCKERS <- list(

  # -- data blockers: these fail the build if they come true -----------------

  # The Flood Vulnerability Index service, 2,208 census tracts carrying ss_cur.
  # Blocks surge_current, which needs tract geometry to tile.
  fvi_tract_geometry = list(
    kind = "data", label = "FVI tract geometry",
    resolved = function(f) isTRUE(f$fvi_rows > 0 && f$fvi_has_geometry)
  ),

  # Hurricane evacuation zones. NOTE: the registry currently spells this token
  # `epne-qv9x`, the Open Data id. Dataset ids make poor tokens - `ayer-cga7`
  # below is the cautionary case - so PR1 renames it to this and the id moves
  # to the `source` column where it belongs.
  hurricane_evac_zones_layer = list(
    kind = "data", label = "Hurricane evacuation zones",
    resolved = function(f) isTRUE(f$evac_zones_rows > 0)
  ),

  # Cool Options, filtered to indoor Cooling Center rooms. Named for the thing,
  # not the dataset, because the dataset has already changed once: cooling
  # CENTERS are emergency-only and cannot be a standing indicator, so the
  # year-round Cool Options list stands in. See METHODOLOGY.md.
  cooling_centers_dataset = list(
    kind = "data", label = "Year-round indoor cool options",
    resolved = function(f) isTRUE(f$cool_options_rows > 0)
  ),

  # Hurricane evacuation centres. The registry token is `ayer-cga7`, which is
  # the WRONG dataset - a visualisation asset with zero columns, 60 rows of
  # empty objects. The working id is p5md-weyf. A row blocked on a dataset id
  # that was never the right dataset can never resolve, so the token is renamed
  # to the capability and the id lives in `source`.
  evacuation_centers_layer = list(
    kind = "data", label = "Hurricane evacuation centres",
    resolved = function(f) isTRUE(f$evac_centers_rows > 0)
  ),

  # The canonical resource store. Blocked three layer rows that PR5 replaces
  # with a single category-toggled `resources` row.
  resource_model = list(
    kind = "data", label = "Canonical resource store",
    resolved = function(f) isTRUE(f$canonical_resources_rows > 0)
  ),

  # The r5r walk-time table. Nine of twelve blocked gaps wait only on this.
  # It is a file, not a target - the DAG reads it and never routes. See
  # ACCESS_MEASURES.md.
  access_measures = list(
    kind = "data", label = "r5r access_stats.csv",
    resolved = function(f) isTRUE(f$access_stats_exists)
  ),

  # Council data request, unfiled. The only item on a third party's clock.
  hospital_surge_capacity = list(
    kind = "data", label = "Hospital surge capacity",
    resolved = function(f) isTRUE(f$hospital_surge_exists)
  ),

  # A second, separate request nobody has opened: p5md-weyf publishes centres
  # but no capacity, so gap 15 stays blocked even once the centres are wired.
  evacuation_center_capacity = list(
    kind = "data", label = "Evacuation centre capacity",
    resolved = function(f) isTRUE(f$evac_capacity_exists)
  ),

  # MOCEJ / EJNYC. Not fetched.
  environmental_burden_score = list(
    kind = "data", label = "Environmental Burden Score",
    resolved = function(f) isTRUE(f$ebs_exists)
  ),

  # The JRA's 2080s coastal surge polygon. Deliberately excluded from the
  # ranking (METHODOLOGY.md ranks coastal storm on present-day ss_cur), and as
  # of PR-scope now excluded as forward-looking context too, so nothing fetches
  # it. Still a data blocker rather than scope: if it is ever fetched, the row
  # is stale and should be revisited.
  coastal_surge_layer = list(
    kind = "data", label = "Coastal Surge Flooding 2080s",
    resolved = function(f) isTRUE(f$coastal_surge_rows > 0)
  ),

  # -- scope decisions: resolving these does not oblige us to build ----------

  # 121 GB of 2017 LiDAR land cover. Cropping and reclassifying it for all of
  # Queens is the only thing that would push COG delivery back into scope.
  # PIPELINE_DESIGN.md section 9 item 5 left this open; it is still open.
  land_cover_processing = list(
    kind = "scope", label = "Queens-wide land cover processing",
    resolved = function(f) FALSE
  ),

  # A composite whose inputs are known but whose formula is not. Five registry
  # rows were "input lists, not formulas" and this is what is left of them.
  # Never resolvable by acquiring data - it needs a method decision.
  method_unspecified = list(
    kind = "scope", label = "Composite method not specified",
    resolved = function(f) FALSE
  ),

  # -- retired reasons: listed for typo-catching, never checked --------------

  respiratory_illness_by_district = list(
    kind = "reason", label = "Respiratory illness by district does not exist",
    resolved = function(f) FALSE
  ),
  no_matching_hazard = list(
    kind = "reason", label = "Attached to a hazard q-map does not carry",
    resolved = function(f) FALSE
  ),
  merged_into_gap_15 = list(
    kind = "reason", label = "Duplicate measure, merged",
    resolved = function(f) FALSE
  ),

  # Gap 17 asked what share of a district's evacuation centres sit inside an
  # evacuation zone. Wrong question for a barrier peninsula: you evacuate OFF
  # the Rockaways, and QN09, QN10 and QN14 hold no centre at all, so the
  # denominator was zero and the row shipped `available` with no value and an
  # uninterpolatable template. Retired rather than repaired - the underlying
  # finding (Queens has 15 of the city's 60 centres, none in the Rockaways) is
  # real and belongs in hazard-page copy, not in a ratio.
  measure_misspecified = list(
    kind = "reason", label = "The measure asks the wrong question",
    resolved = function(f) FALSE
  ),

  # Gap 11 counted critical resources in a flood area. Its only input was the
  # is_critical flag on the category crosswalk, which was arbitrary and is
  # removed. No flag, no denominator.
  critical_flag_removed = list(
    kind = "reason", label = "Depended on the removed is_critical flag",
    resolved = function(f) FALSE
  )
)

# --- gathering the facts ----------------------------------------------------
#
# Called once from a target with the real upstream objects. Everything that
# follows reads this list, so BLOCKERS never has to know a target name and can
# be exercised in a test with a hand-written list.
#
# Missing arguments are treated as absent rather than an error: this is called
# from two registries at different points in the DAG, and a fact nobody asks
# about should not force a dependency.

# PROVISIONAL PATHS. access_stats.csv is real - ACCESS_MEASURES.md specifies it
# and a separate session is producing it. The other three name datasets nobody
# has requested yet, and the paths below are a guess.
#
# Be honest about what that costs: file.exists() on a path nothing ever writes
# returns FALSE forever, so those three blockers behave exactly like `scope`
# ones until the path is real. The check does not protect them - it simply
# does not lie about them. When each request lands, pin the real path here and
# the row starts being watched.
ACCESS_STATS_PATH   <- "data/prepared/access_stats.csv"
HOSPITAL_SURGE_PATH <- "data/prepared/hospital_surge.csv"        # provisional
EVAC_CAPACITY_PATH  <- "data/prepared/evac_capacity.csv"         # provisional
EBS_PATH            <- "data/prepared/environmental_burden.csv"  # provisional

blocker_facts <- function(fvi = NULL, evac_zones = NULL, cool_options = NULL,
                          evac_centers = NULL, canonical_resources = NULL,
                          coastal_surge = NULL,
                          access_stats_path = ACCESS_STATS_PATH,
                          hospital_surge_path = HOSPITAL_SURGE_PATH,
                          evac_capacity_path = EVAC_CAPACITY_PATH,
                          ebs_path = EBS_PATH) {
  n <- function(x) if (is.null(x)) 0L else nrow(x)
  list(
    fvi_rows                 = n(fvi),
    fvi_has_geometry         = inherits(fvi, "sf"),
    evac_zones_rows          = n(evac_zones),
    cool_options_rows        = n(cool_options),
    evac_centers_rows        = n(evac_centers),
    canonical_resources_rows = n(canonical_resources),
    coastal_surge_rows       = n(coastal_surge),
    access_stats_exists      = file.exists(access_stats_path),
    hospital_surge_exists    = file.exists(hospital_surge_path),
    evac_capacity_exists     = file.exists(evac_capacity_path),
    ebs_exists               = file.exists(ebs_path)
  )
}

# --- the assertion ----------------------------------------------------------
#
# `blocked_on` may name more than one blocker, comma-separated. A row is only
# unblocked when EVERY blocker it names has resolved - one of two missing
# datasets landing does not make the row buildable.
#
# Two failures, in order. The vocabulary check runs first because an unknown
# token would otherwise be silently treated as unresolved, which is exactly the
# failure this function exists to prevent - a typo would read as "still
# blocked" forever.

split_blockers <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(character(0))
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

validate_registry_freshness <- function(reg, facts, registry_name,
                                        id_col = "layer_id") {
  tokens <- lapply(reg$blocked_on, split_blockers)

  # 1. Vocabulary. Every token must be declared, or a typo becomes a permanent
  #    false "blocked" that nothing will ever catch.
  unknown <- setdiff(unique(unlist(tokens)), names(BLOCKERS))
  if (length(unknown) > 0) {
    stop(registry_name, ": blocked_on names token(s) not in BLOCKERS - ",
         paste(unknown, collapse = ", "),
         ". Add them to R/registry.R with a kind and a resolver, ",
         "or fix the spelling.")
  }

  # 2. Freshness. Only blocked_on_data rows, and only "data" blockers: a
  #    "scope" blocker resolving is not an error, and a "reason" is not a
  #    blocker at all.
  stale <- character(0)
  for (i in seq_len(nrow(reg))) {
    if (!identical(reg$status[i], "blocked_on_data")) next
    tk <- tokens[[i]]
    if (length(tk) == 0) next

    data_tk <- Filter(function(t) BLOCKERS[[t]]$kind == "data", tk)
    if (length(data_tk) == 0 || length(data_tk) != length(tk)) next

    if (all(vapply(data_tk, function(t) BLOCKERS[[t]]$resolved(facts), logical(1)))) {
      stale <- c(stale, sprintf("%s (blocked_on: %s)",
                                reg[[id_col]][i], paste(tk, collapse = ", ")))
    }
  }

  # Fail with the consequence, not the symptom - the same register
  # validate_gap_registry() uses. A reader of this message should know what
  # breaks on the screen, not merely which assertion tripped.
  if (length(stale) > 0) {
    stop(registry_name, ": row(s) marked blocked_on_data whose data is ",
         "already built - ", paste(stale, collapse = "; "),
         ". The frontend reads this registry as the definitive catalogue, so a ",
         "stale row means a layer or gap that exists is invisible to the app. ",
         "Set `available` if the artifact ships, `pending_build` if the data is ",
         "in hand but the writer is not built, or correct the blocked_on token.")
  }

  TRUE
}
