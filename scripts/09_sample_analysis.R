# ==============================================================================
# Agency-level fatal OIS: pre-registered analysis of the protocol-v1.0 sample
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
# Source:   Protocol v1.0, section 7 (manuscript/protocol/protocol.md;
#           doi:10.5281/zenodo.24248721)
#
# Purpose:
#   Compare, within the same agencies, the people shot and killed by on-duty
#   officers before 1995 with those killed in 2015-2025, for the 56 agencies
#   of the protocol-v1.0 draw (28 certainty, 28 sampled from 8 strata).
#   - Entry rule: at least 5 exposure-years in each era. Recall rule: an
#     agency below 70% recall is a non-respondent (LASD is the approved
#     exception). Agencies that fail either rule are reweighted away
#     within their stratum.
#   - Two estimands, in counts and in rates per 100,000. Population is the
#     SHR median over 1985-94 and 2015-24; an early era that reaches back
#     before 1985 (existing series only) still uses the 1985-94 population.
#     The estimands:
#     the pooled ratio (design-weighted Poisson with agency fixed effects)
#     and the typical-agency ratio (design-weighted mean of agency log rate
#     ratios).
#   - Per-agency exact Poisson tests, the representativeness of the usable
#     universe, the pre-registered sensitivity runs, and the SHR's undercount
#     by era (RQ3).
#
# Inputs:
#   - output/tables/era_series.csv             -- 07: the series behind the era
#     comparison (agency-years plus period totals, with exposure)
#   - output/tables/sample_draw.csv            -- 08c: design and weights
#   - output/tables/sampling_frame_coverage.csv -- 08b: frame plus audit status
#   - output/agency_year_panel.csv             -- 05: slugs, WaPo, FE, SHR
#   - data/historical/recall_checks.csv        -- recall per drawn agency
#   - data/historical/historical_ois_evidence.csv -- to find paper-stated years
#   - data/clean/wapo_agency_oris.csv          -- 02: ORI groups
#   - data/clean/shr_agency_year.csv           -- 04c: SHR killings by ORI-year
#   - data/raw/shr/shr_1976_2024.rds           -- population served (not
#     redistributed, see data/README.md)
#   - data/raw/35158-0001-Data.rda             -- LEAIC 2012 population, used
#     only where SHR has no 2015-24 population (not redistributed)
#
# Outputs (output/tables/):
#   - sample_agencies.csv          -- one row per drawn agency: status, weight,
#     counts, populations, log ratios, exact tests
#   - sample_estimates.csv         -- main estimates and every sensitivity run
#   - sample_representativeness.csv, sample_representativeness_region.csv
#   - sample_shr_undercount.csv    -- RQ3
#   - sample_certainty_unusable.csv -- the 11 certainty agencies without an archive
#   - sample_paper_stated_years.csv -- agency-years treated as paper-stated
#   - sample_attrition.csv         -- drawn, entered, and excluded by stratum
#   - sample_summary.csv           -- every number quoted from this script
#
# Runtime: ~1 min (reading the SHR .rds)
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
library(survey)
library(fixest)
source(here("scripts", "functions.R"))

