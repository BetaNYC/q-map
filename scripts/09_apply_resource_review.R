# scripts/09_apply_resource_review.R
#
# Reads the SME resource review back (see scripts/08_resource_review_sheet.R)
# and turns it into changes to data/canonical/resources.csv.
#
# Proposes by default, like scripts/03_seed_resources.R: nothing in the
# canonical file changes until you have read the proposal and re-run with
# --apply.
#
# Usage:
#   uvr run scripts/09_apply_resource_review.R -- review.csv [missing.csv]
#   uvr run scripts/09_apply_resource_review.R -- review.csv [missing.csv] --apply
#
#   review.csv   the `review` tab, downloaded as CSV
#   missing.csv  the `missing` tab, downloaded as CSV (optional)
#
# Writes data/review/sme_review/:
#   proposed_changes.csv   one row per field changed: Remove and Change
#                          category on rows in the canonical file
#   handwork.csv           everything a person must act on: Fix details,
#                          Unsure, notes on kept rows, anything about a QPL
#                          branch, and rows that changed since the sheet
#   draft_manual_rows.csv  the Missing tab as `manual` rows, geocoded with
#                          GeoSearch. NOT applied. verified_on is left blank,
#                          so the pipeline refuses a row until someone has
#                          confirmed it and dated it. Paste in by hand.
#
# What is applied automatically, and why only this:
#   Remove           removed_reason = "SME review <date>: <note>"
#   Change category  canonical_category = the chosen category
#   a renamed row    name = what the reviewer typed in the name cell
# Each is a single cell with an unambiguous new value. A "Fix details" note
# is free text describing a correction, so a person makes it. Edits typed
# straight into address, phone, website or operator are not applied either,
# but they are listed in handwork.csv rather than lost.
#
# A rename is spotted against `original_name`, the hidden column holding the
# name as sent - not against resources.csv, which may have changed since. If
# both the sheet and the file changed a name, neither wins: it goes to
# handwork.csv.
#
# QPL branches are not in the canonical file (R/qpl.R) and cannot be removed
# or recategorised here. Decisions on them go to handwork.csv, to raise with
# QPL or to override with a manual row.

library(dplyr)
library(readr)

source("R/validate.R")
source("R/content.R")     # for %||%
source("R/resources.R")

CANONICAL <- "data/canonical/resources.csv"
OUT_DIR <- "data/review/sme_review"
REVIEW_DECISIONS <- c("Keep", "Remove", "Change category", "Fix details", "Unsure")
TODAY <- as.character(Sys.Date())

args <- commandArgs(trailingOnly = TRUE)
apply_changes <- "--apply" %in% args
files <- setdiff(args, "--apply")
if (length(files) < 1 || length(files) > 2) {
  stop("Usage: uvr run scripts/09_apply_resource_review.R -- review.csv [missing.csv] [--apply]")
}

# Every value as text, blanks as "", whitespace trimmed: a Sheets export can
# carry a stray space in a dropdown cell, and NA-vs-"" is noise here.
read_tab <- function(path) {
  read_csv(path, col_types = cols(.default = "c"), na = character(),
           show_col_types = FALSE) |>
    mutate(across(everything(), trimws))
}

# --- inputs -------------------------------------------------------------------

cx <- read_resource_categories("data/crosswalk/resource_categories.csv")
category_of <- cx |>
  filter(canonical_category != "exclude") |>
  distinct(canonical_category, canonical_label)

# Read the canonical file as raw text columns, so writing it back changes only
# the cells edited. readr round-trips it byte for byte this way (checked
# 2026-11-04); read_canonical_resources() would retype lon/lat and lose that.
canonical <- read_csv(CANONICAL, col_types = cols(.default = "c"),
                      na = character(), trim_ws = FALSE, show_col_types = FALSE)

review <- read_tab(files[1])
needed <- c("resource_id", "original_name", "name", "district", "category",
            "decision", "new_category", "note")
