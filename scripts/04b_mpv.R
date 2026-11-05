# ==============================================================================
# Agency-level fatal OIS: Mapping Police Violence agency-year counts
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Count people shot and killed by police per agency-year in Mapping Police
#   Violence (MPV), the one national source still updating. MPV records each
#   agency's ORI, so no name matching is needed. A death counts once for each
#   ORI involved (the WaPo/FE convention). Off-duty killings are included and
#   counted separately in n_mpv_offduty, so users can subtract them. Only
#   complete calendar years are kept. MPV is a national census, so ORIs with
#   no record in a year get 0.
#
# Inputs:
#   - data/raw/mpv/mpv_YYYY-MM-DD.csv     -- newest snapshot (tools/fetch_mpv)
#   - data/crosswalks/mpv_snapshots.csv   -- snapshot manifest (checksums)
#   - data/agency_key.csv, data/clean/wapo_agencies.csv, wapo_agency_oris.csv,
#     data/raw/wapo/fatal-police-shootings-data.csv -- for name recovery and
#     ORI aliases (MPV's wapo_id links its deaths to WaPo's)
#
# Outputs:
#   - data/clean/mpv_agency_year.csv -- ori7, year, n_mpv, n_mpv_offduty, n_mpv_multi
#   - data/clean/mpv_agencies.csv    -- ori7, mpv_name, mpv_state
#   - output/tables/mpv_linkage.csv  -- deaths kept, dropped, and why
#   - data/clean/mpv_ori_aliases.csv -- MPV ORIs re-pointed to WaPo's ORI
#   - output/tables/mpv_ori_resolution.csv -- how each agency mention got its ORI
#   - output/tables/mpv_unresolved.csv      -- agency mentions with no ORI, for review
#   - output/tables/mpv_alias_candidates.csv -- every alias candidate and why it passed/failed
#
# Runtime: < 15 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

MPV_FIRST_YEAR <- 2013L

# 1. Load the newest snapshot --------------------------------------------------
manifest <- read_csv(here("data", "crosswalks", "mpv_snapshots.csv"),
                     col_types = cols(.default = col_character()))
snap <- manifest |> arrange(desc(snapshot_date)) |> slice(1)
snap_path <- here("data", "raw", "mpv", snap$file)
if (!file.exists(snap_path)) {
  stop("MPV snapshot ", snap$file, " not found. Run tools/fetch_mpv/fetch_mpv.py ",
       "(see data/README.md).")
}
# Others will fetch newer snapshots, so a mismatch warns rather than stops
check_sha256(snap_path, snap$sha256, strict = FALSE)

mpv_raw <- read_csv(snap_path, show_col_types = FALSE,
                    col_types = cols(.default = col_character()))


# 2. Gunshot deaths in complete years ------------------------------------------
mpv <- mpv_raw |>
  mutate(death_id = row_number(),
         date_parsed = lubridate::mdy(date),
         year = lubridate::year(date_parsed),
         offduty = str_detect(coalesce(off_duty_killing, ""), regex("off.?duty", ignore_case = TRUE)))
stopifnot(!anyNA(mpv$year))

# The last year counts as complete only if the snapshot reaches its final week;
# derived from the data itself, and checked against the manifest
last_incident <- max(mpv$date_parsed)
stopifnot(last_incident <= Sys.Date(),
          as.character(last_incident) == snap$last_incident_date)
last_complete_year <- lubridate::year(last_incident) -
  if (lubridate::month(last_incident) == 12 && lubridate::day(last_incident) >= 25) 0L else 1L
mpv_years <- MPV_FIRST_YEAR:last_complete_year

gunshot <- mpv |>
  filter(str_detect(use_of_force, regex(MPV_GUNSHOT, ignore_case = TRUE)),
         year %in% mpv_years)

# 3. One row per death x listed agency -----------------------------------------
# MPV lists agencies and their ORIs comma-separated in the same order, with a
# placeholder ("Not available") where an agency has no ORI. The ORI list is
# the authoritative agency count; names are split on commas too, so a comma
# inside a name (rare) makes the lists unequal. Equal lists are paired name to
# ORI, so a missing ORI can be recovered from the name. Unequal lists keep
# their ORIs only, and any placeholder in them is counted as lost below.
state_postal <- set_names(c(state.abb, "DC"), toupper(c(state.name, "District of Columbia")))
name_key <- function(x) str_to_upper(str_squish(x))   # case-insensitive name joins

parts <- gunshot |>
  transmute(death_id, year, offduty,
            state = unname(state_postal[toupper(str_squish(state))]),
            names = str_split(agency_responsible, ",\\s*"),
            oris = str_split(coalesce(ori, ""), ",\\s*")) |>
  mutate(paired = lengths(names) == lengths(oris),
         n_listed = if_else(lengths(oris) > 1 | oris != "", lengths(oris), lengths(names)))
