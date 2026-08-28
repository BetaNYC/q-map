# R/districts.R
#
# The 02-screen payload: data/processed/districts/<slug>.json, one per Queens
# district. Sections A, C and D of the wireframe.
#
# Two schema rules from PIPELINE_DESIGN.md 3 are load-bearing here:
#
#   Every statistic is an object, not a scalar. {value, unit, reference_frame}.
#   The screen mixes framings - "3 out of 5, average among citywide Community
#   Districts" sits beside "percent of district in a coastal flood plain" - and
#   if the frame is not a field it becomes a hardcoded English string in a
#   component and drifts from the data.
#
#   Emit facts, let the frontend write the sentence. Copy changes far more often
#   than data, and nobody should re-run R to fix a comma.

stat <- function(value, unit, reference_frame = NULL, ...) {
  out <- list(value = value, unit = unit)
  if (!is.null(reference_frame)) out$reference_frame <- reference_frame
  extra <- list(...)
  if (length(extra) > 0) out <- c(out, extra)
  out
}

# Districts are computed citywide and displayed for Queens. The payloads are
# written only for what ships.
DISPLAY_BORO_CODE <- 4L

build_district_payloads <- function(crosswalk, hazards, measures, chp, lep) {
  chp_d <- chp_districts(chp)
  chp_city <- chp_citywide(chp)

  shipped <- crosswalk |> filter(boro_code == DISPLAY_BORO_CODE)

  lapply(seq_len(nrow(shipped)), function(i) {
    row <- shipped[i, ]
    m <- measures |> filter(cdta2020 == row$cdta2020)
    c_row <- chp_d |> filter(borocd == row$borocd)
    hz <- hazards |> filter(cdta2020 == row$cdta2020) |> arrange(rank)

    list(
      cdta2020 = row$cdta2020,
      slug = row$slug,
      display_name = row$display_name,
      cd_label = row$cd_label,
      boro = row$boro_name,
      coad = if (is.na(row$coad)) NULL else row$coad,

      ## A - hazards, ordered ------------------------------------------------
      hazards = lapply(seq_len(nrow(hz)), function(j) {
        h <- hz[j, ]
        out <- list(
          slug = h$slug, label = h$label,
          rank = h$rank, ranked = h$ranked
        )
        if (h$ranked) {
          out$risk <- round(h$risk, 4)
          out$severity <- h$severity
          out$exposure <- round(h$exposure, 4)
        } else {
          out$reason <- h$pin_reason
        }
        out
      }),

      ## C - risk profile ----------------------------------------------------
      risk_profile = list(
        hvi = stat(m$hvi, "index_1_5", "nyc_cdta_2020",
                   citywide_percentile = round(m$hvi_pct, 3)),
        stormwater_flood_pct = stat(round(m$rain_pct, 2), "pct_area",
                                    "nyc_cdta_2020",
                                    note = paste("DEP stormwater flood area,",
                                                 "current sea levels; includes",
                                                 "nuisance and deep flooding")),
        # Denominator is ACS tract population, NOT the CHP figure reported as
        # population.total below. The two disagree by up to 20% per district
        # (different vintages and small-area methods), so this share is
        # internally consistent within ACS but must not be multiplied by
        # population.total to recover a headcount. See METHODOLOGY.md.
        surge_pop_pct = stat(round(m$coastal_pop_share * 100, 1), "pct_population",
                             "nyc_cdta_2020",
                             source = "acs_2023_5yr",
                             note = "residents in a present-day storm-surge tract"),
        chem_business_count = stat(m$chem_business_count, "count",
                                   "nyc_cdta_2020",
                                   citywide_percentile = round(m$chem_pct, 3)),
        pivi = stat(m$pivi, "index_1_5", "nyc_cdta_2020",
                    note = "pandemic influenza vulnerability; pinned, not ranked")
      ),

      ## D - population ------------------------------------------------------
      population = list(
        # A stat object, not a bare integer, so its source travels with it -
        # this is CHP's modified intercensal estimate, not the ACS figure the
        # surge share is computed against.
        total = stat(as.integer(c_row$Overall_Pop), "count", "nyc_cdta_2020",
                     source = "chp_2026"),
        pct_65_plus = stat(num_or_null(c_row$Age65plus), "pct", "nyc_cdta_2020"),
        pct_limited_english = stat(num_or_null(c_row$Ltd_Eng_Prof), "pct",
                                   "nyc_cdta_2020"),
        neighbors_helpful_pct = stat(num_or_null(c_row$Helpful_Neighbor), "pct",
                                     "nyc_cdta_2020", source = "chp"),
        languages = lep_for_district(lep, row$puma2020),
        # Four citywide PUMAs cover two districts each. All are MN/BX, so this
        # is FALSE for every Queens district - but the field ships anyway so the
        # frontend never has to know that, and it stays correct if scope grows.
        languages_shared_puma = isTRUE(row$puma_shared)
      ),

      meta = list(
        hazard_model = "severity_x_exposure",
        hazard_model_status = "provisional_pending_expert_review",
        citywide_baseline_population = as.integer(chp_city$Overall_Pop)
      )
    )
  }) |> setNames(shipped$slug)
}

