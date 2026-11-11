# ==============================================================================
# Agency-level fatal OIS: long-run trend figures for the README
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Figures and tables that show what the hand-built series can do.
#   (1) A within-agency trend index. A Poisson model with agency fixed effects
#       compares each agency only to itself, so agencies entering or leaving
#       the sample don't move the trend (the flaw in the 2025 blog figure,
#       which averaged across a changing set of agencies). The headline
#       comparison comes from a separate era model fit to one fixed set of
#       agencies observed in both eras.
#   (2) Then vs. now: average deaths per year before 1995 and since 2015 for
#       the same fixed set of agencies.
#   (3) Coverage: which agency-years the hand-built data cover (newspaper
#       reconstructions marked), and the share of WaPo deaths (2015-2024)
#       involving one of these agencies.
#   (4) Sensitivity: the era ratio with and without newspaper-reconstructed
#       agency-years.
#   Most hand-built counts for 2015 on were taken from WaPo, so WaPo fills
#   2015-2024 wherever an agency has no usable hand-built count (hand-built
#   series end in 2022), and MPV on-duty counts fill 2025 for series that
#   reach 2024 (MPV ran a few % above hand-built counts in 2021-22, WaPo
#   closer). Years filled this way are drawn lighter.
#
# Inputs:
#   - output/agency_year_panel.csv                 -- from 05_combine.R
#   - output/tables/source_agreement.csv           -- from 05_combine.R
#   - data/raw/wapo/fatal-police-shootings-data.csv
#   - data/clean/wapo_agency_oris.csv              -- from 02_wapo.R
#   - data/historical/historical_ois_evidence.csv  -- newspaper-sourced years
#
# Outputs:
#   - output/figures/trend_index.png, then_vs_now.png, coverage_tiles.png
#   - output/tables/trend_index.csv, then_vs_now.csv, coverage_share.csv,
#     era_ratio_sensitivity.csv, trend_summary.csv (every number quoted in
#     the README)
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
SPLICE_WAPO   <- 2023:2024     # WaPo where it exists: closest to hand-built counts
SPLICE_MPV    <- 2025L         # MPV (on-duty) after WaPo ended
SPLICE_YEARS  <- c(SPLICE_WAPO, SPLICE_MPV)
WAPO_TILE     <- "WaPo (no hand-built count, 2015–24) / MPV (2025)"
EARLY_ERA     <- 1970:1994
RECENT_ERA    <- 2015:2025
MIN_ERA_YEARS <- 5L            # years of data required in each era
CHANGE_ALPHA  <- 0.05          # then-vs-now: below this, an agency's change is called real
WAPO_YEARS    <- 2015:2024
CHECK_WINDOW  <- 1980:1991     # balanced window used to verify the index math
INDEX_BREAKS  <- c(25, 50, 100, 200, 400, 800)

# Series that aren't person-level fatal shootings: TREND_EXCLUSIONS in functions.R
# Austin 2000-07 was excluded here until Nov 2026; those years now come from the
# Statesman reconstruction (person-level), so the exclusion was lifted.

# 1. Load ----------------------------------------------------------------------
panel <- read_csv(here("output", "agency_year_panel.csv"), show_col_types = FALSE)
agreement <- read_csv(here("output", "tables", "source_agreement.csv"), show_col_types = FALSE)

# 2. Trend series ----------------------------------------------------------------
# Flag on the full panel: flag_newspaper() checks every reconstructed year lands on a row
nix_agencies <- panel |> flag_newspaper() |> filter(in_nix)

# Which source each agency-year uses. Most hand-built counts for 2015 on were
# taken from WaPo in the first place, so WaPo fills 2015-24 wherever the
# hand-built count is missing, partial, or excluded; MPV on-duty extends any
# series that reaches 2024 into 2025.
year_source <- nix_agencies |>
  left_join(TREND_EXCLUSIONS |> select(agency_id, first, last), by = "agency_id") |>
  mutate(excluded = !is.na(first) & year >= first & year <= last,
         # A year where only one of an agency's two slugs has data would undercount
         nix_ok = !is.na(n_nix) & year <= LAST_NIX & !excluded & !(nix_partial %in% TRUE),
         wapo_ok = year %in% WAPO_YEARS & !is.na(n_wapo),
         src = case_when(nix_ok ~ "hand-built",
                         wapo_ok ~ "WaPo",
                         TRUE ~ NA_character_),
         y = case_when(src == "hand-built" ~ n_nix,
                       src == "WaPo" ~ as.numeric(n_wapo)))
