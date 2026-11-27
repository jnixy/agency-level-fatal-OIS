# ==============================================================================
# Agency-level fatal OIS: figures for the protocol-v1.0 sample
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Protocol v1.0 (doi:10.5281/zenodo.24248721); estimates from 09
#
# Purpose:
#   Figures for the pre-registered sample, numbered in the order the paper
#   will use them:
#     Fig 1  where the 56 drawn agencies are (map)
#     Fig 2  the headline: pooled vs. typical-agency ratios
#     Fig 3  why the two differ: each agency's rate then vs. now
#     Fig 4  agency by agency: rates then and now (dumbbell)
#     Fig 5  year by year, with the SHR for the same agencies
#     Fig A1 every robustness run (appendix)
#   Every estimate comes from 09's tables; only the year index in Fig 5 is
#   fit here. Titles are built from the data so they cannot go stale.
#
# Inputs:
#   - output/tables/sample_agencies.csv   -- 09: one row per drawn agency
#   - output/tables/sample_estimates.csv  -- 09: estimates and sensitivity runs
#   - output/tables/sample_shr_undercount.csv -- 09: SHR share by era
#   - output/tables/era_series.csv        -- 07: agency-year counts
#   - output/agency_year_panel.csv        -- 05: SHR counts in every year
#   - data/raw/35158-0001-Data.rda        -- LEAIC 2012: agency coordinates
#     (not redistributed, see data/README.md)
#
# Outputs:
#   - output/figures/fig1_sample_map.png, fig2_estimates.png,
#     fig3_rate_scatter.png, fig4_then_vs_now.png, fig5_trend_shr.png,
#     figA1_robustness.png
#   - output/figures/manuscript/ -- the same six figures for the paper: no
#     in-figure titles (they become captions), sized so figure plus a
#     double-spaced caption fits a page
#   - output/tables/sample_trend_index.csv -- the Fig 5 index
#   - output/tables/sample_figure_captions.csv -- each figure's title, subtitle
#     and note, for the manuscript captions
#
# Runtime: < 30 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
library(fixest)
library(patchwork)
library(ggrepel)
library(usmap)
library(sf)
source(here("scripts", "functions.R"))

fig_dir <- here("output", "figures")
tab_dir <- here("output", "tables")
ms_dir  <- here("output", "figures", "manuscript")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(ms_dir, recursive = TRUE, showWarnings = FALSE)
MS_MAX_HEIGHT <- 7   # inches: figure plus double-spaced caption must fit in 9in

#' Record a figure's title, subtitle and note as caption text, one line each
captions <- list()
record_caption <- function(name, title, subtitle = NA, note = NA) {
  one_line <- \(x) if (is.null(x) || all(is.na(x))) NA_character_ else str_squish(x)
  captions[[name]] <<- tibble(figure = name, title = one_line(title),
                              subtitle = one_line(subtitle), note = one_line(note))
}

#' Save a figure twice: the README version as drawn, and a manuscript version
#' with the title, subtitle and caption removed (they go in the paper's
#' caption) at `ms_height`. `ms_plot` replaces the plot when the manuscript
#' layout differs (Fig 4).
save_both <- function(p, name, height, ms_height, ms_plot = NULL) {
  labs_ <- get_labs(p)
  record_caption(name, labs_$title, labs_$subtitle, labs_$caption)
  ggsave(file.path(fig_dir, paste0(name, ".png")), p,
         width = FIG_WIDTH, height = height, dpi = 300, bg = "white")
  stopifnot(ms_height <= MS_MAX_HEIGHT)
  ms <- (ms_plot %||% p) + labs(title = NULL, subtitle = NULL, caption = NULL)
  ggsave(file.path(ms_dir, paste0(name, ".png")), ms,
         width = FIG_WIDTH, height = ms_height, dpi = 300, bg = "white")
}

LEAIC_PATH   <- here("data", "raw", "35158-0001-Data.rda")
INDEX_EARLY  <- 1970:1994   # the pre-registered early era
INDEX_BASE   <- 1985:1994   # base 100: the years nearly every agency has
INDEX_RECENT <- 2015:2025
SHR_FIRST    <- 1976L       # first SHR year in the panel
SHR_LAST     <- 2024L
N_LABEL      <- 4           # largest departments labeled on the map and scatter
N_LARGE      <- 10          # Fig 3 title: the largest vs. the rest
PSEUDO_SIGMA <- 0.02        # pseudo-log axis: linear below ~0.02 per 100k, so zeros show
RATE_BREAKS  <- c(0, 0.05, 0.1, 0.2, 0.5, 1, 2)
FIG_WIDTH    <- 6.5

