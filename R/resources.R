# R/resources.R
#
# The resource model: three sources, three schemas, three trust levels,
# reconciled into one hand-maintainable canonical file.
#
#   scrape / API  ->  candidate records
#                        |  reconcile by resource_id, then fuzzy name+address
#                 data/review/resources_diff.csv   <- a human reviews
#                        |  merge
#         data/canonical/resources.csv   <- committed, git-diffable
#                        |
#         the pipeline reads ONLY the canonical file
#
# The exception is Queens Public Library branches (source `qpl`). They are
# fetched live in the DAG and bound onto the live canonical rows; see R/qpl.R.
#
# A scrape never overwrites the canonical file. It proposes a diff. That is
# what makes hand corrections survive a re-scrape, and it is the whole point of
# the "trusted messenger" direction.
#
# HAND ADDITIONS AND REMOVALS (2026-10-20). Two things a person can do in the
# canonical file that no scrape will undo:
#
#   add     a row with source = "manual" and resource_id = "manual:<slug>".
#           No scrape produces manual rows, so the seed never proposes
#           removing them. Coordinates are entered by hand.
#   remove  fill `removed_reason` on any row. The row stays in the file - so
#           the seed still recognises the id and never re-proposes it, and the
#           other hand edits survive - but live_resources() drops it before
#           anything is published. Clearing the cell restores it.
#
# Removing a whole SOURCE CATEGORY is a crosswalk edit (`exclude`), not this.

FACDB_URL <- "https://data.cityofnewyork.us/resource/ji82-xba5.json"

# NYC Planning Labs GeoSearch. No API key, NYC-aware, and it returns the
# borough of the match - which is how out-of-borough organisations in the
# Queens directory get flagged rather than silently plotted in Queens.
GEOSEARCH_URL <- "https://geosearch.planninglabs.nyc/v2/search"

# The three scraped sources, which the crosswalk maps and the seed fetches.
RESOURCE_SEEDED_SOURCES <- c("facdb", "qnpd", "franc")
# `manual` is entered by hand in the canonical file and has no crosswalk rows.
RESOURCE_SOURCES <- c(RESOURCE_SEEDED_SOURCES, "manual")
# Sources the crosswalk maps: the scraped three, plus Cool Options, which is
# fetched every build (R/cool_options.R) but resolves its category here like
# the scraped sources do. QPL sets its category in R/qpl.R and has no rows.
RESOURCE_MAPPED_SOURCES <- c(RESOURCE_SEEDED_SOURCES, "cool")

# FacDB records carry a name, an address and a facility type - no contact,
# hours or services. Scoped 2026-10-20 to the categories where the location
# alone is the useful fact. The crosswalk is what enforces this (every other
# FacDB category maps to `exclude`); validate_canonical_resources() checks the
# canonical file agrees, so a hand-added FacDB row cannot slip back in.
FACDB_CATEGORIES <- c("emergency-services", "government-offices",
                      "disability-and-access")

# --- category crosswalk -----------------------------------------------------

read_resource_categories <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    .default = readr::col_character()
  ))
}

validate_resource_categories <- function(cx) {
  required <- c("source", "source_field", "source_category",
                "canonical_category")
  missing <- setdiff(required, names(cx))
  if (length(missing) > 0) {
    stop("resource_categories.csv: missing column(s) ",
         paste(missing, collapse = ", "))
  }
  assert_no_na(cx, required)

  bad_source <- setdiff(cx$source, RESOURCE_MAPPED_SOURCES)
  if (length(bad_source) > 0) {
    stop("resource_categories.csv: unknown source(s) ",
         paste(bad_source, collapse = ", "),
         " - only scraped sources and Cool Options are mapped; manual rows ",
         "carry their category")
  }

  # The FacDB scope, stated once in FACDB_CATEGORIES and enforced here: a
  # FacDB mapping outside it means the scope has drifted in one file but not
  # the other.
  facdb_cats <- unique(cx$canonical_category[cx$source == "facdb" &
                                               cx$canonical_category != "exclude"])
  if (!setequal(facdb_cats, FACDB_CATEGORIES)) {
    stop("resource_categories.csv: FacDB maps to ",
         paste(sort(facdb_cats), collapse = ", "), " but FACDB_CATEGORIES is ",
         paste(sort(FACDB_CATEGORIES), collapse = ", "),
         ". Change both together.")
  }

  # One mapping per (source, field, category) or the lookup is ambiguous.
  dupes <- cx |>
    count(source, source_field, source_category) |>
    filter(n > 1)
  if (nrow(dupes) > 0) {
    stop("resource_categories.csv: duplicate mapping(s) for ",
         paste(dupes$source_category, collapse = ", "))
  }

  # The display label is a property of the canonical category but is stored per
  # row so the file stays a single reviewable sheet. Assert consistency, or a
  # category gets one label from one source and another from the next.
  bad_label <- cx |>
    filter(canonical_category != "exclude") |>
    group_by(canonical_category) |>
    summarise(n = dplyr::n_distinct(canonical_label), .groups = "drop") |>
    filter(n > 1)
  if (nrow(bad_label) > 0) {
    stop("resource_categories.csv: canonical_label disagrees for ",
         paste(bad_label$canonical_category, collapse = ", "))
  }
  TRUE
}