reach_2024 <- year_source |> filter(year == max(WAPO_YEARS), !is.na(y)) |> distinct(agency_id)
year_source <- year_source |>
  mutate(mpv_ok = year %in% SPLICE_MPV & agency_id %in% reach_2024$agency_id & !is.na(n_mpv),
         src = if_else(mpv_ok, "MPV", src),
         y = if_else(mpv_ok, as.numeric(n_mpv - coalesce(n_mpv_offduty, 0)), y),
         spliced = src %in% c("WaPo", "MPV"))

trend <- year_source |>
  filter(!is.na(y), year >= FIRST_YEAR) |>
  select(agency_id, agency_name, state, year, y, src, spliced, newspaper, n_shr)

stopifnot(!anyDuplicated(trend[c("agency_id", "year")]))

# One fixed set of agencies for the headline comparison and Figure 2
era_of <- function(year) case_when(year %in% EARLY_ERA ~ "early",
                                   year %in% RECENT_ERA ~ "recent")
#' Agencies with at least MIN_ERA_YEARS of data in both eras
long_panel_ids <- function(df) {
  df |>
    mutate(era = era_of(year)) |>
    filter(!is.na(era)) |>
    count(agency_id, era) |>
    filter(n >= MIN_ERA_YEARS) |>
    count(agency_id) |>
    filter(n == 2) |>
    select(agency_id)
}
long_ids <- long_panel_ids(trend)

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
to_era <- function(df) df |> mutate(era = era_of(year)) |> filter(!is.na(era))
era_df <- trend |> semi_join(long_ids, by = "agency_id") |> to_era()
#' Era ratio (recent vs early) with a t(G-1) CI, clustered by agency
#' @return tibble(agencies, ratio, ci_lo, ci_hi)
fit_era <- function(df) {
  # All-zero agencies carry no information and fepois drops them; set them
  # aside first so G (clusters, and the t df) counts only agencies used
  kept <- df |> group_by(agency_id) |> filter(sum(y) > 0) |> ungroup()
  m <- fepois(y ~ i(era, ref = "early") | agency_id, data = kept,
              cluster = ~agency_id, notes = FALSE)
  stopifnot(nobs(m) == nrow(kept), rownames(coeftable(m))[1] == "era::recent")
  est <- coeftable(m)[1, ]
  g <- n_distinct(kept$agency_id)
  ci <- exp(est[["Estimate"]] + c(-1, 1) * qt(0.975, df = g - 1) * est[["Std. Error"]])
  tibble(agencies = g, ratio = exp(est[["Estimate"]]), ci_lo = ci[1], ci_hi = ci[2])
}
era_fit <- fit_era(era_df)
g_long <- era_fit$agencies
era_ratio <- era_fit$ratio
era_ci <- c(era_fit$ci_lo, era_fit$ci_hi)

#' Newspaper-year count raised to SHR's where SHR is higher (other years unchanged)
shr_bound <- function(y, shr, newspaper) {
  if_else(newspaper & !is.na(shr), pmax(y, shr), y)
}

