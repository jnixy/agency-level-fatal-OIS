# ==============================================================================
# Agency-level fatal OIS: stratified random draw for the long-run comparison
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Draw the probability sample of agencies whose 1985-94 fatal police
#   shootings will be rebuilt from newspapers. The universe is every frame
#   agency (08_sampling_frame.R) with a usable local archive per the
#   outcome-blind NewsBank audit (08b_coverage_audit.R). Agencies serving
#   500,000 or more are taken with certainty. The other 8 strata are sampled
#   without replacement, allocated in proportion to each stratum's usable pool
#   with at least 2 per stratum (28 in all). Agencies already rebuilt are part
#   of the pool and count only if drawn. The seed is fixed and recorded in the
#   protocol; agencies are sorted by ORI before sampling so the draw does not
#   depend on row order.
#
# Inputs:
#   - output/tables/sampling_frame_coverage.csv -- frame plus audit status
#
# Outputs:
#   - output/tables/sample_draw.csv -- every usable universe agency, with
#     stratum, pool size, allocation, selected flag, and design weight
#
# Runtime: < 5 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)

SEED <- 20261115
USABLE <- c("strong", "usable", "already rebuilt")
ALLOCATION <- c(
  "South 100-250k"     = 7,
  "West 100-250k"      = 4,
  "South 250-500k"     = 4,
  "Northeast 100-250k" = 3,
  "West 250-500k"      = 3,
  "Midwest 100-250k"   = 3,
  "Midwest 250-500k"   = 2,
  "Northeast 250-500k" = 2
)

# 1. Load ----------------------------------------------------------------------
coverage <- read_csv(here("output", "tables", "sampling_frame_coverage.csv"),
                     show_col_types = FALSE)

# 2. Universe ------------------------------------------------------------------
universe <- coverage |>
  filter(audit_status %in% USABLE) |>
  arrange(stratum, ori)

pools <- universe |> filter(stratum != "certainty") |> count(stratum, name = "pool_n")
stopifnot(setequal(pools$stratum, names(ALLOCATION)),
          sum(ALLOCATION) == 28,
          all(ALLOCATION[pools$stratum] <= pools$pool_n))

# 3. Draw ----------------------------------------------------------------------
set.seed(SEED)
drawn <- map(names(ALLOCATION), \(s) {
  ids <- universe$ori[universe$stratum == s]
  sample(ids, ALLOCATION[[s]])
}) |> unlist()

sample_draw <- universe |>
  left_join(pools, by = "stratum") |>
  mutate(alloc_n = if_else(stratum == "certainty", NA_real_, unname(ALLOCATION[stratum])),
         selected = stratum == "certainty" | ori %in% drawn,
         design_weight = case_when(stratum == "certainty" ~ 1,
                                   selected ~ pool_n / alloc_n,
                                   TRUE ~ NA_real_))

message(sprintf("08c: %d certainty + %d sampled agencies (%d of them already rebuilt)",
                sum(sample_draw$stratum == "certainty"), length(drawn),
                sum(sample_draw$selected & sample_draw$stratum != "certainty" &
                      sample_draw$audit_status == "already rebuilt")))

# 4. Export --------------------------------------------------------------------
write_csv(sample_draw, here("output", "tables", "sample_draw.csv"))
