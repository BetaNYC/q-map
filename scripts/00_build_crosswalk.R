# scripts/00_build_crosswalk.R
#
# Builds data/crosswalk/cdta_crosswalk.csv - the geography spine everything
# else joins through.
#
# Standalone, not part of the DAG, and run by hand. The output is committed to
# git and reviewed as a diff; the pipeline only ever reads it. That is
# deliberate: 59 rows of judgment about how five geographies reconcile belong
# in a reviewable file, not in a runtime derivation.
#
# Usage:  uvr run scripts/00_build_crosswalk.R
#
# Inputs:
#   - NYC DCP CDTA 2020 feature service (fetched)
#   - data/source/dcp-top-LEP-lang-spk-at-home-puma_2024acs5yr-PUMS.xlsx
#   - DOHMH Heat Vulnerability Index feature service (fetched)
#
# The LEP workbook is a gitignored Tier-2 mirror. See DATA_SOURCES.md.

library(sf)
library(dplyr)
library(httr)
library(readr)
library(readxl)
library(tidyr)

source("R/validate.R")
source("R/crosswalk.R")

LEP_PATH <- "data/source/dcp-top-LEP-lang-spk-at-home-puma_2024acs5yr-PUMS.xlsx"

OUT_PATH <- "data/crosswalk/cdta_crosswalk.csv"

message("Fetching CDTA 2020 boundaries (CDTAType = 0, citywide) ...")
cdta <- get_cdta()
message("  ", nrow(cdta), " features")

message("Building crosswalk ...")
crosswalk <- build_cdta_crosswalk(cdta, lep_path = LEP_PATH)

message("Validating ...")
message("Fetching HVI (for validation) ...")
hvi <- get_hvi()
invisible(validate_cdta_crosswalk(crosswalk, hvi = hvi))

invisible(write_cdta_crosswalk(crosswalk, OUT_PATH))
message("Wrote ", OUT_PATH, " (", nrow(crosswalk), " rows)")