direction_colors <- c("Fewer now" = source_colors[["Hand-built (Nix)"]],
                      "About the same" = "grey55",
                      "More now" = "#b5462f")
estimand_colors <- c("pooled" = "grey25", "typical agency" = newspaper_color)
shr_color <- source_colors[["FBI SHR"]]

#' Short agency label, e.g. "Chicago", "Harris Co. SO", "Fairfax Co. PD"
#' @param name lower-case agency name; @param state postal code
short_label <- function(name, state) {
  x <- name |>
    str_to_title() |>
    str_replace_all("'S\\b", "'s") |>
    str_replace("^New York City Police Department$", "New York") |>
    str_replace("^Louisville Pd$", "Louisville") |>
    str_replace("^Miami-Dade \\(County\\) Police Department$", "Miami-Dade") |>
    str_replace("^Amherst Town Police Department$", "Amherst") |>
    str_replace(" (County|Parish) Sheriff's (Office|Department)$", " \\1 SO") |>
    str_replace(" County Police (Department|Dept)$", " Co. PD") |>
    str_replace(" County SO$", " Co. SO") |>
    str_replace(" (Police Department|Police Dept|Police)$", "")
  x <- if_else(state == "DC", "Washington", x)
  paste0(x, ", ", state)
}

# 1. Load ----------------------------------------------------------------------
agencies <- read_csv(file.path(tab_dir, "sample_agencies.csv"), show_col_types = FALSE) |>
  mutate(short = short_label(agency_name, state_abb),
         design = if_else(stratum == "certainty", "Certainty (500,000+)", "Sampled"))
estimates <- read_csv(file.path(tab_dir, "sample_estimates.csv"), show_col_types = FALSE)
shr_share <- read_csv(file.path(tab_dir, "sample_shr_undercount.csv"), show_col_types = FALSE)
series <- read_csv(file.path(tab_dir, "era_series.csv"), show_col_types = FALSE,
                   col_types = cols(era = col_character(), src = col_character()))
panel_shr <- read_csv(here("output", "agency_year_panel.csv"), show_col_types = FALSE,
                      col_select = c(agency_id, year, n_shr))

if (!file.exists(LEAIC_PATH)) {
  stop("LEAIC file not found at data/raw/35158-0001-Data.rda. ",
       "See data/README.md for where to download it.")
}
leaic_env <- new.env()
load(LEAIC_PATH, envir = leaic_env)
stopifnot(length(ls(leaic_env)) == 1)
coords <- get(ls(leaic_env), envir = leaic_env) |>
  as_tibble() |>
  transmute(ori = toupper(str_squish(as.character(ORI7))),
            lat = as.numeric(INTPTLAT), lon = as.numeric(INTPTLONG)) |>
  filter(!is.na(lat), !is.na(lon)) |>
  distinct(ori, .keep_all = TRUE)
rm(leaic_env)

stopifnot(nrow(agencies) == 56, !anyDuplicated(agencies$agency_id),
          !anyDuplicated(agencies$short))

entered <- agencies |> filter(status == "entered")
informative <- entered |> filter(deaths_early + deaths_recent > 0)
main <- estimates |> filter(run == "Main")
stopifnot(nrow(main) == 4, all(main$agencies == nrow(informative)))

#' "0.97 (0.69–1.35)"
fmt_est <- function(est, lo, hi) sprintf("%.2f (%.2f–%.2f)", est, lo, hi)
get_est <- function(estimand_, measure_) main |> filter(estimand == estimand_, measure == measure_)

# 2. Fig 1: map ------------------------------------------------------------------
NO_DEATHS <- "No deaths in either era"
map_fills <- c(direction_colors, setNames("grey88", NO_DEATHS), "Did not enter" = "white")
map_pts <- agencies |>
  left_join(coords, by = "ori") |>
  mutate(direction = case_when(status != "entered" ~ "Did not enter",
                               deaths_early + deaths_recent == 0 ~ NO_DEATHS,
                               TRUE ~ change_rate),
         direction = factor(direction, levels = names(map_fills)))
