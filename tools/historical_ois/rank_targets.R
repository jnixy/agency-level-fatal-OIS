# ==============================================================================
# Agency-level fatal OIS: rank hand-built agencies for historical extension
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Decide where to look first for pre-start-year counts. Each hand-built
#   agency is scored by how many people it killed in WaPo's data (a proxy for
#   size, and for the odds that it published annual force reports) times the
#   number of years between a floor year and the start of its hand-built
#   series. Big agencies with long gaps rise to the top.
#
# Inputs:
#   - output/agency_year_panel.csv   -- from scripts/05_combine.R
#
# Outputs:
#   - output/tables/historical_targets.csv -- one row per hand-built agency,
#     ranked by score
#
# Runtime: < 10 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)

# Agency annual reports with shooting counts are rare before ~1980, so years
# earlier than this don't add to an agency's score.
floor_year <- 1980

# 1. Load Data -----------------------------------------------------------------
panel <- read_csv(here("output", "agency_year_panel.csv"),
                  show_col_types = FALSE, guess_max = 1e6)

# 2. Score ---------------------------------------------------------------------
nix <- panel |> filter(in_nix)

coverage <- nix |>
  filter(!is.na(n_nix)) |>
  group_by(agency_id) |>
  summarise(nix_start = min(year), nix_end = max(year),
            nix_years = n_distinct(year),
            # Holes inside the series are also worth filling
            nix_internal_gaps = nix_end - nix_start + 1 - nix_years,
            .groups = "drop")

targets <- nix |>
  group_by(agency_id, ori7, agency_name, state, agency_type) |>
  summarise(wapo_deaths = sum(n_wapo, na.rm = TRUE),
            fe_deaths_2000_on = sum(n_fe, na.rm = TRUE),
            .groups = "drop") |>
  inner_join(coverage, by = "agency_id") |>
  mutate(years_missing = pmax(nix_start - floor_year, 0),
         score = wapo_deaths * years_missing) |>
  arrange(desc(score), desc(wapo_deaths)) |>
  mutate(rank = row_number(), .before = 1)

# 5. Export --------------------------------------------------------------------
dir.create(here("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(targets, here("output", "tables", "historical_targets.csv"))
message("Ranked ", nrow(targets), " agencies; ",
        sum(targets$score > 0), " have a pre-start gap after ", floor_year, ".")
