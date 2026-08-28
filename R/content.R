# R/content.R
#
# Authored hazard guidance: content/hazards/<slug>.yml
#
# The pipeline's job here is to VALIDATE AND COPY, never to generate. R is the
# wrong tool for editing prose, and a hazard page's links are the highest-
# consequence thing in the project - a dead link on an emergency-preparedness
# page is worse than a missing one, because the reader trusts it.
#
# The hazard CATALOG is authored. The per-district hazard ORDERING is derived
# (see R/hazards.R). The two are cross-checked: the catalog must describe
# exactly the hazards the model ranks and pins, no more and no fewer.

HAZARD_CONTENT_DIR <- "content/hazards"

# Per-district overrides live alongside the base files, one directory per
# hazard slug: content/hazards/coastal-storm/q14.yml
#
# Overlays are expected to be RARE - a handful of districts where the guidance
# genuinely differs, such as evacuation routing on the Rockaway peninsula.
# Everything that varies only numerically should use templating against the
# district payload instead (PIPELINE_DESIGN.md section 3: "emit facts, let the
# frontend write the sentence"), not an overlay.
HAZARD_OVERLAY_KEYS <- c("summary", "sections", "map_layers", "resource_categories")

# Every hazard page renders these three, so their absence is a build failure
# rather than an empty accordion. They are the "General template" from the
# wireframe notes.
REQUIRED_SECTIONS <- c("preparedness", "response", "general")

# Hazard-specific sections are optional and free-form ("signs-of-heat-illness",
# "prevention"), but must come from a known vocabulary so a typo becomes an
# error rather than a section nobody notices is missing.
OPTIONAL_SECTIONS <- c(
  "signs-of-heat-illness", "prevention", "evacuation", "after",
  "flooding-basements", "air-quality", "power-outage"
)