stopifnot(!anyNA(map_pts$lat), !anyNA(map_pts$pop_recent), !anyNA(map_pts$direction))
map_sf <- usmap_transform(map_pts, input_names = c("lon", "lat")) |> arrange(desc(pop_recent))
largest <- map_pts |> slice_max(pop_recent, n = N_LABEL) |> pull(agency_id)
n_cert <- sum(agencies$stratum == "certainty")
n_samp <- sum(agencies$stratum != "certainty")
n_strata <- n_distinct(agencies$stratum[agencies$stratum != "certainty"])

# Labels for the largest departments, pushed off their markers (metres in the
# usmap projection): New York into the Atlantic, the rest to open land
label_nudge <- tribble(
  ~agency_id, ~dx,   ~dy,
  "NY03030",  4e5,   -2e5,
  "CA01942",  -1e5,  -3.5e5,
  "ILCPD00",  -4e5,  2.5e5,
  "TXHPD00",  3e5,   -3e5
)
map_labels <- map_sf |>
  filter(agency_id %in% largest) |>
  mutate(x = st_coordinates(geometry)[, 1], y = st_coordinates(geometry)[, 2]) |>
  st_drop_geometry() |>
  left_join(label_nudge, by = "agency_id")
# A changed top 4 must get its own nudges, not labels sitting on their markers
stopifnot(setequal(label_nudge$agency_id, largest), nrow(map_labels) == N_LABEL)
# The sample has no agency in Alaska or Hawaii, so the insets are left off
stopifnot(!any(agencies$state_abb %in% c("AK", "HI")))

p_map <- plot_usmap(regions = "states", exclude = c("AK", "HI"),
                    fill = "grey96", color = "grey75", linewidth = 0.2) +
  geom_sf(data = map_sf, aes(size = pop_recent, fill = direction, shape = design),
          color = "grey15", stroke = 0.3, alpha = 0.9) +
  geom_segment(data = map_labels, aes(x = x, y = y, xend = x + dx * 0.8, yend = y + dy * 0.8),
               color = "grey30", linewidth = 0.3) +
  geom_label(data = map_labels, aes(x = x + dx, y = y + dy, label = str_remove(short, ", [A-Z]{2}$")),
             size = 2.8, color = "grey20", fill = "white", linewidth = 0, label.padding = unit(1, "pt")) +
  scale_fill_manual(values = map_fills, drop = FALSE,
                    name = "Deaths per resident, 2015–25 vs. before 1995") +
  scale_shape_manual(values = c("Certainty (500,000+)" = 21, "Sampled" = 24), name = NULL) +
  scale_size_area(max_size = 9, breaks = c(1e5, 5e5, 1e6, 4e6),
                  labels = c("100,000", "500,000", "1 million", "4 million"),
                  name = "Population served") +
  guides(fill = guide_legend(override.aes = list(shape = 21, size = 3.5), order = 1, ncol = 3),
         shape = guide_legend(override.aes = list(size = 3.5, fill = "grey80"), order = 2),
         size = guide_legend(override.aes = list(shape = 21, fill = "grey80"), order = 3)) +
  labs(title = str_wrap(sprintf(
         "The %d agencies drawn: all %d usable agencies serving 500,000 or more, and %d sampled from %d region-by-size strata",
         nrow(agencies), n_cert, n_samp, n_strata), 70),
       subtitle = str_wrap(sprintf(paste0(
         "%d enter the comparison; %d have too few years before 1995. ",
         "Fill gives each agency's change in deaths per resident (exact Poisson test, p < .05). ",
         "Markers sit at the LEAIC's point for each agency, so a city and its county overlap."),
         nrow(entered), nrow(agencies) - nrow(entered)), 100)) +
  theme(plot.title = element_text(face = "bold", size = 11),
        plot.subtitle = element_text(size = 8.5),
        legend.position = "bottom", legend.box = "vertical",
        legend.title = element_text(size = 8), legend.text = element_text(size = 8),
        legend.title.position = "top", legend.spacing.y = unit(2, "pt"),
        axis.title = element_blank())

save_both(p_map, "fig1_sample_map", height = 6, ms_height = 5.2)

# 3. Fig 2: headline estimates -----------------------------------------------------
est_plot <- main |>
  mutate(estimand_lab = if_else(estimand == "pooled", "Pooled ratio", "Typical-agency ratio"),
         measure_lab = if_else(measure == "count", "Deaths a year", "Deaths per resident"),
         row = fct_rev(fct_inorder(paste(estimand_lab, measure_lab, sep = "\n"))),
         lab = fmt_est(est, ci_lo, ci_hi))

