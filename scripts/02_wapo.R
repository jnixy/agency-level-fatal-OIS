# ==============================================================================
# Agency-level fatal OIS: Washington Post Fatal Force, agency-year counts
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Rewrite of wapo_historical_merge/merge_script.R (Jan 2025)
#
# Purpose:
#   Count people shot and killed by police per agency-year in WaPo's v2 data
#   (2015-2024; the database was archived after 2024). An incident counts once
#   for each agency involved, and once per ORI7, so two WaPo agency records
#   that share an ORI (e.g., name variants) are not double counted. WaPo lists
#   dozens of ORIs for statewide agencies (state police, CHP); those agencies
#   are assigned to a single primary ORI so their deaths aren't repeated
#   across many rows. WaPo is a national census, so agency-years with no
#   record are true zeros.
#
# Inputs:
#   - data/raw/wapo/fatal-police-shootings-data.csv
#   - data/raw/wapo/fatal-police-shootings-agencies.csv
#   - data/agency_key.csv
#
# Outputs:
#   - data/clean/wapo_agency_year.csv -- ori7, year, n_wapo (zero-filled)
#   - data/clean/wapo_agencies.csv    -- one row per ORI7: names, state, type,
#                                        wapo_multi_ori (WaPo lists several ORIs)
#   - data/clean/wapo_agency_oris.csv -- every ORI WaPo lists, with its primary
#
# Runtime: < 10 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

wapo_years <- 2015:2024

# 1. Load ----------------------------------------------------------------------
wapo_dir <- here("data", "raw", "wapo")
# The archived snapshot the panel was built from (see data/README.md)
check_sha256(file.path(wapo_dir, "fatal-police-shootings-data.csv"),
             "606745b7e5189d0291709390e04db1c7ea2f6f901db31584b3ceb22cc842d05c")
check_sha256(file.path(wapo_dir, "fatal-police-shootings-agencies.csv"),
             "45d59f3773af0f9ffbdf739f99b4adeafbdc846c54fd5b46f2631daa670a73da")
incidents <- read_csv(file.path(wapo_dir, "fatal-police-shootings-data.csv"),
                      show_col_types = FALSE,
                      col_types = cols(.default = col_character()))
agencies <- read_csv(file.path(wapo_dir, "fatal-police-shootings-agencies.csv"),
                     show_col_types = FALSE,
                     col_types = cols(.default = col_character()))
agency_key <- read_csv(here("data", "agency_key.csv"), show_col_types = FALSE,
                       col_types = cols(.default = col_character()))

# 2. Assign each WaPo agency one primary ORI7 ----------------------------------
agency_oris_all <- agencies |>
  select(wapo_id = id, name, state, type, oricodes) |>
  separate_longer_delim(oricodes, ";") |>
  mutate(ori7 = to_ori7(oricodes),
         in_key = ori7 %in% agency_key$ori7) |>
  filter(!is.na(ori7)) |>
  distinct(wapo_id, ori7, .keep_all = TRUE) |>
  group_by(wapo_id) |>
  mutate(n_oris = n(), position = row_number()) |>
  ungroup()

# If one WaPo record listed two ORIs that are separate hand-built agencies,
# only one would get its deaths and the other would show a false 0
key_ties <- agency_oris_all |> filter(in_key) |> count(wapo_id) |> filter(n > 1)
if (nrow(key_ties) > 0) {
  stop("WaPo agencies listing more than one hand-built ORI: ",
       paste(key_ties$wapo_id, collapse = ", "))
}

# Hand-checked overrides for WaPo records that split one agency in two
# without sharing an ORI. (Records that do share an ORI already collapse,
# because deaths are counted per ORI. Merging every record linked by any
# shared ORI was tried and rejected: WaPo coding errors chain unrelated
# agencies together, e.g. Metro Nashville PD with Granville Co. SO, NC.)
primary_overrides <- tribble(
  ~wapo_id, ~ori7_override, ~reason,
  "11725",  "GAGSP00",      "'Georgia State Patrol' (GAGSP37;GAGSP42) is the same agency as WaPo 1038 'Georgia State Police'"
)

agency_oris <- agency_oris_all |>
  group_by(wapo_id) |>
  # Prefer an ORI the hand-built key already uses; otherwise the first listed
  arrange(desc(in_key), position, .by_group = TRUE) |>
  slice(1) |>
  ungroup() |>
  left_join(primary_overrides |> select(wapo_id, ori7_override), by = "wapo_id") |>
  mutate(ori7 = coalesce(ori7_override, ori7),
         n_oris = if_else(is.na(ori7_override), n_oris, 2L)) |>
  select(-ori7_override)

stopifnot(all(primary_overrides$wapo_id %in% agency_oris$wapo_id))

wapo_agency_lookup <- agency_oris |>
  select(wapo_id, ori7, n_oris)

# 3. Agency-year counts --------------------------------------------------------
incident_agency <- incidents |>
  transmute(incident_id = id, year = as.integer(str_sub(date, 1, 4)),
            wapo_id = agency_ids) |>
  separate_longer_delim(wapo_id, ";") |>
  mutate(wapo_id = str_squish(wapo_id))

stopifnot(all(incident_agency$year %in% wapo_years))

# One death, one ORI: two WaPo records for the same ORI count once
death_ori <- incident_agency |>
  inner_join(wapo_agency_lookup, by = "wapo_id") |>
  distinct(incident_id, year, ori7)

# Deaths with no ORI-coded agency at all (mostly federal task forces)
n_no_ori <- n_distinct(incidents$id) - n_distinct(death_ori$incident_id)

wapo_counts <- death_ori |> count(ori7, year, name = "n_wapo")

wapo_agency_year <- expand_grid(ori7 = unique(wapo_agency_lookup$ori7),
                                year = wapo_years) |>
  left_join(wapo_counts, by = c("ori7", "year")) |>
  mutate(n_wapo = replace_na(n_wapo, 0L))

wapo_agencies <- agency_oris |>
  group_by(ori7) |>
  summarise(wapo_name = paste(unique(name), collapse = " | "),
            # State from the ORI, not WaPo's field, which can be the state of
            # the incident (Navajo Nation PD is listed under AZ and NM)
            wapo_state = ori_state(first(ori7)),
            wapo_type = first(type),
            wapo_ids = paste(wapo_id, collapse = ";"),
            wapo_multi_ori = any(n_oris > 1),
            .groups = "drop")

stopifnot(
  !anyDuplicated(wapo_agency_year[c("ori7", "year")]),
  # Conservation: every death x ORI pair lands in exactly one cell
  sum(wapo_agency_year$n_wapo) == nrow(death_ori)
)

# 4. Export --------------------------------------------------------------------
write_csv(wapo_agency_year, here("data", "clean", "wapo_agency_year.csv"))
write_csv(wapo_agencies, here("data", "clean", "wapo_agencies.csv"))
# Every ORI WaPo lists, with the primary it was assigned (used by 03 to tell
# one agency's many ORIs apart from distinct agencies with the same name)
write_csv(agency_oris_all |> select(wapo_id, ori7) |>
            left_join(wapo_agency_lookup |> select(wapo_id, primary_ori7 = ori7), by = "wapo_id"),
          here("data", "clean", "wapo_agency_oris.csv"))
message("02: ", nrow(incidents), " WaPo deaths; ", nrow(wapo_agencies),
        " ORI7s; ", n_no_ori, " deaths have no ORI-coded agency")
