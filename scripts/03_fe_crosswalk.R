# ==============================================================================
# Agency-level fatal OIS: Fatal Encounters agency-name -> ORI7 crosswalk
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Matching rules and seed crosswalk from a related project
#           (Brady & Nix, in progress; seed hand-checked Nov 2026)
#
# Purpose:
#   FE identifies agencies only by free-text name + state. This script rebuilds
#   the FE name -> ORI7 crosswalk from scratch on every run for the repo's
#   target agencies: the hand-built key (tier 1) plus every other ORI-coded
#   WaPo agency (tier 2). Matches come from three auditable layers, in order
#   of precedence:
#     1. manual: hand-coded accept / reject / none_found rows in
#        data/crosswalks/fe_crosswalk_decisions.csv
#     2. seed_reviewed: pairs hand-checked for the Brady & Nix LEMAS paper
#     3. exact: normalized name + state + agency type, accepted only when the
#        FE name matches exactly one agency among ALL known agencies (every
#        LEAIC agency and every WaPo agency), not just among targets
#   Looser "variant key" matches and ambiguous exact matches are never
#   accepted automatically; they go to output/fe_review/ for a person to
#   resolve in the decisions file.
#
# Inputs:
#   - data/raw/fatal_encounters.csv               -- FE final release (through 2021)
#   - data/raw/35158-0001-Data.rda                -- LEAIC 2012 (ICPSR 35158)
#   - data/agency_key.csv
#   - data/clean/wapo_agencies.csv, wapo_agency_oris.csv -- from 02_wapo.R
#   - data/crosswalks/fe_agency_crosswalk_seed.csv
#   - data/crosswalks/fe_crosswalk_decisions.csv
#
# Outputs:
#   - data/clean/fe_agency_crosswalk.csv           -- resolved crosswalk
#   - output/fe_review/fe_match_candidates.csv     -- unresolved candidates
#   - output/fe_review/fe_tier1_unresolved.csv     -- key agencies w/o FE match
#   - output/fe_review/fe_layer_conflicts.csv      -- names the layers disagree on
#
# Runtime: < 30 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

review_dir <- here("output", "fe_review")
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Load ----------------------------------------------------------------------
fe_qual <- load_fe_qualifying()

load(here("data", "raw", "35158-0001-Data.rda"))  # -> da35158.0001
leaic <- as_tibble(da35158.0001) |>
  mutate(across(where(is.factor), \(x) str_squish(as.character(x))),
         ori7 = if_else(ORI7 == "-1", to_ori7(ORI9), ORI7)) |>
  filter(!is.na(ori7))

chr <- cols(.default = col_character())
agency_key    <- read_csv(here("data", "agency_key.csv"), col_types = chr)
wapo_agencies <- read_csv(here("data", "clean", "wapo_agencies.csv"), col_types = chr)
wapo_ori_map  <- read_csv(here("data", "clean", "wapo_agency_oris.csv"), col_types = chr) |>
  distinct(ori7, .keep_all = TRUE)
seed      <- read_csv(here("data", "crosswalks", "fe_agency_crosswalk_seed.csv"), col_types = chr)
decisions <- read_csv(here("data", "crosswalks", "fe_crosswalk_decisions.csv"), col_types = chr)

# 2. FE agency names (qualifying deaths only) ----------------------------------
fe_names <- split_fe_agencies(fe_qual) |>
  count(state, fe_agency_name, name = "fe_incidents") |>
  mutate(norm = normalize_name(fe_agency_name),
         vkey = variant_key(fe_agency_name),
         type = classify_agency_type(fe_agency_name))

# 3. Target agencies and every name we know them by ----------------------------
# State comes from the ORI everywhere so key, WaPo, and LEAIC names agree
target_tier <- bind_rows(
  agency_key |> filter(!is.na(ori7)) |> transmute(ori7, tier = 1L),
  wapo_agencies |> transmute(ori7, tier = 2L)
) |>
  group_by(ori7) |>
  summarise(tier = min(tier), .groups = "drop") |>
  mutate(state = ori_state(ori7))

add_keys <- function(df) {
  df |>
    mutate(state = ori_state(ori7),
           norm = normalize_name(target_name),
           vkey = variant_key(target_name),
           type = classify_agency_type(target_name)) |>
    distinct()
}