pc <- get_est("pooled", "count")
tc <- get_est("typical agency", "count")
stopifnot(nrow(pc) == 1, nrow(tc) == 1)
p_est <- ggplot(est_plot, aes(est, row, color = estimand)) +
  geom_vline(xintercept = 1, color = "grey60", linewidth = 0.4) +
  geom_errorbar(aes(xmin = ci_lo, xmax = ci_hi), width = 0, orientation = "y", linewidth = 1.1) +
  geom_point(size = 3.2) +
  geom_text(aes(x = ci_hi, label = lab), hjust = -0.12, size = 3.2, show.legend = FALSE) +
  annotate("text", x = 1, y = 4.6, label = "No change", size = 3, color = "grey45") +
  scale_color_manual(values = estimand_colors, guide = "none") +
  scale_x_continuous(trans = "log", breaks = c(0.5, 0.75, 1, 1.5, 2, 3),
                     labels = c("0.5", "0.75", "1", "1.5", "2", "3"),
                     limits = c(0.5, 5)) +
  scale_y_discrete(expand = expansion(add = c(0.6, 0.9))) +
  labs(x = "Ratio, 2015–25 to before 1995 (log scale)", y = NULL,
       title = str_wrap(sprintf(paste0(
         "Pooled, fatal police shootings are about where they were before 1995 (%.2f); ",
         "the typical agency kills about %s as many people a year (%.2f)"),
         pc$est, if (round(tc$est) == 2) "twice" else sprintf("%.1f times", tc$est), tc$est), 62),
       subtitle = str_wrap(sprintf(paste0(
         "%d agencies, design-weighted, with 95%% CIs (t on %d df). The pooled ratio weights ",
         "agencies by their deaths, so large departments dominate it; the typical-agency ratio ",
         "is the mean of each agency's own log ratio."), unique(main$agencies), unique(main$df)), 95)) +
  theme_project() +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 9),
        panel.grid.major.y = element_blank(), axis.text.y = element_text(hjust = 0))

save_both(p_est, "fig2_estimates", height = 3.6, ms_height = 2.6)

# 4. Fig 3: rate then vs. now ------------------------------------------------------
scatter <- informative |>
  mutate(below = rate_recent < rate_early,
         rank = min_rank(desc(pop_recent)),
         large = rank <= N_LARGE)
n_large_down <- sum(scatter$large & scatter$below)
n_rest <- sum(!scatter$large)
n_rest_up <- sum(!scatter$large & scatter$rate_recent > scatter$rate_early)
rate_lims <- c(0, max(c(scatter$rate_early, scatter$rate_recent)) * 1.1)

p_scatter <- ggplot(scatter, aes(rate_early, rate_recent)) +
  geom_abline(slope = 1, intercept = 0, color = "grey60", linetype = "22") +
  annotate("text", x = 1.3, y = 1.3, label = "No change", angle = 45, vjust = -0.6,
           size = 3, color = "grey45") +
  annotate("text", x = 0.03, y = 1.3, label = "Higher now", hjust = 0, size = 3.2,
           color = direction_colors[["More now"]], fontface = "bold") +
  annotate("text", x = 1.3, y = 0.03, label = "Lower now", hjust = 1, size = 3.2,
           color = direction_colors[["Fewer now"]], fontface = "bold") +
  geom_point(aes(size = pop_recent, fill = large), shape = 21, color = "grey15",
             stroke = 0.3, alpha = 0.85) +
  geom_text_repel(data = scatter |> filter(rank <= N_LABEL),
                  aes(label = str_remove(short, ", [A-Z]{2}$")), size = 2.9, color = "grey20",
                  min.segment.length = 0, box.padding = 0.6, seed = 1) +
  scale_fill_manual(values = c(`TRUE` = "grey25", `FALSE` = newspaper_color),
                    labels = c(`TRUE` = sprintf("%d largest", N_LARGE), `FALSE` = "Others"),
                    breaks = c("TRUE", "FALSE"), name = NULL) +
  scale_size_area(max_size = 10, guide = "none") +
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = PSEUDO_SIGMA),
                     breaks = RATE_BREAKS, limits = rate_lims) +
  scale_y_continuous(trans = scales::pseudo_log_trans(sigma = PSEUDO_SIGMA),
                     breaks = RATE_BREAKS, limits = rate_lims) +
  coord_equal() +
  guides(fill = guide_legend(override.aes = list(size = 3.5))) +
  labs(x = "Deaths per 100,000 a year, before 1995", y = "Deaths per 100,000 a year, 2015–25",
       title = str_wrap(sprintf(paste0(
         "%d of the %d largest departments have lower rates per resident than before 1995; ",
         "%d of the other %d have higher rates (point estimates)"), n_large_down, N_LARGE, n_rest_up, n_rest), 60),
       subtitle = str_wrap(paste0(
         "One point per agency, sized by population served. Departments with high rates before 1995 ",
         "mostly fell and those with low rates mostly rose. Axes are log-like above 0.05 and ",
         "linear near zero, so agencies with no deaths in an era sit on the axis."), 92)) +
  theme_project() +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 9),
        legend.position = "inside", legend.position.inside = c(0.98, 0.3),
        legend.justification = c(1, 0))