stopifnot(!anyNA(parts$state))

agency_parts <- bind_rows(
  parts |> filter(paired) |> unnest(c(names, oris)),
  parts |> filter(!paired) |> select(-names) |> unnest(oris) |> mutate(names = NA_character_)
) |>
  transmute(death_id, year, offduty, state, n_listed, paired,
            agency = str_squish(names), agency_u = name_key(names),
            mpv_ori7 = to_ori7(oris))

# 3a. Recover missing ORIs from names -------------------------------------------
# (1) the same name and state carries a valid ORI elsewhere in MPV (one ORI only)
# (2) else an exact normalized name + state + type match to exactly one agency
#     in the agency key or WaPo's agency file
# (3) else a hand decision (data/crosswalks/mpv_name_decisions.csv). Looser
#     automatic matching was rejected: it matched Hawaii's state Department of
#     Public Safety to Hawaii County PD.
mpv_named <- agency_parts |>
  filter(!is.na(mpv_ori7), !is.na(agency_u)) |>
  distinct(state, agency_u, mpv_ori7) |>
  group_by(state, agency_u) |>
  filter(n_distinct(mpv_ori7) == 1) |>
  ungroup() |>
  transmute(state, agency_u, ori7_mpv_name = mpv_ori7)

agency_key <- read_csv(here("data", "agency_key.csv"), col_types = cols(.default = col_character()))
wapo_agencies <- read_csv(here("data", "clean", "wapo_agencies.csv"),
                          col_types = cols(.default = col_character()))
target_names <- bind_rows(
  agency_key |> filter(!is.na(ori7)) |> transmute(ori7, state, name = agency_name),
  wapo_agencies |> transmute(ori7, state = wapo_state, name = wapo_name) |>
    separate_longer_delim(name, " | ")
) |>
  mutate(norm = normalize_name(name), type = classify_agency_type(name)) |>
  distinct(ori7, state, norm, type) |>
  group_by(state, norm, type) |>
  filter(n_distinct(ori7) == 1) |>          # ambiguous names are never matched
  ungroup() |>
  transmute(state, norm, type, ori7_exact = ori7)

name_decisions <- read_csv(here("data", "crosswalks", "mpv_name_decisions.csv"),
                           col_types = cols(.default = col_character())) |>
  transmute(state, agency_u = name_key(agency), ori7_manual = ori7)
stopifnot(!anyDuplicated(name_decisions[c("state", "agency_u")]))

agency_parts <- agency_parts |>
  mutate(norm = normalize_name(agency), type = classify_agency_type(agency)) |>
  left_join(mpv_named, by = c("state", "agency_u")) |>
  left_join(target_names, by = c("state", "norm", "type")) |>
  left_join(name_decisions, by = c("state", "agency_u")) |>
  mutate(ori7 = coalesce(mpv_ori7, ori7_mpv_name, ori7_exact, ori7_manual),
         ori_source = case_when(!is.na(mpv_ori7) ~ "mpv_ori",
                                !is.na(ori7_mpv_name) ~ "mpv_same_name",
                                !is.na(ori7_exact) ~ "exact_name",
                                !is.na(ori7_manual) ~ "manual",
                                TRUE ~ "unresolved"))

# A hand decision must still be needed: present in the data and not already
# resolved by a higher-priority rule
decision_use <- agency_parts |>
  semi_join(name_decisions, by = c("state", "agency_u")) |>
  count(state, agency_u, used = ori_source == "manual")
stale <- name_decisions |>
  anti_join(decision_use |> filter(used), by = c("state", "agency_u"))
if (nrow(stale) > 0) {
  stop("MPV name decisions no longer needed or not found: ",
       paste(stale$agency_u, collapse = "; "))
}

# 3b. ORI aliases --------------------------------------------------------------
# Some agencies appear in MPV under a different ORI than in WaPo and the key
# (e.g., Jacksonville SO: FL01624 in MPV, FL01602 elsewhere; state police
# troop codes). Using deaths in both MPV and WaPo (MPV's wapo_id), an MPV ORI
# that neither WaPo (any ORI it lists) nor the key uses is aliased to the WaPo
# ORI when:
#   - at least ALIAS_MIN_DEATHS shared single-agency deaths, and at least
#     ALIAS_MIN_SHARE of all its WaPo-matched deaths, point to that one ORI;
#   - both ORIs are in the same state; and
#   - if both ORIs share a county code (first five characters), the agency
#     names must also match, since two agencies in one county differ by ORI
#     suffix (e.g., a county police department and sheriff's office).
ALIAS_MIN_DEATHS <- 3L
ALIAS_MIN_SHARE  <- 0.8

wapo_inc <- read_csv(here("data", "raw", "wapo", "fatal-police-shootings-data.csv"),
                     col_types = cols(.default = col_character()))
