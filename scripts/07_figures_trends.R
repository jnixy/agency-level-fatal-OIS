# ==============================================================================
# Agency-level fatal OIS: long-run trend figures for the README
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Three figures that show what the hand-built series can do.
#   (1) A within-agency trend index. A Poisson model with agency fixed effects
#       compares each agency only to itself, so agencies entering or leaving
#       the sample don't move the trend (the flaw in the 2025 blog figure,
#       which averaged across a changing set of agencies). The headline
#       comparison comes from a separate era model fit to one fixed set of
#       agencies observed in both eras.
#   (2) Then vs. now: average deaths per year before 1995 and since 2015 for
#       the same fixed set of agencies.
#   (3) Coverage: which agency-years the hand-built data cover, and the share
#       of WaPo deaths (2015-2024) involving one of these agencies.
#   Hand-built series end in 2022; 2023-2024 are filled with WaPo counts for
#   agencies whose hand-built series runs into 2021-2022 (drawn lighter).
#
# Inputs:
#   - output/agency_year_panel.csv                 -- from 05_combine.R
#   - output/tables/source_agreement.csv           -- from 05_combine.R
#   - data/raw/wapo/fatal-police-shootings-data.csv
#   - data/clean/wapo_agency_oris.csv              -- from 02_wapo.R
#
# Outputs:
#   - output/figures/trend_index.png, then_vs_now.png, coverage_tiles.png
#   - output/tables/trend_index.csv, then_vs_now.csv, coverage_share.csv,
#     trend_summary.csv (every number quoted in the README)
#   - output/trend_models.rds                      -- fitted fixest models
#
# Runtime: < 30 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
library(fixest)
library(patchwork)
source(here("scripts", "functions.R"))