# Sensitivity: how much the newspaper reconstructions move the headline.
# "Without" changes both the agency set and some agencies' early windows, so
# the cleaner like-for-like comparator is the non-newspaper agencies only.
# Chicago and LAPD: their newspaper years are department counts the papers
# printed, not case-by-case rebuilds, and they outweigh the rest of the pool
BIG_DEPT_IDS <- c(chicago = "ILCPD00", lapd = "CA01942")
stopifnot(all(BIG_DEPT_IDS %in% era_df$agency_id))
no_news <- trend |> filter(!newspaper)
news_long <- era_df |> filter(newspaper) |> distinct(agency_id)
era_sensitivity <- bind_rows(
  fit_era(era_df) |> mutate(sample = "All long-panel agencies (headline)"),
  fit_era(no_news |> semi_join(long_panel_ids(no_news), by = "agency_id") |> to_era()) |>
    mutate(sample = "Without newspaper-reconstructed years"),
  fit_era(era_df |> semi_join(news_long, by = "agency_id")) |>
    mutate(sample = "Only agencies with newspaper-reconstructed years"),
  fit_era(era_df |> anti_join(news_long, by = "agency_id")) |>
    mutate(sample = "Only agencies without newspaper-reconstructed years"),
  # Upper bound for newspaper undercounts: a search can miss deaths, so in
  # newspaper years use SHR's count wherever it is higher. SHR also counts
  # off-duty killings, so this overstates the correction.
  fit_era(era_df |> mutate(y = shr_bound(y, n_shr, newspaper))) |>
    mutate(sample = "All long-panel agencies, newspaper years raised to SHR where higher"),
  fit_era(era_df |> semi_join(news_long, by = "agency_id") |>
            mutate(y = shr_bound(y, n_shr, newspaper))) |>
    mutate(sample = "Only agencies with newspaper years, raised to SHR where higher"),
  # The newspaper pool without the two big departments (see BIG_DEPT_IDS)
  fit_era(era_df |> semi_join(news_long, by = "agency_id") |>
            filter(!agency_id %in% BIG_DEPT_IDS)) |>
    mutate(sample = "Only agencies with newspaper years, excluding Chicago and LAPD"),
  fit_era(era_df |> semi_join(news_long, by = "agency_id") |>
            filter(!agency_id %in% BIG_DEPT_IDS) |>
            mutate(y = shr_bound(y, n_shr, newspaper))) |>
    mutate(sample = "Only agencies with newspaper years, excluding Chicago and LAPD, raised to SHR where higher")
) |> relocate(sample)

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
# Independent comparison only: most hand-built 2015+ counts were copied from WaPo
wapo_gap <- agreement |> filter(comparison == "Hand-built (non-WaPo sources) vs WaPo") |> pull(pct_diff_total)
stopifnot(length(wapo_gap) == 1)
mpv_gap  <- agreement |> filter(comparison == "Hand-built vs MPV on-duty") |> pull(pct_diff_total)
x_limits <- c(FIRST_YEAR - 0.5, max(SPLICE_YEARS) + 0.5)

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
  scale_x_continuous(breaks = seq(1970, 2020, 10), limits = x_limits) +
  labs(x = NULL, y = "Fatal police shootings\n(2015 = 100, log scale)",
       title = str_wrap(index_title, 60),
       subtitle = str_wrap(sprintf(paste0(
         "Era ratio %.2f (95%% CI %.2f–%.2f), Poisson model with agency fixed effects. ",
         "Light points use WaPo (%s) and MPV on-duty (%d) counts."),
         era_ratio, era_ci[1], era_ci[2],
         paste(range(SPLICE_WAPO), collapse = "–"), SPLICE_MPV), 100)) +
  theme_project() +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 9))

p_n <- ggplot(trend_index, aes(year, agencies)) +
  geom_col(aes(fill = spliced), width = 0.8) +
  scale_fill_manual(values = c(`FALSE` = "grey60", `TRUE` = spliced_color), guide = "none") +
  scale_x_continuous(breaks = seq(1970, 2020, 10), limits = x_limits) +
  scale_y_continuous(breaks = c(0, 150, 300)) +
  labs(x = NULL, y = "Agencies",
       caption = str_wrap(sprintf(paste0(
         "Before 2000 the index rests on %d–%d large-city agencies; CIs use t(agencies − 1). ",
         "WaPo totals run %.0f%% %s hand-built counts not taken from WaPo (2015–22); MPV on-duty runs %.0f%% %s all hand-built counts (2013–22). ",
         "Excludes series that mix in nonfatal shootings or count incidents."),
         min(pre2000$agencies), max(pre2000$agencies),
         abs(wapo_gap), if (wapo_gap < 0) "below" else "above",
         abs(mpv_gap), if (mpv_gap < 0) "below" else "above"), 120)) +
  theme_project(base_size = 9) +
  theme(panel.grid.major.x = element_blank(), plot.caption = element_text(hjust = 0))