read_hazard_content <- function(dir = HAZARD_CONTENT_DIR) {
  files <- list.files(dir, pattern = "\\.ya?ml$", full.names = TRUE)
  if (length(files) == 0) stop("No hazard content found in ", dir)

  out <- lapply(files, function(f) {
    y <- yaml::read_yaml(f)
    y$.file <- basename(f)
    y
  })
  names(out) <- vapply(out, function(y) y$slug %||% NA_character_, character(1))
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Read per-district overrides: content/hazards/<hazard>/<district>.yml
read_hazard_overlays <- function(dir = HAZARD_CONTENT_DIR) {
  subdirs <- list.dirs(dir, recursive = FALSE)
  out <- list()
  for (d in subdirs) {
    hazard <- basename(d)
    for (f in list.files(d, pattern = "\\.ya?ml$", full.names = TRUE)) {
      district <- sub("\\.ya?ml$", "", basename(f))
      y <- yaml::read_yaml(f)
      y$.file <- file.path(hazard, basename(f))
      out[[paste(hazard, district, sep = "/")]] <- y
    }
  }
  out
}

# Shallow merge: an overlay replaces a whole top-level key rather than merging
# into it. Section-level merging looks friendlier but makes the result hard to
# predict from either file alone - an author editing the base could not tell
# what a district actually renders. Replacing whole keys keeps both files
# readable in isolation.
merge_hazard_overlay <- function(base, overlay) {
  for (k in intersect(names(overlay), HAZARD_OVERLAY_KEYS)) {
    base[[k]] <- overlay[[k]]
  }
  base$.overridden <- intersect(names(overlay), HAZARD_OVERLAY_KEYS)
  base
}

# --- validation -------------------------------------------------------------

validate_hazard_content <- function(content, model_slugs, registry_ids = character()) {
  if (anyNA(names(content))) {
    stop("Hazard content: a file has no `slug`: ",
         paste(vapply(content[is.na(names(content))],
                      function(y) y$.file, character(1)), collapse = ", "))
  }

  # The catalog and the ranking model must describe the same eight hazards.
  # A hazard in the model with no content renders an empty page; a hazard in
  # the catalog the model does not know about is unreachable.
  missing_content <- setdiff(model_slugs, names(content))
  orphan_content <- setdiff(names(content), model_slugs)
  if (length(missing_content) > 0 || length(orphan_content) > 0) {
    stop(paste0(
      "Hazard catalog does not match the ranking model. ",
      if (length(missing_content)) paste0(
        "Ranked/pinned with no content: ",
        paste(missing_content, collapse = ", "), ". ") else "",
      if (length(orphan_content)) paste0(
        "Content with no hazard: ",
        paste(orphan_content, collapse = ", "), ".") else ""
    ))
  }

  for (slug in names(content)) {
    y <- content[[slug]]
    where <- paste0(y$.file, " (", slug, ")")

    # The filename must match the slug, or a rename silently orphans the file.
    if (!identical(y$.file, paste0(slug, ".yml"))) {
      stop(where, ": filename does not match slug")
    }
    for (f in c("label", "summary", "sections")) {
      if (is.null(y[[f]]) || !nzchar(as.character(y[[f]])[1])) {
        stop(where, ": missing required field `", f, "`")
      }
    }

    ids <- vapply(y$sections, function(s) s$id %||% NA_character_, character(1))
    if (anyNA(ids)) stop(where, ": a section has no `id`")
    if (anyDuplicated(ids)) stop(where, ": duplicate section id")

    missing_req <- setdiff(REQUIRED_SECTIONS, ids)
    if (length(missing_req) > 0) {
      stop(where, ": missing required section(s) ",
           paste(missing_req, collapse = ", "))
    }
    unknown <- setdiff(ids, c(REQUIRED_SECTIONS, OPTIONAL_SECTIONS))
    if (length(unknown) > 0) {
      stop(where, ": unknown section id(s) ", paste(unknown, collapse = ", "),
           " - add to OPTIONAL_SECTIONS if intended")
    }

    for (lyr in y$map_layers %||% list()) {
      if (!lyr %in% registry_ids) {
        stop(where, ": map_layer '", lyr, "' is not in data/registry/map_layers.csv")
      }
    }

    for (s in y$sections) {
      # A stub section may legitimately be empty while content is being
      # written; a section with items must have well-formed ones.
      for (it in s$items %||% list()) {
        if (is.null(it$label) || !nzchar(it$label)) {
          stop(where, " [", s$id, "]: an item has no label")
        }
        if (is.null(it$url) || !grepl("^https://", it$url)) {
          stop(where, " [", s$id, "]: item '", it$label,
               "' needs an https:// url")
        }
      }
    }
  }
  TRUE
}

# Collect every URL in the catalog, with enough context to report a failure
# against the file and section it came from.
#
# Overlays are included. They are the files most likely to carry a stale link -
# they are edited rarely and reviewed less - so excluding them would leave the
# least-watched content unchecked. Found the hard way: three of the four links
# in the first overlay written were dead.
hazard_links <- function(content, overlays = list()) {
  all_content <- content
  for (key in names(overlays)) {
    parts <- strsplit(key, "/", fixed = TRUE)[[1]]
    merged <- merge_hazard_overlay(content[[parts[1]]], overlays[[key]])
    all_content[[key]] <- merged
  }
  rows <- lapply(names(all_content), function(slug) {
    y <- all_content[[slug]]
    lapply(y$sections, function(s) {
      items <- s$items %||% list()
      if (length(items) == 0) return(NULL)
      tibble::tibble(
        slug = slug, section = s$id,
        label = vapply(items, function(i) i$label, character(1)),
        url = vapply(items, function(i) i$url, character(1))
      )
    }) |> bind_rows()
  })
  bind_rows(rows)
}

# Check that every authored link resolves.
#
# Deliberately asymmetric about failure. A 404 or 410 is a real dead link and
# fails the build - that is the whole point of the check. A timeout, a 5xx, or a
# refused connection is far more likely to be CI flakiness or a bot filter than
# a broken page, so those warn instead. A link check that fails the build on a
# transient 503 gets disabled within a week, and then nothing is checked at all.
#
# HEAD first, falling back to GET: many nyc.gov pages reject HEAD.
#
# Two settings that look like cargo-culting but are load-bearing, both found by
# the check failing on real content:
#
#   A browser User-Agent. nyc.gov returns 403 to an honest descriptive agent.
#   With the honest string every nyc.gov link came back "unreachable, not
#   confirmed dead" - and four of the seven authored links were in fact 404.
#   The bot filter was masking real dead links, which makes the check worse than
#   useless: it reports reassuring warnings while the page ships broken.
#
#   HTTP/1.1. weather.gov emits a Content-Security-Policy header containing raw
#   newlines, which is illegal in HTTP/2 framing and aborts the connection.
#   Forcing 1.1 tolerates it.
LINK_CHECK_UA <- paste(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"
)

check_link <- function(url, timeout = 20) {
  try_once <- function(verb) {
    tryCatch(
      httr::VERB(verb, url, httr::timeout(timeout),
                 httr::user_agent(LINK_CHECK_UA),
                 httr::config(http_version = 2L)),  # 2L = HTTP/1.1 in libcurl
      error = function(e) e
    )
  }
  r <- try_once("HEAD")
  if (inherits(r, "error") || httr::status_code(r) >= 400) {
    r2 <- try_once("GET")
    if (!inherits(r2, "error")) r <- r2
  }
  if (inherits(r, "error")) {
    return(list(status = NA_integer_, note = conditionMessage(r)))
  }
  list(status = httr::status_code(r), note = NA_character_)
}

validate_hazard_links <- function(content, overlays = list(),
                                  dead_codes = c(404L, 410L)) {
  links <- hazard_links(content, overlays)
  if (nrow(links) == 0) {
    message("Link check: no links authored yet")
    return(TRUE)
  }

  results <- lapply(links$url, check_link)
  links$status <- vapply(results, function(r) r$status, integer(1))
  links$note <- vapply(results, function(r) r$note, character(1))

  dead <- links |> filter(status %in% dead_codes)
  if (nrow(dead) > 0) {
    stop(paste0(
      nrow(dead), " dead link(s) in hazard content:\n",
      paste0("  ", dead$slug, " [", dead$section, "] ", dead$status, " ",
             dead$url, collapse = "\n")
    ))
  }

  unreachable <- links |> filter(is.na(status) | status >= 400)
  if (nrow(unreachable) > 0) {
    warning(paste0(
      nrow(unreachable), " link(s) unreachable but not confirmed dead ",
      "(transient, or blocked by a bot filter):\n",
      paste0("  ", unreachable$slug, " [", unreachable$section, "] ",
             coalesce(as.character(unreachable$status), unreachable$note), " ",
             unreachable$url, collapse = "\n")
    ))
  }

  message(sprintf("Link check: %d links, %d ok, %d unreachable, 0 dead",
                  nrow(links), sum(links$status < 400, na.rm = TRUE),
                  nrow(unreachable)))
  TRUE
}

# --- output -----------------------------------------------------------------

# Fields that must always serialise as a JSON array, even with one element.
#
# auto_unbox = TRUE is what makes scalars come out as values rather than
# 1-element arrays, but it applies to everything - so a hazard with a single
# map layer emitted `"map_layers": "hvi_choropleth"` while every other hazard
# emitted `[]`. A frontend iterating that field works on seven hazards and
# breaks on the eighth. I() marks a value AsIs, which auto_unbox leaves alone.
HAZARD_ARRAY_FIELDS <- c("sections", "items", "map_layers")

force_arrays <- function(x, fields = HAZARD_ARRAY_FIELDS) {
  if (is.list(x)) {
    nms <- names(x)
    x <- lapply(x, force_arrays, fields = fields)
    names(x) <- nms
    if (!is.null(nms)) {
      for (f in intersect(nms, fields)) {
        if (!is.null(x[[f]])) x[[f]] <- I(x[[f]])
      }
    }
  }
  x
}

# Copy, not generate. The internal `.file` marker is dropped; everything else
# ships exactly as authored.
write_hazard_content <- function(content, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- vapply(names(content), function(slug) {
    y <- content[[slug]]
    y$.file <- NULL
    p <- file.path(dir, paste0(slug, ".json"))
    jsonlite::write_json(force_arrays(y), p, auto_unbox = TRUE,
                         null = "null", na = "null")
    p
  }, character(1))
  unname(paths)
}

# Assert the shape the frontend will actually iterate over. Catches the
# unboxing trap above, and anything else that collapses an array.
validate_hazard_output <- function(paths) {
  for (p in paths) {
    j <- jsonlite::fromJSON(p, simplifyVector = FALSE)
    if (!is.null(j$map_layers) && !is.list(j$map_layers)) {
      stop(basename(p), ": map_layers is not a JSON array")
    }
    if (!is.list(j$sections) || !is.null(names(j$sections))) {
      stop(basename(p), ": sections is not a JSON array")
    }
    for (s in j$sections) {
      if (!is.null(s$items) && (!is.list(s$items) || !is.null(names(s$items)))) {
        stop(basename(p), " [", s$id, "]: items is not a JSON array")
      }
    }
  }
  TRUE
}

# --- map layer registry -----------------------------------------------------
#
# Committed, hand-edited, reviewed as a diff - the same idiom as the geography
# crosswalk and the gap registry. It is the vocabulary that hazard content's
# `map_layers` must draw from, and the source of the layer ids that appear in
# map URLs.
#
# LAYER IDS ARE PERMALINK SURFACE. Once /q14/map?layers=hvi_choropleth has been
# shared, renaming that id breaks the link. Treat an id like `slug` and
# `resource_id`: additive changes are free, renames are a migration.

LAYER_STATUSES <- c("available", "blocked_on_data", "deferred")
LAYER_KINDS <- c("context", "resource")
LAYER_DELIVERY <- c("inline", "geojson", "pmtiles", "cog")

read_layer_registry <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    .default = readr::col_character()
  ))
}