fig_dir <- here("output", "figures")
tab_dir <- here("output", "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

REF_YEAR      <- 2015L
FIRST_YEAR    <- 1970L         # 1969 is Chicago alone
LAST_NIX      <- 2022L         # last year of hand-built data
SPLICE_YEARS  <- 2023:2024
EARLY_ERA     <- 1970:1994
RECENT_ERA    <- 2015:2024
MIN_ERA_YEARS <- 5L            # years of data required in each era
WAPO_YEARS    <- 2015:2024
CHECK_WINDOW  <- 1980:1991     # balanced window used to verify the index math
INDEX_BREAKS  <- c(25, 50, 100, 200, 400, 800)

# Series that aren't person-level fatal shootings (see README caveats)
TREND_EXCLUSIONS <- tribble(
  ~agency_id, ~first, ~last, ~reason,
  "OHCIP00",  -Inf,   2014,  "Cincinnati before 2015: fatal and nonfatal shootings mixed",
  "NV00201",  -Inf,   Inf,   "LVMPD: hand-built figures mix fatal and nonfatal shootings",
  "TX22701",  2000,   2007,  "Austin 2000-07: may count incidents rather than people"
)

# 1. Load ----------------------------------------------------------------------
panel <- read_csv(here("output", "agency_year_panel.csv"), show_col_types = FALSE)
agreement <- read_csv(here("output", "tables", "source_agreement.csv"), show_col_types = FALSE)

# 2. Trend series ----------------------------------------------------------------
nix_agencies <- panel |> filter(in_nix)

# Splice WaPo only onto series still running at the end of the hand-built
# data, so 2023-24 extend a series rather than revive one
splice_ok <- nix_agencies |>
  filter(year %in% (LAST_NIX - 1):LAST_NIX, !is.na(n_nix)) |>
  distinct(agency_id)

trend <- nix_agencies |>
  # A year where only one of an agency's two slugs has data would undercount
  filter(!(nix_partial %in% TRUE)) |>
  mutate(spliced = year %in% SPLICE_YEARS & agency_id %in% splice_ok$agency_id,
         y = case_when(year <= LAST_NIX ~ n_nix,
                       spliced ~ as.numeric(n_wapo),
                       TRUE ~ NA_real_)) |>
  left_join(TREND_EXCLUSIONS |> select(agency_id, first, last), by = "agency_id") |>
  filter(is.na(first) | !(year >= first & year <= last)) |>
  filter(!is.na(y), year >= FIRST_YEAR) |>
  select(agency_id, agency_name, state, year, y, spliced)

stopifnot(!anyDuplicated(trend[c("agency_id", "year")]))

# One fixed set of agencies for the headline comparison and Figure 2
era_of <- function(year) case_when(year %in% EARLY_ERA ~ "early",
                                   year %in% RECENT_ERA ~ "recent")
long_ids <- trend |>
  mutate(era = era_of(year)) |>
  filter(!is.na(era)) |>
  count(agency_id, era) |>
  filter(n >= MIN_ERA_YEARS) |>
  count(agency_id) |>
  filter(n == 2) |>
  select(agency_id)

# 3. Figure 1: within-agency trend index -----------------------------------------
#' Fit the year-effects index. Agencies with no deaths in any year carry no
#' information in a fixed-effects Poisson model, so they are set aside first
#' (rather than read back from fixest internals).
#' @return list(index = tibble, model, kept = data, n_dropped)
fit_index <- function(df, ref = REF_YEAR) {
  kept <- df |> group_by(agency_id) |> filter(sum(y) > 0) |> ungroup()
  # fixest parses i() arguments literally, so the reference year is spliced
  # into the formula text rather than passed as a variable
  fml <- as.formula(sprintf("y ~ i(year, ref = %d) | agency_id", as.integer(ref)))
  m <- fepois(fml, data = kept, cluster = ~agency_id, notes = FALSE)
  stopifnot(nobs(m) == nrow(kept))
  coefs <- as_tibble(coeftable(m), rownames = "term") |>
    transmute(year = as.integer(str_extract(term, "\\d{4}$")),
              est = Estimate, se = `Std. Error`)
  n_by_year <- kept |> count(year, name = "agencies")
  index <- bind_rows(coefs, tibble(year = ref, est = 0, se = 0)) |>
    left_join(n_by_year, by = "year") |>
    # Few clusters inform the early years, so use t(agencies - 1) rather than
    # z: deliberately conservative where only a handful of cities report
    mutate(crit = qt(0.975, df = pmax(agencies - 1, 1)),
           index = 100 * exp(est),
           lo = 100 * exp(est - crit * se),
           hi = 100 * exp(est + crit * se)) |>
    arrange(year)
  list(index = index, model = m, kept = kept,
       n_dropped = n_distinct(df$agency_id) - n_distinct(kept$agency_id))
}

main <- fit_index(trend)
long <- fit_index(trend |> semi_join(long_ids, by = "agency_id"))

# Headline: one model, one fixed set of agencies, one ratio with a CI
era_df <- trend |>
  semi_join(long_ids, by = "agency_id") |>
  mutate(era = era_of(year)) |>
  filter(!is.na(era))
m_era <- fepois(y ~ i(era, ref = "early") | agency_id, data = era_df,
                cluster = ~agency_id, notes = FALSE)
era_est <- coeftable(m_era)[1, ]
g_long <- n_distinct(era_df$agency_id)
era_crit <- qt(0.975, df = g_long - 1)
era_ratio <- exp(era_est[["Estimate"]])
era_ci <- exp(era_est[["Estimate"]] + c(-1, 1) * era_crit * era_est[["Std. Error"]])

# Correctness check of the index construction: on a balanced panel, Poisson
# fixed-effects year ratios equal ratios of summed counts exactly
balanced_ids <- trend |>
  filter(year %in% CHECK_WINDOW) |>
  count(agency_id) |>
  filter(n == length(CHECK_WINDOW)) |>
  select(agency_id)
balanced <- trend |> filter(year %in% CHECK_WINDOW) |> semi_join(balanced_ids, by = "agency_id")
check_fit <- fit_index(balanced, ref = min(CHECK_WINDOW))$index
raw_sums <- balanced |> group_by(year) |> summarise(total = sum(y)) |>
  mutate(raw_index = 100 * total / total[year == min(CHECK_WINDOW)])
index_check <- check_fit |> select(year, index) |> left_join(raw_sums, by = "year")
stopifnot(nrow(balanced_ids) >= 5,
          max(abs(index_check$index - index_check$raw_index)) < 1e-4)

trend_index <- main$index |>
  left_join(long$index |> select(year, index_long = index), by = "year") |>
  mutate(spliced = year %in% SPLICE_YEARS)

pre2000 <- trend_index |> filter(year < 2000)
wapo_gap <- agreement |> filter(comparison == "Hand-built vs WaPo") |> pull(pct_diff_total)

index_title <- sprintf(
  "In the same %d agencies, fatal police shootings since 2015 run %s %s their %d–%d level",
  g_long, scales::percent(abs(era_ratio - 1), accuracy = 1),
  if (era_ratio < 1) "below" else "above", min(EARLY_ERA), max(EARLY_ERA))

p_index <- ggplot(trend_index, aes(year)) +
  geom_hline(yintercept = 100, color = "grey70", linewidth = 0.4) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = source_colors[["Hand-built (Nix)"]],
              alpha = 0.18) +
  geom_line(aes(y = index_long), color = "grey25", linewidth = 0.6,
            linetype = "22", na.rm = TRUE) +
  geom_line(aes(y = index), color = source_colors[["Hand-built (Nix)"]], linewidth = 0.9) +
  geom_point(data = filter(trend_index, spliced), aes(y = index),
             color = spliced_color, size = 2.2) +
  # Direct labels in the empty upper right instead of a legend
  annotate("text", x = 1990, y = 600, hjust = 0, size = 3.1,
           color = source_colors[["Hand-built (Nix)"]],
           label = "Solid: all hand-built agencies (95% CI)") +
  annotate("text", x = 1990, y = 480, hjust = 0, size = 3.1, color = "grey25",
           label = sprintf("Dashed: the %d agencies observed in both eras", g_long)) +
  scale_y_continuous(trans = "log2", breaks = INDEX_BREAKS) +
  scale_x_continuous(breaks = seq(1970, 2020, 10), limits = c(FIRST_YEAR - 0.5, 2024.5)) +
  labs(x = NULL, y = "Fatal police shootings\n(2015 = 100, log scale)",
       title = str_wrap(index_title, 60),
       subtitle = str_wrap(sprintf(paste0(
         "Era ratio %.2f (95%% CI %.2f–%.2f), Poisson model with agency fixed effects. ",
         "Light points (%s) use WaPo counts."),
         era_ratio, era_ci[1], era_ci[2],
         paste(range(SPLICE_YEARS), collapse = "–")), 100)) +
  theme_project() +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 9))