p_trend <- p_index / p_n + plot_layout(heights = c(4, 1))
ggsave(file.path(fig_dir, "trend_index.png"), p_trend,
       width = 6.5, height = 5.4, dpi = 300, bg = "white")

# 4. Figure 2: then vs. now -------------------------------------------------------
then_vs_now <- era_df |>
  group_by(agency_id, agency_name, state, era) |>
  summarise(years = n(), first = min(year), last = max(year),
            per_year = mean(y), deaths = sum(y), .groups = "drop") |>
  pivot_wider(id_cols = c(agency_id, agency_name, state),
              names_from = era, values_from = c(per_year, years, first, last, deaths)) |>
  mutate(label = city_label(agency_name, state),
         change = per_year_recent - per_year_early,
         lower_now = change < 0,
         # Exact Poisson comparison of the two eras' rates per year, so small
         # agencies aren't called "up" or "down" on a difference of one death
         p_change = pmap_dbl(list(deaths_recent, deaths_early, years_recent, years_early),
                             \(dr, de, yr, ye) poisson.test(round(c(dr, de)), c(yr, ye))$p.value),
         direction = case_when(p_change >= CHANGE_ALPHA ~ "About the same",
                               change < 0 ~ "Fewer now",
                               TRUE ~ "More now")) |>
  arrange(per_year_early)

n_lower <- sum(then_vs_now$lower_now)
n_total <- nrow(then_vs_now)
n_fewer <- sum(then_vs_now$direction == "Fewer now")
n_more  <- sum(then_vs_now$direction == "More now")
n_same  <- sum(then_vs_now$direction == "About the same")
stopifnot(n_total == g_long, n_fewer + n_more + n_same == n_total)

direction_colors <- c("Fewer now" = source_colors[["Hand-built (Nix)"]],
                      "More now" = "#b5462f",
                      "About the same" = "grey20")  # darker than the grey early-era dot

dumbbell <- then_vs_now |> mutate(label = fct_inorder(label))
top_row <- slice_tail(dumbbell, n = 1)

p_then_now <- ggplot(dumbbell, aes(y = label)) +
  geom_segment(aes(x = per_year_early, xend = per_year_recent, yend = label,
                   color = direction), linewidth = 1.2, alpha = 0.35) +
  geom_point(aes(x = per_year_early), color = "grey55", size = 2.8) +
  geom_point(aes(x = per_year_recent, color = direction), size = 2.8) +
  scale_color_manual(values = direction_colors, name = NULL,
                     breaks = c("Fewer now", "About the same", "More now")) +
  # Direct labels on the top row instead of a legend
  geom_text(data = top_row, aes(x = per_year_early,
                                label = sprintf("%d–%d", min(EARLY_ERA), max(EARLY_ERA))),
            vjust = -1.1, size = 3, color = "grey45") +
  geom_text(data = top_row, aes(x = per_year_recent,
                                label = sprintf("%d–%d", min(RECENT_ERA), max(RECENT_ERA))),
            vjust = -1.1, size = 3, color = "grey30") +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.1))) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "Average people shot and killed per year", y = NULL,
       # Built from the counts so it can't go stale if the data change
       title = str_wrap(sprintf(
         "Since 2015, %d of %d long-running agencies kill clearly fewer people a year than before 1995, %d clearly more",
         n_fewer, n_total, n_more), 62),
       subtitle = str_wrap(sprintf(paste0(
         "In the other %d, the change is too small to tell from chance (exact Poisson test, ",
         "p < %.2f). Agencies with at least %d years of data in both eras; years observed vary by ",
         "agency. Counts, not rates: populations changed."), n_same, CHANGE_ALPHA, MIN_ERA_YEARS), 95)) +
  theme_project() +
  theme(plot.title.position = "plot", panel.grid.major.y = element_blank(),
        plot.subtitle = element_text(size = 9.5), legend.position = "top",
        legend.justification = "left")

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

