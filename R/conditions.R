# R/conditions.R
#
# Current conditions - the respiratory illness trend behind the chip on screen
# 01 and box B on screen 02.
#
# THE ARCHIVE IS THE SOURCE OF TRUTH, not the live feed.
#
# DOHMH publishes only a 12-week rolling window. Anything older is gone and
# cannot be recovered from anywhere. So a scheduled job appends each week to
# `data/archive/respiratory_illness.csv`, which is committed, and the pipeline
# computes from the archive rather than the feed. That makes the build
# reproducible and means a seasonal comparison becomes possible later - it is
# impossible today only because nobody started archiving sooner.
#
# Decided 2026-08-31 (PIPELINE_DESIGN.md section 9 item 0): use the CITYWIDE
# AGGREGATE and label it citywide. The aggregate metric has submetric `Overall`
# and no borough breakdown, and the three named pathogens that do have one are
# percentages of ED visits for potentially co-coded categories, so they cannot
# validly be summed into a Queens figure.

RESPIRATORY_URL <- paste0(
  "https://raw.githubusercontent.com/nychealth/respiratory-illness-data/",
  "main/data/ED_data_respiratory_illness.csv")

# The narrow file, not the wide OpenData export. Three columns, clean ISO
# dates, no malformed values. The wide file carries 223 rows whose `Date` is a
# bare integer - Unix epoch days - which a naive as.Date() turns into NA or,
# worse, silently parses against the wrong origin. All of those rows are
# death-related metrics this project never touches.
RESPIRATORY_METRICS <- c("Respiratory illness visits",
                         "Respiratory illness hospitalizations")

ARCHIVE_PATH <- "data/archive/respiratory_illness.csv"

fetch_respiratory <- function(url = RESPIRATORY_URL) {
  raw <- readr::read_csv(url, show_col_types = FALSE, col_types = readr::cols(
    date = readr::col_date(format = "%Y-%m-%d"), .default = readr::col_double()
  ))

  missing <- setdiff(RESPIRATORY_METRICS, names(raw))
  if (length(missing) > 0) {
    stop("Respiratory feed: missing metric column(s) ",
         paste(missing, collapse = ", "), " - has the file schema changed?")
  }

  raw |>
    tidyr::pivot_longer(all_of(RESPIRATORY_METRICS),
                        names_to = "metric", values_to = "value") |>
    filter(!is.na(value)) |>
    arrange(date, metric)
}

# Append-only. Existing rows are never modified, because a published figure
# that later changes upstream is itself information, and because the archive is
# the only record that the window ever contained them.
merge_respiratory_archive <- function(archive, incoming,
                                      today = as.character(Sys.Date())) {
  incoming <- incoming |> mutate(first_seen = today)
  if (is.null(archive) || nrow(archive) == 0) return(incoming)

  new_rows <- incoming |> anti_join(archive, by = c("date", "metric"))
  bind_rows(archive, new_rows) |> arrange(date, metric)
}

read_respiratory_archive <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    date = readr::col_date(format = "%Y-%m-%d"),
    metric = readr::col_character(),
    value = readr::col_double(),
    first_seen = readr::col_character()
  ))
}

validate_respiratory <- function(x) {
  assert_no_na(x, c("date", "metric", "value"))

  # The Unix-epoch-days trap. A bare integer date parsed against R's 1970
  # origin yields something plausible-looking rather than an error, so assert
  # the parsed dates land in a sane range rather than merely being non-NA.
  if (any(x$date < as.Date("2020-01-01") | x$date > Sys.Date() + 30)) {
    stop("Respiratory archive: date(s) outside 2020-today. A bare-integer ",
         "date parsed against the wrong origin produces exactly this.")
  }

  bad_metric <- setdiff(x$metric, RESPIRATORY_METRICS)
  if (length(bad_metric) > 0) {
    stop("Respiratory archive: unexpected metric(s) ",
         paste(bad_metric, collapse = ", "))
  }

  # The values are PERCENTAGES of ED visits, not counts. "6.11" means 6.11% of
  # emergency department visits, not 6,110 people. The wide OpenData file
  # carries a `display` column that says so; the narrow file does not, so the
  # equivalent guard is a range assertion. A switch to counts would put these
  # in the hundreds or thousands and fail here rather than rendering a number
  # roughly 100x too small with a percent sign after it.
  if (any(x$value < 0 | x$value > 100)) {
    stop("Respiratory archive: value(s) outside 0-100. These are percentages ",
         "of ED visits - has the feed switched to counts?")
  }

  # Weekly series, published on Fridays.
  gaps <- x |>
    group_by(metric) |>
    arrange(date, .by_group = TRUE) |>
    mutate(gap = as.numeric(date - dplyr::lag(date))) |>
    filter(!is.na(gap), gap != 7)
  if (nrow(gaps) > 0) {
    warning(nrow(gaps), " non-weekly interval(s) in the respiratory archive - ",
            "a missed run leaves a permanent hole")
  }
  TRUE
}

# Emit the derived object, not the series - plus the 12 most recent points, so
# a sparkline is possible without a second request. Under 1 KB either way.
build_conditions <- function(archive, data_as_of = as.character(Sys.Date())) {
  latest <- archive |>
    group_by(metric) |>
    arrange(date, .by_group = TRUE) |>
    slice_tail(n = 2) |>
    ungroup()

  short <- latest |> count(metric) |> filter(n < 2)
  if (nrow(short) > 0) {
    stop("Respiratory: fewer than 2 points for ",
         paste(short$metric, collapse = ", "), " - cannot state a direction")
  }

  mk <- function(m) {
    rows <- latest |> filter(metric == m) |> arrange(date)
    cur <- rows$value[2]; prev <- rows$value[1]
    series <- archive |> filter(metric == m) |> arrange(date) |> slice_tail(n = 12)
    list(
      # geography is an explicit field for the same reason reference_frame is:
      # this number sits on a district page and is NOT about that district.
      geography = "nyc",
      metric = m,
      value = cur,
      previous = prev,
      direction = if (cur > prev) "up" else if (cur < prev) "down" else "flat",
      pct_change = round((cur - prev) / prev * 100, 1),
      unit = "pct_of_ed_visits",
      window_weeks = 12L,
      as_of = as.character(rows$date[2]),
      series = lapply(seq_len(nrow(series)), function(i) {
        list(date = as.character(series$date[i]), value = series$value[i])
      })
    )
  }

  list(
    as_of = as.character(max(archive$date)),
    data_as_of = data_as_of,
    archive_weeks = as.integer(dplyr::n_distinct(archive$date)),
    respiratory_illness_visits = mk("Respiratory illness visits"),
    respiratory_illness_hospitalizations = mk("Respiratory illness hospitalizations")
  )
}

write_conditions <- function(conditions, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(force_arrays(conditions, c("series")), path,
                       auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  path
}