# Map a source category to the canonical vocabulary. facdb is looked up at
# facsubgrp level first, then facgroup, because HUMAN SERVICES and HEALTH CARE
# each span several canonical categories while the rest do not.
map_category <- function(cx, source, values, field) {
  m <- cx |> filter(source == !!source, source_field == !!field)
  idx <- match(values, m$source_category)
  tibble::tibble(
    canonical_category = m$canonical_category[idx],
    canonical_label = m$canonical_label[idx]
  )
}

# --- display casing ---------------------------------------------------------
#
# FacDB publishes `facname` in ALL CAPS - 5,485 of 5,732 shipped records, 96%.
# Screens 05 and 06 render title case ("Ravenswood Branch", "LIC Community Boat
# House"). Somebody has to convert, and it is the pipeline rather than the
# frontend: the casing of a proper noun is a property of the record, the
# exceptions are editorial judgment, and a Svelte component is the wrong place
# for a list of NYC acronyms nobody reviews.
#
# Note `opname` does NOT need this in most cases - FacDB already title-cases it
# (84% of Queens rows). It is run through the same function anyway so the 16%
# that arrive shouting come out consistent with everything else.
#
# WHY A NAIVE TITLE-CASER IS NOT ENOUGH
#
# Measured against the real names, four classes break it:
#
#   acronyms   "PS 811Q", "JHS 190", "NYPD", "FDNY", "YMCA", "LIC"
#              -> a naive caser gives "Ps 811q", "Nypd", "Ymca"
#   suffixes   "TOPAZ ARTS, INC." -> "Topaz Arts, Inc." not "Inc"
#   particles  "TEMPLE OF ISRAEL" -> "Temple of Israel", lowercase interior
#              "of/the/and/for" but never the FIRST word
#   ordinals   "ST. JOHN'S" -> "St. John's"; "101ST STREET" -> "101st Street"
#              (a naive caser gives "101St")
#
# So: title-case as the default, then a reviewable exception list restores the
# tokens that must not be title-cased. The list lives here rather than in the
# canonical CSV because it is a property of the LANGUAGE, not of any one
# record - putting it in the CSV would mean repeating it on every row that
# happens to contain "NYPD".
#
# Records whose correct casing is genuinely idiosyncratic are corrected by hand
# in data/canonical/resources.csv, which is the file's whole purpose. This
# function only has to be right about the general case.

# Tokens that stay fully upper. Matched case-insensitively against whole words.
DISPLAY_UPPER <- c(
  "NYC", "NYPD", "FDNY", "MTA", "NYCHA", "DOE", "HRA", "DSS", "ACS", "DOT",
  "DEP", "DOB", "DHS", "OEM", "EMS", "PAL", "YMCA", "YWCA", "JCC", "USA", "US",
  "LIC", "JFK", "PS", "IS", "JHS", "MS", "HS", "CUNY", "SUNY", "LGBT", "LGBTQ",
  "HIV", "AIDS", "WIC", "SNAP", "GED", "ESL", "STEM", "VFW", "AME", "UFT",
  "NAACP", "NY", "II", "III", "IV",
  # Religious and community-organisation acronyms that turn up repeatedly in
  # the Queens data and read as words otherwise.
  "SDA", "YM", "YWHA", "YMHA", "CYO", "COGIC", "UMC", "AMEZ"
)

# Words that stay lower when they fall inside a name (never first).
#
# `van` and `von` are deliberately NOT here, though they are Dutch/German
# particles. In Queens "Van Wyck" is a road, a house and a dozen organisation
# names, and it wants the capital; "mobile van" wants the lowercase. Capitalised
# is right far more often, and "Show Lincoln Mobile Van Extension Clinic" is a
# tolerable miss where "van wyck" would not be.
#
# The Spanish particles stay, because Queens organisation names use them the
# other way round - "Mexicanos Unidos de Queens" is the common shape.
DISPLAY_LOWER <- c(
  "a", "an", "and", "as", "at", "by", "de", "del", "for", "from", "in", "la",
  "las", "los", "of", "on", "or", "the", "to", "with"
)

# Fixed spellings for things neither rule gets right.
DISPLAY_FIXED <- c(
  "Inc." = "Inc.", "Inc" = "Inc", "Llc" = "LLC", "L.L.C." = "LLC",
  "Co." = "Co.", "Corp." = "Corp.", "Mt." = "Mt.", "St." = "St.",
  "Ft." = "Ft.", "Jr." = "Jr.", "Sr." = "Sr."
)

