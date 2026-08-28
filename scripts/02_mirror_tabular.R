# scripts/02_mirror_tabular.R
#
# Tier-2 mirror: the two hand-downloaded workbooks.
#
#   DCP  Top LEP Languages Spoken at Home by PUMA  (ACS 2020-2024 5-yr PUMS)
#   DOHMH Community Health Profiles Public Use Dataset, 2026
#
# Neither has an API. Both are Excel workbooks with a two-row split header and
# trailing footnote rows, so unlike the stormwater layers these are genuinely
# transformed rather than copied: the mirror flattens them into plain CSV once,
# here, rather than re-deriving the same fragile parse on every pipeline run.
#
# Usage:  uvr run scripts/02_mirror_tabular.R
#
# Outputs: data/prepared/lep_languages_puma.csv
#          data/prepared/chp_by_cd.csv
#
# Published as assets of the data-v* GitHub Release. See DATA_SOURCES.md.

library(readxl)
library(dplyr)
library(readr)
library(tidyr)

SRC <- "data/source"
OUT <- "data/prepared"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## --- DCP LEP languages by PUMA ---------------------------------------------
#
# Sheet layout: title on rows 1-2, blank rows 3-4, a two-row split header on
# rows 5-6, data from row 7. read_excel(skip = 6) mangles the names, so they
# are supplied explicitly.
#
# PUMA20 is read as character. It is a 4-digit code today; coercing to numeric
# would strip any future leading zero.

LEP_SRC   <- file.path(SRC, "dcp-top-LEP-lang-spk-at-home-puma_2024acs5yr-PUMS.xlsx")
LEP_SHEET <- "Top 10 Langs Spkn (LEP) by PUMA"

lep <- read_excel(
  LEP_SRC, sheet = LEP_SHEET, skip = 6,
  col_names = c("borough", "puma2020", "cd_string",
                "puma_rank", "language", "estimate", "moe", "cv"),
  col_types = c("text", "text", "text", "text", "text",
                "numeric", "numeric", "numeric")
) |>
  filter(!is.na(puma2020), !is.na(language))

# Each PUMA's block opens with a Total row (rank blank, language "Total"),
# then ranks 1..10. Keep both - the total is the denominator for any share.
stopifnot(sum(lep$language == "Total") > 0)

write_csv(lep, file.path(OUT, "lep_languages_puma.csv"), na = "")
message(sprintf("lep_languages_puma.csv   %5d rows  %4d PUMAs",
                nrow(lep), dplyr::n_distinct(lep$puma2020)))

## --- DOHMH Community Health Profiles ---------------------------------------
#
# CHP_all_data has section groupings on row 1 ("Who We Are", "Housing and
# Neighborhood Conditions") and the real variable names on row 2, so skip = 1.
# The last rows are footnotes about suppression and relative standard error,
# not data, and are dropped by keeping only numeric IDs.
#
# ID is a BoroCD for districts (101-503) and 0-5 for the city and boroughs.
# The city and borough rows are kept deliberately: they are the comparison
# baselines the wireframe's "average for the city" framing needs, and they cost
# six rows.

CHP_SRC <- file.path(SRC, "2026-chp-pud.xlsx")

chp_raw <- read_excel(CHP_SRC, sheet = "CHP_all_data", skip = 1,
                      .name_repair = "unique_quiet")

chp <- chp_raw |>
  filter(!is.na(suppressWarnings(as.numeric(ID)))) |>
  mutate(ID = as.integer(ID)) |>
  # drop columns that are entirely empty - artefacts of the merged section
  # header rather than real variables
  select(where(~ !all(is.na(.)))) |>
  rename(borocd = ID)

n_cd <- sum(chp$borocd >= 100)
if (n_cd != 59) {
  stop("CHP: expected 59 community-district rows, got ", n_cd)
}

write_csv(chp, file.path(OUT, "chp_by_cd.csv"), na = "")
message(sprintf("chp_by_cd.csv            %5d rows  %4d cols  (%d districts + %d baselines)",
                nrow(chp), ncol(chp), n_cd, nrow(chp) - n_cd))

message("\nMirrored 2 tabular sources to ", OUT)