save_both(p_scatter, "fig3_rate_scatter", height = 7, ms_height = 6.2)

# 5. Fig 4: dumbbell ---------------------------------------------------------------
dumbbell <- informative |>
  mutate(direction = factor(change_rate, levels = names(direction_colors))) |>
  arrange(rate_early) |>
  mutate(short = fct_inorder(short))
stopifnot(!anyNA(dumbbell$direction))
n_dir <- count(dumbbell, direction, .drop = FALSE) |> deframe()
# The eras are named in the subtitle rather than on a row: the top rows'
# dots sit too close together for direct labels
p_dumbbell <- ggplot(dumbbell, aes(y = short)) +
  geom_segment(aes(x = rate_early, xend = rate_recent, yend = short, color = direction),
               linewidth = 1.2, alpha = 0.35) +
  geom_point(aes(x = rate_early), color = "grey55", size = 2.4) +
  geom_point(aes(x = rate_recent, color = direction), size = 2.4) +
  scale_color_manual(values = direction_colors, name = NULL, drop = FALSE) +
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = PSEUDO_SIGMA),
                     breaks = RATE_BREAKS, expand = expansion(mult = c(0.02, 0.1))) +
  scale_y_discrete(expand = expansion(add = 0.6)) +
  facet_grid(rows = vars(design), scales = "free_y", space = "free_y") +
  labs(x = "Deaths per 100,000 residents a year (log-like scale; zero at left)", y = NULL,
       title = str_wrap(sprintf(paste0(
         "Per resident, %d of the %d agencies kill clearly fewer people than before 1995, ",
         "%d clearly more"), n_dir[["Fewer now"]], nrow(dumbbell), n_dir[["More now"]]), 62),
       subtitle = str_wrap(sprintf(paste0(
         "Grey dot: before 1995; colored dot: 2015–25. In the other %d, the change is too small ",
         "to tell from chance (exact Poisson test, p < .05). Population is the SHR median for ",
         "1985–94 and 2015–24 (LEAIC 2012 where the SHR has none)."),
         n_dir[["About the same"]]), 95)) +
  theme_project(base_size = 10) +
  theme(plot.title.position = "plot", panel.grid.major.y = element_blank(),
        plot.subtitle = element_text(size = 9), legend.position = "top",
        legend.justification = "left", strip.text.y = element_text(angle = 270))

# One column of 52 rows is too tall for a manuscript page, so the paper's
# version puts the certainty and sampled agencies side by side
ms_rows <- max(count(dumbbell, design)$n)
p_dumbbell_ms <- p_dumbbell +
  facet_wrap(~design, ncol = 2, scales = "free_y") +
  # Half-width panels have room for fewer ticks
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = PSEUDO_SIGMA),
                     breaks = c(0, 0.1, 0.5, 2), labels = c("0", "0.1", "0.5", "2"),
                     expand = expansion(mult = c(0.02, 0.1))) +
  labs(x = "Deaths per 100,000 residents a year (log-like scale)") +
  theme(strip.text = element_text(size = 9, hjust = 0), panel.spacing.x = unit(10, "pt"))
save_both(p_dumbbell, "fig4_then_vs_now", height = 1.8 + 0.17 * nrow(dumbbell),
          ms_height = 1.2 + 0.2 * ms_rows, ms_plot = p_dumbbell_ms)

# 6. Fig 5: year index and the SHR's coverage --------------------------------------
# Top: a design-weighted Poisson index with agency fixed effects, fit to the
# count alone (hand-built, or WaPo/MPV where 07 splices them in), only in the
# two eras the sample was built for. A model that also put the SHR on the
# agencies' shared baseline was tried and moved this line by up to 30%: the
# SHR's coverage differs too much across agencies for a shared baseline.
# Middle: the SHR's share of the deaths counted here, year by year, over
# agency-years with both a count and an SHR filing (NA = not filed), as in 09.
idx_ids <- informative |> select(agency_id, w)
stopifnot(!anyNA(idx_ids$w))
own <- series |>
  filter(src != "period total", year %in% c(INDEX_EARLY, INDEX_RECENT)) |>
  inner_join(idx_ids, by = "agency_id") |>
  group_by(agency_id) |>
  filter(sum(y) > 0) |>
  ungroup()
