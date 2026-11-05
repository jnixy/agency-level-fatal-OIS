# Codebook

## `output/agency_year_panel.csv`

One row per agency-year. The panel is deliberately **unbalanced**: an agency has rows only for the years at least one source covers it. A missing row means no source covers that agency-year, not zero deaths. Don't `complete()` the panel and fill in zeros.

| Variable | Type | Description |
|---|---|---|
| `agency_id` | string | ORI7 when the agency has one. Otherwise the hand-built slug (only `utah_doc`). Unique together with `year`. |
| `ori7` | string | 7-character FBI ORI. The first 7 characters of the LEAIC ORI9. Nebraska ORIs begin "NB". |
| `agency_name` | string | Agency name. From the WaPo agency file where available, otherwise the LEAIC 2012 (hand-built agencies) or MPV (agencies only MPV records). Agencies that share an ORI list both names, separated by " / ". |
| `state` | string | Two-letter postal code, taken from the ORI. |
| `agency_type` | string | For hand-built agencies: `local_police`, `sheriff`, `state`, `special`, or `constable` (from the LEAIC). For WaPo-only agencies: WaPo's own type labels. NA for agencies only MPV records. |
| `in_nix` | logical | TRUE if the agency has a hand-built series. |
| `slugs` | string | Column name(s) in `agency-level-fatal-ois.csv`, separated by ";". Two agencies have two slugs each: Savannah and Macon-Bibb. |
| `wapo_multi_ori` | logical | TRUE if WaPo lists this agency under several ORIs (state police, highway patrols, some federal agencies). All its WaPo deaths are assigned to this one ORI, so it is left out of the source-agreement comparisons. |
| `year` | integer | Calendar year of death, 1969–2025. |
| `n_nix` | number | People shot and killed by the agency's on-duty officers, from the hand-built sources (see README). NA means no data. Some series include nonfatal shootings; see README caveats. |
| `nix_partial` | logical | For agencies with two slugs: TRUE if only one of them has data that year. FALSE for every hand-built row in the current data. |
| `n_wapo` | integer | *Washington Post* Fatal Force deaths, 2015–2024. 0 for any hand-built or WaPo-coded agency WaPo did not record in a year. NA outside 2015–2024, and for agencies known only from MPV. |
| `n_fe` | integer | Fatal Encounters deaths, 2000–2021: deaths coded "Gunshot" with intended force "Deadly force". Excludes deaths that FE's disposition field codes as "Murder/suicide", "Accidental", or "Ruled suicide"; "Ruled suicide by police" (suicide-by-cop) is kept. NA if the agency was never linked to FE, or outside 2000–2021. See the notes below. |
| `n_fe_multi` | integer | How many of `n_fe` list more than one agency in FE. Counted before linking, so a partner agency outside the panel still makes a death "shared". |
| `n_fe_flagged` | integer | How many of `n_fe` have an FE description mentioning a self-inflicted, accidental, or off-duty shooting (pattern in `scripts/functions.R`, `FE_FLAG_PATTERN`). These deaths may not be intentional on-duty police shootings. The keyword search also catches legitimate cases, so they are flagged, not dropped. `n_fe - n_fe_flagged` gives a conservative count. |
| `n_mpv` | integer | Mapping Police Violence deaths where the recorded use of force includes a gunshot, 2013 through the snapshot's last complete year (2025 in the current build). **Includes off-duty killings.** 0 for any ORI-coded agency MPV did not record in a year. |
| `n_mpv_offduty` | integer | How many of `n_mpv` MPV flags as off-duty killings. `n_mpv - n_mpv_offduty` matches the hand-built (on-duty) definition. |
| `n_mpv_multi` | integer | How many of `n_mpv` list more than one agency in MPV. |
| `n_shr` | integer | FBI Supplementary Homicide Reports, 1976–2024 (Kaplan's concatenated files). People whose killing the agency recorded with circumstance "felon killed by police" and a firearm as the officer's weapon. A record counts each of its victims. 0 when the agency filed at least one SHR record (for any homicide) that year; NA when it filed none. Filed under the reporting agency, which is not always the agency whose officer fired. A known undercount, and its zeros can be false; see README. |

**Counting rules**
- In WaPo, FE, and MPV, a death involving several agencies counts once for each agency listed. Summing `n_wapo`, `n_fe`, or `n_mpv` across agencies therefore overcounts.
- Within one agency, a death counts once, even if two spellings of that agency appear in the same record.

**MPV ORIs.** MPV supplies each agency's ORI. Three adjustments are written to audit files:
- Codes that WaPo lists under a statewide agency (e.g., a state police troop code) are mapped to that agency's primary ORI, the same one WaPo's deaths use.
- Other MPV codes that no other source uses are re-pointed when deaths in both MPV and WaPo show they're the same agency (`data/clean/mpv_ori_aliases.csv`). This requires all of:
  - at least 3 shared deaths;
  - at least 80% of them pointing to one ORI;
  - the same state;
  - matching agency names, if the two codes share a county code.

  Every candidate is listed in `output/tables/mpv_alias_candidates.csv`.
- Where MPV has no ORI, it is recovered from the agency name, either by an exact, unique match to the agency key or WaPo's names, or by a hand decision (`data/crosswalks/mpv_name_decisions.csv`).
- Deaths with no recoverable ORI (mostly federal agencies) are left out. `output/tables/mpv_linkage.csv` counts them, and `output/tables/mpv_unresolved.csv` lists the agency names.

**FE zeros.** A linked agency gets `n_fe = 0` in any year with no linked death. That can be a false zero in two cases:
- FE also used a spelling of the agency's name that isn't in the crosswalk. The largest unlinked names are listed in `output/tables/fe_top_unmatched_names.csv`.
- The year is early in FE's coverage. FE was compiled after the fact and is thinner before about 2013.

## `agency-level-fatal-ois.csv`

The original hand-built file. Columns:
- `year`
- one column per agency slug: the count of people shot and killed in that year.

A blank cell means no data. `data/agency_key.csv` maps each slug to its ORI, name, state, and type, and its `note` column records how any ORI was resolved.

## Supporting tables (`output/tables/`)

| File | Contents |
|---|---|
| `source_agreement.csv` | Pairwise comparison of the series over overlapping agency-years. Columns: correlation, total-deaths difference (%), mean absolute difference, share of agency-years with identical counts (all, and where either source > 0). Each comparison is also restricted to the common support, 2015–2021, where the hand-built, WaPo, and FE series are all observed. MPV is compared on its on-duty count and including off-duty killings. SHR is compared with each of the other sources. |
| `source_disagreements.csv` | Agency-level totals over each pair's overlap where the sources differ, largest gap first. |
| `coverage_by_year.csv` | Agencies with data in each source, by year. |
| `fe_linkage.csv` | How many qualifying FE deaths link to a panel agency. |
| `mpv_linkage.csv` | MPV snapshot used, gunshot deaths kept, off-duty, and deaths with no recoverable ORI. |
| `shr_linkage.csv` | SHR records read, exact duplicates dropped, police-killing records, non-firearm records dropped, and people counted. |
| `mpv_ori_resolution.csv` | How each MPV agency mention got its ORI (MPV's own code, an alias, a name match, or a hand decision). |
| `fe_top_unmatched_names.csv` | The 200 FE agency names with the most deaths that are not linked. Use these to extend the crosswalk. |

`output/fe_review/` holds the crosswalk's review queue: unresolved match candidates, hand-built agencies with no FE match, and names the matching layers disagree on. All three are empty in the current build.