display_case <- function(x) {
  out <- vapply(x, function(s) {
    if (is.na(s) || !nzchar(s)) return(s)

    # Leave anything already mixed-case alone. FacDB's opname is mostly correct
    # already, and re-casing a hand-corrected canonical name would undo the
    # correction on every rebuild - which is exactly the failure the canonical
    # file exists to prevent.
    if (s != toupper(s)) return(s)

    words <- strsplit(s, " ", fixed = TRUE)[[1]]
    n <- length(words)

    cased <- vapply(seq_along(words), function(i) {
      w <- words[i]
      if (!nzchar(w)) return(w)

      bare <- gsub("[^A-Za-z]", "", w)

      # Acronyms keep their case wherever they appear.
      if (nzchar(bare) && toupper(bare) %in% DISPLAY_UPPER) return(toupper(w))

      # Ordinals: 101ST -> 101st, 3RD -> 3rd. Digits then letters.
      if (grepl("^[0-9]+(ST|ND|RD|TH)[[:punct:]]*$", w)) return(tolower(w))

      # Anything with an interior digit is a code, not a word: 811Q, P.S.811
      if (grepl("[0-9]", w) && grepl("[A-Za-z]", w)) return(toupper(w))

      lowered <- tolower(w)

      # Particles stay lower unless they lead the name.
      if (i > 1 && lowered %in% DISPLAY_LOWER) return(lowered)

      # Title-case each alphabetic run: MOTHER-IN-LAW -> Mother-In-Law.
      # Apostrophes are kept inside the run so JOHN'S -> John's and not
      # John'S - a possessive must not capitalise.
      w2 <- gsub("([A-Za-z])([A-Za-z']*)", "\\U\\1\\L\\2", lowered, perl = TRUE)

      # Two name prefixes the general rule gets wrong, both common enough in
      # this data to be worth encoding rather than hand-correcting record by
      # record:
      #
      #   O'BRIEN   -> O'Brien   (Irish O', capitalises the next letter)
      #   MCAULIFFE -> McAuliffe (Mc/Mac, same)
      #
      # The O' rule is anchored to a SINGLE leading letter so it fires on
      # "O'Brien" and "D'Angelo" but never on the possessive in "John's".
      w2 <- gsub("^([A-Za-z])'([a-z])", "\\U\\1\\E'\\U\\2", w2, perl = TRUE)
      w2 <- gsub("^(Ma?c)([a-z])", "\\1\\U\\2", w2, perl = TRUE)
      w2
    }, character(1))

    res <- paste(cased, collapse = " ")

    # Fixed spellings last, so they win over the general rules.
    for (k in names(DISPLAY_FIXED)) {
      res <- gsub(paste0("\\b", gsub("\\.", "\\\\.", k), "\\b"),
                  DISPLAY_FIXED[[k]], res, perl = TRUE)
    }
    res
  }, character(1), USE.NAMES = FALSE)
  out
}

# --- geocoding --------------------------------------------------------------

geocode_one <- function(address, timeout = 20) {
  blank <- list(lon = NA_real_, lat = NA_real_,
                geocode_boro = NA_character_, geocode_match = NA_character_)
  if (is.na(address) || !nzchar(trimws(address))) return(blank)
  url <- paste0(GEOSEARCH_URL, "?size=1&text=",
                utils::URLencode(trimws(address), reserved = TRUE))
  r <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE),
                error = function(e) NULL)
  f <- r$features
  if (is.null(f) || length(f) == 0) return(blank)
  list(
    lon = f[[1]]$geometry$coordinates[[1]],
    lat = f[[1]]$geometry$coordinates[[2]],
    geocode_boro = f[[1]]$properties$borough %||% NA_character_,
    geocode_match = f[[1]]$properties$label %||% NA_character_
  )
}

geocode_addresses <- function(addresses, pause = 0.12) {
  out <- lapply(addresses, function(a) {
    res <- geocode_one(a)
    Sys.sleep(pause)
    res
  })
  tibble::tibble(
    lon = vapply(out, function(x) as.numeric(x$lon %||% NA), numeric(1)),
    lat = vapply(out, function(x) as.numeric(x$lat %||% NA), numeric(1)),
    geocode_boro = vapply(out, function(x) x$geocode_boro %||% NA_character_, character(1)),
    geocode_match = vapply(out, function(x) x$geocode_match %||% NA_character_, character(1))
  )
}

# --- stable ids -------------------------------------------------------------

slugify <- function(x) {
  x |>
    tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-+|-+$", "", x = _) |>
    substr(1, 60)
}

# resource_id must be stable across rebuilds: permalinks depend on it, and so
# does every hand correction in the canonical file. Derived from a source id
# where one exists, otherwise from source plus a name slug - never from row
# order or a scrape-time index.
#
# The disambiguation suffix uses a DOUBLE dash. slugify() collapses every run
# of non-alphanumerics to a single dash, so "--" can never occur in a slug and
# a suffix can never collide with a real name.
#
# That collision is not hypothetical: a single-dash suffix produced
# facdb:al-ihsan-academy-3 for the third "AL-IHSAN ACADEMY", which is also the
# slug of the genuinely distinct "AL-IHSAN ACADEMY 3". Eight ids collided that
# way in the first seed.
ID_SUFFIX_SEP <- "--"

make_resource_id <- function(source, name, address = NULL, source_id = NULL) {
  # Prefer a stable upstream id. FacDB publishes `uid`, which removes 5,486 of
  # 5,800 records from the slug-collision problem entirely.
  if (!is.null(source_id) && all(!is.na(source_id))) {
    return(paste0(source, ":", source_id))
  }
  base <- paste0(source, ":", slugify(name))
  ord <- order(name, address %||% rep("", length(name)))
  out <- base
  for (b in unique(base[duplicated(base)])) {
    idx <- ord[base[ord] == b]
    out[idx] <- paste0(b, ID_SUFFIX_SEP, seq_along(idx))
  }
  out
}


# --- source readers ---------------------------------------------------------

