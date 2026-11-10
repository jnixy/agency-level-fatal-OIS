# Data

| Path | What it is | In git? |
|---|---|---|
| `agency_key.csv` | One row per hand-built agency slug: ORI7, name, state, type, and notes on how its ORI was resolved. Maintained by hand. | yes |
| `crosswalks/fe_agency_crosswalk_seed.csv` | FE name ↔ ORI pairs hand-checked in a related project (Brady & Nix, in progress). `agency_id` is the ORI9. | yes |
| `crosswalks/fe_crosswalk_decisions.csv` | Hand-coded FE matching decisions: `accept`, `reject`, or `none_found` (reviewed, no FE incidents). | yes |
| `crosswalks/mpv_snapshots.csv` | One row per MPV snapshot fetched: date, file, SHA-256, rows, last incident date. The pipeline uses the newest. | yes |
| `crosswalks/mpv_name_decisions.csv` | Hand-coded ORIs for MPV agencies listed without one (e.g., Columbus Division of Police). | yes |
| `raw/` | Unmodified source files (see below). Never edited. | partly |
| `clean/` | Intermediate files written by `scripts/01`–`04c`, including `mpv_ori_aliases.csv`. | yes |

## Raw files

| File | Source | Retrieved | SHA-256 | In git? |
|---|---|---|---|---|
| `raw/wapo/fatal-police-shootings-data.csv` | [*Washington Post*, Fatal Force v2](https://github.com/washingtonpost/data-police-shootings) (archived; deaths 2015-01-02 to 2024-12-31). CC BY-NC-SA 4.0. | 2026-11-04 | `606745b7e5189d0291709390e04db1c7ea2f6f901db31584b3ceb22cc842d05c` | yes |
| `raw/wapo/fatal-police-shootings-agencies.csv` | same | 2026-11-04 | `45d59f3773af0f9ffbdf739f99b4adeafbdc846c54fd5b46f2631daa670a73da` | yes |
| `raw/fatal_encounters.csv` | [Fatal Encounters](https://fatalencounters.org/), final release (deaths through 2021-12-31; 31,498 rows) | 2026-03 | `847ed97ad8a94a595733c0613c6162da1602c539a196665b23779a318baebf5c` | **no** |
| `raw/mpv/mpv_YYYY-MM-DD.csv` | [Mapping Police Violence](https://mappingpoliceviolence.org/) (Campaign Zero), full export of the public Airtable view; still updating | see `crosswalks/mpv_snapshots.csv` | see `crosswalks/mpv_snapshots.csv` | **no** |
| `raw/shr/shr_1976_2024.rds` | Kaplan, J. [*Jacob Kaplan's Concatenated Files: UCR Program Data: Supplementary Homicide Reports (SHR), 1976–2024*](https://doi.org/10.3886/E100699V16), openICPSR 100699 V16 (CC BY 4.0, under ICPSR's terms of use) | 2026-11-05 | `fa7569f31451cec5703e0031b89931ac73bd38d5fc127b4f19e4199fc0454c4a` | **no** |
| `raw/35158-0001-Data.rda` | [Law Enforcement Agency Identifiers Crosswalk, 2012](https://www.icpsr.umich.edu/web/NACJD/studies/35158) (ICPSR 35158), R version | — | — | **no** |

`scripts/02_wapo.R` stops if either WaPo file's checksum differs.

**Fatal Encounters** is linked rather than redistributed. Fatal Encounters stopped collecting data after 2021, and its final release is what the panel uses.

To rebuild the FE columns:
1. Download the spreadsheet from [fatalencounters.org](https://fatalencounters.org/).
2. Export its "Form Responses" sheet as CSV.
3. Save it as `data/raw/fatal_encounters.csv`.

`scripts/03` and `scripts/04` check the file in two ways:
- **Release check (hard):** it must be the final release, 31,498 rows with the last death on 12/31/2021. Anything else stops the pipeline.
- **Checksum (warning only):** they compare its SHA-256 to the copy the published panel was built from. A fresh export can differ byte-for-byte even when the content is the same, so a mismatch only produces a warning.

**Mapping Police Violence** is linked rather than redistributed, and it updates continuously.

To fetch a snapshot, run `python tools/fetch_mpv/fetch_mpv.py` from the project root. It:
- downloads the current export;
- saves it unmodified, named by today's date, in the `mpv` folder under `raw/`;
- records the file's checksum in `crosswalks/mpv_snapshots.csv`.

`scripts/04b_mpv.R` reads the newest snapshot. It warns if that snapshot's checksum differs from the manifest, and it keeps only complete calendar years.

If MPV's undocumented download endpoint changes, download the CSV by hand from the [Airtable view](https://airtable.com/appzVzSeINK1S3EVR/shroOenW19l1m3w0H/tblxearKzw8W7ViN8) and run `python tools/fetch_mpv/fetch_mpv.py --csv <file>`.

The published outputs were built from the snapshot dated 2026-11-04.

**Kaplan's SHR** is linked rather than redistributed. To rebuild the `n_shr` column:
1. Download version 16 of [openICPSR project 100699](https://www.openicpsr.org/openicpsr/project/100699). This needs a free ICPSR login and acceptance of ICPSR's terms of use.
2. Save `shr_1976_2024.rds` in the `shr` folder under `raw/`.

`scripts/04c_shr.R` warns if the file's checksum differs from the one above. Only the aggregated agency-year counts (`clean/shr_agency_year.csv`) are in the repo.

**The LEAIC** is distributed by ICPSR under terms that do not allow redistribution. To run `03_fe_crosswalk.R` (and `tools/agency_key/build_agency_key.R`):
1. Download ICPSR 35158 in R format.
2. Put `35158-0001-Data.rda` in `data/raw/`.

Nothing else in the pipeline needs it.

**Without FE, MPV, and the LEAIC**, steps 01–02 still run, and the published `data/clean/` and `output/` files are already in the repo.

## How the national sources were merged

These are the November 2026 merge mechanics, moved here from the main README.

- **Fatal Encounters.** FE identifies agencies only by name, so linking it takes a name → ORI crosswalk, rebuilt from scratch on every run. Every match comes from one of three places:
  - a hand-checked seed;
  - an exact match on normalized name + state + agency type, accepted only when no other agency in the state (among every agency in the LEAIC and WaPo) has the same name;
  - a hand decision, with a note, recorded in `crosswalks/fe_crosswalk_decisions.csv`.

  FE counts gunshot deaths that FE coded as an intentional use of deadly force. Deaths that FE's own disposition field codes as murder/suicide, accidental, or ruled suicide are dropped (89). That leaves 18,749 deaths from 2000 to 2021, of which 16,706 (89%) link to an agency in the panel.
- **Mapping Police Violence.** MPV records each agency's ORI, so it joins directly, with three fixes, each written to an audit file:
  - **Same agency, different code.** 23 codes that WaPo lists under a statewide agency (mostly state police troops) are mapped to that agency's primary ORI. Three more aliases are identified from deaths that appear in both MPV and WaPo (`clean/mpv_ori_aliases.csv`); Jacksonville SO, filed under FL01624 in MPV, is one. Every candidate and the reason it passed or failed is in `output/tables/mpv_alias_candidates.csv`.
  - **Missing ORIs.** Where MPV has no ORI (e.g., Columbus and Cleveland Divisions of Police), the ORI is recovered from the agency name, through an exact, unique name match or a hand decision in `crosswalks/mpv_name_decisions.csv`.
  - **Off-duty killings** are included in `n_mpv` and counted separately in `n_mpv_offduty`.
- **FBI Supplementary Homicide Reports.** `n_shr` counts people whose killing the reporting agency coded "felon killed by police" with a firearm: 18,361 people over 1976–2024. SHR is not a census of agencies, so `n_shr` is 0 only when the agency filed some SHR record that year, and NA otherwise. It adds earlier years for agencies already in the panel, not new agencies. Counts are listed in `output/tables/shr_linkage.csv`.
- **The WaPo merge was rebuilt.** It reads local, checksummed copies of the archived v2 data instead of live URLs. It handles agencies that WaPo lists under several ORIs (the old merge silently missed 96 of them), and it writes the merged file to disk.
- **Agency key fixes.**
  - Five wrong ORI codes corrected: Forsyth Co. SO, Macon-Bibb Co. SO, Richmond Co. SO, and Gwinnett Co. PD (all GA), plus Louisville Metro PD.
  - Missing ORIs filled in for Orange Co. SD (CA), Arlington Co. PD (VA), and two small Minnesota departments.
  - Every fix was confirmed by year-by-year agreement with WaPo or from the LEAIC. The reasons are recorded in `agency_key.csv`.
- **Two pairs of columns share an ORI** and are summed in the panel: Savannah PD and Savannah-Chatham Metro PD, and Bibb Co. SO and Macon-Bibb Co. SO. That's why 416 columns become 414 agencies.
