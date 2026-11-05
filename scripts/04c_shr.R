# ==============================================================================
# Agency-level fatal OIS: FBI Supplementary Homicide Reports agency-year counts
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Kaplan, J. (2017-). "Jacob Kaplan's Concatenated Files: UCR Program
#           Data: Supplementary Homicide Reports (SHR), 1976-2024." ICPSR
#           [distributor], V16. https://doi.org/10.3886/E100699V16
#
# Purpose:
#   Count people killed by police with a firearm per agency-year in the FBI's
#   SHR, the only national source that reaches back before 2000. A death
#   counts when an offender on the record has the circumstance "felon killed
#   by police" and that offender's weapon is a firearm. The record's victim
#   count (1 + additional victims) is the number of people killed.
#   SHR is not a census of agencies: agencies that file nothing in a year are
#   not in the file. So n_shr is 0 only when the agency filed at least one SHR
#   record that year, and NA otherwise. Deaths are filed under the REPORTING
#   agency, which is sometimes the investigating agency rather than the one
#   whose officer fired. SHR is known to miss many police killings.
#
# Inputs:
#   - data/raw/shr/shr_1976_2024.rds -- Kaplan's concatenated SHR (openICPSR
#     100699 V16; not redistributed, see data/README.md)
#
# Outputs:
#   - data/clean/shr_agency_year.csv -- ori7, year, n_shr (only ORIs with at
#     least one SHR record that year)
#   - output/tables/shr_linkage.csv  -- police killings kept and dropped, and why
#
# Runtime: ~30 sec (reading the .rds)
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

SHR_PATH   <- here("data", "raw", "shr", "shr_1976_2024.rds")
SHR_SHA256 <- "fa7569f31451cec5703e0031b89931ac73bd38d5fc127b4f19e4199fc0454c4a"
POLICE_CIRC <- "felon killed by police"
FIREARMS <- c("handgun", "rifle", "shotgun", "other firearm",
              "firearm (type not stated)")

# 1. Load ----------------------------------------------------------------------
if (!file.exists(SHR_PATH)) {
  stop("SHR file not found at data/raw/shr/shr_1976_2024.rds. ",
       "See data/README.md for where to download it.")
}
check_sha256(SHR_PATH, SHR_SHA256, strict = FALSE)
shr <- readRDS(SHR_PATH)

# Normalise codes before matching, so a year coded with different case or
# padding can't silently drop out
code_cols <- grep("^offender_[0-9]+_(circumstance|weapon)$", names(shr), value = TRUE)
shr <- shr |>
  mutate(ori = toupper(str_squish(ori)),
         across(all_of(code_cols), \(x) str_to_lower(str_squish(as.character(x)))))

stopifnot(
  !anyNA(shr$ori), all(nchar(shr$ori) == 7),
  is.numeric(shr$additional_victim_count),
  all(shr$additional_victim_count %in% c(NA, 0:99))
)

# 2. Police killings -----------------------------------------------------------
# Exact duplicate records are dropped once. The comparison includes
# incident_number and month, so two separate incidents can't collapse
n_raw <- nrow(shr)
shr <- distinct(shr)
n_dupes <- n_raw - nrow(shr)

offender_slots <- 1:11
circ_cols   <- paste0("offender_", offender_slots, "_circumstance")
weapon_cols <- paste0("offender_", offender_slots, "_weapon")
stopifnot(all(c(circ_cols, weapon_cols) %in% names(shr)))

# Usually offender 1 is the officer; a handful of records list the police
# circumstance only for a later offender, so every slot is checked
is_police  <- map(circ_cols, \(v) shr[[v]] %in% POLICE_CIRC)
police_gun <- map2(circ_cols, weapon_cols,
                   \(circ, wpn) shr[[circ]] %in% POLICE_CIRC & shr[[wpn]] %in% FIREARMS)

shr <- shr |>
  mutate(any_police = Reduce(`|`, is_police),
         police_firearm = Reduce(`|`, police_gun),
         people = 1L + coalesce(as.integer(additional_victim_count), 0L))

police <- shr |> filter(any_police)

linkage <- tibble(
  step = c("SHR records (all homicides)", "exact duplicate records dropped",
           "records: felon killed by police", "  of which weapon not a firearm (dropped)",
           "people killed by police with a firearm"),
  n = c(n_raw, n_dupes, nrow(police), sum(!police$police_firearm),
        sum(police$people[police$police_firearm])))

# 3. Agency-year ---------------------------------------------------------------
# Agency-years with any SHR record: these are where a 0 means "reported, none"
reporting <- shr |> distinct(ori7 = ori, year = as.integer(year))

shr_agency_year <- reporting |>
  left_join(police |> filter(police_firearm) |>
              group_by(ori7 = ori, year = as.integer(year)) |>
              summarise(n_shr = sum(people), .groups = "drop"),
            by = c("ori7", "year")) |>
  mutate(n_shr = replace_na(n_shr, 0L)) |>
  arrange(ori7, year)

stopifnot(
  !anyDuplicated(shr_agency_year[c("ori7", "year")]),
  sum(shr_agency_year$n_shr) == sum(police$people[police$police_firearm])
)

# 4. Export --------------------------------------------------------------------
dir.create(here("data", "clean"), recursive = TRUE, showWarnings = FALSE)
dir.create(here("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(shr_agency_year, here("data", "clean", "shr_agency_year.csv"))
write_csv(linkage, here("output", "tables", "shr_linkage.csv"))
message("04c: ", sum(shr_agency_year$n_shr), " people killed by police with a firearm, ",
        min(shr_agency_year$year), "-", max(shr_agency_year$year), "; ",
        n_distinct(shr_agency_year$ori7), " reporting ORIs")