p_n <- ggplot(trend_index, aes(year, agencies)) +
  geom_col(aes(fill = spliced), width = 0.8) +
  scale_fill_manual(values = c(`FALSE` = "grey60", `TRUE` = spliced_color), guide = "none") +
  scale_x_continuous(breaks = seq(1970, 2020, 10), limits = c(FIRST_YEAR - 0.5, 2024.5)) +
  scale_y_continuous(breaks = c(0, 150, 300)) +
  labs(x = NULL, y = "Agencies",
       caption = str_wrap(sprintf(paste0(
         "Before 2000 the index rests on %d–%d large-city agencies; CIs use t(agencies − 1). ",
         "WaPo counts run %.0f%% %s hand-built counts where both exist (2015–22). ",
         "Excludes series that mix in nonfatal shootings or count incidents."),
         min(pre2000$agencies), max(pre2000$agencies),
         abs(wapo_gap), if (wapo_gap < 0) "below" else "above"), 120)) +
  theme_project(base_size = 9) +
  theme(panel.grid.major.x = element_blank(), plot.caption = element_text(hjust = 0))

p_trend <- p_index / p_n + plot_layout(heights = c(4, 1))
ggsave(file.path(fig_dir, "trend_index.png"), p_trend,
       width = 6.5, height = 5.4, dpi = 300, bg = "white")

# 4. Figure 2: then vs. now -------------------------------------------------------
then_vs_now <- era_df |>
  group_by(agency_id, agency_name, state, era) |>
  summarise(years = n(), first = min(year), last = max(year),
            per_year = mean(y), .groups = "drop") |>
  pivot_wider(id_cols = c(agency_id, agency_name, state),
              names_from = era, values_from = c(per_year, years, first, last)) |>
  mutate(label = city_label(agency_name, state),
         change = per_year_recent - per_year_early,
         lower_now = change < 0) |>
  arrange(per_year_early)

n_lower <- sum(then_vs_now$lower_now)
n_total <- nrow(then_vs_now)
stopifnot(n_total == g_long)

dumbbell <- then_vs_now |> mutate(label = fct_inorder(label))
top_row <- slice_tail(dumbbell, n = 1)