# Every name for every agency we know of: the universe for ambiguity checks
universe_names <- bind_rows(
  agency_key |> filter(!is.na(ori7)) |> transmute(ori7, target_name = agency_name),
  wapo_agencies |> transmute(ori7, target_name = wapo_name) |>
    separate_longer_delim(target_name, " | "),
  leaic |> transmute(ori7, target_name = NAME)
) |>
  add_keys()

target_names <- universe_names |> filter(ori7 %in% target_tier$ori7)

# 4. Hand decisions: validate before use ---------------------------------------
stopifnot(all(decisions$decision %in% c("accept", "reject", "none_found")))
accepts    <- decisions |> filter(decision == "accept")
rejects    <- decisions |> filter(decision == "reject")
none_found <- decisions |> filter(decision == "none_found")

pair <- c("ori7", "state", "fe_agency_name")
bad <- list(
  `none_found ORI is not a target agency` =
    none_found |> filter(!ori7 %in% target_tier$ori7),
  `accept/reject ORI is not a target agency` =
    bind_rows(accepts, rejects) |> filter(!ori7 %in% target_tier$ori7),
  `accept/reject names no qualifying FE agency (typo?)` =
    bind_rows(accepts, rejects) |> anti_join(fe_names, by = c("state", "fe_agency_name")),
  `same pair both accepted and rejected` =
    inner_join(accepts, rejects, by = pair),
  `duplicate decision rows` =
    decisions |> filter(duplicated(pick(all_of(pair))))
)
bad <- keep(bad, \(d) nrow(d) > 0)
if (length(bad) > 0) {
  stop("Problems in fe_crosswalk_decisions.csv:\n",
       paste0("  ", names(bad), ": ",
              map_chr(bad, \(d) paste(d$ori7, d$fe_agency_name, collapse = "; ")),
              collapse = "\n"))
}

# 5. Layers --------------------------------------------------------------------
layer_manual <- accepts |>
  transmute(ori7, state, fe_agency_name, match_method = "manual", note)

seed_all <- seed |>
  transmute(ori7 = to_ori7(agency_id), state = toupper(state), fe_agency_name,
            match_method = "seed_reviewed", note)
layer_seed <- seed_all |> filter(ori7 %in% target_tier$ori7)
n_seed_dropped <- nrow(seed_all) - nrow(layer_seed)  # agencies outside the repo

# Exact: unique among targets AND among every known agency in the state
exact_target <- fe_names |>
  inner_join(target_names |> distinct(ori7, state, norm, type),
             by = c("state", "norm", "type"), relationship = "many-to-many")

# The LEAIC lists reporting sub-units under the parent's name (Atlanta PD is
# GAAPD00/30/40/41; a state police agency has one ORI per troop), so ambiguity
# is counted over distinct *agencies*, not ORIs: ORIs one WaPo agency lists
# together are one agency, and otherwise ORIs sharing their first five
# characters (state + county or agency code) are one agency. Two same-named
# agencies in different counties still count as ambiguous.
prefix5 <- function(x) str_sub(x, 1, 5)
# Every prefix that appears in a WaPo agency's ORI list points to that
# agency's primary prefix, so both rules resolve to one shared key
prefix_canon <- wapo_ori_map |>
  transmute(prefix = prefix5(ori7), canon = prefix5(primary_ori7)) |>
  distinct(prefix, .keep_all = TRUE)
canonical_agency <- function(ori7) {
  p <- prefix5(ori7)
  coalesce(prefix_canon$canon[match(p, prefix_canon$prefix)], p)
}

universe_hits <- fe_names |>
  inner_join(universe_names |> distinct(ori7, state, norm, type),
             by = c("state", "norm", "type"), relationship = "many-to-many") |>
  mutate(agency = canonical_agency(ori7)) |>
  group_by(state, fe_agency_name) |>
  summarise(n_universe = n_distinct(agency),
            universe_oris = paste(sort(unique(ori7)), collapse = ";"),
            .groups = "drop")

exact_scored <- exact_target |>
  distinct(ori7, state, fe_agency_name, fe_incidents) |>
  left_join(universe_hits, by = c("state", "fe_agency_name"))