absent <- setdiff(needed, names(review))
if (length(absent) > 0) {
  stop(files[1], " is missing column(s) ", paste(absent, collapse = ", "),
       ". Is it the `review` tab?")
}

# --- validate the whole sheet before acting on any of it ----------------------
#
# Every problem is collected and reported at once, so a round trip to the
# reviewer fixes them all rather than one per run.

problems <- character()
note_problem <- function(rows, what) {
  if (nrow(rows) > 0) {
    problems <<- c(problems, paste0(what, ": ",
                                    paste(head(rows$resource_id, 5), collapse = ", "),
                                    if (nrow(rows) > 5) paste0(" (+", nrow(rows) - 5, " more)")))
  }
}

# Match the dropdown case-insensitively. A typed "remove" means Remove.
review <- review |>
  mutate(decision = coalesce(
    REVIEW_DECISIONS[match(tolower(decision), tolower(REVIEW_DECISIONS))], decision))

note_problem(filter(review, nzchar(decision), !decision %in% REVIEW_DECISIONS),
             "decision not one of the dropdown values")
note_problem(filter(review, resource_id %in% resource_id[duplicated(resource_id)]),
             "resource_id appears twice")
note_problem(filter(review, !nzchar(resource_id)), "row with no resource_id")
note_problem(filter(review, !nzchar(name)), "name left blank")

# An id that is neither in the canonical file nor a QPL branch means the
# column was edited, or the sheet is from another project.
known <- review$resource_id %in% canonical$resource_id | startsWith(review$resource_id, "qpl:")
note_problem(review[!known & nzchar(review$resource_id), ], "resource_id not recognised")

# A category given either as its label (the dropdown) or its slug.
review <- review |>
  mutate(new_slug = category_of$canonical_category[
    coalesce(match(tolower(new_category), tolower(category_of$canonical_label)),
             match(tolower(new_category), category_of$canonical_category))])
note_problem(filter(review, decision == "Change category", is.na(new_slug)),
             "Change category with no category, or one not in the list")

if (length(problems) > 0) {
  stop("The review has problems; nothing was changed.\n  - ",
       paste(problems, collapse = "\n  - "), call. = FALSE)
}

# --- route each decision ------------------------------------------------------

# Whitespace collapsed for comparison only, exactly as the generator did, or
# the 36 names with stray line breaks would all read as renamed.
squish <- function(x) gsub("\\s+", " ", trimws(coalesce(x, "")))

current <- canonical |>
  select(resource_id, cur_category = canonical_category, removed_reason,
         cur_name = name, cur_operator = operator, cur_address = address,
         cur_phone = phone, cur_website = website)
review <- review |> left_join(current, by = "resource_id")

is_qpl <- startsWith(review$resource_id, "qpl:")
is_removed <- !is.na(review$removed_reason) & nzchar(review$removed_reason)
# The sheet shows category LABELS. A row whose label no longer matches the
# canonical file was edited after the sheet was made, and the reviewer judged
# something that is no longer there.
cur_label <- category_of$canonical_label[match(review$cur_category, category_of$canonical_category)]
drifted <- !is_qpl & !is.na(cur_label) & cur_label != review$category

review <- review |>
  mutate(route = case_when(
    !nzchar(decision) ~ "unreviewed",
    is_qpl & decision %in% c("Remove", "Change category", "Fix details", "Unsure") ~ "handwork: QPL branch - raise with QPL, or override with a manual row",
    is_qpl & nzchar(note) ~ "handwork: note on a QPL branch",
    is_qpl ~ "keep",
    is_removed ~ "handwork: already removed since the sheet was made",
    drifted ~ "handwork: category changed since the sheet was made",
    decision == "Remove" ~ "apply",
    decision == "Change category" & new_slug == cur_category ~ "keep",
    decision == "Change category" ~ "apply",
    decision == "Fix details" ~ "handwork: fix details",
    decision == "Unsure" ~ "handwork: reviewer unsure",
    nzchar(note) ~ "handwork: note on a kept row",
    TRUE ~ "keep"
  ))