wapo_oris <- read_csv(here("data", "clean", "wapo_agency_oris.csv"),
                      col_types = cols(.default = col_character()))
wapo_primary <- wapo_oris |> distinct(wapo_id, primary_ori7)
known_oris <- unique(c(wapo_oris$ori7, wapo_oris$primary_ori7, na.omit(agency_key$ori7)))

wapo_death_ori <- wapo_inc |>
  transmute(wid = id, wapo_id = agency_ids) |>
  separate_longer_delim(wapo_id, ";") |>
  left_join(wapo_primary, by = "wapo_id") |>
  filter(!is.na(primary_ori7)) |>
  group_by(wid) |>
  filter(n_distinct(primary_ori7) == 1) |>
  summarise(wapo_ori7 = first(primary_ori7), .groups = "drop")

mpv_ori_names <- agency_parts |>
  filter(n_listed == 1, !is.na(agency), !is.na(ori7)) |>
  count(ori7, agency, sort = TRUE) |>
  distinct(ori7, .keep_all = TRUE) |>
  select(ori7, mpv_name = agency)
wapo_ori_names <- wapo_agencies |>
  transmute(wapo_ori7 = ori7, wapo_name = str_remove(wapo_name, " \\|.*$"))

alias_candidates <- gunshot |>
  filter(!is.na(wapo_id)) |>
  transmute(death_id, wid = str_squish(wapo_id)) |>
  inner_join(agency_parts |> filter(n_listed == 1, !is.na(ori7)) |>
               select(death_id, ori7, state), by = "death_id") |>
  inner_join(wapo_death_ori, by = "wid") |>
  filter(!ori7 %in% known_oris) |>
  group_by(ori7) |>
  mutate(matched = n()) |>                   # denominator: all matched deaths
  group_by(ori7, wapo_ori7, matched) |>
  summarise(shared = n(), state = first(state), .groups = "drop") |>
  mutate(share = shared / matched) |>
  left_join(mpv_ori_names, by = "ori7") |>
  left_join(wapo_ori_names, by = "wapo_ori7") |>
  mutate(same_county = str_sub(ori7, 1, 5) == str_sub(wapo_ori7, 1, 5),
         names_match = variant_key(mpv_name) == variant_key(wapo_name),
         accept = shared >= ALIAS_MIN_DEATHS & share >= ALIAS_MIN_SHARE &
           ori_state(wapo_ori7) == state & ori_state(ori7) == state &
           (!same_county | names_match %in% TRUE))

aliases <- alias_candidates |>
  filter(accept) |>
  transmute(ori7, alias_to = wapo_ori7, mpv_name, wapo_name, shared, matched,
            share = round(share, 3))
stopifnot(!anyDuplicated(aliases$ori7),
          all(aliases$alias_to %in% known_oris),
          all(str_sub(aliases$ori7, 1, 2) == str_sub(aliases$alias_to, 1, 2)))

# 3c. ORIs WaPo itself assigns to another agency -------------------------------
# WaPo lists dozens of ORIs for statewide agencies (e.g., Pennsylvania State
# Police: PA001SP, PAPSP00, ...) and assigns their deaths to one primary ORI
# (02_wapo.R). MPV often uses one of the secondary codes. Those are mapped to
# WaPo's primary for the same agency, unless the code is itself a primary or a
# hand-built agency's ORI.
member_map <- wapo_oris |>
  filter(ori7 != primary_ori7,
         !ori7 %in% wapo_oris$primary_ori7,
         !ori7 %in% agency_key$ori7) |>
  distinct(ori7, primary_ori7) |>
  group_by(ori7) |>
  filter(n_distinct(primary_ori7) == 1) |>
  ungroup() |>
  transmute(ori7, member_of = primary_ori7)
stopifnot(!any(aliases$ori7 %in% member_map$ori7))

# 3d. One row per death x ORI --------------------------------------------------
death_ori <- agency_parts |>
  left_join(aliases |> select(ori7, alias_to), by = "ori7") |>
  left_join(member_map, by = "ori7") |>
  mutate(ori_source = case_when(!is.na(alias_to) ~ paste0(ori_source, "+alias"),
                                !is.na(member_of) ~ paste0(ori_source, "+wapo_member"),
                                TRUE ~ ori_source),
         ori7 = coalesce(alias_to, member_of, ori7)) |>
  filter(!is.na(ori7)) |>
  # One death, one ORI: an agency listed twice still counts once
  distinct(death_id, year, ori7, .keep_all = TRUE) |>
  mutate(multi = n_listed > 1)

ori_resolution <- agency_parts |>
  left_join(aliases |> select(ori7, alias_to), by = "ori7") |>
  left_join(member_map, by = "ori7") |>
  count(ori_source, aliased = !is.na(alias_to), wapo_member = !is.na(member_of),
        paired, name = "agency_mentions")