tab_dir <- here("output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

SHR_PATH         <- here("data", "raw", "shr", "shr_1976_2024.rds")
SHR_SHA256       <- "fa7569f31451cec5703e0031b89931ac73bd38d5fc127b4f19e4199fc0454c4a"
LEAIC_PATH       <- here("data", "raw", "35158-0001-Data.rda")
EARLY_ERA        <- 1970:1994   # years before 1985 come only from existing series
RECENT_ERA       <- 2015:2025
POP_EARLY_YEARS  <- 1985:1994
POP_RECENT_YEARS <- 2015:2024   # SHR ends in 2024
MIN_ERA_YEARS    <- 5           # protocol section 7
RECALL_MIN       <- 0.70        # protocol section 6
CHANGE_ALPHA     <- 0.05
CONTINUITY       <- 0.5         # added to each era's count in the typical-agency ratio
N_LARGEST        <- 4           # sensitivity: drop the four largest departments
PER              <- 1e5
CI_Q             <- 1 - CHANGE_ALPHA / 2   # two-sided 95% intervals
CHECK_TOL        <- 1e-6        # survey vs. fixest point estimates
WAPO_YEARS       <- 2015:2024   # representativeness: WaPo's full years
FE_YEARS         <- 2000:2021   # Fatal Encounters' coverage
N_EXTRA          <- 20          # protocol: rebuilt before the protocol, not drawn
USABLE           <- c("strong", "usable", "already rebuilt")  # as in 08c
# Recall statuses with no recall value that still count as respondents:
# no FE cases to test, or a department/paper-stated series with no recall run
RECALL_NA_OK     <- c("not measurable", "not applicable")

# Below 70% recall but entered by an approved deviation (protocol section 8)
RECALL_DEVIATIONS <- c(
  "CA01900" = "LASD: entered on the Daily News period total plus Bobb (JN, 2026-11-15)"
)
# Frame ORI -> panel agency where the WaPo ORI groups do not link them
PANEL_ID_OVERRIDES <- c(
  "KY05602" = "KY05680"   # Louisville PD: series summed into Louisville Metro (JN, 2026-11-26)
)
# Series that sum predecessor agencies: early-era population sums them too
POP_PREDECESSORS <- list(
  "KY05680" = c("KY05601", "KY05602")   # Jefferson County PD + Louisville PD
)
# Paper-stated years the evidence text rule below does not catch
PAPER_STATED_EXTRA <- tribble(
  ~slug,            ~year,
  "chicago_il",     1992L,   # spokesman's count (memory: paper-stated department counts)
  "los_angeles_ca", 1993L,   # Use of Force Review Section figures printed in the Daily News
  "los_angeles_ca", 1994L
)

options(survey.lonely.psu = "adjust")

era_of <- function(year) case_when(year %in% EARLY_ERA ~ "early",
                                   year %in% RECENT_ERA ~ "recent")

# 1. Load ----------------------------------------------------------------------
if (!file.exists(SHR_PATH)) {
  stop("SHR file not found at data/raw/shr/shr_1976_2024.rds. ",
       "See data/README.md for where to download it.")
}
check_sha256(SHR_PATH, SHR_SHA256, strict = FALSE)
shr_raw <- readRDS(SHR_PATH)

draw <- read_csv(file.path(tab_dir, "sample_draw.csv"), show_col_types = FALSE)
coverage <- read_csv(file.path(tab_dir, "sampling_frame_coverage.csv"), show_col_types = FALSE)
long_panel <- read_csv(file.path(tab_dir, "then_vs_now.csv"), show_col_types = FALSE)
series <- read_csv(file.path(tab_dir, "era_series.csv"), show_col_types = FALSE,
                   col_types = cols(era = col_character(), src = col_character()))
panel <- read_csv(here("output", "agency_year_panel.csv"), show_col_types = FALSE)
recall <- read_csv(here("data", "historical", "recall_checks.csv"), show_col_types = FALSE)
evidence <- read_csv(here("data", "historical", "historical_ois_evidence.csv"),
                     col_types = cols(.default = col_character()))
wapo_groups <- read_csv(here("data", "clean", "wapo_agency_oris.csv"),
                        col_types = cols(.default = "c")) |>
  distinct(ori7, primary_ori7)
shr_counts <- read_csv(here("data", "clean", "shr_agency_year.csv"), show_col_types = FALSE)
leaic_env <- new.env()
load(LEAIC_PATH, envir = leaic_env)
leaic <- get(ls(leaic_env)[1], envir = leaic_env) |>
  as_tibble() |>
  transmute(ori7 = toupper(str_squish(as.character(ORI7))), leaic_pop = as.numeric(U_TPOP)) |>
  filter(leaic_pop > 0) |>
  group_by(ori7) |>
  summarise(leaic_pop = max(leaic_pop), .groups = "drop")

# 2. Clean ---------------------------------------------------------------------
# 2a. Frame ORI -> panel agency_id (the WaPo primary ORI, or an override)
frame_ids <- coverage |>
  distinct(ori) |>
  left_join(wapo_groups, by = c("ori" = "ori7")) |>
  mutate(agency_id = coalesce(unname(PANEL_ID_OVERRIDES[ori]), primary_ori7, ori)) |>
  select(ori, agency_id)
stopifnot(!anyDuplicated(frame_ids$ori), !anyDuplicated(frame_ids$agency_id))

# 2b. Population served, per era. SHR has one row per homicide record, so
# collapse to one value per ORI-year. An agency's series may sit under any ORI
# in its WaPo group (Providence: RI00400 in the panel, RI00409 in SHR), so take
# the largest population the group reports each year, then the era median.
shr_pop <- shr_raw |>
  mutate(ori = toupper(str_squish(ori))) |>
  filter(year %in% c(POP_EARLY_YEARS, POP_RECENT_YEARS), !is.na(population), population > 0) |>
  group_by(ori, year) |>
  summarise(pop = max(population), .groups = "drop")
rm(shr_raw)

# Agencies needing a population: the frame, plus the long-panel agencies
# outside it (the "adding the earlier rebuilds" sensitivity run)
pop_ids <- union(frame_ids$agency_id, long_panel$agency_id)
# The agency's own ORIs (panel ID, frame ORI) come first; other ORIs in its
# WaPo group fill only years the agency's own ORIs did not file, so a larger
# jurisdiction in the same group can't inflate the denominator
pop_members <- bind_rows(
  frame_ids |> transmute(agency_id, member = ori, own = TRUE),
  tibble(agency_id = pop_ids, member = pop_ids, own = TRUE),
  wapo_groups |> transmute(agency_id = primary_ori7, member = ori7, own = FALSE)
) |>
  filter(agency_id %in% pop_ids) |>
  arrange(desc(own)) |>
  distinct(agency_id, member, .keep_all = TRUE)

group_pop <- pop_members |>
  # many-to-many by design: an ORI files many years, and a frame ORI can sit
  # in its own group as well as a merged agency's (Louisville PD)
  inner_join(shr_pop, by = c("member" = "ori"), relationship = "many-to-many") |>
  group_by(agency_id, year) |>
  summarise(pop = if (any(own)) max(pop[own]) else max(pop), .groups = "drop")
# Merged agencies: sum the predecessors, and only in years all of them filed
pred_pop <- enframe(POP_PREDECESSORS, name = "agency_id", value = "member") |>
  unnest(member) |>
  inner_join(shr_pop |> filter(year %in% POP_EARLY_YEARS), by = c("member" = "ori")) |>
  group_by(agency_id, year) |>
  summarise(pop = sum(pop), n = n(), .groups = "drop") |>
  filter(n == lengths(POP_PREDECESSORS)[agency_id]) |>
  select(-n)

era_pop <- bind_rows(
  group_pop |> filter(year %in% POP_EARLY_YEARS, !agency_id %in% names(POP_PREDECESSORS)),
  pred_pop,
  group_pop |> filter(year %in% POP_RECENT_YEARS)
) |>
  mutate(era = era_of(year)) |>
  group_by(agency_id, era) |>
  summarise(pop = median(pop), pop_years = n(), .groups = "drop") |>
  pivot_wider(names_from = era, values_from = c(pop, pop_years))

# Where SHR has no 2015-24 population (Volusia SO: Florida files no SHR),
# fall back to the LEAIC 2012 population of the agency's ORIs
leaic_group <- pop_members |>
  inner_join(leaic, by = c("member" = "ori7")) |>
  group_by(agency_id) |>
  summarise(leaic_pop = max(leaic_pop), .groups = "drop")
agency_pop <- tibble(agency_id = pop_ids) |>
  left_join(era_pop, by = "agency_id") |>
  left_join(leaic_group, by = "agency_id") |>
  mutate(pop_recent_source = case_when(!is.na(pop_recent) ~ "SHR 2015-24 median",
                                       !is.na(leaic_pop) ~ "LEAIC 2012"),
         pop_recent = coalesce(pop_recent, leaic_pop)) |>
  select(agency_id, pop_early, pop_years_early, pop_recent, pop_years_recent, pop_recent_source)

# 2c. Paper-stated years: an evidence row used in the panel whose note opens
# "Paper-stated", or whose scope says the series is paper-stated and not
# case-by-case, plus the listed extras. Period totals built from a paper's
# stated total (LASD) count as paper-stated too.
paper_rows <- evidence |>
  filter(str_to_lower(str_squish(use_in_panel)) == "yes") |>
  mutate(year = as.integer(year),
         by_note = str_detect(note, regex("^\\s*paper[- ]stated", ignore_case = TRUE)),
         by_scope = str_detect(scope, regex("\\(paper-stated", ignore_case = TRUE)) &
           !str_detect(scope, regex("case-by-case", ignore_case = TRUE))) |>
  filter(by_note | by_scope) |>
  transmute(slug, year, rule = if_else(by_note, "note", "scope")) |>
  bind_rows(PAPER_STATED_EXTRA |> mutate(rule = "listed")) |>
  mutate(slug_key = str_to_upper(str_squish(slug))) |>
  distinct(slug_key, year, .keep_all = TRUE)
slug_years <- panel |>
  filter(!is.na(slugs)) |>
  distinct(agency_id, year, slugs) |>
  separate_longer_delim(slugs, ";") |>
  mutate(slug_key = str_to_upper(str_squish(slugs)))
paper_stated <- paper_rows |>
  inner_join(slug_years, by = c("slug_key", "year")) |>
  distinct(agency_id, year, slug, rule)
# Every paper-stated slug-year lands on exactly one panel agency-year
stopifnot(nrow(anti_join(paper_rows, paper_stated, by = c("slug", "year"))) == 0,
          !anyDuplicated(paper_stated[c("agency_id", "year")]))
paper_periods <- recall |>
  filter(str_detect(pre_source_type, "paper-stated period total")) |>
  left_join(frame_ids, by = "ori") |>
  pull(agency_id)

# 2d. The era series, with the paper-stated flag
series <- series |>
  mutate(era = coalesce(era, era_of(year))) |>
  filter(!is.na(era)) |>
  left_join(paper_stated |> distinct(agency_id, year) |> mutate(paper = TRUE),
            by = c("agency_id", "year")) |>
  mutate(paper = coalesce(paper, FALSE) |
           (src == "period total" & agency_id %in% paper_periods))

# 3. Sample --------------------------------------------------------------------
drawn <- draw |>
  filter(selected) |>
  left_join(frame_ids, by = "ori") |>
  left_join(recall |> select(ori, recall, recall_status = status), by = "ori") |>
  left_join(agency_pop, by = "agency_id") |>
  mutate(respondent = (is.na(recall) & recall_status %in% RECALL_NA_OK) |
           (!is.na(recall) & recall >= RECALL_MIN) | ori %in% names(RECALL_DEVIATIONS),
         label = city_label(agency_name, state_abb))
# A missing recall must carry a status that explains it, never a silent pass
stopifnot(nrow(drawn) == 56, !anyNA(drawn$recall_status),
          all(drawn$recall_status[is.na(drawn$recall)] %in% RECALL_NA_OK),
          all(drawn$agency_id %in% series$agency_id),
          all(names(RECALL_DEVIATIONS) %in% drawn$ori))

# The 20 agencies rebuilt before the protocol that the draw did not select;
# they enter only the sensitivity run that adds them, each with weight 1.
# The 17 inside the frame are also counted in their strata's pools, so that
# run counts them twice by construction (it is a convenience-sample check).
extra <- long_panel |>
  filter(!agency_id %in% drawn$agency_id) |>
  select(agency_id, agency_name, state) |>
  left_join(coverage |> left_join(frame_ids, by = "ori") |>
              select(agency_id, ori, pop_median_1985_94), by = "agency_id") |>
  left_join(agency_pop, by = "agency_id") |>
  mutate(stratum = "not drawn (pre-protocol)", pool_n = NA_real_, design_weight = 1,
         respondent = TRUE, label = city_label(agency_name, state))
stopifnot(nrow(extra) == N_EXTRA)

#' Collapse an agency-year series to one row per agency with both eras, apply
#' the entry rule, and adjust the weights. Sampled strata are reweighted to
#' their usable pool over the agencies that enter; certainty and non-drawn
#' agencies keep weight 1.
#' @param rows era-series rows (y, exposure, era) for the agencies in `agencies`
#' @param agencies one row per agency: agency_id, stratum, pool_n,
#'   design_weight, respondent, pop_early, pop_recent, label
#' @return the agencies with deaths/years by era, `status`, and weight `w`
build_wide <- function(rows, agencies) {
  eras <- rows |>
    group_by(agency_id, era) |>
    summarise(deaths = sum(y), years = sum(exposure),
              first = min(coalesce(year, year_first)), last = max(coalesce(year, year_last)),
              .groups = "drop") |>
    pivot_wider(names_from = era, values_from = c(deaths, years, first, last))
  agencies |>
    left_join(eras, by = "agency_id") |>
    mutate(across(c(years_early, years_recent), \(x) coalesce(x, 0)),
           status = case_when(!respondent ~ "non-respondent (recall below 70%)",
                              years_early < MIN_ERA_YEARS ~ "fewer than 5 years before 1995",
                              years_recent < MIN_ERA_YEARS ~ "fewer than 5 years since 2015",
                              TRUE ~ "entered")) |>
    group_by(stratum) |>
    mutate(n_entered = sum(status == "entered"),
           w = case_when(status != "entered" ~ NA_real_,
                         stratum == "certainty" | is.na(pool_n) ~ 1,
                         TRUE ~ pool_n / n_entered)) |>
    ungroup()
}

agency_cols <- c("agency_id", "ori", "label", "stratum", "pool_n", "design_weight",
                 "respondent", "pop_median_1985_94", "pop_early", "pop_recent")
main_wide <- build_wide(series |> filter(agency_id %in% drawn$agency_id),
                        drawn |> select(all_of(agency_cols)))
entered <- main_wide |> filter(status == "entered")

# Every sampled stratum keeps at least two agencies, and the adjusted weights
# still add up to each stratum's usable pool
sampled_check <- entered |>
  filter(stratum != "certainty") |>
  group_by(stratum) |>
  summarise(n = n(), w_sum = sum(w), pool = first(pool_n), .groups = "drop")
stopifnot(all(sampled_check$n >= 2), all(abs(sampled_check$w_sum - sampled_check$pool) < 1e-9),
          !anyNA(entered$pop_early), !anyNA(entered$pop_recent))

# 4. Estimation ----------------------------------------------------------------
#' Add the design columns: fpc_n is each stratum's population size (the usable
#' pool for sampled strata; for certainty and non-drawn agencies, the agencies
#' themselves, so n = N), and `informative` marks agencies with any death.
add_design_cols <- function(wide) {
  wide |>
    group_by(stratum) |>
    mutate(fpc_n = if_else(stratum == "certainty" | is.na(pool_n), as.numeric(n()), pool_n)) |>
    ungroup() |>
    mutate(informative = deaths_early + deaths_recent > 0)
}

#' Design degrees of freedom: clusters minus strata, over every agency in the
#' design (not only those a domain keeps). Under the finite-population
#' correction the certainty and non-drawn strata are censuses and add no
#' variance, so only the sampled strata count.
design_df <- function(wide, fpc = FALSE) {
  if (fpc) wide <- wide |> filter(stratum != "certainty", !is.na(pool_n))
  sum(count(wide, stratum)$n - 1)
}

#' Pooled ratio: design-weighted quasi-Poisson with agency fixed effects on
#' agency-era totals (the same estimate as on agency-years, since agency and
#' era totals are sufficient). Variance by linearization, clustered on agency
#' within strata; CI from t on the design df. All-zero agencies carry no
#' information, so they are left out of the fit; the df still counts them.
#' @param rate TRUE for deaths per 100,000 (population in the offset)
#' @param fpc TRUE to treat each stratum as sampled without replacement from
#'   its pool (certainty agencies then contribute no variance)
#' @return tibble(estimand, measure, agencies, est, ci_lo, ci_hi, df)
fit_pooled <- function(wide, rate = FALSE, fpc = FALSE) {
  if (rate) wide <- wide |> filter(!is.na(pop_early), !is.na(pop_recent))
  wide <- add_design_cols(wide)
  df <- design_df(wide, fpc)
  # The fixed effects need at least one death per agency, so the fit runs on
  # informative agencies only; their linearization variance is unchanged by
  # agencies that contribute zero scores
  long <- wide |>
    filter(informative) |>
    select(agency_id, stratum, w, fpc_n, deaths_early, deaths_recent, years_early,
           years_recent, pop_early, pop_recent) |>
    pivot_longer(c(deaths_early, deaths_recent, years_early, years_recent, pop_early, pop_recent),
                 names_to = c(".value", "era"), names_sep = "_") |>
    mutate(recent = as.integer(era == "recent"),
           off = log(years * if (rate) pop / PER else 1))
  des <- svydesign(ids = ~agency_id, strata = ~stratum, weights = ~w, data = long,
                   fpc = if (fpc) ~fpc_n else NULL)
  m <- svyglm(deaths ~ recent + factor(agency_id) + offset(off), design = des,
              family = quasipoisson())
  b <- coef(m)[["recent"]]
  se <- SE(m)[["recent"]]
  tibble(estimand = "pooled", measure = if (rate) "rate" else "count",
         agencies = n_distinct(long$agency_id), est = exp(b),
         ci_lo = exp(b - qt(CI_Q, df) * se), ci_hi = exp(b + qt(CI_Q, df) * se), df = df)
}

#' Agency log rate ratio (recent vs. early) with `cc` added to each era's
#' count so agencies with a zero era have a finite ratio
log_rr <- function(wide, rate = FALSE, cc = CONTINUITY) {
  lr <- log((wide$deaths_recent + cc) / wide$years_recent) -
    log((wide$deaths_early + cc) / wide$years_early)
  if (rate) lr - log(wide$pop_recent / wide$pop_early) else lr
}

#' Typical-agency ratio: design-weighted mean of agency log rate ratios
#' @param zero "set aside" estimates over the domain of agencies with any
#'   death (the design keeps every agency, so the variance and df are right);
#'   "as no change" keeps all-zero agencies at no change per year, which in
#'   rates means the ratio implied by the population change alone
#' @param cc_zero_only TRUE adds the continuity correction only to agencies
#'   with a zero era
fit_typical <- function(wide, rate = FALSE, zero = "set aside", cc_zero_only = FALSE,
                        fpc = FALSE) {
  if (rate) wide <- wide |> filter(!is.na(pop_early), !is.na(pop_recent))
  wide <- add_design_cols(wide)
  any_zero <- wide$deaths_early == 0 | wide$deaths_recent == 0
  cc <- if (cc_zero_only) if_else(any_zero, CONTINUITY, 0) else CONTINUITY
  wide$lrr <- log_rr(wide, rate, cc)
  if (zero == "as no change") {
    wide$lrr[!wide$informative] <- if (rate) {
      -log(wide$pop_recent / wide$pop_early)[!wide$informative]
    } else 0
  }
  des <- svydesign(ids = ~1, strata = ~stratum, weights = ~w, data = wide,
                   fpc = if (fpc) ~fpc_n else NULL)
  if (zero == "set aside") des <- subset(des, informative)
  est <- svymean(~lrr, des)
  b <- coef(est)[[1]]
  se <- SE(est)[[1]]
  df <- design_df(wide, fpc)
  tibble(estimand = "typical agency", measure = if (rate) "rate" else "count",
         agencies = if (zero == "set aside") sum(wide$informative) else nrow(wide),
         est = exp(b), ci_lo = exp(b - qt(CI_Q, df) * se), ci_hi = exp(b + qt(CI_Q, df) * se),
         df = df)
}

#' All four estimates (pooled and typical, counts and rates) for one run
fit_all <- function(wide, run, fpc = FALSE, ...) {
  wide <- wide |> filter(status == "entered")
  bind_rows(fit_pooled(wide, FALSE, fpc), fit_pooled(wide, TRUE, fpc),
            fit_typical(wide, FALSE, fpc = fpc, ...), fit_typical(wide, TRUE, fpc = fpc, ...)) |>
    mutate(run = run, .before = 1)
}

# Correctness check: with equal weights, the survey point estimates must equal
# fixest's agency fixed-effects Poisson on the same agency-years, for counts
# and for rates (population in the offset)
check_rows <- series |>
  inner_join(entered |> filter(deaths_early + deaths_recent > 0) |>
               select(agency_id, pop_early, pop_recent), by = "agency_id") |>
  # fixest evaluates the offset inside the data, so build it as a column
  mutate(pop = if_else(era == "early", pop_early, pop_recent),
         pop_years = exposure * pop / PER)
fe_count <- fepois(y ~ i(era, ref = "early") | agency_id, data = check_rows,
                   offset = ~log(exposure), notes = FALSE)
fe_rate <- fepois(y ~ i(era, ref = "early") | agency_id, data = check_rows,
                  offset = ~log(pop_years), notes = FALSE)
stopifnot(abs(log(fit_pooled(entered |> mutate(w = 1))$est) -
                coef(fe_count)[["era::recent"]]) < CHECK_TOL,
          abs(log(fit_pooled(entered |> mutate(w = 1), rate = TRUE)$est) -
                coef(fe_rate)[["era::recent"]]) < CHECK_TOL)

estimates_main <- fit_all(main_wide, "Main")

# 5. Per-agency comparisons ------------------------------------------------------
#' Exact Poisson test of two eras' yearly rates (counts), or of rates per
#' person-year (rates)
exact_p <- function(dr, de, tr, te) {
  map_dbl(seq_along(dr), \(i) poisson.test(round(c(dr[i], de[i])), c(tr[i], te[i]))$p.value)
}
classify <- function(p, lrr) case_when(p >= CHANGE_ALPHA ~ "About the same",
                                       lrr < 0 ~ "Fewer now",
                                       TRUE ~ "More now")

sample_agencies <- main_wide |>
  left_join(drawn |> select(agency_id, agency_name, state_abb, recall, recall_status,
                            pop_recent_source), by = "agency_id") |>
  mutate(per_year_early = deaths_early / years_early,
         per_year_recent = deaths_recent / years_recent,
         rate_early = per_year_early / pop_early * PER,
         rate_recent = per_year_recent / pop_recent * PER,
         all_zero = deaths_early + deaths_recent == 0,
         log_rr_count = if_else(all_zero, NA_real_, log_rr(pick(everything()), FALSE)),
         log_rr_rate = if_else(all_zero, NA_real_, log_rr(pick(everything()), TRUE)))
tested <- sample_agencies$status == "entered" & !sample_agencies$all_zero
sample_agencies <- sample_agencies |>
  mutate(p_count = NA_real_, p_rate = NA_real_)
sample_agencies$p_count[tested] <- with(sample_agencies[tested, ],
  exact_p(deaths_recent, deaths_early, years_recent, years_early))
sample_agencies$p_rate[tested] <- with(sample_agencies[tested, ],
  exact_p(deaths_recent, deaths_early, years_recent * pop_recent, years_early * pop_early))
sample_agencies <- sample_agencies |>
  mutate(change_count = if_else(tested, classify(p_count, per_year_recent - per_year_early), NA),
         change_rate = if_else(tested, classify(p_rate, rate_recent - rate_early), NA)) |>
  arrange(stratum != "certainty", stratum, desc(pop_median_1985_94))

# 6. Sensitivity runs ------------------------------------------------------------
#' Newspaper-year count raised to SHR's where SHR is higher (as in 07)
shr_bound <- function(y, shr, newspaper) if_else(newspaper & !is.na(shr), pmax(y, shr), y)

drawn_rows <- series |> filter(agency_id %in% drawn$agency_id)
drawn_agencies <- drawn |> select(all_of(agency_cols))
largest <- entered |> slice_max(pop_median_1985_94, n = N_LARGEST) |> pull(agency_id)
extra_agencies <- extra |> select(all_of(agency_cols))

paper_wide <- build_wide(drawn_rows |> filter(!paper), drawn_agencies)
estimates <- bind_rows(
  estimates_main,
  fit_all(build_wide(drawn_rows |> mutate(y = shr_bound(y, n_shr, newspaper)), drawn_agencies),
          "Newspaper years raised to SHR where higher (upper bound)"),
  fit_all(paper_wide, "Excluding paper-stated years"),
  fit_all(main_wide |> filter(!agency_id %in% largest),
          sprintf("Excluding the %d largest departments", N_LARGEST)),
  fit_all(build_wide(bind_rows(drawn_rows, series |> filter(agency_id %in% extra$agency_id)),
                     bind_rows(drawn_agencies, extra_agencies)),
          "Adding the agencies rebuilt before the protocol but not drawn (weight 1; in-frame ones also in their pools)"),
  fit_all(main_wide |> filter(!ori %in% names(RECALL_DEVIATIONS)),
          "Excluding LASD (recall deviation)"),
  fit_all(main_wide, "Typical agency: all-zero agencies kept as no change", zero = "as no change"),
  fit_all(main_wide, "Typical agency: continuity correction only for agencies with a zero era",
          cc_zero_only = TRUE),
  fit_all(main_wide, "Finite-population correction (certainty agencies fixed)", fpc = TRUE)
) |>
  # The zero-handling runs change only the typical-agency estimate
  filter(!(str_starts(run, "Typical agency") & estimand == "pooled"))

# 7. Representativeness ----------------------------------------------------------
# Usable vs. unusable frame agencies: SHR police killings per 100,000 a year in
# 1985-94 (years the agency filed), and WaPo deaths per 100,000 a year in
# 2015-24. The frame is built from SHR, so SHR counts join on the frame ORI.
shr_early <- shr_counts |>
  filter(year %in% POP_EARLY_YEARS, !is.na(n_shr)) |>
  group_by(ori = ori7) |>
  summarise(shr_deaths = sum(n_shr), shr_years = n(), .groups = "drop")
wapo_recent <- panel |>
  filter(year %in% WAPO_YEARS) |>
  group_by(agency_id) |>
  summarise(wapo_deaths = sum(n_wapo, na.rm = TRUE), fe_deaths = sum(n_fe, na.rm = TRUE),
            fe_linked = any(!is.na(n_fe)), .groups = "drop")
fe_all <- panel |>
  filter(year %in% FE_YEARS) |>
  group_by(agency_id) |>
  summarise(fe_2000_21 = if (any(!is.na(n_fe))) sum(n_fe, na.rm = TRUE) else NA_real_,
            .groups = "drop")
frame_rates <- coverage |>
  left_join(frame_ids, by = "ori") |>
  left_join(agency_pop |> select(agency_id, pop_recent), by = "agency_id") |>
  left_join(shr_early, by = "ori") |>
  left_join(wapo_recent, by = "agency_id") |>
  mutate(usable = audit_status %in% USABLE,
         group = if_else(usable, "Usable archive (study universe)", "No usable archive"),
         size = if_else(stratum == "certainty", "500k+", size_tier),
         shr_rate_early = shr_deaths / (shr_years * pop_median_1985_94) * PER,
         wapo_rate_recent = wapo_deaths / (length(WAPO_YEARS) * pop_recent) * PER)
stopifnot(nrow(frame_rates) == nrow(coverage))

#' Agencies, median population, and SHR/WaPo rates (mean of agencies, pooled)
summarise_rates <- function(df) {
  df |>
    summarise(agencies = n(),
              median_pop_1985_94 = median(pop_median_1985_94),
              shr_agencies = sum(!is.na(shr_rate_early)),
              shr_rate_mean = mean(shr_rate_early, na.rm = TRUE),
              shr_rate_pooled = sum(shr_deaths, na.rm = TRUE) /
                sum((shr_years * pop_median_1985_94)[!is.na(shr_deaths)]) * PER,
              wapo_agencies = sum(!is.na(wapo_rate_recent)),
              wapo_rate_mean = mean(wapo_rate_recent, na.rm = TRUE),
              wapo_rate_pooled = sum(wapo_deaths[!is.na(wapo_rate_recent)]) /
                sum((length(WAPO_YEARS) * pop_recent)[!is.na(wapo_rate_recent)]) * PER,
              .groups = "drop")
}
#' Wilcoxon rank-sum p, usable vs. unusable agencies
compute_wilcox_p <- function(df, var) {
  x <- df[[var]]
  suppressWarnings(wilcox.test(x[df$usable], x[!df$usable])$p.value)
}
representativeness <- bind_rows(
  frame_rates |> group_by(size = "All", group) |> summarise_rates(),
  frame_rates |> group_by(size, group) |> summarise_rates()
) |>
  left_join(bind_rows(
    tibble(size = "All", p_shr = compute_wilcox_p(frame_rates, "shr_rate_early"),
           p_wapo = compute_wilcox_p(frame_rates, "wapo_rate_recent")),
    frame_rates |> group_by(size) |>
      group_modify(\(d, k) tibble(p_shr = compute_wilcox_p(d, "shr_rate_early"),
                                  p_wapo = compute_wilcox_p(d, "wapo_rate_recent")))
  ), by = "size") |>
  arrange(factor(size, c("All", "500k+", "250-500k", "100-250k")), group)
representativeness_region <- frame_rates |>
  count(group, region) |>
  group_by(group) |>
  mutate(share = n / sum(n)) |>
  ungroup()

# Design-weighted sample vs. the universe it stands for, on the same measures
sample_vs_universe <- entered |>
  left_join(frame_rates |> select(agency_id, shr_rate_early, wapo_rate_recent), by = "agency_id") |>
  summarise(weighted_shr_rate_mean = weighted.mean(shr_rate_early, w, na.rm = TRUE),
            weighted_wapo_rate_mean = weighted.mean(wapo_rate_recent, w, na.rm = TRUE))

# The certainty agencies with no usable archive, reported by name
certainty_unusable <- frame_rates |>
  filter(stratum == "certainty", !usable) |>
  left_join(fe_all, by = "agency_id") |>
  transmute(ori, agency_id, agency_name, state_abb, pop_median_1985_94,
            shr_deaths_1985_94 = shr_deaths, shr_years_filed_1985_94 = shr_years,
            fe_2000_21, wapo_2015_24 = wapo_deaths) |>
  arrange(desc(pop_median_1985_94))
stopifnot(nrow(certainty_unusable) == 11)

# 8. SHR undercount by era (RQ3) ---------------------------------------------------
# Every agency-year of the entered agencies with both a count and an SHR filing
shr_years <- series |>
  filter(src != "period total", !is.na(n_shr)) |>
  inner_join(entered |> select(agency_id, w), by = "agency_id")
#' SHR deaths against the counts used here, per era
#' @param balanced TRUE keeps only agencies with SHR filings in both eras, so
#'   the eras compare the same agencies
summarise_shr <- function(df, balanced) {
  if (balanced) df <- df |> group_by(agency_id) |> filter(n_distinct(era) == 2) |> ungroup()
  df |>
  group_by(era) |>
  summarise(agencies = n_distinct(agency_id), agency_years = n(),
            deaths = sum(y), shr_deaths = sum(n_shr),
            shr_share = shr_deaths / deaths,
            shr_share_weighted = sum(w * n_shr) / sum(w * y),
            years_shr_below = sum(n_shr < y), years_shr_equal = sum(n_shr == y),
            years_shr_above = sum(n_shr > y), .groups = "drop") |>
  mutate(agencies_set = if (balanced) "SHR filed in both eras" else "all", .before = 1)
}
# Recent-era counts come from WaPo and the hand-built series; 2025 has no SHR yet
shr_undercount <- bind_rows(summarise_shr(shr_years, FALSE), summarise_shr(shr_years, TRUE))

# 9. Export --------------------------------------------------------------------
main_est <- estimates_main |> mutate(key = paste(estimand, measure))
get_est <- function(k, col) main_est[[col]][main_est$key == k]
n_tested <- sum(tested)
summary_tbl <- tribble(
  ~metric, ~value,
  "drawn", nrow(drawn),
  "entered", nrow(entered),
  "excluded_nonrespondent", sum(main_wide$status == "non-respondent (recall below 70%)"),
  "excluded_short_early", sum(main_wide$status == "fewer than 5 years before 1995"),
  "excluded_short_recent", sum(main_wide$status == "fewer than 5 years since 2015"),
  "entered_all_zero", sum(entered$deaths_early + entered$deaths_recent == 0),
  "entered_certainty", sum(entered$stratum == "certainty"),
  "entered_sampled", sum(entered$stratum != "certainty"),
  "deaths_early", sum(entered$deaths_early),
  "deaths_recent", sum(entered$deaths_recent),
  "pooled_count_ratio", get_est("pooled count", "est"),
  "pooled_count_ci_lo", get_est("pooled count", "ci_lo"),
  "pooled_count_ci_hi", get_est("pooled count", "ci_hi"),
  "pooled_rate_ratio", get_est("pooled rate", "est"),
  "pooled_rate_ci_lo", get_est("pooled rate", "ci_lo"),
  "pooled_rate_ci_hi", get_est("pooled rate", "ci_hi"),
  "typical_count_ratio", get_est("typical agency count", "est"),
  "typical_count_ci_lo", get_est("typical agency count", "ci_lo"),
  "typical_count_ci_hi", get_est("typical agency count", "ci_hi"),
  "typical_rate_ratio", get_est("typical agency rate", "est"),
  "typical_rate_ci_lo", get_est("typical agency rate", "ci_lo"),
  "typical_rate_ci_hi", get_est("typical agency rate", "ci_hi"),
  "agencies_tested", n_tested,
  "count_fewer", sum(sample_agencies$change_count == "Fewer now", na.rm = TRUE),
  "count_more", sum(sample_agencies$change_count == "More now", na.rm = TRUE),
  "count_same", sum(sample_agencies$change_count == "About the same", na.rm = TRUE),
  "rate_fewer", sum(sample_agencies$change_rate == "Fewer now", na.rm = TRUE),
  "rate_more", sum(sample_agencies$change_rate == "More now", na.rm = TRUE),
  "rate_same", sum(sample_agencies$change_rate == "About the same", na.rm = TRUE),
  "pop_recent_from_leaic", sum(entered$agency_id %in%
                                 agency_pop$agency_id[agency_pop$pop_recent_source %in% "LEAIC 2012"]),
  "paper_stated_agency_years", nrow(paper_stated),
  "sample_weighted_shr_rate_mean", sample_vs_universe$weighted_shr_rate_mean,
  "sample_weighted_wapo_rate_mean", sample_vs_universe$weighted_wapo_rate_mean
)
stopifnot(sum(summary_tbl$value[summary_tbl$metric %in%
                                    c("count_fewer", "count_more", "count_same")]) == n_tested,
          nrow(drawn) == nrow(entered) + sum(main_wide$status != "entered"),
          all(is.finite(estimates$est)), all(is.finite(estimates$ci_lo)),
          all(is.finite(estimates$ci_hi)))
# Who was drawn, who entered, and why the rest did not, by stratum
attrition <- main_wide |>
  count(stratum, pool_n, status) |>
  pivot_wider(names_from = status, values_from = n, values_fill = 0)

round_dbl <- function(df, digits = 3) df |> mutate(across(where(is.double), \(x) round(x, digits)))
write_csv(sample_agencies |>
            select(ori, agency_id, agency_name, state_abb, label, stratum, pool_n, design_weight,
                   w, status, recall, recall_status, deaths_early, years_early, first_early,
                   last_early, deaths_recent, years_recent, first_recent, last_recent,
                   pop_early, pop_recent, pop_recent_source, per_year_early, per_year_recent,
                   rate_early, rate_recent, log_rr_count, log_rr_rate, p_count, p_rate,
                   change_count, change_rate) |>
            round_dbl(4),
          file.path(tab_dir, "sample_agencies.csv"))
write_csv(estimates |> round_dbl(4), file.path(tab_dir, "sample_estimates.csv"))
write_csv(representativeness |> round_dbl(4), file.path(tab_dir, "sample_representativeness.csv"))
write_csv(representativeness_region |> round_dbl(4),
          file.path(tab_dir, "sample_representativeness_region.csv"))
write_csv(shr_undercount |> round_dbl(4), file.path(tab_dir, "sample_shr_undercount.csv"))
write_csv(certainty_unusable, file.path(tab_dir, "sample_certainty_unusable.csv"))
write_csv(paper_stated |> arrange(agency_id, year), file.path(tab_dir, "sample_paper_stated_years.csv"))
write_csv(summary_tbl |> mutate(value = round(value, 4)), file.path(tab_dir, "sample_summary.csv"))
write_csv(attrition, file.path(tab_dir, "sample_attrition.csv"))

message(sprintf(paste0("09: %d of %d drawn agencies entered; pooled ratio %.2f ",
                       "(%.2f-%.2f) counts, %.2f rates; typical agency %.2f counts, %.2f rates"),
                nrow(entered), nrow(drawn),
                get_est("pooled count", "est"), get_est("pooled count", "ci_lo"),
                get_est("pooled count", "ci_hi"), get_est("pooled rate", "est"),
                get_est("typical agency count", "est"), get_est("typical agency rate", "est")))
