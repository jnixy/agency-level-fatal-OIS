# ==============================================================================
# Agency-level fatal OIS: sampling frame for the long-run comparison
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Kaplan, J. (2017-). "Jacob Kaplan's Concatenated Files: UCR Program
#           Data: Supplementary Homicide Reports (SHR), 1976-2024." ICPSR
#           [distributor], V16. https://doi.org/10.3886/E100699V16
#
# Purpose:
#   Define the agencies the long-run (then vs. now) comparison generalizes to,
#   using only a pre-period characteristic, so that no outcome plays a part in
#   who is included. The frame is every local police department and sheriff's
#   office whose median population served in 1985-1994 was at least 100,000.
#   Agencies serving 500,000 or more form a certainty stratum; the rest are
#   split into 8 sampling strata (4 Census regions x 2 size tiers).
#   Population comes from SHR because it is already linked to the pipeline.
#   SHR lists an agency only in years it filed a homicide record, so the median
#   is taken over the years it appears (Florida, for example, filed nothing in
#   1988-91). Large agencies that filed nothing at all in 1985-94 are missing.
#
# Inputs:
#   - data/raw/shr/shr_1976_2024.rds -- Kaplan's concatenated SHR (not
#     redistributed, see data/README.md)
#   - output/tables/then_vs_now.csv  -- current long-panel agencies (07)
#
# Outputs:
#   - output/tables/sampling_frame.csv -- one row per frame agency: ORI,
#     name, state, type, Census division and region, median 1985-94
#     population, years observed, stratum, and current long-panel status
#
# Runtime: ~30 sec (reading the .rds)
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

SHR_PATH    <- here("data", "raw", "shr", "shr_1976_2024.rds")
SHR_SHA256  <- "fa7569f31451cec5703e0031b89931ac73bd38d5fc127b4f19e4199fc0454c4a"
FRAME_YEARS <- 1985:1994
POP_FLOOR   <- 1e5   # frame: median population served >= 100,000
POP_CERTAIN <- 5e5   # certainty stratum: >= 500,000
TIER_CUT    <- 2.5e5 # sampling strata split at 250,000
FRAME_TYPES <- c("local police department", "sheriffs office")

REGIONS <- c(
  "new england" = "Northeast", "middle atlantic" = "Northeast",
  "east north central" = "Midwest", "west north central" = "Midwest",
  "south atlantic" = "South", "east south central" = "South",
  "west south central" = "South",
  "mountain" = "West", "pacific" = "West"
)

# 1. Load ----------------------------------------------------------------------
if (!file.exists(SHR_PATH)) {
  stop("SHR file not found at data/raw/shr/shr_1976_2024.rds. ",
       "See data/README.md for where to download it.")
}
check_sha256(SHR_PATH, SHR_SHA256, strict = FALSE)
shr <- readRDS(SHR_PATH)
long_panel <- read_csv(here("output", "tables", "then_vs_now.csv"),
                       show_col_types = FALSE)

# 2. Clean ---------------------------------------------------------------------
# SHR has one row per incident; population is an agency-year attribute, so
# collapse to one value per agency-year before taking the median
agency_year <- shr |>
  mutate(ori = toupper(str_squish(ori)),
         agency_type = str_to_lower(str_squish(as.character(agency_type))),
         country_division = str_to_lower(str_squish(as.character(country_division)))) |>
  filter(year %in% FRAME_YEARS, agency_type %in% FRAME_TYPES,
         !is.na(population), population > 0) |>
  group_by(ori, year) |>
  summarise(population = max(population),
            agency_name = first(crosswalk_agency_name),
            state_abb = first(state_abb),
            agency_type = first(agency_type),
            division = first(country_division),
            .groups = "drop")

stopifnot(all(agency_year$division %in% names(REGIONS)))

# 3. Build frame ---------------------------------------------------------------
frame <- agency_year |>
  group_by(ori) |>
  summarise(agency_name = last(agency_name),
            state_abb = last(state_abb),
            agency_type = last(agency_type),
            division = last(division),
            pop_median_1985_94 = median(population),
            years_observed = n(),
            .groups = "drop") |>
  filter(pop_median_1985_94 >= POP_FLOOR) |>
  mutate(region = unname(REGIONS[division]),
         size_tier = if_else(pop_median_1985_94 >= TIER_CUT, "250-500k", "100-250k"),
         stratum = if_else(pop_median_1985_94 >= POP_CERTAIN, "certainty",
                           paste(region, size_tier)),
         in_long_panel = ori %in% long_panel$agency_id) |>
  arrange(desc(pop_median_1985_94))

stopifnot(!anyDuplicated(frame$ori), !anyNA(frame$region))
message(sprintf("08: frame has %d agencies (%d certainty); %d already in the long panel",
                nrow(frame), sum(frame$stratum == "certainty"), sum(frame$in_long_panel)))

# 4. Export --------------------------------------------------------------------
dir.create(here("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(frame, here("output", "tables", "sampling_frame.csv"))