stopifnot(!anyDuplicated(own[c("agency_id", "year")]),
          n_distinct(own$agency_id) == nrow(informative))

ref_year <- max(INDEX_EARLY)
fml <- as.formula(sprintf("y ~ i(year, ref = %d) | agency_id", ref_year))
m_idx <- fepois(fml, data = own, weights = ~w, cluster = ~agency_id, notes = FALSE)
stopifnot(nobs(m_idx) == nrow(own))

trend <- as_tibble(coeftable(m_idx), rownames = "term") |>
  transmute(year = as.integer(str_extract(term, "\\d{4}$")), est = Estimate, se = `Std. Error`) |>
  bind_rows(tibble(year = ref_year, est = 0, se = 0)) |>
  arrange(year)
# A year fixest drops (collinear or separated) would vanish silently
stopifnot(nrow(trend) == n_distinct(own$year))
# Base 100 = the geometric mean of the 1985-94 year effects
base <- mean(trend$est[trend$year %in% INDEX_BASE])
agencies_by_year <- own |> count(year, name = "agencies")
trend <- trend |>
  left_join(agencies_by_year, by = "year") |>
  # Few clusters inform the early years: t(agencies - 1), as in 07
  mutate(crit = qt(0.975, df = pmax(agencies - 1, 1)),
         index = 100 * exp(est - base),
         lo = 100 * exp(est - base - crit * se),
         hi = 100 * exp(est - base + crit * se),
         segment = if_else(year %in% INDEX_EARLY, "early", "recent"))
stopifnot(!anyNA(trend$agencies))

coverage <- own |>
  filter(!is.na(n_shr), year <= SHR_LAST) |>
  group_by(year) |>
  summarise(agencies = n(), deaths = sum(y), shr_deaths = sum(n_shr), .groups = "drop") |>
  mutate(share = shr_deaths / deaths,
         segment = if_else(year %in% INDEX_EARLY, "early", "recent"))
shr_early <- shr_share |> filter(agencies_set == "all", era == "early")
shr_recent <- shr_share |> filter(agencies_set == "all", era == "recent")
stopifnot(nrow(shr_early) == 1, nrow(shr_recent) == 1)
# The panel's era totals must reproduce 09's (same rows, all informative agencies
# enter both; 09's all-zero agencies add no deaths)
cov_era <- coverage |> group_by(segment) |> summarise(share = sum(shr_deaths) / sum(deaths))
stopifnot(abs(cov_era$share[cov_era$segment == "early"] - shr_early$shr_share) < 1e-3,
          abs(cov_era$share[cov_era$segment == "recent"] - shr_recent$shr_share) < 1e-3)

gap <- c(max(INDEX_EARLY) + 0.5, min(INDEX_RECENT) - 0.5)
x_lim <- c(min(INDEX_EARLY) - 0.5, max(INDEX_RECENT) + 0.5)
x_breaks <- seq(min(INDEX_EARLY), max(INDEX_RECENT), 5)
gap_layer <- annotate("rect", xmin = gap[1], xmax = gap[2], ymin = -Inf, ymax = Inf,
                      fill = "grey93")
y_top <- max(trend$hi) * 1.05
recent_mean <- exp(mean(log(trend$index[trend$year %in% INDEX_RECENT])))
count_color <- source_colors[["Hand-built (Nix)"]]

