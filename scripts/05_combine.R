# ==============================================================================
# Agency-level fatal OIS: combine the four sources into one panel
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Join the hand-built, WaPo, FE, and MPV agency-year series side by side. No
#   source is used to fill another's gaps. Each column is NA wherever its
#   source has no data for that agency-year:
#     n_nix  NA = no hand-built data for that agency-year
#     n_wapo 0 for every ORI-coded agency 2015-2024 (WaPo is a national census)
#     n_fe   0/count 2000-2021 for linked agencies, NA where never linked
#     n_mpv  0 for every ORI-coded agency, 2013 to the snapshot's last complete
#            year (MPV is a national census; includes off-duty, see n_mpv_offduty)
#     n_shr  FBI SHR, 1976-2024: 0/count where the agency filed any SHR record
#            that year, NA where it filed none. Only agencies already in the
#            panel (SHR adds years, not agencies)
#   The panel is deliberately unbalanced: an agency has rows only for years
#   some source covers. A missing row means no source, not zero deaths.
#   Also writes source-agreement and coverage tables.
#
# Inputs:
#   - data/agency_key.csv
#   - data/clean/{nix,wapo,fe,mpv,shr}_agency_year.csv
#   - data/clean/wapo_agencies.csv, data/clean/mpv_agencies.csv
#
# Outputs:
#   - output/agency_year_panel.csv           -- the published merged file
#   - output/tables/source_agreement.csv     -- pairwise agreement on overlap
#   - output/tables/source_disagreements.csv -- largest agency-level gaps
#   - output/tables/coverage_by_year.csv     -- agencies with data, by source
#
# Runtime: < 10 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

wapo_years <- 2015:2024
chr <- cols(.default = col_character())

# 1. Load ----------------------------------------------------------------------
agency_key <- read_csv(here("data", "agency_key.csv"), col_types = chr)
nix  <- read_csv(here("data", "clean", "nix_agency_year.csv"),
                 col_types = cols(year = "i", n_nix = "d", nix_partial = "l", .default = "c"))
wapo <- read_csv(here("data", "clean", "wapo_agency_year.csv"),
                 col_types = cols(year = "i", n_wapo = "i", .default = "c"))
fe   <- read_csv(here("data", "clean", "fe_agency_year.csv"),
                 col_types = cols(year = "i", n_fe = "i", n_fe_multi = "i", n_fe_flagged = "i", .default = "c"))
wapo_agencies <- read_csv(here("data", "clean", "wapo_agencies.csv"), col_types = chr)
mpv  <- read_csv(here("data", "clean", "mpv_agency_year.csv"),
                 col_types = cols(year = "i", n_mpv = "i", n_mpv_offduty = "i",
                                  n_mpv_multi = "i", .default = "c"))
mpv_agencies <- read_csv(here("data", "clean", "mpv_agencies.csv"), col_types = chr)
mpv_years <- sort(unique(mpv$year))
shr  <- read_csv(here("data", "clean", "shr_agency_year.csv"),
                 col_types = cols(year = "i", n_shr = "i", .default = "c"))

# 2. Agency metadata (one row per agency_id) -----------------------------------
key_meta <- agency_key |>
  mutate(agency_id = coalesce(ori7, slug)) |>
  group_by(agency_id) |>
  summarise(ori7 = first(ori7),
            agency_name = paste(unique(agency_name), collapse = " / "),
            state = first(state), agency_type = first(agency_type),
            slugs = paste(sort(slug), collapse = ";"),
            .groups = "drop")

wapo_meta <- wapo_agencies |>
  filter(!ori7 %in% key_meta$ori7) |>
  transmute(agency_id = ori7, ori7,
            agency_name = str_remove(wapo_name, " \\|.*$"),
            state = wapo_state, agency_type = wapo_type, slugs = NA_character_)

# Agencies only MPV has recorded (e.g., killings since WaPo ended)
mpv_meta <- mpv_agencies |>
  filter(!ori7 %in% c(key_meta$ori7, wapo_meta$ori7)) |>
  transmute(agency_id = ori7, ori7, agency_name = coalesce(mpv_name, ori7),
            state = mpv_state, agency_type = NA_character_, slugs = NA_character_)

meta <- bind_rows(key_meta, wapo_meta, mpv_meta) |>
  left_join(wapo_agencies |> select(ori7, wapo_multi_ori), by = "ori7") |>
  mutate(in_nix = !is.na(slugs),
         wapo_multi_ori = replace_na(as.logical(wapo_multi_ori), FALSE))