p_then_now <- ggplot(dumbbell, aes(y = label)) +
  geom_segment(aes(x = per_year_early, xend = per_year_recent, yend = label),
               color = "grey75", linewidth = 1.2) +
  geom_point(aes(x = per_year_early), color = "grey55", size = 2.8) +
  geom_point(aes(x = per_year_recent), color = source_colors[["Hand-built (Nix)"]], size = 2.8) +
  # Direct labels on the top row instead of a legend
  geom_text(data = top_row, aes(x = per_year_early,
                                label = sprintf("%d–%d", min(EARLY_ERA), max(EARLY_ERA))),
            vjust = -1.1, size = 3, color = "grey45") +
  geom_text(data = top_row, aes(x = per_year_recent,
                                label = sprintf("%d–%d", min(RECENT_ERA), max(RECENT_ERA))),
            vjust = -1.1, size = 3, color = source_colors[["Hand-built (Nix)"]]) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.1))) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "Average people shot and killed per year", y = NULL,
       # The title reports whichever direction most agencies moved, so it
       # can't go stale if the data change
       title = if (n_lower >= n_total / 2) {
         sprintf("%d of %d long-running agencies kill fewer people a year than before 1995",
                 n_lower, n_total)
       } else {
         sprintf("%d of %d long-running agencies kill more people a year than before 1995",
                 n_total - n_lower, n_total)
       },
       subtitle = str_wrap(sprintf(paste0(
         "Agencies with at least %d years of data in both eras; years observed vary by ",
         "agency. Counts, not rates: populations changed."), MIN_ERA_YEARS), 95)) +
  theme_project() +
  theme(plot.title.position = "plot", panel.grid.major.y = element_blank(),
        plot.subtitle = element_text(size = 9.5))

ggsave(file.path(fig_dir, "then_vs_now.png"), p_then_now,
       width = 6.5, height = 1.8 + 0.28 * n_total, dpi = 300, bg = "white")

# 5. Figure 3: coverage and reach ----------------------------------------------
# Death-level share: a WaPo death counts once if any agency involved maps (via
# its primary ORI, as assigned in 02_wapo.R) to a hand-built agency. Deaths
# credited only to a non-primary ORI, and hand-built agencies without an ORI,
# can't match, so the share is a lower bound.
wapo_file <- here("data", "raw", "wapo", "fatal-police-shootings-data.csv")
check_sha256(wapo_file, WAPO_SHA256[["fatal-police-shootings-data.csv"]])
incidents <- read_csv(wapo_file, col_types = cols(.default = col_character())) |>
  filter(as.integer(str_sub(date, 1, 4)) %in% WAPO_YEARS)
wapo_primary <- read_csv(here("data", "clean", "wapo_agency_oris.csv"),
                         col_types = cols(.default = col_character())) |>
  distinct(wapo_id, primary_ori7)
stopifnot(!anyDuplicated(wapo_primary$wapo_id))
nix_oris <- nix_agencies |> filter(!is.na(ori7)) |> distinct(ori7) |> pull()

death_reach <- incidents |>
  transmute(id, wapo_id = agency_ids) |>
  separate_longer_delim(wapo_id, ";") |>
  mutate(wapo_id = str_squish(wapo_id)) |>
  left_join(wapo_primary, by = "wapo_id") |>
  group_by(id) |>
  summarise(hand_built = any(primary_ori7 %in% nix_oris), .groups = "drop")

coverage_share <- tibble(
  years = paste(range(WAPO_YEARS), collapse = "-"),
  wapo_deaths = nrow(death_reach),
  deaths_involving_hand_built = sum(death_reach$hand_built),
  share = deaths_involving_hand_built / wapo_deaths,
  hand_built_agencies = n_distinct(nix_agencies$agency_id),
  hand_built_with_ori = length(nix_oris)
)
stopifnot(coverage_share$wapo_deaths == n_distinct(incidents$id))

tiles <- nix_agencies |>
  mutate(spliced = year %in% SPLICE_YEARS & agency_id %in% splice_ok$agency_id,
         status = case_when(year <= LAST_NIX & !is.na(n_nix) ~ "Hand-built",
                            spliced ~ "Washington Post (2023–24)")) |>
  filter(!is.na(status))