# CHP marks suppressed and unreliable estimates with symbols rather than NA, so
# a column can arrive as character. Coerce, and let a non-numeric become NULL
# in the payload rather than the string "^" reaching a component.
num_or_null <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  if (length(v) == 0 || is.na(v)) NULL else round(v, 1)
}

write_district_payloads <- function(payloads, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- vapply(names(payloads), function(slug) {
    p <- file.path(dir, paste0(slug, ".json"))
    jsonlite::write_json(payloads[[slug]], p, auto_unbox = TRUE,
                         digits = NA, null = "null", na = "null")
    p
  }, character(1))
  unname(paths)
}

# --- validation -------------------------------------------------------------

validate_district_payloads <- function(payloads, crosswalk) {
  shipped <- crosswalk |> filter(boro_code == DISPLAY_BORO_CODE)
  if (length(payloads) != nrow(shipped)) {
    stop("Expected ", nrow(shipped), " district payloads, got ", length(payloads))
  }

  n_ranked <- length(HAZARD_SEVERITY)
  n_total <- n_ranked + length(HAZARD_PINNED)

  for (slug in names(payloads)) {
    p <- payloads[[slug]]

    # Fields the wireframe renders unconditionally must never be null. coad is
    # excluded deliberately - null is its normal value in 13 of 14 districts.
    for (f in c("cdta2020", "slug", "display_name", "cd_label", "boro")) {
      if (is.null(p[[f]]) || is.na(p[[f]])) {
        stop(slug, ": required field '", f, "' is null")
      }
    }
    tot <- p$population$total
    if (is.null(tot$value) || is.na(tot$value) || tot$value <= 0) {
      stop(slug, ": population total is missing or non-positive")
    }
    if (is.null(tot$source)) stop(slug, ": population total has no source")

    # Every hazard appears exactly once, ranks are 1..8 with no gaps, and the
    # ranked ones come first. A gap here would render as a missing row.
    if (length(p$hazards) != n_total) {
      stop(slug, ": expected ", n_total, " hazards, got ", length(p$hazards))
    }
    ranks <- vapply(p$hazards, function(h) h$rank, numeric(1))
    if (!identical(sort(ranks), as.numeric(seq_len(n_total)))) {
      stop(slug, ": hazard ranks are not 1..", n_total, " exactly once")
    }
    slugs <- vapply(p$hazards, function(h) h$slug, character(1))
    if (anyDuplicated(slugs)) stop(slug, ": duplicate hazard slug")
    is_ranked <- vapply(p$hazards, function(h) isTRUE(h$ranked), logical(1))
    if (!identical(is_ranked, c(rep(TRUE, n_ranked), rep(FALSE, length(HAZARD_PINNED))))) {
      stop(slug, ": ranked hazards must occupy positions 1-", n_ranked)
    }

    # A pinned hazard must carry its reason, or the UI has no way to say why it
    # is not ranked and "#5 of 8" reads as "less dangerous than #4".
    for (h in p$hazards[!is_ranked]) {
      if (is.null(h$reason) || !nzchar(h$reason)) {
        stop(slug, ": pinned hazard '", h$slug, "' has no reason")
      }
    }

    # Every risk_profile entry must carry its unit and frame, or the number
    # becomes uninterpretable the moment it leaves this file.
    for (nm in names(p$risk_profile)) {
      s <- p$risk_profile[[nm]]
      if (is.null(s$unit)) stop(slug, ": risk_profile$", nm, " has no unit")
      if (is.null(s$reference_frame)) {
        stop(slug, ": risk_profile$", nm, " has no reference_frame")
      }
    }
  }

  TRUE
}

# The Rockaways is the calibration case for the whole hazard model: the most
# surge-exposed district in Queens by a wide margin. If it is not coastal-storm
# led, the severity weights or the exposure normalisation are wrong. Asserted
# rather than spot-checked so a future weight change cannot quietly break it.
validate_hazard_calibration <- function(payloads) {
  qn14 <- payloads[["q14"]]
  if (is.null(qn14)) stop("q14 (The Rockaways) payload missing")
  if (qn14$hazards[[1]]$slug != "coastal-storm") {
    stop("Calibration: QN14 The Rockaways leads with '",
         qn14$hazards[[1]]$slug, "', expected 'coastal-storm'")
  }

  qn01 <- payloads[["q01"]]
  if (qn01$hazards[[1]]$slug == "hazmat") {
    stop("Calibration: QN01 Astoria-Queensbridge leads with hazmat - the ",
         "chemical-business count is dominating the ordering again")
  }
  TRUE
}