validate_layer_registry <- function(reg) {
  required <- c("layer_id", "label", "kind", "geometry", "delivery", "status")
  missing <- setdiff(required, names(reg))
  if (length(missing) > 0) {
    stop("map_layers.csv: missing column(s) ", paste(missing, collapse = ", "))
  }
  assert_no_na(reg, required)
  assert_unique(reg, "layer_id")

  # Ids end up in URLs, so constrain them to something URL-safe and stable
  # rather than discovering later that a layer is called "FEMA 100yr".
  bad_id <- reg$layer_id[!grepl("^[a-z0-9_]+$", reg$layer_id)]
  if (length(bad_id) > 0) {
    stop("map_layers.csv: layer_id must be lowercase/digits/underscore - ",
         paste(bad_id, collapse = ", "))
  }

  for (col in c("kind", "delivery", "status")) {
    allowed <- switch(col, kind = LAYER_KINDS,
                      delivery = LAYER_DELIVERY, status = LAYER_STATUSES)
    bad <- setdiff(reg[[col]], allowed)
    if (length(bad) > 0) {
      stop("map_layers.csv: unknown ", col, " value(s) ",
           paste(bad, collapse = ", "))
    }
  }

  # A blocked layer must say what it is blocked on, or the registry stops
  # doubling as an acquisition backlog.
  blocked_no_reason <- reg |>
    filter(status == "blocked_on_data", is.na(blocked_on) | !nzchar(blocked_on))
  if (nrow(blocked_no_reason) > 0) {
    stop("map_layers.csv: blocked_on_data layer(s) with no blocked_on: ",
         paste(blocked_no_reason$layer_id, collapse = ", "))
  }
  TRUE
}