stopifnot(
  !anyDuplicated(meta$agency_id),
  all(meta$state %in% c(state.abb, "DC", "PR", "GU", "VI"))
)

# 3. Panel ---------------------------------------------------------------------
# WaPo zero rows for every hand-built or WaPo-coded agency, so hand-built
# agencies WaPo never recorded still show n_wapo = 0 in 2015-2024. Agencies
# known only from MPV get NA, not 0: WaPo having no agency with that ORI can
# mean a coding difference (secondary agency, unmatched alias) rather than
# no deaths.
wapo_full <- expand_grid(agency_id = meta$agency_id[!is.na(meta$ori7) &
                                                      !meta$agency_id %in% mpv_meta$agency_id],
                         year = wapo_years) |>
  left_join(wapo |> rename(agency_id = ori7), by = c("agency_id", "year")) |>
  mutate(n_wapo = replace_na(n_wapo, 0L))

# Same logic for MPV over its complete years
mpv_full <- expand_grid(agency_id = meta$agency_id[!is.na(meta$ori7)],
                        year = mpv_years) |>
  left_join(mpv |> rename(agency_id = ori7), by = c("agency_id", "year")) |>
  mutate(across(c(n_mpv, n_mpv_offduty, n_mpv_multi), \(x) replace_na(x, 0L)))

# SHR covers every reporting agency in the country; keep only agencies the
# panel already has, so SHR extends their years without adding agencies
shr_in_panel <- shr |>
  filter(ori7 %in% meta$ori7) |>
  rename(agency_id = ori7)

joined <- nix |> select(agency_id, year, n_nix, nix_partial) |>
  full_join(wapo_full, by = c("agency_id", "year")) |>
  full_join(fe |> rename(agency_id = ori7), by = c("agency_id", "year")) |>
  full_join(mpv_full, by = c("agency_id", "year")) |>
  full_join(shr_in_panel, by = c("agency_id", "year"))

# Every agency-year must have metadata; an inner join would drop it silently
orphans <- anti_join(joined, meta, by = "agency_id")
if (nrow(orphans) > 0) {
  stop("Agency-years with no metadata: ",
       paste(unique(orphans$agency_id), collapse = ", "))
}

panel <- joined |>
  inner_join(meta, by = "agency_id") |>
  select(agency_id, ori7, agency_name, state, agency_type, in_nix, slugs,
         wapo_multi_ori, year, n_nix, nix_partial, n_wapo, n_fe, n_fe_multi, n_fe_flagged,
         n_mpv, n_mpv_offduty, n_mpv_multi, n_shr) |>
  arrange(state, agency_name, year)

stopifnot(
  !anyDuplicated(panel[c("agency_id", "year")]),
  nrow(panel) == nrow(joined),
  # nothing lost in the joins
  sum(panel$n_nix, na.rm = TRUE) == sum(nix$n_nix),
  sum(panel$n_wapo, na.rm = TRUE) == sum(wapo$n_wapo),
  sum(panel$n_fe, na.rm = TRUE) == sum(fe$n_fe),
  sum(panel$n_mpv, na.rm = TRUE) == sum(mpv$n_mpv),
  sum(panel$n_shr, na.rm = TRUE) == sum(shr_in_panel$n_shr)
)

# 4. Agreement on overlapping agency-years -------------------------------------
# Most agency-years are 0 in both sources, which inflates raw agreement, so
# agreement is also reported on agency-years where at least one source > 0.
# WaPo multi-ORI agencies are left out of every comparison: their deaths sit on
# one primary ORI, so they aren't comparable to per-ORI counts.
compare_sources <- function(df, a, b, label) {
  d <- df |> filter(!is.na(.data[[a]]), !is.na(.data[[b]]))
  nz <- d |> filter(.data[[a]] + .data[[b]] > 0)
  safe_cor <- function(x, y) {
    if (length(x) < 3 || sd(x) == 0 || sd(y) == 0) NA_real_ else cor(x, y)
  }
  tibble(comparison = label,
         years = if (nrow(d) > 0) paste(range(d$year), collapse = "-") else NA_character_,
         agencies = n_distinct(d$agency_id),
         agency_years = nrow(d),
         total_a = sum(d[[a]]), total_b = sum(d[[b]]),
         pct_diff_total = 100 * (total_b - total_a) / total_a,
         correlation = safe_cor(d[[a]], d[[b]]),
         mean_abs_diff = mean(abs(d[[a]] - d[[b]])),
         share_exact = mean(d[[a]] == d[[b]]),
         agency_years_nonzero = nrow(nz),
         share_exact_nonzero = mean(nz[[a]] == nz[[b]]))
}