tiles <- year_source |>
  mutate(status = case_when(year <= LAST_NIX & !is.na(n_nix) & newspaper ~ "Newspaper reconstruction",
                            year <= LAST_NIX & !is.na(n_nix) ~ "Hand-built (other sources)",
                            spliced ~ WAPO_TILE)) |>
  filter(!is.na(status))

# One labeled row per agency is only readable for the long-run core
first_year <- tiles |>
  filter(status != WAPO_TILE) |>
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
  scale_fill_manual(values = c("Hand-built (other sources)" = source_colors[["Hand-built (Nix)"]],
                               "Newspaper reconstruction" = newspaper_color,
                               setNames(spliced_color, WAPO_TILE)),
                    name = NULL) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
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
         "Hand-built counts for Las Vegas and Cincinnati are shown here but left out of the trend ",
         "figures, because they mix in nonfatal shootings; WaPo stands in for them from 2015."), 105)) +
  theme_project(base_size = 10) +
  theme(panel.grid.major.y = element_blank(), plot.title.position = "plot",
        plot.caption.position = "plot",
        legend.position = "top", legend.justification = "left",
        plot.caption = element_text(hjust = 0, color = "grey35"))

ggsave(file.path(fig_dir, "coverage_tiles.png"), p_tiles,
       width = 6.5, height = 2.1 + 0.2 * nrow(core), dpi = 300, bg = "white")

# 6. Export --------------------------------------------------------------------
# Same filters as the SHR benchmark in 06_figures.R, so the numbers agree
news_rows <- nix_agencies |>
  filter(newspaper, !(nix_partial %in% TRUE)) |>
  anti_join(TREND_EXCLUSIONS, by = "agency_id")
stopifnot(!anyNA(news_rows$n_nix))
news_shr <- news_rows |> filter(!is.na(n_shr))
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
  "then_now_fewer_sig",            n_fewer,
  "then_now_more_sig",             n_more,
  "then_now_same",                 n_same,
  "then_now_total",                n_total,
  "core_tiles_pre2000",            nrow(core),
  "agencies_starting_2000_plus",   n_later,
  "wapo_share_lower_bound",        round(coverage_share$share, 4),
  "index_check_balanced_agencies", nrow(balanced_ids),
  "newspaper_agencies",            n_distinct(news_rows$agency_id),
  "newspaper_agency_years",        nrow(news_rows),
  "newspaper_deaths",              sum(news_rows$n_nix),
  "newspaper_years_with_shr",      nrow(news_shr),
  "newspaper_deaths_in_shr_years", sum(news_shr$n_nix),
  "shr_deaths_in_newspaper_years", sum(news_shr$n_shr),
  "newspaper_years_exact_shr",     sum(news_shr$n_nix == news_shr$n_shr),
  "long_panel_with_newspaper",     nrow(news_long)
)

write_csv(trend_index |> mutate(across(where(is.double), \(x) round(x, 4))),
          file.path(tab_dir, "trend_index.csv"))
write_csv(then_vs_now |> mutate(across(where(is.double), \(x) round(x, 3))),
          file.path(tab_dir, "then_vs_now.csv"))
write_csv(coverage_share |> mutate(share = round(share, 4)),
          file.path(tab_dir, "coverage_share.csv"))
write_csv(era_sensitivity |> mutate(across(where(is.double), \(x) round(x, 3))),
          file.path(tab_dir, "era_ratio_sensitivity.csv"))
write_csv(trend_summary, file.path(tab_dir, "trend_summary.csv"))
# Fitted models are not saved: fixest objects carry their environment, which
# would publish local paths, and every estimate used is in the tables above

message("07: index from ", n_distinct(main$kept$agency_id), " agencies; era ratio ",
        round(era_ratio, 2), " in ", g_long, " long-panel agencies; ", n_lower, " of ",
        n_total, " lower now; hand-built share of WaPo deaths >= ",
        scales::percent(coverage_share$share, accuracy = 0.1))