# --- per-district hazard content --------------------------------------------

# Which (district, hazard) pairs have an override. Emitted into the district
# payload so the frontend knows whether to fetch a district-specific file, and
# never has to probe for a 404.
hazard_override_index <- function(overlays) {
  if (length(overlays) == 0) {
    return(tibble::tibble(hazard = character(), district = character()))
  }
  parts <- strsplit(names(overlays), "/", fixed = TRUE)
  tibble::tibble(
    hazard = vapply(parts, `[`, character(1), 1),
    district = vapply(parts, `[`, character(1), 2)
  )
}

validate_hazard_overlays <- function(overlays, content, district_slugs) {
  idx <- hazard_override_index(overlays)
  bad_hazard <- setdiff(idx$hazard, names(content))
  if (length(bad_hazard) > 0) {
    stop("Overlay for unknown hazard(s): ", paste(bad_hazard, collapse = ", "))
  }
  bad_district <- setdiff(idx$district, district_slugs)
  if (length(bad_district) > 0) {
    stop("Overlay for unknown district(s): ",
         paste(bad_district, collapse = ", "),
         " - expected a district slug like q14")
  }
  TRUE
}

# Write only the districts that actually override something. 112 near-identical
# files would be the alternative; this emits 8 base files plus one per real
# override, and the district payload says which exist.
write_hazard_overlays <- function(content, overlays, dir) {
  if (length(overlays) == 0) return(character())
  paths <- vapply(names(overlays), function(key) {
    parts <- strsplit(key, "/", fixed = TRUE)[[1]]
    hazard <- parts[1]; district <- parts[2]
    merged <- merge_hazard_overlay(content[[hazard]], overlays[[key]])
    merged$.file <- NULL
    merged$district <- district
    out_dir <- file.path(dir, district, "hazards")
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    p <- file.path(out_dir, paste0(hazard, ".json"))
    jsonlite::write_json(force_arrays(merged), p, auto_unbox = TRUE,
                         null = "null", na = "null")
    p
  }, character(1))
  unname(paths)
}