# DCP Facilities Database, scoped by facgroup rather than by datasource.
#
# The research script scoped this by `datasource` and pulled wastewater
# treatment plants and solid waste sites - infrastructure, not resources a
# resident seeks - while omitting health care, human services, libraries and
# emergency services. Scoping by the crosswalk means the decision about what
# counts as a resource lives in a reviewable CSV rather than in a query string.
get_facdb <- function(cx, boro = "QUEENS", url = FACDB_URL) {
  groups <- cx |>
    filter(source == "facdb", source_field == "facgroup",
           canonical_category != "exclude") |>
    pull(source_category)
  subgroups <- cx |>
    filter(source == "facdb", source_field == "facsubgrp",
           canonical_category != "exclude") |>
    pull(source_category)

  quote_in <- function(x) paste0("'", gsub("'", "''", x), "'", collapse = ",")
  where <- sprintf(
    "boro='%s' AND (facgroup IN (%s) OR facsubgrp IN (%s))",
    boro, quote_in(groups), quote_in(subgroups)
  )

  # Socrata pages at 1000 by default; ask for more and paginate to be safe.
  pages <- list(); offset <- 0
  repeat {
    q <- list(`$where` = where, `$limit` = 5000, `$offset` = offset,
              `$select` = paste("uid,facname,address,city,zipcode,boro,cd",
                                "facgroup,facsubgrp,factype,datasource",
                                "capacity,latitude,longitude,opname", sep = ","))
    parsed <- httr::parse_url(url); parsed$query <- q
    page <- jsonlite::fromJSON(httr::build_url(parsed))
    if (length(page) == 0 || nrow(page) == 0) break
    pages[[length(pages) + 1]] <- page
    if (nrow(page) < 5000) break
    offset <- offset + 5000
  }
  bind_rows(pages) |> tibble::as_tibble()
}

read_qnpd <- function(path) {
  readr::read_csv(path, show_col_types = FALSE,
                  col_types = readr::cols(.default = readr::col_character()))
}

read_franc <- function(path) {
  x <- read_sf(path)
  # 81 points and one stray polygon. point_on_surface normalises them so the
  # centroid of the polygon is used rather than the feature being dropped.
  suppressWarnings(st_point_on_surface(x))
}

# --- candidate assembly -----------------------------------------------------
#
# Each source is normalised onto the union schema. Fields a source cannot
# supply stay NA rather than being invented - "nullable by source" is the point
# of the union schema, and a blank mission on a FacDB record is information.

CANONICAL_COLUMNS <- c(
  "resource_id", "source", "source_id", "provenance", "verified_on",
  "name", "operator", "canonical_category", "subcategory",
  "address", "lon", "lat", "geocode_boro", "geocode_match",
  "in_queens", "serves_queens", "is_coad_member",
  "mission", "contact", "contact_name", "email", "phone", "website", "social",
  "languages", "accepts_referrals", "fees", "capacity", "review_note",
  # Blank on a live row. Any text removes the row from every output; see the
  # header of this file.
  "removed_reason"
)

candidates_facdb <- function(facdb, cx, verified_on) {
  # facsubgrp wins where it maps, else facgroup - HUMAN SERVICES and HEALTH
  # CARE each span several canonical categories.
  sub <- map_category(cx, "facdb", facdb$facsubgrp, "facsubgrp")
  grp <- map_category(cx, "facdb", facdb$facgroup, "facgroup")
  cat <- dplyr::coalesce(sub$canonical_category, grp$canonical_category)

  tibble::tibble(
    source = "facdb",
    source_id = facdb$uid,
    provenance = "dcp_facilities_database",
    verified_on = verified_on,
    name = display_case(facdb$facname),
    # FacDB already title-cases opname on 84% of Queens rows; the other 16%
    # arrive shouting, so it goes through the same normaliser.
    operator = display_case(facdb$opname),
    canonical_category = cat,
    subcategory = facdb$factype,
    address = display_case(paste_na(facdb$address, facdb$city, facdb$zipcode)),
    # FacDB uses 0/0 as a null-coordinate sentinel rather than leaving the
    # field empty - 89 Queens records, mostly cultural institutions. Treated as
    # missing so they can be geocoded from their address instead of plotting
    # in the Gulf of Guinea.
    lon = na_if_zero(suppressWarnings(as.numeric(facdb$longitude))),
    lat = na_if_zero(suppressWarnings(as.numeric(facdb$latitude))),
    geocode_boro = "Queens",
    geocode_match = NA_character_,
    capacity = suppressWarnings(as.numeric(facdb$capacity))
  ) |>
    filter(!is.na(canonical_category), canonical_category != "exclude")
}

candidates_qnpd <- function(qnpd, cx, geo, verified_on) {
  m <- map_category(cx, "qnpd", qnpd$organization_type, "organization_type")
  # NOT named `contact`: tibble() masks it with the `contact` column below.
  parsed <- parse_qnpd_contact(qnpd$contact)
  tibble::tibble(
    source = "qnpd",
    source_id = NA_character_,
    provenance = "queens_nonprofit_directory_v3",
    verified_on = verified_on,
    name = qnpd$name,
    canonical_category = m$canonical_category,
    subcategory = qnpd$organization_type,
    address = qnpd$address,
    lon = geo$lon, lat = geo$lat,
    geocode_boro = geo$geocode_boro,
    geocode_match = geo$geocode_match,
    mission = qnpd$mission_statement,
    contact = qnpd$contact,
    contact_name = parsed$contact_name,
    email = parsed$email,
    phone = parsed$phone,
    website = parsed$website,
    social = qnpd$social_media,
    languages = qnpd$languages_spoken,
    accepts_referrals = qnpd$accepts_referrals,
    fees = qnpd$fees
  )
}