# n_mpv_onduty matches the hand-built definition (people shot by on-duty officers)
comparable <- panel |> filter(!wapo_multi_ori) |>
  mutate(n_mpv_onduty = n_mpv - n_mpv_offduty)
nix_panel  <- comparable |> filter(in_nix)
# Common support: all three sources observed (2015-2021)
common     <- nix_panel |> filter(!is.na(n_nix), !is.na(n_wapo), !is.na(n_fe))

agreement <- bind_rows(
  compare_sources(nix_panel, "n_nix", "n_wapo", "Hand-built vs WaPo"),
  compare_sources(nix_panel, "n_nix", "n_fe",   "Hand-built vs FE"),
  compare_sources(nix_panel, "n_wapo", "n_fe",  "WaPo vs FE (hand-built agencies)"),
  compare_sources(common, "n_nix", "n_wapo", "Hand-built vs WaPo (common support)"),
  compare_sources(common, "n_nix", "n_fe",   "Hand-built vs FE (common support)"),
  compare_sources(common, "n_wapo", "n_fe",  "WaPo vs FE (common support)"),
  compare_sources(comparable, "n_wapo", "n_fe", "WaPo vs FE (all linked agencies)"),
  compare_sources(nix_panel, "n_nix", "n_mpv_onduty", "Hand-built vs MPV on-duty"),
  compare_sources(nix_panel, "n_nix", "n_mpv", "Hand-built vs MPV (incl. off-duty)"),
  compare_sources(comparable, "n_wapo", "n_mpv", "WaPo vs MPV (all agencies)"),
  compare_sources(comparable, "n_fe", "n_mpv", "FE vs MPV (all linked agencies)"),
  compare_sources(nix_panel, "n_nix", "n_shr", "Hand-built vs SHR"),
  compare_sources(comparable, "n_wapo", "n_shr", "WaPo vs SHR (all agencies)"),
  compare_sources(comparable, "n_fe", "n_shr", "FE vs SHR (all linked agencies)"),
  compare_sources(comparable, "n_mpv_onduty", "n_shr", "MPV on-duty vs SHR (all agencies)")
) |>
  mutate(across(where(is.double), \(x) round(x, 3)))

# Agency-level totals over each pair's overlap, largest gaps first
disagreements <- bind_rows(
  nix_panel |> filter(!is.na(n_nix), !is.na(n_wapo)) |>
    group_by(agency_id, agency_name, state) |>
    summarise(pair = "nix_vs_wapo", years = paste(range(year), collapse = "-"),
              a = sum(n_nix), b = sum(n_wapo), .groups = "drop"),
  comparable |> filter(!is.na(n_fe), !is.na(n_wapo)) |>
    group_by(agency_id, agency_name, state) |>
    summarise(pair = "fe_vs_wapo", years = paste(range(year), collapse = "-"),
              a = sum(n_fe), b = sum(n_wapo), .groups = "drop")
) |>
  mutate(diff = a - b) |>
  filter(diff != 0) |>
  arrange(pair, desc(abs(diff)))

coverage <- panel |>
  group_by(year) |>
  summarise(agencies_nix = sum(!is.na(n_nix)),
            agencies_wapo = sum(!is.na(n_wapo)),
            agencies_fe = sum(!is.na(n_fe)),
            agencies_mpv = sum(!is.na(n_mpv)),
            agencies_shr = sum(!is.na(n_shr)),
            deaths_nix = sum(n_nix, na.rm = TRUE),
            .groups = "drop")

# 5. Export --------------------------------------------------------------------
write_csv(panel, here("output", "agency_year_panel.csv"), na = "")
write_csv(agreement, here("output", "tables", "source_agreement.csv"))
write_csv(disagreements, here("output", "tables", "source_disagreements.csv"))
write_csv(coverage, here("output", "tables", "coverage_by_year.csv"))
message("05: panel has ", n_distinct(panel$agency_id), " agencies, ",
        nrow(panel), " agency-years (", sum(!is.na(panel$n_nix)), " hand-built, ",
        sum(!is.na(panel$n_wapo)), " WaPo, ", sum(!is.na(panel$n_fe)), " FE, ",
        sum(!is.na(panel$n_mpv)), " MPV, ", sum(!is.na(panel$n_shr)), " SHR)")
