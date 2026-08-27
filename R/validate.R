# R/validate.R

# Shared, generic helpers check a single property
# stop() accompanied by a diagnostic message
#
# Ported from d26-gi-web-map/R/validate.R. The five assert_* helpers below are
# unchanged. Everything after them is new and q-map specific.

assert_crs <- function(x, expected_epsg) {
  actual <- st_crs(x)$epsg
  if (is.na(actual) || actual != expected_epsg) {
    stop(paste0("CRS: expected EPSG:", expected_epsg, ", got EPSG:", actual))
  }
}

assert_row_count <- function(x, min, max) {
  n <- nrow(x)
  if (n < min || n > max) {
    stop(paste0("Row count: ", n, ", expected ", min, "-", max))
  }
}

assert_no_na <- function(x, cols) {
  for (col in cols) {
    n_na <- sum(is.na(x[[col]]))
    if (n_na > 0) {
      stop(paste0("Column '", col, "' has ", n_na, " NA values"))
    }
  }
}

assert_col_type <- function(x, col, expected_type) {
  actual <- class(x[[col]])[1]
  if (actual != expected_type) {
    stop(paste0("Column '", col, "': expected ", expected_type, ", got ", actual))
  }
}

assert_valid_geom <- function(x) {
  if (!all(st_is_valid(x))) {
    stop(paste0(sum(!st_is_valid(x)), " invalid geometries"))
  }
}

# --- q-map additions -------------------------------------------------------

# Uniqueness. d26 never needed this because ZCTA5 uniqueness fell out of the
# census join. q-map has five identifier schemes for the same 59 rows, and a
# silent many-to-one in any of them corrupts every figure joined through it.
assert_unique <- function(x, col) {
  dupes <- x[[col]][duplicated(x[[col]])]
  if (length(dupes) > 0) {
    stop(paste0(
      "Column '", col, "' is not unique: ", length(unique(dupes)),
      " duplicated value(s) - ", paste(unique(dupes), collapse = ", ")
    ))
  }
}

# Uniqueness with a known, enumerated set of legitimate duplicates.
#
# This exists because of a specific finding: 2020 PUMAs do NOT nest 1:1 with
# community districts, contrary to what PIPELINE_DESIGN.md 2 assumed. Four
# PUMAs each cover two CDs (4121 = MN 1&2, 4165 = MN 5&6, 4221 = BX 1&2,
# 4263 = BX 3&6). A plain assert_unique() would fail on correct data; dropping
# the check entirely would hide a real regression. So: duplicates are allowed,
# but only exactly these, and their absence is an error too.
assert_unique_except <- function(x, col, allowed) {
  dupes <- sort(unique(x[[col]][duplicated(x[[col]])]))
  allowed <- sort(unique(allowed))
  unexpected <- setdiff(dupes, allowed)
  missing <- setdiff(allowed, dupes)
  if (length(unexpected) > 0) {
    stop(paste0(
      "Column '", col, "' has unexpected duplicate(s): ",
      paste(unexpected, collapse = ", ")
    ))
  }
  if (length(missing) > 0) {
    stop(paste0(
      "Column '", col, "' was expected to have duplicate(s) that are absent: ",
      paste(missing, collapse = ", "),
      " - upstream geography may have changed"
    ))
  }
}

assert_matches <- function(x, col, pattern) {
  bad <- x[[col]][!grepl(pattern, x[[col]])]
  if (length(bad) > 0) {
    stop(paste0(
      "Column '", col, "': ", length(bad), " value(s) do not match ", pattern,
      " - e.g. '", bad[1], "'"
    ))
  }
}

# Two-way set equality on a key, by anti_join in both directions.
#
# This is d26's validate_nfhl() idiom generalized. It is a structural-drift
# check, not a shape check: it fails both when we lose a row upstream expects
# and when upstream grows a row we do not know about. That second direction is
# the one that catches silent problems.
assert_keys_match <- function(x, y, by, label_x = "left", label_y = "right") {
  missing_from_y <- dplyr::anti_join(x, y, by = by)
  missing_from_x <- dplyr::anti_join(y, x, by = by)
  if (nrow(missing_from_y) > 0 || nrow(missing_from_x) > 0) {
    stop(paste0(
      "Key mismatch on '", paste(by, collapse = ", "), "': ",
      nrow(missing_from_y), " row(s) in ", label_x, " absent from ", label_y,
      "; ", nrow(missing_from_x), " row(s) in ", label_y, " absent from ",
      label_x
    ))
  }
}