candidates_franc <- function(franc, cx, verified_on) {
  m <- map_category(cx, "franc", franc$source_layer, "source_layer")
  coords <- st_coordinates(franc)
  tibble::tibble(
    source = "franc",
    source_id = NA_character_,
    provenance = "franc_resource_map",
    verified_on = verified_on,
    name = franc$Name,
    canonical_category = m$canonical_category,
    subcategory = franc$source_layer,
    address = NA_character_,
    lon = coords[, "X"], lat = coords[, "Y"],
    geocode_boro = "Queens",
    geocode_match = NA_character_,
    mission = franc$description,
    # FRANC's "FRANC Members" layer is a membership, not a category. It becomes
    # a flag so a food pantry that is also a member keeps its real category.
    is_coad_member = franc$source_layer == "FRANC Members"
  )
}

na_if_zero <- function(x) ifelse(!is.na(x) & x == 0, NA_real_, x)

# The Queens Nonprofit Directory crams contact details into one semicolon
# string, with a variable number of fields:
#
#   "Jim Burke; jim@example.org; 419.971.1372; example.org"
#   "Lynn Koehler; Operations Manager; lynn@example.org; 610.703.3828; example.org"
#
# Splitting by position therefore misassigns every record that includes a job
# title. Fields are identified by shape instead: an email contains @, a phone
# matches a digit pattern, a website has a dot and no @. What is left, in
# order, is the contact name and their title.
parse_qnpd_contact <- function(x) {
  parts <- strsplit(ifelse(is.na(x), "", x), "\\s*;\\s*")
  pick <- function(p, pattern, negate = FALSE) {
    hit <- grepl(pattern, p)
    if (negate) hit <- !hit
    if (any(hit)) p[which(hit)[1]] else NA_character_
  }
  out <- lapply(parts, function(p) {
    p <- trimws(p); p <- p[nzchar(p)]
    if (length(p) == 0) {
      return(list(contact_name = NA_character_, email = NA_character_,
                  phone = NA_character_, website = NA_character_))
    }
    email <- pick(p, "@")
    phone <- pick(p, "[0-9]{3}[.\\-\\s][0-9]{3}[.\\-\\s][0-9]{4}")
    rest <- setdiff(p, c(email, phone))
    site <- rest[grepl("\\.", rest) & !grepl("@", rest) &
                 !grepl("^[0-9 .()\\-]+$", rest)]
    site <- if (length(site)) site[length(site)] else NA_character_
    name <- setdiff(rest, site)
    list(
      contact_name = if (length(name)) name[1] else NA_character_,
      email = email, phone = phone, website = site
    )
  })
  tibble::tibble(
    contact_name = vapply(out, function(o) o$contact_name, character(1)),
    email = vapply(out, function(o) o$email, character(1)),
    phone = vapply(out, function(o) o$phone, character(1)),
    website = vapply(out, function(o) o$website, character(1))
  )
}

paste_na <- function(...) {
  parts <- list(...)
  out <- do.call(paste, c(lapply(parts, function(x) ifelse(is.na(x), "", x)),
                          list(sep = ", ")))
  out <- gsub("(, )+", ", ", out)
  out <- gsub("^, |, $", "", out)
  ifelse(nzchar(out), out, NA_character_)
}

build_resource_candidates <- function(facdb, qnpd, qnpd_geo, franc, cx,
                                      verified_on = as.character(Sys.Date())) {
  # Trim whitespace on ingest. FRANC carries names with trailing spaces, and
  # without this every review cycle re-proposes a cosmetic diff - the first run
  # of the reconcile loop reported exactly one "change", and it was a trailing
  # space on an assembly member's name.
  trim <- function(x) if (is.character(x)) trimws(x) else x

  all <- bind_rows(
    candidates_facdb(facdb, cx, verified_on),
    candidates_qnpd(qnpd, cx, qnpd_geo, verified_on),
    candidates_franc(franc, cx, verified_on)
  )

  all |>
    group_by(source) |>
    mutate(
      resource_id = make_resource_id(
        dplyr::first(source), name, address,
        source_id = if (all(!is.na(source_id))) source_id else NULL
      )
    ) |>
    ungroup() |>
    mutate(
      # Out-of-borough organisations are kept, not dropped: an organisation
      # headquartered in Manhattan that serves Queens is still worth calling.
      # in_queens gates whether it becomes a map dot; serves_queens records why
      # it is in the file at all.
      in_queens = !is.na(geocode_boro) & geocode_boro == "Queens" &
                  !is.na(lon) & !is.na(lat),
      serves_queens = TRUE,
      is_coad_member = dplyr::coalesce(is_coad_member, FALSE),
      review_note = dplyr::case_when(
        canonical_category == "unassigned" ~ "category needs per-record review",
        is.na(lon) ~ "not geocoded",
        !in_queens ~ paste0("address is in ", geocode_boro),
        TRUE ~ NA_character_
      ),
      # A scrape never removes anything; only a person does.
      removed_reason = NA_character_
    ) |>
    mutate(across(where(is.character), trim)) |>
    select(any_of(CANONICAL_COLUMNS)) |>
    arrange(source, resource_id)
}

# --- canonical file ---------------------------------------------------------