p_trend <- ggplot(trend, aes(year)) +
  # A log axis cannot take -Inf, so this panel's shading starts just above zero
  annotate("rect", xmin = gap[1], xmax = gap[2], ymin = 1e-3, ymax = Inf, fill = "grey93") +
  annotate("text", x = mean(gap), y = y_top, size = 3, color = "grey40", vjust = 1,
           label = sprintf("Not rebuilt for the sample\n(%d–%d)", max(INDEX_EARLY) + 1,
                           min(INDEX_RECENT) - 1)) +
  geom_hline(yintercept = 100, color = "grey70", linewidth = 0.4) +
  geom_ribbon(aes(ymin = lo, ymax = hi, group = segment), fill = count_color, alpha = 0.18) +
  geom_line(aes(y = index, group = segment), color = count_color, linewidth = 0.9) +
  geom_point(aes(y = index), color = count_color, size = 1.5) +
  scale_x_continuous(breaks = x_breaks, limits = x_lim) +
  scale_y_continuous(trans = "log2", breaks = c(25, 50, 100, 200, 400, 800)) +
  coord_cartesian(ylim = c(min(trend$lo) * 0.95, y_top)) +
  labs(x = NULL, y = sprintf("Deaths a year\n(%d–%s = 100, log scale)", min(INDEX_BASE),
                             str_sub(max(INDEX_BASE), 3, 4)),
       title = str_wrap(sprintf(paste0(
         "In the same agencies, the SHR records %s of the deaths counted here before 1995, ",
         "but only %s since 2015"),
         scales::percent(shr_early$shr_share, accuracy = 1),
         scales::percent(shr_recent$shr_share, accuracy = 1)), 62),
       subtitle = str_wrap(sprintf(paste0(
         "Top: deaths a year in the %d sample agencies (design-weighted Poisson model with agency ",
         "fixed effects, 95%% CI), about %.0f in 2015–25 against 100 in %d–%s. The early 1970s, ",
         "with only a few large cities, ran far higher, so the pre-registered pooled ratio over ",
         "1970–94 is %s. Middle: the SHR's share of these deaths, where the agency filed."),
         n_distinct(own$agency_id), recent_mean, min(INDEX_BASE), str_sub(max(INDEX_BASE), 3, 4),
         fmt_est(pc$est, pc$ci_lo, pc$ci_hi)), 100)) +
  theme_project() +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 9),
        axis.text.x = element_blank())

p_cov <- ggplot(coverage, aes(year, share)) +
  gap_layer +
  geom_hline(yintercept = 1, color = "grey70", linewidth = 0.4) +
  geom_line(aes(group = segment), color = shr_color, linewidth = 0.8) +
  geom_point(color = shr_color, size = 1.5) +
  scale_x_continuous(breaks = x_breaks, limits = x_lim) +
  scale_y_continuous(labels = scales::percent, limits = c(0, max(1.05, max(coverage$share))),
                     breaks = c(0, 0.5, 1)) +
  labs(x = NULL, y = "SHR share\nof deaths") +
  theme_project(base_size = 10) +
  theme(axis.text.x = element_blank())

p_n <- ggplot(agencies_by_year, aes(year, agencies)) +
  gap_layer +
  geom_col(fill = "grey60", width = 0.8) +
  scale_x_continuous(breaks = x_breaks, limits = x_lim) +
  labs(x = NULL, y = "Agencies",
       caption = str_wrap(sprintf(paste0(
         "Counts are hand-built, or WaPo/MPV where 07 splices them in. The SHR share uses agency-years ",
         "where the agency filed (Florida agencies file none) and ends in %d; the drop after 2020 ",
         "coincides with the FBI's move to NIBRS. The LA County Sheriff's 1985–90 period total has ",
         "no yearly breakdown and is left out of this figure."), SHR_LAST), 110)) +
  theme_project(base_size = 10) +
  theme(panel.grid.major.x = element_blank(), plot.caption = element_text(hjust = 0, size = 8),
        plot.caption.position = "plot")

# Three stacked panels: save_both takes one ggplot, so this figure is saved here
fig5_heights <- c(3.2, 1.3, 0.9)
record_caption("fig5_trend_shr", get_labs(p_trend)$title, get_labs(p_trend)$subtitle,
               get_labs(p_n)$caption)
ggsave(file.path(fig_dir, "fig5_trend_shr.png"),
       p_trend / p_cov / p_n + plot_layout(heights = fig5_heights),
       width = FIG_WIDTH, height = 6.4, dpi = 300, bg = "white")
strip_labs <- labs(title = NULL, subtitle = NULL, caption = NULL)
ggsave(file.path(ms_dir, "fig5_trend_shr.png"),
       (p_trend + strip_labs) / p_cov / (p_n + strip_labs) + plot_layout(heights = fig5_heights),
       width = FIG_WIDTH, height = 5.4, dpi = 300, bg = "white")

# 7. Fig A1: robustness ------------------------------------------------------------
run_order <- c("Main",
               "Newspaper years raised to SHR where higher (upper bound)",
               "Excluding paper-stated years",
               "Excluding the 4 largest departments",
               "Excluding LASD (recall deviation)",
               "Adding the agencies rebuilt before the protocol but not drawn (weight 1; in-frame ones also in their pools)",
               "Finite-population correction (certainty agencies fixed)",
               "Typical agency: all-zero agencies kept as no change",
               "Typical agency: continuity correction only for agencies with a zero era",
               "Early era 1985-94 only (not pre-registered)")
