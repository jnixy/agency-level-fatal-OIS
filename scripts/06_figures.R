# ==============================================================================
# Agency-level fatal OIS: figures
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   (1) Coverage: how many agencies each source covers, by year.
#   (2) Sixteen large cities: all five series overlaid (hand-built, WaPo, FE,
#       MPV on-duty, and FBI SHR), ported from the 2025 merge script's 16-city panel.
#   (3) Agreement: agency totals, WaPo vs FE and hand-built vs WaPo.
#   (4) SHR benchmark: SHR deaths per hand-built death, by decade, for
#       newspaper-reconstructed and other hand-built agency-years.
#
# Inputs:
#   - output/agency_year_panel.csv, output/tables/coverage_by_year.csv
#   - data/historical/historical_ois_evidence.csv (newspaper-sourced years)
#
# Outputs:
#   - output/figures/coverage_by_year.png
#   - output/figures/sixteen_cities.png
#   - output/figures/source_agreement.png
#   - output/figures/shr_benchmark.png, output/tables/shr_benchmark.csv
#
# Runtime: < 30 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))
fig_dir <- here("output", "figures")
tab_dir <- here("output", "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Load ----------------------------------------------------------------------
panel <- read_csv(here("output", "agency_year_panel.csv"), show_col_types = FALSE)
coverage <- read_csv(here("output", "tables", "coverage_by_year.csv"),
                     show_col_types = FALSE)

source_labels <- c(n_nix = "Hand-built (Nix)", n_wapo = "Washington Post",
                   n_fe = "Fatal Encounters", n_mpv = "Mapping Police Violence",
                   n_shr = "FBI SHR")

# 2. Coverage ------------------------------------------------------------------
cov_long <- coverage |>
  pivot_longer(starts_with("agencies_"), names_to = "source", values_to = "agencies") |>
  mutate(source = factor(source_labels[str_replace(source, "agencies_", "n_")],
                         levels = source_labels)) |>
  filter(agencies > 0)

p_cov <- ggplot(cov_long, aes(year, agencies, color = source)) +
  geom_line(linewidth = 0.9) +
  scale_y_log10(labels = scales::label_comma()) +
  scale_x_continuous(breaks = seq(1970, 2020, 10)) +
  scale_color_manual(values = source_colors) +
  labs(x = NULL, y = "Agencies with data (log scale)", color = NULL) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_project()

ggsave(file.path(fig_dir, "coverage_by_year.png"), p_cov,
       width = 6.5, height = 4, dpi = 300, bg = "white")

# 3. Sixteen cities ------------------------------------------------------------
city_slugs <- c(
  "los_angeles_ca", "new_york_city", "philadelphia_pa", "denver_co", "seattle_wa",
  "chicago_il", "dallas_tx", "houston_tx", "atlanta_ga", "san_diego_ca",
  "indianapolis_in", "kansas_city_mo", "st_louis_metro_mo",
  "washington_dc", "san_francisco_ca", "anaheim_ca"
)

# Panel labels: city + state (city_label() is in scripts/functions.R)

cities <- panel |>
  filter(slugs %in% city_slugs) |>
  # MPV includes off-duty killings; plot its on-duty count so all five series
  # share the hand-built definition (people shot by on-duty officers)
  mutate(label = city_label(agency_name, state),
         n_mpv = n_mpv - n_mpv_offduty) |>
  pivot_longer(c(n_nix, n_wapo, n_fe, n_mpv, n_shr), names_to = "source", values_to = "n") |>
  # Fill missing years with NA within each series so lines break at gaps
  # instead of drawing straight across decades with no data
  group_by(label, source) |>
  filter(any(!is.na(n))) |>
  complete(year = full_seq(year, 1)) |>
  ungroup() |>
  mutate(source = factor(source_labels[source], levels = source_labels),
         # Order panels by the non-SHR series, so adding SHR didn't reshuffle them
         label = fct_reorder(label, if_else(source == "FBI SHR", NA_real_, n),
                             .fun = max, .na_rm = TRUE, .desc = TRUE))

stopifnot(n_distinct(cities$label) == length(city_slugs))

p_cities <- ggplot(cities, aes(year, n, color = source)) +
  geom_line(linewidth = 0.5, na.rm = TRUE) +
  geom_point(size = 0.6, na.rm = TRUE) +
  facet_wrap(~ label, ncol = 4, scales = "free_y") +
  scale_x_continuous(breaks = c(1970, 1995, 2020)) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  scale_color_manual(values = source_colors) +
  labs(x = NULL, y = "People shot and killed by police", color = NULL,
       caption = paste("Mapping Police Violence counts exclude off-duty killings, matching the hand-built definition.",
                       "FBI SHR counts are filed by the reporting agency and miss many police killings.",
                       sep = "\n")) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_project(base_size = 9) +
  theme(panel.spacing = unit(0.6, "lines"),
        plot.caption = element_text(hjust = 0, color = "grey35"))

ggsave(file.path(fig_dir, "sixteen_cities.png"), p_cities,
       width = 6.5, height = 7, dpi = 300, bg = "white")

# 4. Agreement -----------------------------------------------------------------
# Agency totals over the years both series cover; the facet label carries the
# actual year range so it can't go stale. Multi-ORI WaPo agencies are left out,
# as in 05_combine.R.
pair_totals <- function(df, ycol, label) {
  d <- df |> filter(!wapo_multi_ori, !is.na(.data[[ycol]]), !is.na(n_wapo))
  d |>
    group_by(agency_id, agency_name) |>
    summarise(x = sum(n_wapo), y = sum(.data[[ycol]]), .groups = "drop") |>
    mutate(pair_id = ycol,
           pair = paste0(label, " vs. WaPo, ", paste(range(d$year), collapse = "-")))
}

agency_totals <- bind_rows(
  pair_totals(panel, "n_fe", "FE"),
  pair_totals(panel |> filter(in_nix), "n_nix", "Hand-built")
)

# Cincinnati's hand-built series includes nonfatal shootings (see README)
outliers <- agency_totals |>
  filter(pair_id == "n_nix", abs(log1p(y) - log1p(x)) > 1.5) |>
  mutate(label = str_remove(agency_name, " Police Department$"))

# log(1 + count) axes so agencies with zero deaths stay on the plot
log1p_trans <- scales::new_transform("log1p", log1p, expm1)
count_breaks <- c(0, 1, 3, 10, 30, 100)

p_agree <- ggplot(agency_totals, aes(x, y)) +
  geom_abline(color = "grey60", linetype = "dashed") +
  geom_point(alpha = 0.35, size = 1, color = neutral_point_color) +
  geom_text(data = outliers, aes(label = label), size = 2.8, hjust = -0.15,
            color = "grey25") +
  facet_wrap(~ pair) +
  scale_x_continuous(trans = log1p_trans, breaks = count_breaks) +
  scale_y_continuous(trans = log1p_trans, breaks = count_breaks) +
  labs(x = "WaPo total", y = "Comparison total") +
  theme_project()

ggsave(file.path(fig_dir, "source_agreement.png"), p_agree,
       width = 6.5, height = 3.6, dpi = 300, bg = "white")

# 5. SHR benchmark ---------------------------------------------------------------
# SHR is a crude yardstick: it undercounts nationally, agencies skip years, and
# it has no on/off-duty flag (so it also counts off-duty killings that the
# hand-built data leave out). Compare only agency-years where both exist, and
# drop the series that mix in nonfatal shootings.
# Flag on the full panel first: flag_newspaper() checks that every
# reconstructed year lands on a panel row
shr_pairs <- panel |>
  flag_newspaper() |>
  filter(in_nix, !is.na(n_nix), !is.na(n_shr), !(nix_partial %in% TRUE)) |>
  left_join(TREND_EXCLUSIONS |> select(agency_id, first, last), by = "agency_id") |>
  filter(is.na(first) | !(year >= first & year <= last)) |>
  mutate(decade = year %/% 10 * 10,
         source = if_else(newspaper, "Newspaper reconstructions", "Other hand-built sources"))

shr_benchmark <- shr_pairs |>
  group_by(source, decade) |>
  summarise(agency_years = n(), agencies = n_distinct(agency_id),
            hand_built = sum(n_nix), shr = sum(n_shr),
            exact = sum(n_nix == n_shr), .groups = "drop") |>
  mutate(shr_per_hand_built = if_else(hand_built > 0, shr / hand_built, NA_real_),
         exact_share = exact / agency_years)
shr_all <- shr_pairs |>
  group_by(decade) |>
  summarise(source = "All hand-built", agency_years = n(), agencies = n_distinct(agency_id),
            hand_built = sum(n_nix), shr = sum(n_shr), exact = sum(n_nix == n_shr),
            .groups = "drop") |>
  mutate(shr_per_hand_built = if_else(hand_built > 0, shr / hand_built, NA_real_),
         exact_share = exact / agency_years)
shr_benchmark <- bind_rows(shr_all, shr_benchmark) |> arrange(source, decade)
stopifnot(sum(shr_all$agency_years) == nrow(shr_pairs),
          all(is.finite(shr_benchmark$shr_per_hand_built)))

# Title wording comes from the data, so it can't go stale
shr_overall <- shr_pairs |>
  group_by(source) |>
  summarise(r = sum(n_shr) / sum(n_nix), .groups = "drop") |>
  deframe()
more_fewer <- \(r) if (r > 1) "more" else "fewer"
shr_title <- sprintf(paste0("The FBI's SHR counts %s deaths than the newspaper ",
                            "reconstructions, and %s than the other hand-built sources"),
                     more_fewer(shr_overall[["Newspaper reconstructions"]]),
                     more_fewer(shr_overall[["Other hand-built sources"]]))

shr_colors <- c("Other hand-built sources" = source_colors[["Hand-built (Nix)"]],
                "Newspaper reconstructions" = newspaper_color)
shr_plot <- shr_benchmark |>
  filter(source != "All hand-built") |>
  mutate(decade_label = paste0(decade, "s"))
shr_end <- shr_plot |> group_by(source) |> slice_max(decade, n = 1)

p_shr <- ggplot(shr_plot, aes(decade, shr_per_hand_built, color = source)) +
  geom_hline(yintercept = 1, color = "grey60", linetype = "dashed") +
  geom_line(linewidth = 0.8) +
  geom_point(aes(size = agency_years)) +
  geom_text(data = shr_end, aes(label = source), hjust = -0.08, size = 3.1,
            show.legend = FALSE) +
  annotate("text", x = 1970, y = 1.03, label = "SHR = hand-built", hjust = 0,
           vjust = 0, size = 2.9, color = "grey40") +
  scale_color_manual(values = shr_colors, guide = "none") +
  scale_size_area(max_size = 5, name = "Agency-years compared") +
  scale_x_continuous(breaks = seq(1970, 2020, 10), labels = \(x) paste0(x, "s"),
                     expand = expansion(add = c(3, 30))) +
  scale_y_continuous(limits = c(0, NA), labels = scales::label_number(accuracy = 0.1)) +
  labs(x = NULL, y = "SHR deaths per hand-built death",
       title = str_wrap(shr_title, 70),
       subtitle = str_wrap(paste0("Same agencies and years only. SHR also counts off-duty ",
                                  "killings, which the hand-built data leave out, and ",
                                  "reporting to SHR thinned after the 2021 switch to NIBRS."), 95)) +
  theme_project(base_size = 10) +
  theme(plot.title.position = "plot")

ggsave(file.path(fig_dir, "shr_benchmark.png"), p_shr,
       width = 6.5, height = 4, dpi = 300, bg = "white")
write_csv(shr_benchmark |> mutate(across(c(shr_per_hand_built, exact_share), \(x) round(x, 3))),
          file.path(tab_dir, "shr_benchmark.csv"))

message("06: figures written to output/figures/")