read_canonical_resources <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    lon = readr::col_double(), lat = readr::col_double(),
    capacity = readr::col_double(),
    in_queens = readr::col_logical(),
    serves_queens = readr::col_logical(),
    is_coad_member = readr::col_logical(),
    .default = readr::col_character()
  ))
}

validate_canonical_resources <- function(res, cx) {
  # A spreadsheet round-trip can drop or rename a column. Losing
  # removed_reason would silently republish every removed resource.
  absent <- setdiff(CANONICAL_COLUMNS, names(res))
  if (length(absent) > 0) {
    stop("resources.csv: missing column(s) ", paste(absent, collapse = ", "))
  }

  assert_no_na(res, c("resource_id", "source", "name", "canonical_category"))

  # Permalinks and every hand correction key off this. A collision silently
  # merges two organisations into one page.
  assert_unique(res, "resource_id")

  # QPL branches are fetched by the DAG and bound on after this file is read
  # (R/qpl.R). A qpl row here would publish the branch twice.
  if (any(res$source == "qpl")) {
    stop("resources.csv: qpl rows are fetched from QPL by the pipeline and ",
         "must not be entered here")
  }
  # Likewise Cool Options (R/cool_options.R).
  if (any(res$source == "cool")) {
    stop("resources.csv: cool rows are fetched from NYC OEM Cool Options by ",
         "the pipeline and must not be entered here")
  }

  bad_source <- setdiff(res$source, RESOURCE_SOURCES)
  if (length(bad_source) > 0) {
    stop("resources.csv: unknown source(s) ", paste(bad_source, collapse = ", "))
  }

  # The id is `<source>:<key>`, and the frontend splits it on that colon to
  # build /resource/{source}/{slug}. A hand-added row with the wrong prefix
  # would get a detail URL under another source.
  bad_prefix <- res |> filter(!startsWith(resource_id, paste0(source, ":")))
  if (nrow(bad_prefix) > 0) {
    stop("resources.csv: resource_id must start with '<source>:' - ",
         paste(head(bad_prefix$resource_id, 3), collapse = ", "))
  }

  # A hand-added row has no scrape behind it, so the row itself is the only
  # record of where it came from and when it was last true.
  manual <- res |> filter(source == "manual")
  bad_manual <- manual |>
    filter(is.na(provenance) | !nzchar(provenance) |
             is.na(verified_on) | !nzchar(verified_on) |
             is.na(in_queens) | is.na(serves_queens))
  if (nrow(bad_manual) > 0) {
    stop("resources.csv: manual row(s) need provenance, verified_on, ",
         "in_queens and serves_queens: ",
         paste(head(bad_manual$resource_id, 3), collapse = ", "))
  }
  # The slug becomes a URL: /q{NN}/resource/manual/<slug>. The frontend build
  # refuses anything but lowercase letters, digits and dashes, up to 60 chars
  # (web/src/routes/[district]/resource/[source]/[slug]/+page.server.ts);
  # failing here says so in the pipeline, next to the row, instead.
  bad_slug <- manual |> filter(!grepl("^manual:[a-z0-9-]{1,60}$", resource_id))
  if (nrow(bad_slug) > 0) {
    stop("resources.csv: manual resource_id must be manual:<slug>, the slug ",
         "lowercase letters, digits and dashes, at most 60 characters - ",
         paste(head(bad_slug$resource_id, 3), collapse = ", "))
  }

  # THE FACDB SCOPE. The crosswalk stops the seed proposing other FacDB
  # categories; this stops the canonical file holding them, which a by-hand
  # recategorisation or an old --force seed could otherwise do. Removed rows
  # are included: an out-of-scope FacDB row should be deleted, not parked.
  out_of_scope <- res |>
    filter(source == "facdb", !canonical_category %in% FACDB_CATEGORIES)
  if (nrow(out_of_scope) > 0) {
    stop("resources.csv: ", nrow(out_of_scope), " FacDB row(s) outside ",
         paste(FACDB_CATEGORIES, collapse = ", "), ": ",
         paste(unique(out_of_scope$canonical_category), collapse = ", "))
  }

  # Every category must resolve through the crosswalk, so a hand edit cannot
  # invent a category the frontend has no label for.
  vocab <- unique(c(cx$canonical_category[cx$canonical_category != "exclude"]))
  bad_cat <- setdiff(res$canonical_category, vocab)
  if (length(bad_cat) > 0) {
    stop("resources.csv: category not in the crosswalk: ",
         paste(bad_cat, collapse = ", "))
  }
  if (any(res$canonical_category == "exclude")) {
    stop("resources.csv: an excluded category reached the canonical file")
  }

  # Anything flagged in_queens must actually have coordinates, or it becomes a
  # map dot at NULL island.
  bad_geo <- res |> filter(in_queens, is.na(lon) | is.na(lat))
  if (nrow(bad_geo) > 0) {
    stop(nrow(bad_geo), " resource(s) marked in_queens with no coordinates: ",
         paste(head(bad_geo$resource_id, 3), collapse = ", "))
  }

  # NYC bounding box. Catches a lon/lat swap, which produces plausible-looking
  # numbers that plot in the Indian Ocean.
  pts <- res |> filter(!is.na(lon), !is.na(lat))
  off <- pts |> filter(lon < -74.3 | lon > -73.6 | lat < 40.4 | lat > 41.0)
  if (nrow(off) > 0) {
    stop(nrow(off), " resource(s) outside the NYC bounding box - check for a ",
         "lon/lat swap: ", paste(head(off$resource_id, 3), collapse = ", "))
  }
  TRUE
}

