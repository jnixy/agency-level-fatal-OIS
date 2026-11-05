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
