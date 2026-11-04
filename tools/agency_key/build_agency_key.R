# ==============================================================================
# Agency-level fatal OIS: build the initial agency key
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   One-time build of data/agency_key.csv. This records where each column came
#   from. After this runs, edit data/agency_key.csv by hand; do not re-run this
#   script, because it would overwrite those edits. It takes the January 2025
#   slug-to-ORI7 list, fills in ORIs that were missing, and adds the agency name,
#   state, and type from the Law Enforcement Agency Identifiers Crosswalk (LEAIC).
#
# Inputs:
#   - tools/agency_key/ori_codes_2025.csv   -- slug -> ORI7 (UCR 2020), 416 rows
#   - data/raw/35158-0001-Data.rda          -- LEAIC 2012 (ICPSR 35158)
#   - data/raw/wapo/fatal-police-shootings-agencies.csv -- preferred names
#
# Outputs:
#   - data/agency_key.csv
#
# Runtime: < 10 sec
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------
library(tidyverse)
library(here)
source(here("scripts", "functions.R"))

out_path <- here("data", "agency_key.csv")
if (file.exists(out_path)) {
  stop("data/agency_key.csv already exists and is hand-maintained. Delete it ",
       "first if you really mean to rebuild from scratch.")
}

# 1. Load ----------------------------------------------------------------------
ori_2025 <- read_csv(here("tools", "agency_key", "ori_codes_2025.csv"),
                     show_col_types = FALSE) |>
  rename(slug = agency, ori7 = oricodes)

load(here("data", "raw", "35158-0001-Data.rda"))  # -> da35158.0001
leaic <- as_tibble(da35158.0001) |>
  mutate(across(where(is.factor), \(x) str_squish(as.character(x))))

# 2. Resolve missing / non-UCR ORIs --------------------------------------------
# The evidence for each fix is in its note, which carries into the key.
# orange_county and arlington_county were identified by exact year-by-year
# agreement of the hand-built counts with WaPo (2015-2022). The three small MN
# agencies never reported to UCR, so the LEAIC lists their ORI7 as -1; the ORI7
# is the first 7 characters of their ORI9.
ori_fixes <- tribble(
  ~slug,              ~ori7_fix,  ~note,
  "orange_county",    "CA03000",  "Orange County SD (CA); ORI matched via exact WaPo agreement 2015-22",
  "arlington_county", "VA00701",  "Arlington County PD (VA); ORI matched via WaPo agreement 2015-22",
  "backus_mn",        "MN01106",  "Non-UCR reporter; ORI7 = first 7 of LEAIC ORI9 MN0110600",
  "miltona_mn",       "MN02107",  "Non-UCR reporter; ORI7 = first 7 of LEAIC ORI9 MN0210700",
  "sebeka_mn",        "MN08002",  "Non-UCR reporter; ORI7 = first 7 of LEAIC ORI9 MN0800200",
  "mn_bca",           "MNBCA00",  "Minnesota BCA; state agency ORI, no LEAIC ORI7",
  "utah_doc",         NA,         "Utah Dept. of Corrections; no ORI found in LEAIC",
  # The 2025 list had these three GA (AJC) agencies on the wrong ORI; the
  # corrected ORIs agree with WaPo 2015-2020 (exactly, 4 of 6, 5 of 6 years)
  "forsyth_county_ga",    "GA05800", "Forsyth County SO; 2025 list had GA10201 (Forsyth city PD, Monroe Co.)",
  "macon_bibb_county_ga", "GA01100", "Macon-Bibb County SO (Bibb ORI); 2025 list had GA09600 (Macon County SO). Same agency as bibb_county_ga (consolidated 2014); summed in panel",
  "bibb_county_ga",       "GA01100", "Same agency as macon_bibb_county_ga (AJC lists both names); summed in panel",
  "richmond_county_ga",   "GA12100", "Richmond County SO (Augusta); 2025 list had GA12102",
  "gwinnett_county_ga",   "GA06702", "Gwinnett County PD; 2025 list had GA06700 (Gwinnett SO). Matches WaPo exactly 2015-19",
  "louisville_ky",        "KY05680", "Louisville Metro PD; 2025 list had KY05602 (pre-merger Louisville PD). Matches WaPo exactly 2015-22",
  "athens_clarke_county_ga", "GA02901", "Athens-Clarke PD. 2019 hand-built count (5) equals WaPo PD (1) + SO (4); AJC data may combine both agencies",
  "savannah_ga",      "GA02503",  "Shares ORI with savannah_chatham_metro_ga (SCMPD 2005-2018); summed in panel",
  "savannah_chatham_metro_ga", "GA02503", "Shares ORI with savannah_ga; summed in panel"
)