stopifnot(setequal(run_order, unique(estimates$run)))
# Agencies the "adding" run brings in: its count-run agencies beyond the main 52
n_added <- estimates |> filter(str_starts(run, "Adding"), estimand == "pooled", measure == "count") |>
  pull(agencies) - nrow(informative)
stopifnot(length(n_added) == 1, n_added > 0)
rob <- estimates |>
  mutate(run_lab = run |>
           str_replace("^Adding the agencies rebuilt before the protocol but not drawn.*$",
                       sprintf("Adding the %d agencies rebuilt before the protocol", n_added)) |>
           str_remove("^Typical agency: ") |>
           str_to_sentence() |>
           str_replace("\\blasd\\b", "LASD") |>
           str_replace("\\bshr\\b", "SHR") |>
           str_replace("1985-94", "1985–94") |>
           str_wrap(34),
         run_lab = fct_rev(factor(run_lab, levels = unique(run_lab[order(match(run, run_order))]))),
         estimand_lab = if_else(estimand == "pooled", "Pooled ratio", "Typical-agency ratio"),
         measure_lab = if_else(measure == "count", "Deaths a year", "Deaths per resident"))

# The one run that was not pre-registered sits last (bottom row), below a rule
stopifnot(str_detect(last(run_order), "not pre-registered"))
p_rob <- ggplot(rob, aes(est, run_lab, color = measure_lab)) +
  geom_vline(xintercept = 1, color = "grey60", linewidth = 0.4) +
  geom_hline(yintercept = 1.5, color = "grey50", linewidth = 0.3, linetype = "22") +
  geom_errorbar(aes(xmin = ci_lo, xmax = ci_hi), width = 0, orientation = "y", linewidth = 0.8,
                 position = position_dodge(width = 0.6)) +
  geom_point(size = 2, position = position_dodge(width = 0.6)) +
  facet_wrap(~estimand_lab) +
  scale_color_manual(values = c("Deaths a year" = "grey25",
                                "Deaths per resident" = source_colors[["Hand-built (Nix)"]]),
                     name = NULL) +
  scale_x_continuous(trans = "log", breaks = c(0.5, 0.75, 1, 1.5, 2, 3),
                     labels = c("0.5", "0.75", "1", "1.5", "2", "3")) +
  labs(x = "Ratio, 2015–25 to before 1995 (log scale, 95% CI)", y = NULL,
       title = str_wrap(paste0("The typical-agency ratio stays near 2 in every run; the pooled ratio ",
                               "depends on a few large departments and on the early 1970s"), 70),
       subtitle = str_wrap(paste0(
         "The pooled ratio rises without the four largest departments, and when the early era ",
         "starts in 1985 (below the rule: not pre-registered), since a few large cities ran far ",
         "higher in the 1970s. Zero-handling runs apply to the typical-agency ratio only. ",
         "Every run is in sample_estimates.csv."), 100)) +
  theme_project(base_size = 10) +
  theme(plot.title.position = "plot", plot.subtitle = element_text(size = 8.5),
        panel.grid.major.y = element_blank(), legend.position = "top",
        legend.justification = "left", axis.text.y = element_text(size = 8))

save_both(p_rob, "figA1_robustness", height = 6.8, ms_height = 6)

# 8. Export ----------------------------------------------------------------------
write_csv(trend |>
            select(year, agencies, est, se, index, lo, hi) |>
            left_join(coverage |> select(year, shr_agency_years = agencies, deaths, shr_deaths,
                                         shr_share = share), by = "year") |>
            mutate(across(where(is.double), \(x) round(x, 4))),
          file.path(tab_dir, "sample_trend_index.csv"))
caption_tbl <- bind_rows(captions)
stopifnot(nrow(caption_tbl) == 6, !anyNA(caption_tbl$title),
          all(file.exists(file.path(ms_dir, paste0(caption_tbl$figure, ".png")))))
write_csv(caption_tbl, file.path(tab_dir, "sample_figure_captions.csv"))

message("10: six figures; index from ", n_distinct(own$agency_id), " agencies; 2015-25 mean ",
        round(recent_mean), " vs. ", min(INDEX_BASE), "-", max(INDEX_BASE), " = 100")
