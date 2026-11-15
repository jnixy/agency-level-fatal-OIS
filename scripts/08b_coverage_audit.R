# ==============================================================================
# Agency-level fatal OIS: NewsBank coverage audit of the sampling frame
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Summarize an outcome-blind audit of whether each frame agency has a usable
#   local newspaper archive in NewsBank (Access World News), before any sample
#   is drawn. For each agency the audit searched the agency phrase (e.g.,
#   "Tucson police") across all sources for 1990-94, took the highest-volume
#   source located in the agency's state among the top four, and counted that
#   source's hits by year (1990-94, and 1985-89 if needed). It counts stories
#   that mention the agency; it reads no articles and records no shootings.
#   Rule, fixed before the audit ran: an agency is USABLE if one in-state source
#   has at least MIN_HITS hits in at least MIN_YEARS of 1985-1994, and STRONG if
#   it has at least STRONG_HITS hits in at least MIN_YEARS of those years.
#   Agencies already rebuilt in the long panel are usable by construction.
#
# Inputs:
#   - output/tables/sampling_frame.csv    -- frame (08_sampling_frame.R)
#   - data/historical/coverage_audit.csv  -- raw audit results, one row per
#     audited agency (search term, chosen source, hits by year)
#
# Outputs:
#   - output/tables/sampling_frame_coverage.csv -- frame plus audit status
#   - output/tables/coverage_by_stratum.csv      -- counts by stratum and status
#
# Runtime: < 5 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)

MIN_HITS    <- 50
STRONG_HITS <- 150
MIN_YEARS   <- 5
YEARS       <- 1985:1994

# 1. Load ----------------------------------------------------------------------
frame <- read_csv(here("output", "tables", "sampling_frame.csv"), show_col_types = FALSE)
audit <- read_csv(here("data", "historical", "coverage_audit.csv"), show_col_types = FALSE)

stopifnot(!anyDuplicated(audit$ori))

# 2. Classify ------------------------------------------------------------------
hit_cols <- paste0("hits_", YEARS)
audit <- audit |>
  mutate(across(all_of(hit_cols), \(x) replace_na(x, 0)),
         years_usable = rowSums(across(all_of(hit_cols), \(x) x >= MIN_HITS)),
         years_strong = rowSums(across(all_of(hit_cols), \(x) x >= STRONG_HITS)),
         audit_status = case_when(
           is.na(source) ~ "no in-state source",
           years_strong >= MIN_YEARS ~ "strong",
           years_usable >= MIN_YEARS ~ "usable",
           TRUE ~ "too thin"))

coverage <- frame |>
  left_join(audit |> select(ori, term, source, years_usable, years_strong, audit_status),
            by = "ori") |>
  mutate(audit_status = if_else(in_long_panel, "already rebuilt", audit_status))

missing <- coverage |> filter(is.na(audit_status))
if (nrow(missing) > 0) {
  stop(nrow(missing), " frame agencies have no audit result: ",
       paste(head(missing$ori, 10), collapse = ", "))
}

by_stratum <- coverage |>
  count(stratum, audit_status) |>
  pivot_wider(names_from = audit_status, values_from = n, values_fill = 0) |>
  mutate(total = rowSums(across(where(is.numeric))))

message(sprintf("08b: %d of %d frame agencies usable or already rebuilt",
                sum(coverage$audit_status %in% c("strong", "usable", "already rebuilt")),
                nrow(coverage)))

# 3. Export --------------------------------------------------------------------
write_csv(coverage, here("output", "tables", "sampling_frame_coverage.csv"))
write_csv(by_stratum, here("output", "tables", "coverage_by_stratum.csv"))
