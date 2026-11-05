# ==============================================================================
# Agency-level fatal OIS: shared helper functions
# ==============================================================================
#
# Sourced by the numbered scripts and tools/agency_key/build_agency_key.R.
# normalize_name() and classify_agency_type() follow the rules used to build
# the hand-checked seed crosswalk (Brady & Nix, in progress), so FE matches
# here agree with that crosswalk.
# Packages: tidyverse (dplyr, stringr, readr, ggplot2), here, janitor, digest
# ==============================================================================

library(tidyverse)
library(here)

# Fatal Encounters ------------------------------------------------------------

# FE is not redistributed here, so users download their own copy. The SHA is
# the copy the published panel was built from; a different export of the same
# final release may differ byte-for-byte, so a mismatch only warns, and the
# hard gate is the release's row count and last date.
FE_SHA256    <- "847ed97ad8a94a595733c0613c6162da1602c539a196665b23779a318baebf5c"
FE_ROWS      <- 31498L
FE_LAST_DATE <- "12/31/2021"
FE_YEARS     <- 2000:2021

# FE's "Deadly force" intent code still includes some deaths that are not
# police use of force. Deaths FE's own disposition field codes as below are
# dropped. "Ruled suicide by police" (suicide-by-cop) is a police shooting
# and is kept.
FE_EXCLUDE_DISPOSITIONS <- c("murder/suicide", "accidental", "ruled suicide")

# Descriptions suggesting a death may not be an intentional on-duty police
# shooting. Matches are flagged (n_fe_flagged), not dropped: the search also
# catches legitimate cases, e.g., an off-duty officer stopping a robbery.
FE_FLAG_PATTERN <- paste(
  "shot (himself|herself)", "self-inflicted", "turned the gun on (himself|herself)",
  "killed (himself|herself)", "accidental(ly)? (discharg|fired|shot)", "accidentally",
  "training accident", "cleaning (his|her) gun", "off-duty", "off duty",
  sep = "|")

#' Load FE and keep qualifying deaths: gunshot deaths where FE coded the
#' intended force as deadly (drops suicides, pursuits, accidental shootings),
#' minus deaths FE's disposition field codes as murder/suicide, accidental, or
#' ruled suicide. Adds `fe_flag` (description suggests not an on-duty shooting).
#' Shared by 03 and 04 so the two can never filter differently.
#' @return tibble, one row per qualifying death, with `year` and upper-case `state`
load_fe_qualifying <- function(path = here("data", "raw", "fatal_encounters.csv")) {
  if (!file.exists(path)) {
    stop("Fatal Encounters file not found at data/raw/fatal_encounters.csv. ",
         "See data/README.md for where to download it.")
  }
  check_sha256(path, FE_SHA256, strict = FALSE)
  fe_all <- read_csv(path, show_col_types = FALSE, name_repair = "unique_quiet",
                     col_types = cols(.default = col_character())) |>
    janitor::clean_names()
  dates <- fe_all$date_of_injury_resulting_in_death_month_day_year
  if (nrow(fe_all) != FE_ROWS || !FE_LAST_DATE %in% dates) {
    stop("data/raw/fatal_encounters.csv is not the FE final release this panel ",
         "was built from (expected ", FE_ROWS, " rows ending ", FE_LAST_DATE,
         "; got ", nrow(fe_all), " rows).")
  }
  fe <- fe_all |>
    filter(highest_level_of_force == "Gunshot",
           intended_use_of_force_developing == "Deadly force") |>
    mutate(year = as.integer(str_sub(date_of_injury_resulting_in_death_month_day_year, -4)),
           state = toupper(str_squish(state)),
           disposition = tolower(str_squish(dispositions_exclusions_internal_use_not_for_analysis)),
           fe_flag = str_detect(tolower(brief_description), FE_FLAG_PATTERN) %in% TRUE)
  if (anyNA(fe$year)) stop("FE dates that do not end in a 4-digit year")
  if (anyDuplicated(fe$unique_id)) stop("Duplicate FE unique_id")
  fe <- filter(fe, year %in% FE_YEARS)
  excluded <- fe$disposition %in% FE_EXCLUDE_DISPOSITIONS
  out <- fe[!excluded, ]
  # Kept as attributes so 04 can report them in the linkage table
  attr(out, "n_gunshot_deadly_force") <- nrow(fe)
  attr(out, "n_excluded_disposition") <- sum(excluded)
  out
}

#' Split FE's comma-separated agency field: one row per death x listed agency.
#' `multi_agency` is TRUE when the record lists more than one distinct name
#' (before linking, so an unlinked partner agency still counts as sharing).
split_fe_agencies <- function(fe_qual) {
  fe_qual |>
    transmute(unique_id, year, state, fe_flag, fe_agency_name = agency_or_agencies_involved) |>
    separate_longer_delim(fe_agency_name, ",") |>
    mutate(fe_agency_name = str_squish(fe_agency_name)) |>
    filter(!is.na(fe_agency_name), fe_agency_name != "") |>
    group_by(unique_id) |>
    mutate(multi_agency = n_distinct(fe_agency_name) > 1) |>
    ungroup()
}