# LEAIC lookup keyed on ORI7, plus an ORI9-derived key for non-UCR reporters
leaic_lookup <- leaic |>
  mutate(key7 = if_else(ORI7 == "-1", str_sub(ORI9, 1, 7), ORI7)) |>
  filter(key7 != "-1") |>
  # Prefer rows with a real ORI7, then the agency's own ORI9 (ORI7 + "00") over
  # sub-units that share the first 7 characters
  arrange(key7, ORI7 == "-1", ORI9 != paste0(key7, "00"), ORI9) |>
  distinct(key7, .keep_all = TRUE) |>
  transmute(ori7 = key7, leaic_name = NAME, leaic_type = AGCYTYPE)

type_map <- c(
  "(000) Local police department"      = "local_police",
  "(001) Sheriff's office"             = "sheriff",
  "(005) State law enforcement agency" = "state",
  "(006) Special jurisdiction"         = "special",
  "(007) Constable/Marshal"            = "constable",
  "(997) Federal"                      = "federal"
)

# 3. Build ---------------------------------------------------------------------
manual_names <- tribble(
  ~slug,       ~manual_name,                                   ~manual_type,
  "mn_bca",    "Minnesota Bureau of Criminal Apprehension",    "state",
  "utah_doc",  "Utah Department of Corrections",               "state"
)

# WaPo's agency names are cleaner than the LEAIC's ("Orange Cnty Sheriffs
# Dept"); use them where WaPo lists exactly one agency under the ORI
wapo_names <- read_csv(here("data", "raw", "wapo", "fatal-police-shootings-agencies.csv"),
                       show_col_types = FALSE, col_types = cols(.default = col_character())) |>
  separate_longer_delim(oricodes, ";") |>
  mutate(ori7 = str_sub(str_squish(oricodes), 1, 7)) |>
  filter(!is.na(ori7)) |>
  group_by(ori7) |>
  filter(n_distinct(name) == 1) |>
  summarise(wapo_name = first(name), .groups = "drop")

agency_key <- ori_2025 |>
  left_join(ori_fixes, by = "slug") |>
  mutate(ori7 = if_else(slug %in% ori_fixes$slug, ori7_fix, ori7)) |>
  left_join(leaic_lookup, by = "ori7") |>
  left_join(manual_names, by = "slug") |>
  left_join(wapo_names, by = "ori7") |>
  mutate(
    leaic_title = str_to_title(leaic_name) |>
      str_replace_all("'S\\b", "'s") |>
      str_replace_all("\\bPd\\b", "Police Department"),
    agency_name = coalesce(manual_name, wapo_name, leaic_title),
    agency_type = coalesce(manual_type, unname(type_map[leaic_type])),
    # ORI prefixes are postal codes except Nebraska, whose ORIs start "NB"
    state = coalesce(ori_state(ori7), if_else(slug == "utah_doc", "UT", NA)),
    name_source = case_when(!is.na(manual_name) ~ "manual",
                            !is.na(wapo_name) ~ "WaPo",
                            TRUE ~ "LEAIC 2012")
  ) |>
  select(slug, ori7, agency_name, state, agency_type, name_source, note) |>
  arrange(slug)

# Slugs allowed to share an ORI (same agency under two names in the sources)
shared_ori_ok <- c("GA02503", "GA01100")
dup_oris <- agency_key$ori7[duplicated(agency_key$ori7) & !is.na(agency_key$ori7)]

stopifnot(
  nrow(agency_key) == nrow(ori_2025),
  !anyDuplicated(agency_key$slug),
  all(!is.na(agency_key$agency_name)),
  all(is.na(agency_key$ori7) | str_detect(agency_key$ori7, "^[A-Z0-9]{7}$")),
  all(agency_key$state %in% c(state.abb, "DC")),
  all(dup_oris %in% shared_ori_ok)
)

# 4. Export --------------------------------------------------------------------
write_csv(agency_key, out_path, na = "")
message("Wrote ", nrow(agency_key), " agencies to data/agency_key.csv")