unresolved <- agency_parts |>
  filter(ori_source == "unresolved") |>
  count(state, agency, paired, name = "deaths", sort = TRUE)

counts <- death_ori |>
  group_by(ori7, year) |>
  summarise(n_mpv = n(), n_mpv_offduty = sum(offduty), n_mpv_multi = sum(multi),
            .groups = "drop")

mpv_agency_year <- expand_grid(ori7 = unique(death_ori$ori7), year = mpv_years) |>
  left_join(counts, by = c("ori7", "year")) |>
  mutate(across(c(n_mpv, n_mpv_offduty, n_mpv_multi), \(x) replace_na(x, 0L)))

# Name and state per ORI: names from single-agency deaths only, where the
# name-to-ORI pairing is unambiguous
mpv_agencies <- death_ori |>
  filter(!multi, !is.na(agency)) |>
  count(ori7, mpv_name = agency, sort = TRUE) |>
  distinct(ori7, .keep_all = TRUE) |>
  select(-n) |>
  right_join(tibble(ori7 = unique(death_ori$ori7)), by = "ori7") |>
  mutate(mpv_state = ori_state(ori7))

# Conservation, anchored to the raw snapshot
linked_ids <- unique(death_ori$death_id)
deaths_by_year <- gunshot |> count(year, name = "raw")
linked_by_year <- death_ori |> distinct(death_id, year) |> count(year, name = "linked")
year_check <- deaths_by_year |> left_join(linked_by_year, by = "year")
stopifnot(
  !anyDuplicated(mpv_agency_year[c("ori7", "year")]),
  # every raw gunshot death is either linked or counted as unlinked
  all(linked_ids %in% gunshot$death_id),
  # no death lands in a year other than its own
  all(replace_na(year_check$linked, 0L) <= year_check$raw),
  sum(linked_by_year$linked) == length(linked_ids),
  # every death x ORI pair lands in exactly one cell
  sum(mpv_agency_year$n_mpv) == nrow(distinct(death_ori, death_id, ori7)),
  all(mpv_agency_year$n_mpv_offduty <= mpv_agency_year$n_mpv),
  all(mpv_agency_year$n_mpv_multi <= mpv_agency_year$n_mpv),
  # off-duty deaths: each linked off-duty death counted once per ORI it links to
  sum(mpv_agency_year$n_mpv_offduty) == sum(death_ori$offduty),
  !anyDuplicated(mpv_agencies$ori7)
)

# 4. Linkage accounting --------------------------------------------------------
mpv_linkage <- tibble(
  measure = c("Snapshot", "Last incident in snapshot", "Years kept",
              "Gunshot deaths in years kept",
              "  off-duty",
              "  with no ORI recoverable (not linked)",
              "Deaths linked to >= 1 ORI",
              "Agency-death links (multi-agency deaths count per agency)",
              "Agency mentions with no ORI recoverable (incl. on linked deaths)",
              "  of which on deaths with unequal name/ORI lists",
              "ORI aliases applied (from shared deaths)",
              "ORIs mapped to their WaPo agency's primary ORI",
              "ORI7 agencies"),
  value = c(snap$file, as.character(last_incident),
            paste(range(mpv_years), collapse = "-"),
            nrow(gunshot), sum(gunshot$offduty),
            nrow(gunshot) - length(linked_ids),
            length(linked_ids), nrow(death_ori),
            sum(unresolved$deaths), sum(unresolved$deaths[!unresolved$paired]),
            nrow(aliases), sum(member_map$ori7 %in% agency_parts$ori7),
            n_distinct(death_ori$ori7))
)

# 5. Export --------------------------------------------------------------------
write_csv(mpv_agency_year, here("data", "clean", "mpv_agency_year.csv"))
write_csv(mpv_agencies, here("data", "clean", "mpv_agencies.csv"), na = "")
write_csv(aliases, here("data", "clean", "mpv_ori_aliases.csv"), na = "")
write_csv(mpv_linkage, here("output", "tables", "mpv_linkage.csv"))
write_csv(ori_resolution, here("output", "tables", "mpv_ori_resolution.csv"))
write_csv(unresolved, here("output", "tables", "mpv_unresolved.csv"), na = "")
write_csv(alias_candidates |> mutate(share = round(share, 3)),
          here("output", "tables", "mpv_alias_candidates.csv"), na = "")
message("04b: ", snap$file, "; ", nrow(gunshot), " gunshot deaths ",
        paste(range(mpv_years), collapse = "-"), " (", sum(gunshot$offduty),
        " off-duty); ", length(linked_ids), " linked to ",
        n_distinct(death_ori$ori7), " ORI7s; ", nrow(aliases), " aliases")