# --- renames ----------------------------------------------------------------
#
# Separate from the decision: a row can be kept, or recategorised, AND
# renamed. A rename on a row being removed is moot and ignored.

renamed <- squish(review$name) != squish(review$original_name)
review <- review |>
  mutate(name_route = case_when(
    !renamed ~ "none",
    decision == "Remove" ~ "none",
    is_qpl ~ "handwork: rename of a QPL branch - raise with QPL",
    is_removed ~ "none",   # already routed to handwork above
    squish(cur_name) != squish(original_name) ~
      "handwork: renamed in the sheet, but resources.csv also changed the name since",
    TRUE ~ "apply"
  ))

# --- edits typed into other detail cells ---------------------------------------
#
# Not applied: an address edit moves a map point and needs regeocoding, and a
# phone typed into a sheet is easy to garble. But never dropped silently.
# Compared with resources.csv, so a field changed there since the sheet was
# made shows up here too; either way a person should look.
detail_cols <- c("operator", "address", "phone", "website")
detail_cols <- intersect(detail_cols, names(review))
edited_details <- vapply(seq_len(nrow(review)), function(i) {
  if (is_qpl[i] || is_removed[i]) return("")
  hit <- detail_cols[vapply(detail_cols, function(f)
    squish(review[[f]][i]) != squish(review[[paste0("cur_", f)]][i]), logical(1))]
  paste(hit, collapse = ", ")
}, character(1))

to_apply <- review |> filter(route == "apply")
changes <- bind_rows(
  to_apply |> filter(decision == "Remove") |>
    transmute(resource_id, name, field = "removed_reason", old = "",
              new = paste0("SME review ", TODAY, ": ",
                           ifelse(nzchar(note), note, "removed"))),
  to_apply |> filter(decision == "Change category") |>
    transmute(resource_id, name, field = "canonical_category",
              old = cur_category, new = new_slug),
  review |> filter(name_route == "apply") |>
    transmute(resource_id, name, field = "name", old = cur_name, new = name)
)

hand_cols <- function(x, action) {
  x |> transmute(resource_id, name, district, category, decision,
                 new_category, note, action = action)
}
handwork <- bind_rows(
  review |> filter(startsWith(route, "handwork")) |>
    hand_cols(sub("^handwork: ", "", review$route[startsWith(review$route, "handwork")])),
  review |> filter(startsWith(name_route, "handwork")) |>
    hand_cols(sub("^handwork: ", "",
                  review$name_route[startsWith(review$name_route, "handwork")])),
  review[nzchar(edited_details), ] |>
    hand_cols(paste0("differs from resources.csv in ",
                     edited_details[nzchar(edited_details)],
                     " - not applied; make the change by hand"))
)

# --- the Missing tab ----------------------------------------------------------

