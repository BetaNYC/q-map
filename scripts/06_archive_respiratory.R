# scripts/06_archive_respiratory.R
#
# Appends this week's respiratory illness figures to the committed archive.
#
# DOHMH publishes a 12-week rolling window. Anything that falls out of it is
# gone permanently and cannot be recovered from any source. This script is the
# only thing standing between the project and losing that history week by week.
#
# Run WEEKLY. The feed updates on Fridays. Missing a run leaves a permanent
# hole - validate_respiratory() warns about non-weekly intervals so a hole is
# visible rather than silent.
#
# This is d26's refresh-311.yml pattern and should become a scheduled workflow:
# fetch, append, commit only if changed. Until CI exists it is run by hand.
#
# Usage:  uvr run scripts/06_archive_respiratory.R

library(dplyr)
library(readr)
library(tidyr)

source("R/validate.R")
source("R/content.R")   # force_arrays, %||%
source("R/conditions.R")

message("Fetching the respiratory illness feed ...")
incoming <- fetch_respiratory()
message("  ", nrow(incoming), " rows, ",
        dplyr::n_distinct(incoming$date), " weeks: ",
        min(incoming$date), " to ", max(incoming$date))

archive <- if (file.exists(ARCHIVE_PATH)) read_respiratory_archive(ARCHIVE_PATH) else NULL
before <- if (is.null(archive)) 0L else nrow(archive)

merged <- merge_respiratory_archive(archive, incoming)
invisible(validate_respiratory(merged))

dir.create(dirname(ARCHIVE_PATH), showWarnings = FALSE, recursive = TRUE)
write_csv(merged, ARCHIVE_PATH)

added <- nrow(merged) - before
message("\nArchive: ", before, " -> ", nrow(merged), " rows (+", added, ")")
message("  weeks held: ", dplyr::n_distinct(merged$date),
        " (", min(merged$date), " to ", max(merged$date), ")")
if (added == 0) message("  nothing new - the feed has not advanced since the last run")