layer_exact <- exact_scored |>
  filter(n_universe == 1) |>
  transmute(ori7, state, fe_agency_name, match_method = "exact", note = NA_character_)

ambiguous <- exact_scored |> filter(n_universe > 1)

# 6. Resolve -------------------------------------------------------------------
all_layers <- bind_rows(layer_manual, layer_seed, layer_exact) |>
  anti_join(rejects, by = pair)

# Names the layers send to different ORIs; precedence (manual > seed > exact)
# decides, but every disagreement is reported for a person to look at
layer_conflicts <- all_layers |>
  group_by(state, fe_agency_name) |>
  filter(n_distinct(ori7) > 1) |>
  ungroup() |>
  arrange(state, fe_agency_name, match_method)

crosswalk <- all_layers |>
  distinct(state, fe_agency_name, .keep_all = TRUE) |>   # first = highest precedence
  left_join(fe_names |> select(state, fe_agency_name, fe_incidents),
            by = c("state", "fe_agency_name")) |>
  left_join(target_tier |> select(ori7, tier), by = "ori7") |>
  arrange(ori7, desc(fe_incidents))

missing_names <- crosswalk |> filter(is.na(fe_incidents))
if (nrow(missing_names) > 0) {
  stop("Seed names not found among qualifying FE deaths: ",
       paste(missing_names$state, missing_names$fe_agency_name, collapse = "; "))
}
stopifnot(
  all(crosswalk$ori7 %in% target_tier$ori7),
  !any(none_found$ori7 %in% crosswalk$ori7),
  # each accepted decision survived resolution
  nrow(semi_join(accepts, crosswalk, by = pair)) == nrow(accepts)
)

# 7. Review files --------------------------------------------------------------
matched_names <- crosswalk |> select(state, fe_agency_name)

variant_cands <- fe_names |>
  anti_join(matched_names, by = c("state", "fe_agency_name")) |>
  inner_join(target_names |> distinct(ori7, state, vkey, type, target_name),
             by = c("state", "vkey", "type"), relationship = "many-to-many") |>
  filter(vkey != "") |>
  mutate(reason = "variant_key")

ambiguous_cands <- ambiguous |>
  anti_join(matched_names, by = c("state", "fe_agency_name")) |>
  left_join(target_names |> distinct(ori7, target_name), by = "ori7",
            relationship = "many-to-many") |>
  mutate(reason = paste0("ambiguous_exact (", universe_oris, ")"))

candidates <- bind_rows(ambiguous_cands, variant_cands) |>
  anti_join(decisions, by = pair) |>
  group_by(ori7, state, fe_agency_name, fe_incidents, reason) |>
  summarise(target_names = paste(unique(target_name), collapse = " | "), .groups = "drop") |>
  left_join(target_tier |> select(ori7, tier), by = "ori7") |>
  arrange(tier, desc(fe_incidents))

tier1_unresolved <- agency_key |>
  filter(!is.na(ori7), !ori7 %in% crosswalk$ori7, !ori7 %in% none_found$ori7) |>
  select(slug, ori7, agency_name, state, agency_type) |>
  mutate(has_candidate = ori7 %in% candidates$ori7)

# 8. Export --------------------------------------------------------------------
write_csv(crosswalk, here("data", "clean", "fe_agency_crosswalk.csv"), na = "")
write_csv(candidates, file.path(review_dir, "fe_match_candidates.csv"), na = "")
write_csv(tier1_unresolved, file.path(review_dir, "fe_tier1_unresolved.csv"), na = "")
write_csv(layer_conflicts, file.path(review_dir, "fe_layer_conflicts.csv"), na = "")

method_counts <- count(crosswalk, match_method)
message("03: ", nrow(crosswalk), " FE names -> ", n_distinct(crosswalk$ori7), " ORI7s (",
        paste(method_counts$match_method, method_counts$n, sep = "=", collapse = ", "),
        "); ", n_seed_dropped, " seed rows outside the repo's agencies; ",
        nrow(layer_conflicts), " layer-conflict rows; ", nrow(candidates),
        " candidates and ", nrow(tier1_unresolved), " key agencies to review")