drafts <- tibble::tibble()
if (length(files) == 2) {
  missing <- read_tab(files[2]) |> filter(nzchar(name))
  if (nrow(missing) > 0) {
    message("Geocoding ", nrow(missing), " missing resource(s) with GeoSearch ...")
    geo <- geocode_addresses(ifelse(nzchar(missing$address), missing$address, NA))
    slug <- substr(slugify(missing$name), 1, 52)
    # Never reuse an id: a clash with an existing row, or between two drafts,
    # gets a --n suffix the way the seed disambiguates.
    taken <- canonical$resource_id
    ids <- character(nrow(missing))
    for (i in seq_along(ids)) {
      id <- paste0("manual:", slug[i]); k <- 1
      while (id %in% c(taken, ids)) { k <- k + 1; id <- paste0("manual:", slug[i], "--", k) }
      ids[i] <- id
    }
    cat_slug <- category_of$canonical_category[
      coalesce(match(tolower(missing$category), tolower(category_of$canonical_label)),
               match(tolower(missing$category), category_of$canonical_category))]
    dupe_of <- review$resource_id[match(slugify(missing$name), slugify(review$name))]
    drafts <- tibble::tibble(
      resource_id = ids, source = "manual", source_id = "",
      provenance = paste0("SME review ", TODAY,
                          ifelse(nzchar(missing$why), paste0(": ", missing$why), "")),
      # Left blank on purpose: validate_canonical_resources() refuses a
      # manual row without it, so a draft cannot publish until someone has
      # confirmed it and dated that.
      verified_on = "",
      name = missing$name, operator = "",
      canonical_category = coalesce(cat_slug, ""),
      subcategory = "", address = missing$address,
      lon = ifelse(is.na(geo$lon), "", as.character(round(geo$lon, 7))),
      lat = ifelse(is.na(geo$lat), "", as.character(round(geo$lat, 7))),
      geocode_boro = coalesce(geo$geocode_boro, ""),
      geocode_match = coalesce(geo$geocode_match, ""),
      in_queens = ifelse(!is.na(geo$geocode_boro) & geo$geocode_boro == "Queens",
                         "TRUE", "FALSE"),
      serves_queens = "TRUE", is_coad_member = "FALSE",
      phone = missing$phone, website = missing$website,
      # Reviewers list from memory, and the sheet has 500 rows. A name that
      # matches something already on the map is most likely already there.
      review_note = case_when(
        !is.na(dupe_of) ~ paste0("possible duplicate of ", dupe_of),
        is.na(cat_slug) ~ "category not in the list - choose one",
        is.na(geo$lon) ~ "not geocoded - check the address",
        geo$geocode_boro != "Queens" ~ paste0("address is in ", geo$geocode_boro),
        TRUE ~ ""
      ),
      removed_reason = ""
    )
    # Same column order as the canonical file, so rows paste straight in.
    for (col in setdiff(names(canonical), names(drafts))) drafts[[col]] <- ""
    drafts <- drafts[, names(canonical)]
  }
}

# --- write the proposal -------------------------------------------------------

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_csv(changes,  file.path(OUT_DIR, "proposed_changes.csv"), na = "")
write_csv(handwork, file.path(OUT_DIR, "handwork.csv"), na = "")
if (nrow(drafts) > 0) write_csv(drafts, file.path(OUT_DIR, "draft_manual_rows.csv"), na = "")

message("\nReviewed ", sum(review$route != "unreviewed"), " of ", nrow(review),
        " rows.")
print(count(review, decision = ifelse(nzchar(decision), decision, "(blank)")), n = Inf)
message("\n", nrow(changes), " change(s) proposed  -> ", OUT_DIR, "/proposed_changes.csv")
message(nrow(handwork), " row(s) for a person   -> ", OUT_DIR, "/handwork.csv")
if (nrow(drafts) > 0) {
  message(nrow(drafts), " draft manual row(s)   -> ", OUT_DIR, "/draft_manual_rows.csv")
}

# --- apply --------------------------------------------------------------------

if (!apply_changes) {
  message("\nNothing changed. Read the proposal, then re-run with --apply.")
  quit(save = "no")
}
if (nrow(changes) == 0) {
  message("\nNo changes to apply.")
  quit(save = "no")
}

updated <- canonical
for (i in seq_len(nrow(changes))) {
  row <- match(changes$resource_id[i], updated$resource_id)
  updated[[changes$field[i]]][row] <- changes$new[i]
}

# Validate before touching the real file: write to a temporary copy, read it
# back the way the pipeline does, run the pipeline's own check on it.
tmp <- tempfile(fileext = ".csv")
write_csv(updated, tmp, na = "", eol = "\r\n")
invisible(validate_canonical_resources(read_canonical_resources(tmp), cx))
file.copy(tmp, CANONICAL, overwrite = TRUE)
message("\nApplied ", nrow(changes), " change(s) to ", CANONICAL,
        ". Review with `git diff`, then run the pipeline.")
