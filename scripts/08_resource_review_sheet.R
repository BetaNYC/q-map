# scripts/08_resource_review_sheet.R
#
# Builds the SME resource review: every resource on the map, one row each, as
# CSVs to import into a Google Sheet. The reviewer fills three columns
# (decision, new_category, note) and lists anything missing on a second tab.
# scripts/09_apply_resource_review.R reads the exported tabs back.
#
# Standalone and not part of the DAG: its output is a file a person edits, the
# same reason scripts/03_seed_resources.R is standalone. It reads the DAG's
# resources_cdta, the exact set the map publishes, so it needs a current local
# build:
#
#   uvr run scripts/run_pipeline.R
#   uvr run scripts/08_resource_review_sheet.R
#
# Writes data/review/sme_review/:
#   review.csv   the main tab, one row per resource on the map
#   missing.csv  an empty tab for resources that should be on the map
#   lists.csv    the dropdown values for decision and category
#   readme.csv   reviewer instructions. The rubric is Andrew's to write.
#
# SETTING UP THE SHEET (once):
#   1. New Google Sheet. File > Import > Upload review.csv > "Replace
#      spreadsheet", and UNTICK "Convert text to numbers, dates, and formulas".
#      Otherwise a phone or an id can be mangled.
#   2. Import readme.csv, missing.csv and lists.csv the same way, each with
#      "Insert new sheet(s)". Drag `readme` to the front.
#   3. Data > Data validation:
#        review  column `decision`      dropdown from range lists!A2:A6
#        review  column `new_category`  dropdown from range lists!B2:B20
#        missing column `category`      dropdown from range lists!B2:B20
#   4. Hide the columns resource_id and original_name: they are how the
#      import matches rows and spots a renamed one. Optional: freeze row 1,
#      hide `lists`, and protect every review column except name, decision,
#      new_category and note.
#   5. Share with the reviewer as an editor.
#
# GETTING IT BACK: File > Download > CSV, once on the `review` tab and once on
# `missing`, then run scripts/09_apply_resource_review.R.

library(dplyr)
library(readr)

source("R/validate.R")
source("R/resources.R")

OUT_DIR <- "data/review/sme_review"
SITE_BASE <- "https://betanyc.github.io/q-map"

# Exactly these strings. The import script matches them case-insensitively,
# so the dropdown and the importer cannot disagree.
REVIEW_DECISIONS <- c("Keep", "Remove", "Change category", "Fix details", "Unsure")

SOURCE_LABELS <- c(
  facdb = "DCP Facilities Database", qnpd = "Queens Nonprofit Directory",
  franc = "FRANC Resource Map", qpl = "Queens Library Branches",
  manual = "Added by hand"
)

# --- inputs -------------------------------------------------------------------

cx <- read_resource_categories("data/crosswalk/resource_categories.csv")
labels <- cx |>
  filter(canonical_category != "exclude") |>
  distinct(canonical_category, canonical_label) |>
  arrange(canonical_label)

districts <- read_csv("data/crosswalk/cdta_crosswalk.csv", show_col_types = FALSE,
                      col_types = cols(.default = "c")) |>
  filter(boro_code == "4") |>
  select(cdta2020, slug, district_name = display_name)

built <- targets::tar_read(resources_cdta)
published <- built |> filter(cdta2020 %in% districts$cdta2020)

# The build must describe the canonical file as it is NOW, or the sheet would
# show rows that have since been removed or recategorised. Two ways on id,
# name and category: catches a row added, removed or edited since the last
# build. resources_cdta holds every located live row, before the district
# filter, so the two sides are the same set when the build is current.
canonical_located <- read_canonical_resources("data/canonical/resources.csv") |>
  live_resources() |>
  filter(in_queens, !is.na(lon), !is.na(lat))
built_canonical <- built |> filter(source != "qpl")
keys <- c("resource_id", "name", "canonical_category")
n_stale <- nrow(anti_join(canonical_located, built_canonical, by = keys)) +
  nrow(anti_join(built_canonical, canonical_located, by = keys))
if (n_stale > 0) {
  stop("The local build is behind data/canonical/resources.csv (", n_stale,
       " row(s) differ). Run `uvr run scripts/run_pipeline.R` first.")
}

# --- the review tab -------------------------------------------------------------

# Long missions make the sheet unreadable. The link shows the full record.
short_text <- function(x, n = 300) {
  x <- gsub("<br\\s*/?>", " / ", x, ignore.case = TRUE)
  x <- gsub("\\s+", " ", trimws(x))
  ifelse(!is.na(x) & nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x)
}

