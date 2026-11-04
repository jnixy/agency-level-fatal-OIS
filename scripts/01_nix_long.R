# ==============================================================================
# Agency-level fatal OIS: reshape the hand-built counts to agency-year
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Turn the wide hand-built file (one column per agency) into a long
#   agency-year file keyed by ORI7. Blank cells mean "no data," not zero, so
#   they are dropped rather than zero-filled. Slugs that share an ORI7
#   (Savannah PD / SCMPD) are summed into one agency.
#
# Inputs:
#   - agency-level-fatal-ois.csv   -- hand-built counts, wide
#   - data/agency_key.csv          -- slug -> ORI7, name, state, type
#
# Outputs:
#   - data/clean/nix_agency_year.csv -- agency_id, ori7, year, n_nix, slugs,
#                                       nix_partial (only some slugs had data)
#
# Runtime: < 10 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))
dir.create(here("data", "clean"), recursive = TRUE, showWarnings = FALSE)

# 1. Load ----------------------------------------------------------------------
wide <- read_csv(here("agency-level-fatal-ois.csv"), show_col_types = FALSE,
                 col_types = cols(.default = col_double()))
agency_key <- read_csv(here("data", "agency_key.csv"), show_col_types = FALSE,
                       col_types = cols(.default = col_character()))

stopifnot(
  "year" %in% names(wide),
  !anyNA(wide$year),
  !anyDuplicated(wide$year),
  all(is.na(agency_key$ori7) | str_detect(agency_key$ori7, "^[A-Z0-9]{7}$"))
)

# 2. Reshape and key -----------------------------------------------------------
nix_long <- wide |>
  pivot_longer(-year, names_to = "slug", values_to = "n_nix",
               values_drop_na = TRUE) |>
  mutate(year = as.integer(year))

missing_from_key <- setdiff(unique(nix_long$slug), agency_key$slug)
if (length(missing_from_key) > 0) {
  stop("Slugs in the CSV but not in data/agency_key.csv: ",
       paste(missing_from_key, collapse = ", "))
}
stopifnot(
  all(nix_long$n_nix >= 0),
  all(nix_long$n_nix == round(nix_long$n_nix))
)

# Agencies without an ORI (utah_doc) keep their slug as the ID so they are not
# silently dropped, as the 2025 merge script did.
nix_agency_year <- nix_long |>
  left_join(agency_key |> select(slug, ori7), by = "slug") |>
  mutate(agency_id = coalesce(ori7, slug)) |>
  group_by(agency_id, ori7, year) |>
  summarise(n_nix = sum(n_nix),
            slugs = paste(sort(unique(slug)), collapse = ";"),
            .groups = "drop")

# For agencies with two slugs, flag years where only one slug has data:
# the sum is then only as complete as that one source
slugs_per_agency <- agency_key |>
  mutate(agency_id = coalesce(ori7, slug)) |>
  count(agency_id, name = "n_slugs_total")
nix_agency_year <- nix_agency_year |>
  left_join(slugs_per_agency, by = "agency_id") |>
  mutate(nix_partial = str_count(slugs, ";") + 1 < n_slugs_total) |>
  select(-n_slugs_total)

# Every count in the wide file must survive the reshape
stopifnot(
  sum(nix_agency_year$n_nix) == sum(as.matrix(wide[-1]), na.rm = TRUE),
  !anyDuplicated(nix_agency_year[c("agency_id", "year")])
)

# 3. Export --------------------------------------------------------------------
write_csv(nix_agency_year, here("data", "clean", "nix_agency_year.csv"), na = "")
message("01: ", n_distinct(nix_agency_year$agency_id), " agencies, ",
        nrow(nix_agency_year), " agency-years with hand-built data")
