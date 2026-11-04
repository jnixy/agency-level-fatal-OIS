# ==============================================================================
# Agency-level fatal OIS: combine the three sources into one panel
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Join the hand-built, WaPo, and FE agency-year series side by side. No
#   source is used to fill another's gaps. Each column is NA wherever its
#   source has no data for that agency-year:
#     n_nix  NA = no hand-built data for that agency-year
#     n_wapo 0 for every ORI-coded agency 2015-2024 (WaPo is a national census)
#     n_fe   0/count 2000-2021 for linked agencies, NA where never linked
#   The panel is deliberately unbalanced: an agency has rows only for years
#   some source covers. A missing row means no source, not zero deaths.
#   Also writes source-agreement and coverage tables.
#
# Inputs:
#   - data/agency_key.csv
#   - data/clean/{nix,wapo,fe}_agency_year.csv, data/clean/wapo_agencies.csv
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

meta <- bind_rows(key_meta, wapo_meta) |>
  left_join(wapo_agencies |> select(ori7, wapo_multi_ori), by = "ori7") |>
  mutate(in_nix = !is.na(slugs),
         wapo_multi_ori = replace_na(as.logical(wapo_multi_ori), FALSE))

stopifnot(
  !anyDuplicated(meta$agency_id),
  all(meta$state %in% c(state.abb, "DC", "PR", "GU", "VI"))
)

# 3. Panel ---------------------------------------------------------------------
# WaPo zero rows for every ORI-coded agency, so hand-built agencies WaPo never
# recorded still show n_wapo = 0 in 2015-2024
wapo_full <- expand_grid(agency_id = meta$agency_id[!is.na(meta$ori7)],
                         year = wapo_years) |>
  left_join(wapo |> rename(agency_id = ori7), by = c("agency_id", "year")) |>
  mutate(n_wapo = replace_na(n_wapo, 0L))

joined <- nix |> select(agency_id, year, n_nix, nix_partial) |>
  full_join(wapo_full, by = c("agency_id", "year")) |>
  full_join(fe |> rename(agency_id = ori7), by = c("agency_id", "year"))

# Every agency-year must have metadata; an inner join would drop it silently
orphans <- anti_join(joined, meta, by = "agency_id")
if (nrow(orphans) > 0) {
  stop("Agency-years with no metadata: ",
       paste(unique(orphans$agency_id), collapse = ", "))
}

panel <- joined |>
  inner_join(meta, by = "agency_id") |>
  select(agency_id, ori7, agency_name, state, agency_type, in_nix, slugs,
         wapo_multi_ori, year, n_nix, nix_partial, n_wapo, n_fe, n_fe_multi, n_fe_flagged) |>
  arrange(state, agency_name, year)

stopifnot(
  !anyDuplicated(panel[c("agency_id", "year")]),
  nrow(panel) == nrow(joined),
  # nothing lost in the joins
  sum(panel$n_nix, na.rm = TRUE) == sum(nix$n_nix),
  sum(panel$n_wapo, na.rm = TRUE) == sum(wapo$n_wapo),
  sum(panel$n_fe, na.rm = TRUE) == sum(fe$n_fe)
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

comparable <- panel |> filter(!wapo_multi_ori)
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
  compare_sources(comparable, "n_wapo", "n_fe", "WaPo vs FE (all linked agencies)")
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
            deaths_nix = sum(n_nix, na.rm = TRUE),
            .groups = "drop")

# 5. Export --------------------------------------------------------------------
write_csv(panel, here("output", "agency_year_panel.csv"), na = "")
write_csv(agreement, here("output", "tables", "source_agreement.csv"))
write_csv(disagreements, here("output", "tables", "source_disagreements.csv"))
write_csv(coverage, here("output", "tables", "coverage_by_year.csv"))
message("05: panel has ", n_distinct(panel$agency_id), " agencies, ",
        nrow(panel), " agency-years (", sum(!is.na(panel$n_nix)), " hand-built, ",
        sum(!is.na(panel$n_wapo)), " WaPo, ", sum(!is.na(panel$n_fe)), " FE)")