# Mapping Police Violence -------------------------------------------------------

# use_of_force can list several ("Gunshot,Conducted Energy Device"); any
# mention of a gunshot counts as a shooting death
MPV_GUNSHOT <- "gunshot"

# Agency names ----------------------------------------------------------------

#' Strip agency-type boilerplate so "Omaha Police Department" ~ "OMAHA POLICE DEPT."
#' Exact-match key: casing and agency-type words only.
#' @param x character vector of agency names
normalize_name <- function(x) {
  x |>
    tolower() |>
    str_replace_all("’", "'") |>
    # "\\.?" sits after the closing boundary: "\\b" cannot follow a period
    str_remove_all("\\bpolice department\\b|\\bpolice dept\\b\\.?") |>
    str_remove_all("\\bsheriff'?s? (office|department|dept)\\b\\.?") |>
    str_remove_all("\\bdepartment\\b|\\bpolice\\b|\\bsheriff'?s?\\b") |>
    str_squish()
}

# Words FE and the LEAIC use inconsistently ("city of", "metropolitan")
VARIANT_STOPWORDS <- c("city", "of", "the", "metro", "metropolitan", "division",
                       "bureau", "dept", "office", "pd", "so", "twp", "township",
                       "county", "co", "parish", "public safety", "department of")

#' Looser key for review candidates only; never accepted automatically.
variant_key <- function(x) {
  x |>
    normalize_name() |>
    str_replace_all("[[:punct:]]", " ") |>
    str_remove_all(paste0("\\b(", paste(VARIANT_STOPWORDS, collapse = "|"), ")\\b")) |>
    str_replace_all("\\bsaint\\b", "st") |>
    str_squish()
}

#' Coarse agency type used to block cross-type matches (city PD vs county SO).
#' @return "sheriff", "police", or "other"
classify_agency_type <- function(x) {
  x_lower <- tolower(x)
  case_when(
    str_detect(x_lower, "sheriff") ~ "sheriff",
    str_detect(x_lower, "police|division of police|metro pd|public safety|\\bpd\\b") ~ "police",
    TRUE ~ "other"
  )
}

# ORIs ------------------------------------------------------------------------

#' First 7 characters of an ORI (ORI9 -> ORI7); NA for malformed codes.
to_ori7 <- function(x) {
  x <- str_squish(toupper(x))
  if_else(nchar(x) %in% c(7, 9), str_sub(x, 1, 7), NA_character_)
}

#' Postal state from an ORI. Prefixes are postal codes except Nebraska ("NB").
ori_state <- function(ori) {
  prefix <- str_sub(ori, 1, 2)
  if_else(prefix == "NB", "NE", prefix)
}

# Files -----------------------------------------------------------------------

#' SHA-256 gate so a silently replaced raw file can't change results.
#' strict = FALSE warns instead of stopping (for files users download themselves).
check_sha256 <- function(path, expected, strict = TRUE) {
  got <- digest::digest(file = path, algo = "sha256")
  if (!identical(got, expected)) {
    msg <- paste0("Checksum mismatch for ", path, "\n  expected ", expected,
                  "\n  got      ", got, "\nSee data/README.md.")
    if (strict) stop(msg) else warning(msg, call. = FALSE)
  }
  invisible(identical(got, expected))
}

# Figures ---------------------------------------------------------------------

#' Short "City, ST" label from an agency name, for facets and row labels.
#' @param name agency name; @param state postal code
#' @return character, e.g. "Chicago, IL"; non-city agencies keep a short name
city_label <- function(name, state) {
  city <- name |>
    str_remove("( Metropolitan)? Police Department$") |>
    str_replace("^New York$", "New York City") |>
    str_replace(" County Sheriff's (Department|Office)$", " Co. Sheriff") |>
    str_replace("^Los Angeles Co\\.", "LA Co.")
  # DC's agency is "Metropolitan Police Department", which names no city
  city <- if_else(state == "DC", "Washington", city)
  paste0(city, ", ", state)
}

# Legend order follows this vector in every figure (validated with the
# dataviz palette checker: CVD separation and lightness/chroma bands pass)
source_colors <- c(
  "Hand-built (Nix)"   = "#2e6da4",
  "Washington Post"    = "#c0392b",
  "Fatal Encounters"   = "#d68910",
  "Mapping Police Violence" = "#7d3c98"
)
spliced_color <- "#9dbfe0"     # lighter tint of the hand-built blue (WaPo-filled years)
neutral_point_color <- "grey30"

# WaPo snapshot checksums (data/README.md); used by 02 and 07
WAPO_SHA256 <- c(
  "fatal-police-shootings-data.csv"     = "606745b7e5189d0291709390e04db1c7ea2f6f901db31584b3ceb22cc842d05c",
  "fatal-police-shootings-agencies.csv" = "45d59f3773af0f9ffbdf739f99b4adeafbdc846c54fd5b46f2631daa670a73da"
)

#' base_size 9-11 because figures are drawn at their printed 6.5in width
theme_project <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold"),
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold")
    )
}