# Same shape as the app's own mapReturnPath(): category switched on, popup
# open. Every row gets one, FacDB included, which has no detail page.
map_link <- function(slug, category, id) {
  paste0(SITE_BASE, "/", slug, "/map?categories=",
         utils::URLencode(category, reserved = TRUE),
         "&resource=", utils::URLencode(id, reserved = TRUE))
}

review <- published |>
  left_join(districts, by = "cdta2020") |>
  left_join(labels, by = "canonical_category") |>
  mutate(
    # The suggested order, as a sortable column: flagged rows, then the
    # records people will call, then FacDB, then QPL's own list.
    priority = case_when(
      !is.na(review_note) & nzchar(review_note) ~ 1L,
      source %in% c("qnpd", "franc", "manual") ~ 2L,
      source == "facdb" ~ 3L,
      TRUE ~ 4L
    ),
    district = toupper(slug),
    # Whitespace collapsed (36 FRANC and QNPD names carry line breaks or
    # trailing spaces) but never truncated: the reviewer may correct this
    # cell, and the import applies what they type.
    name = gsub("\\s+", " ", trimws(name)),
    original_name = name,
    description = short_text(mission),
    source_label = unname(SOURCE_LABELS[source]),
    link = map_link(slug, canonical_category, resource_id),
    decision = "", new_category = "", note = ""
  ) |>
  arrange(slug, canonical_label, name) |>
  transmute(
    district, district_name, priority,
    category = canonical_label, name, operator, description,
    address, phone, website, hours_url,
    source = source_label, flag = review_note, link,
    decision, new_category, note,
    resource_id, original_name
  )

assert_unique(review, "resource_id")
if (any(is.na(review$category))) stop("a resource has no category label")

# --- the other tabs -----------------------------------------------------------

missing <- tibble::tibble(
  district = character(), name = character(), address = character(),
  category = character(), phone = character(), website = character(),
  why = character()
)

# "Unassigned" is where rows wait for this review, so it is shown in the
# sheet but never offered as somewhere to move a row to.
targets_cat <- labels |> filter(canonical_category != "unassigned")
n_lists <- max(length(REVIEW_DECISIONS), nrow(targets_cat))
pad <- function(x) c(x, rep("", n_lists - length(x)))
lists <- tibble::tibble(decision = pad(REVIEW_DECISIONS),
                        category = pad(targets_cat$canonical_label))

commit <- tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                   error = function(e) "unknown")
readme <- tibble::tibble(`Read me` = c(
  sprintf("Queens resource review. %d resources across %d districts, as on the map on %s (commit %s).",
          nrow(review), dplyr::n_distinct(review$district), Sys.Date(), commit),
  "",
  "WHAT TO JUDGE",
  "[RUBRIC - Andrew to write: what makes a resource belong on this map.]",
  "",
  "HOW TO FILL IN THE REVIEW TAB",
  "decision: Keep, Remove, Change category, Fix details or Unsure. Leave it blank if you have not looked at the row.",
  "new_category: only with Change category. Pick from the list.",
  "name: if a name is wrong, correct it in place. The map will use your spelling. (Library branch names come from QPL, so a correction there is passed to them.)",
  "note: why you removed it, what is wrong with its details, or anything else. A note is always welcome.",
  "Other details (address, phone, website): choose Fix details and write the correction in note. Those are checked by hand before they change.",
  "link: opens the resource on the live map.",
  "priority: 1 = already flagged for review, 2 = nonprofit and community listings, 3 = city facilities, 4 = library branches. Work through them in that order if time is short.",
  "The same organisation can appear more than once, once per category it is listed under. Judge each row on its category.",
  "Sort and filter freely, but do not edit resource_id. It is how your decisions are matched back.",
  "",
  "LIBRARY BRANCHES (source: Queens Library Branches) come from Queens Public Library's own list. Mark problems with them, and we will take them to QPL.",
  "",
  "MISSING TAB: add anything that should be on the map and is not, one per row. Name and address are the minimum."
))

# --- write --------------------------------------------------------------------

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_csv(review,  file.path(OUT_DIR, "review.csv"),  na = "")
write_csv(missing, file.path(OUT_DIR, "missing.csv"), na = "")
write_csv(lists,   file.path(OUT_DIR, "lists.csv"),   na = "")
write_csv(readme,  file.path(OUT_DIR, "readme.csv"),  na = "")

message("Wrote ", OUT_DIR, "/: ", nrow(review), " resources for review")
print(count(review, priority, source), n = Inf)
message("Set-up steps are in the header of this script.")