# One labeled row per agency is only readable for the long-run core
first_year <- tiles |>
  filter(status == "Hand-built") |>
  group_by(agency_id, agency_name, state) |>
  summarise(first = min(year), years = n(), .groups = "drop")
core <- first_year |>
  filter(first < 2000) |>
  arrange(first, desc(years)) |>
  mutate(label = fct_rev(fct_inorder(city_label(agency_name, state))))
n_later <- nrow(first_year) - nrow(core)

p_tiles <- ggplot(tiles |> inner_join(core |> select(agency_id, label), by = "agency_id"),
                  aes(year, label, fill = status)) +
  geom_tile(height = 0.8, width = 0.9) +
  scale_fill_manual(values = c("Hand-built" = source_colors[["Hand-built (Nix)"]],
                               "Washington Post (2023–24)" = spliced_color),
                    name = NULL) +
  scale_x_continuous(breaks = seq(1970, 2020, 10), expand = expansion(add = 0.5)) +
  labs(x = NULL, y = NULL,
       title = str_wrap(sprintf(paste0("Agencies in these data were involved in at least %s ",
                                       "of all fatal police shootings nationwide, %s"),
                                scales::percent(coverage_share$share, accuracy = 1),
                                str_replace(coverage_share$years, "-", "–")), 60),
       subtitle = sprintf(paste0("The %d agencies with data before 2000 are shown; ",
                                 "%d more have data starting in 2000 or later"),
                          nrow(core), n_later),
       caption = str_wrap(paste0(
         "Share of all deaths in The Washington Post's Fatal Force database. ",
         "Las Vegas and Cincinnati before 2015 are shown here but left out of the trend ",
         "figures, because their series mix in nonfatal shootings."), 105)) +
  theme_project(base_size = 10) +
  theme(panel.grid.major.y = element_blank(), plot.title.position = "plot",
        plot.caption.position = "plot",
        legend.position = "top", legend.justification = "left",
        plot.caption = element_text(hjust = 0, color = "grey35"))

ggsave(file.path(fig_dir, "coverage_tiles.png"), p_tiles,
       width = 6.5, height = 2.1 + 0.2 * nrow(core), dpi = 300, bg = "white")

# 6. Export --------------------------------------------------------------------
excluded_entirely <- TREND_EXCLUSIONS |> filter(is.infinite(first), is.infinite(last))
trend_summary <- tribble(
  ~metric,                         ~value,
  "agencies_hand_built",           n_distinct(nix_agencies$agency_id),
  "agencies_excluded_entirely",    nrow(excluded_entirely),
  "agencies_in_index",             n_distinct(main$kept$agency_id),
  "agencies_dropped_all_zero",     main$n_dropped,
  "pre2000_agencies_min",          min(pre2000$agencies),
  "pre2000_agencies_max",          max(pre2000$agencies),
  "long_panel_agencies",           g_long,
  "era_ratio_recent_vs_early",     round(era_ratio, 3),
  "era_ratio_ci_lo",               round(era_ci[1], 3),
  "era_ratio_ci_hi",               round(era_ci[2], 3),
  "then_now_lower",                n_lower,
  "then_now_total",                n_total,
  "core_tiles_pre2000",            nrow(core),
  "agencies_starting_2000_plus",   n_later,
  "wapo_share_lower_bound",        round(coverage_share$share, 4),
  "index_check_balanced_agencies", nrow(balanced_ids)
)

write_csv(trend_index |> mutate(across(where(is.double), \(x) round(x, 4))),
          file.path(tab_dir, "trend_index.csv"))
write_csv(then_vs_now |> mutate(across(where(is.double), \(x) round(x, 3))),
          file.path(tab_dir, "then_vs_now.csv"))
write_csv(coverage_share |> mutate(share = round(share, 4)),
          file.path(tab_dir, "coverage_share.csv"))
write_csv(trend_summary, file.path(tab_dir, "trend_summary.csv"))
saveRDS(list(main = main$model, long = long$model, era = m_era),
        here("output", "trend_models.rds"))

message("07: index from ", n_distinct(main$kept$agency_id), " agencies; era ratio ",
        round(era_ratio, 2), " in ", g_long, " long-panel agencies; ", n_lower, " of ",
        n_total, " lower now; hand-built share of WaPo deaths >= ",
        scales::percent(coverage_share$share, accuracy = 0.1))
