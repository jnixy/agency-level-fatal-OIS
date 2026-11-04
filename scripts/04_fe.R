# ==============================================================================
# Agency-level fatal OIS: Fatal Encounters agency-year counts
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Count FE fatal police shootings per agency-year (2000-2021) for every agency
#   in the resolved crosswalk. A multi-agency incident counts once for each
#   agency listed (matching WaPo's convention); n_fe_multi reports how many of
#   an agency's deaths were shared with another agency. Agencies reviewed by
#   hand and found to have no FE incidents ("none_found") get zeros; agencies
#   never matched stay NA, because a missing name match is not the same as a
#   zero. Caveat: a linked agency gets 0 in any year with no linked death,
#   which can be a false zero if FE also used an unlinked spelling of its
#   name, and FE's retrospective coverage is thinner before about 2013.
#   multi_agency is flagged before linking (any second listed name counts).
#
# Inputs:
#   - data/raw/fatal_encounters.csv
#   - data/clean/fe_agency_crosswalk.csv          -- from 03_fe_crosswalk.R
#   - data/crosswalks/fe_crosswalk_decisions.csv
#
# Outputs:
#   - data/clean/fe_agency_year.csv   -- ori7, year, n_fe, n_fe_multi, n_fe_flagged
#   - output/tables/fe_linkage.csv    -- how many qualifying FE deaths link
#   - output/tables/fe_top_unmatched_names.csv -- largest FE agencies not linked
#
# Runtime: < 30 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

dir.create(here("output", "tables"), recursive = TRUE, showWarnings = FALSE)

# 1. Load ----------------------------------------------------------------------
# Same loader and filters as 03 (scripts/functions.R)
fe_qual <- load_fe_qualifying()
chr <- cols(.default = col_character())
crosswalk <- read_csv(here("data", "clean", "fe_agency_crosswalk.csv"), col_types = chr)
decisions <- read_csv(here("data", "crosswalks", "fe_crosswalk_decisions.csv"), col_types = chr)

# 2. One row per death x listed agency -----------------------------------------
fe_parts <- split_fe_agencies(fe_qual)

# 3. Link and count ------------------------------------------------------------
linked <- fe_parts |>
  inner_join(crosswalk |> select(state, fe_agency_name, ori7),
             by = c("state", "fe_agency_name")) |>
  # Two FE spellings of one agency in the same incident still count once
  distinct(unique_id, year, ori7, multi_agency, fe_flag)

counts <- linked |>
  group_by(ori7, year) |>
  summarise(n_fe = n(), n_fe_multi = sum(multi_agency),
            n_fe_flagged = sum(fe_flag), .groups = "drop")

fe_agencies <- union(crosswalk$ori7,
                     decisions$ori7[decisions$decision == "none_found"])

fe_agency_year <- expand_grid(ori7 = fe_agencies, year = FE_YEARS) |>
  left_join(counts, by = c("ori7", "year")) |>
  mutate(across(c(n_fe, n_fe_multi, n_fe_flagged), \(x) replace_na(x, 0L)))

stopifnot(
  !anyDuplicated(fe_agency_year[c("ori7", "year")]),
  # Conservation: every linked death x agency pair lands in exactly one cell
  sum(fe_agency_year$n_fe) == nrow(linked),
  sum(fe_agency_year$n_fe_multi) == sum(linked$multi_agency),
  sum(fe_agency_year$n_fe_flagged) == sum(linked$fe_flag)
)

# 4. Linkage accounting --------------------------------------------------------
linked_ids <- unique(linked$unique_id)
fe_linkage <- tibble(
  measure = c("FE gunshot deaths coded 'Deadly force', 2000-2021",
              "  excluded: disposition murder/suicide, accidental, or ruled suicide",
              "Qualifying FE deaths, 2000-2021",
              "  flagged: description mentions self-inflicted, accidental, or off-duty",
              "  single-agency",
              "  multi-agency",
              "  no agency listed",
              "Deaths linked to >= 1 repo agency",
              "Agency-death links (multi-agency deaths count per agency)",
              "Distinct FE agency names linked",
              "ORI7 agencies with FE counts (incl. reviewed zeros)"),
  value = c(attr(fe_qual, "n_gunshot_deadly_force"),
            attr(fe_qual, "n_excluded_disposition"),
            nrow(fe_qual),
            sum(fe_qual$fe_flag),
            n_distinct(fe_parts$unique_id[!fe_parts$multi_agency]),
            n_distinct(fe_parts$unique_id[fe_parts$multi_agency]),
            nrow(fe_qual) - n_distinct(fe_parts$unique_id),
            length(linked_ids),
            nrow(linked),
            nrow(crosswalk),
            length(fe_agencies))
)

top_unmatched <- fe_parts |>
  anti_join(crosswalk, by = c("state", "fe_agency_name")) |>
  count(state, fe_agency_name, name = "fe_deaths", sort = TRUE) |>
  slice_head(n = 200)

# 5. Export --------------------------------------------------------------------
write_csv(fe_agency_year, here("data", "clean", "fe_agency_year.csv"))
write_csv(fe_linkage, here("output", "tables", "fe_linkage.csv"))
write_csv(top_unmatched, here("output", "tables", "fe_top_unmatched_names.csv"))
message("04: ", length(linked_ids), " of ", nrow(fe_qual),
        " qualifying FE deaths linked to ", length(fe_agencies), " agencies")