# The rows that publish. The ONLY place removed_reason is read: every output
# - district payloads, map points, category counts - descends from this, so a
# removed resource cannot reach one output and not another.
live_resources <- function(res) {
  res |> filter(is.na(removed_reason) | !nzchar(trimws(removed_reason)))
}

# Assign each resource to a district by point-in-polygon.
#
# Uses the unsimplified boundaries: a resource near a border must land in the
# right district, and simplification moves borders by up to a few hundred feet.
resources_to_cdta <- function(res, cdta) {
  located <- res |> filter(in_queens, !is.na(lon), !is.na(lat))
  pts <- st_as_sf(located, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |>
    st_transform(2263)
  joined <- st_join(pts, select(st_transform(cdta, 2263), CDTA2020),
                    join = st_within)
  joined |>
    st_drop_geometry() |>
    rename(cdta2020 = CDTA2020) |>
    as_tibble()
}

# Section E of the 02 screen: which categories are present in THIS district.
#
# Derived per district, never a hardcoded global list. The two wireframe
# screens show conflicting category lists because they render different
# districts, and both are right - hardcoding either would look broken in 13 of
# 14 districts.
#
# `default_on` comes from data/registry/resource_categories.csv: whether the
# category's points are on when a map opens with no `?categories=`.
resource_categories_per_district <- function(res_cdta, cx, registry) {
  labels <- cx |>
    filter(canonical_category != "exclude") |>
    distinct(canonical_category, canonical_label)

  res_cdta |>
    filter(!is.na(cdta2020)) |>
    count(cdta2020, canonical_category, name = "count") |>
    left_join(labels, by = "canonical_category") |>
    left_join(registry, by = c("canonical_category" = "category")) |>
    arrange(cdta2020, desc(count))
}

# --- category registry --------------------------------------------------------
#
# data/registry/resource_categories.csv: one row per canonical category, for
# properties of the category itself rather than of a source mapping.
#
# WHY NOT A COLUMN ON THE CROSSWALK. data/crosswalk/resource_categories.csv
# has a row per SOURCE category, several per canonical one, so a per-category
# flag there would be repeated across rows and need an agreement check, as
# canonical_label already does. Here it is stated once.
#
# `default_on`: the categories whose points are on when a map opens with no
# `?categories=` (public feedback, 2026-11-04: Emergency services and Food
# assistance). Every map reads it - the district map page and the docked map
# beside district, hazard and resource pages.
#
# `group`: the colour group of the category's lettered mark (public feedback,
# 2026-11-05: "some colour-coding of resources"). The letter still identifies
# the category; the fill says what kind of help it is. Four groups, because
# four colours because eleven could not be told apart (worst pair 5-8). The
# fills are muted (2026-11-05, "M1 soft"), so colour is a hint and the letter
# the identity. The fills are the frontend's ($lib/map/palette.ts); the
# grouping is data, so it is validated here.

# The group vocabulary and its display labels, in legend order.
CATEGORY_GROUPS <- c(
  "emergency"              = "Emergency",
  "basic-needs"            = "Basic needs",
  "health-and-care"        = "Health and care",
  "community-and-services" = "Community and services"
)

# Categories that exist in the crosswalk but never reach a payload. `exclude`
# drops the record; `unassigned` is a staging value for FRANC records awaiting
# per-record review (see the crosswalk's notes).
CATEGORY_NON_DISPLAY <- c("exclude", "unassigned")

read_category_registry <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    category = readr::col_character(),
    default_on = readr::col_logical(),
    group = readr::col_character()
  ))
}

# `per_district` is resource_categories_per_district()'s output and
# `queens_cdtas` the shipped districts; both are needed for the last check.
validate_category_registry <- function(registry, cx, per_district, queens_cdtas) {
  if (!identical(names(registry), c("category", "default_on", "group"))) {
    stop("resource_categories registry: columns must be exactly ",
         "category, default_on, group - got ", paste(names(registry), collapse = ", "))
  }
  # col_logical() reads anything but TRUE/FALSE (a "yes", a blank) as NA, so
  # a typo would silently mean "off".
  assert_no_na(registry, c("category", "default_on", "group"))

  # Both ways: a mistyped group would draw an uncoloured mark, and a group no
  # category uses would sit in the legend with nothing on the map.
  bad_group <- setdiff(registry$group, names(CATEGORY_GROUPS))
  if (length(bad_group) > 0) {
    stop("resource_categories registry: unknown group(s) ",
         paste(bad_group, collapse = ", "), ". Groups are ",
         paste(names(CATEGORY_GROUPS), collapse = ", "), " (CATEGORY_GROUPS).")
  }
  unused <- setdiff(names(CATEGORY_GROUPS), registry$group)
  if (length(unused) > 0) {
    stop("CATEGORY_GROUPS has group(s) no category uses: ",
         paste(unused, collapse = ", "))
  }
  assert_unique(registry, "category")

  # Two-way against the crosswalk's vocabulary. One way would catch a typo
  # here; the other catches a category added or renamed in the crosswalk and
  # never given a row, which would ship with default_on null.
  vocabulary <- cx |>
    filter(!canonical_category %in% CATEGORY_NON_DISPLAY) |>
    distinct(category = canonical_category)
  assert_keys_match(registry, vocabulary, by = "category",
                    label_x = "registry/resource_categories.csv",
                    label_y = "crosswalk/resource_categories.csv")

  # And against what ships. A category reaching a district payload without a
  # registry row would carry default_on NA - unassigned leaking through is the
  # likely way.
  unknown <- setdiff(per_district$canonical_category, registry$category)
  if (length(unknown) > 0) {
    stop("A district payload carries category(ies) with no registry row: ",
         paste(unknown, collapse = ", "))
  }

  # A map that opens empty looks broken, not deliberate. Every shipped
  # district must hold at least one default-on category. Today Emergency
  # services is in all 14; Food assistance in 7.
  covered <- per_district |>
    filter(cdta2020 %in% queens_cdtas, default_on) |>
    distinct(cdta2020)
  empty <- setdiff(queens_cdtas, covered$cdta2020)
  if (length(empty) > 0) {
    stop("No default-on category has resources in: ",
         paste(empty, collapse = ", "),
         ". Its map would open with no points. Turn another category on in ",
         "data/registry/resource_categories.csv, or accept it and relax this check.")
  }
  TRUE
}

# Per-district resource lists, detail inlined - the 02/05/06 screen payload.
#
# Only resources located in the district. Organisations that serve Queens from
# outside it are kept in the canonical file but excluded here, because this
# payload drives a map.
write_resource_payloads <- function(res_cdta, crosswalk, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  shipped <- crosswalk |> filter(boro_code == 4)

  paths <- vapply(seq_len(nrow(shipped)), function(i) {
    row <- shipped[i, ]
    rows <- res_cdta |> filter(cdta2020 == row$cdta2020)

    payload <- list(
      cdta2020 = row$cdta2020,
      slug = row$slug,
      count = nrow(rows),
      resources = lapply(seq_len(nrow(rows)), function(j) {
        r <- rows[j, ]
        compact_list(list(
          resource_id = r$resource_id,
          name = r$name,
          # The operating organisation, where the facility name alone does not
          # identify it - screen 06 renders "Ravenswood Branch" over "Queens
          # Public Library". FacDB `opname`, or QPL_OPERATOR for qpl; absent
          # for qnpd and franc, where the record IS the organisation.
          operator = na_null(col_or_na(r, "operator")),
          category = r$canonical_category,
          subcategory = na_null(r$subcategory),
          is_coad_member = isTRUE(r$is_coad_member),
          lon = r$lon, lat = r$lat,
          address = na_null(r$address),
          mission = na_null(r$mission),
          contact_name = na_null(col_or_na(r, "contact_name")),
          email = na_null(col_or_na(r, "email")),
          phone = na_null(col_or_na(r, "phone")),
          website = na_null(col_or_na(r, "website")),
          # The branch page where QPL publishes opening hours. qpl only.
          hours_url = na_null(col_or_na(r, "hours_url")),
          social = na_null(col_or_na(r, "social")),
          languages = na_null(r$languages),
          accepts_referrals = na_null(r$accepts_referrals),
          fees = na_null(r$fees),
          # Omitted when zero, not emitted as 0. FacDB uses 0 for "not
          # reported" on 5,021 of 5,432 records, and a detail screen that
          # renders the field faithfully prints "Capacity: 0" for 88% of
          # resources - which reads as a fact rather than an absence.
          capacity = if (is.na(r$capacity) || r$capacity == 0) NULL else r$capacity,
          source = r$source,
          provenance = r$provenance,
          verified_on = r$verified_on
        ))
      })
    )
    p <- file.path(dir, paste0(row$slug, ".json"))
    jsonlite::write_json(force_arrays(payload, c("resources")), p,
                         auto_unbox = TRUE, digits = NA, null = "null", na = "null")
    p
  }, character(1))
  unname(paths)
}

na_null <- function(x) if (length(x) == 0 || is.na(x) || !nzchar(x)) NULL else x

# A column the union schema declares but no source in this build populates.
# Returns NA rather than warning, so the payload stays quiet about fields that
# are legitimately absent for every current source.
col_or_na <- function(row, col) if (col %in% names(row)) row[[col]] else NA_character_
compact_list <- function(x) x[!vapply(x, is.null, logical(1))]

validate_resource_payloads <- function(paths, res_cdta) {
  total <- 0L
  for (p in paths) {
    j <- jsonlite::fromJSON(p, simplifyVector = FALSE)
    if (!is.list(j$resources) || (length(j$resources) > 0 && !is.null(names(j$resources)))) {
      stop(basename(p), ": resources is not a JSON array")
    }
    if (j$count != length(j$resources)) {
      stop(basename(p), ": count disagrees with the resources array")
    }
    for (r in j$resources) {
      if (is.null(r$resource_id) || is.null(r$name) || is.null(r$category)) {
        stop(basename(p), ": a resource is missing id, name or category")
      }
      if (is.null(r$lon) || is.null(r$lat)) {
        stop(basename(p), ": resource ", r$resource_id, " has no coordinates")
      }
    }
    total <- total + length(j$resources)
  }
  # Every located resource must land in exactly one district payload.
  expected <- sum(!is.na(res_cdta$cdta2020) &
                  substr(res_cdta$cdta2020, 1, 2) == "QN")
  if (total != expected) {
    stop("Resource payloads hold ", total, " records but ", expected,
         " Queens resources were located - some were dropped")
  }
  TRUE
}
