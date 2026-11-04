# Codebook

## `output/agency_year_panel.csv`

One row per agency-year. The panel is deliberately **unbalanced**: an agency has rows only for the years at least one source covers it. A missing row means no source covers that agency-year, not zero deaths. Don't `complete()` the panel and fill in zeros.

| Variable | Type | Description |
|---|---|---|
| `agency_id` | string | ORI7 when the agency has one. Otherwise the hand-built slug (only `utah_doc`). Unique together with `year`. |
| `ori7` | string | 7-character FBI ORI. The first 7 characters of the LEAIC ORI9. Nebraska ORIs begin "NB". |
| `agency_name` | string | Agency name. From the WaPo agency file where available, otherwise the LEAIC 2012. Agencies that share an ORI list both names, separated by " / ". |
| `state` | string | Two-letter postal code, taken from the ORI. |
| `agency_type` | string | For hand-built agencies: `local_police`, `sheriff`, `state`, `special`, or `constable` (from the LEAIC). For WaPo-only agencies: WaPo's own type labels. |
| `in_nix` | logical | TRUE if the agency has a hand-built series. |
| `slugs` | string | Column name(s) in `agency-level-fatal-ois.csv`, separated by ";". Two agencies have two slugs each: Savannah and Macon-Bibb. |
| `wapo_multi_ori` | logical | TRUE if WaPo lists this agency under several ORIs (state police, highway patrols, some federal agencies). All its WaPo deaths are assigned to this one ORI, so it is left out of the source-agreement comparisons. |
| `year` | integer | Calendar year of death, 1969–2024. |
| `n_nix` | number | People shot and killed by the agency's on-duty officers, from the hand-built sources (see README). NA means no data. Some series include nonfatal shootings; see README caveats. |
| `nix_partial` | logical | For agencies with two slugs: TRUE if only one of them has data that year. FALSE for every hand-built row in the current data. |
| `n_wapo` | integer | *Washington Post* Fatal Force deaths, 2015–2024. 0 for any ORI-coded agency WaPo did not record in a year. NA outside 2015–2024. |
| `n_fe` | integer | Fatal Encounters deaths, 2000–2021: deaths coded "Gunshot" with intended force "Deadly force". Excludes deaths that FE's disposition field codes as "Murder/suicide", "Accidental", or "Ruled suicide"; "Ruled suicide by police" (suicide-by-cop) is kept. NA if the agency was never linked to FE, or outside 2000–2021. See the notes below. |
| `n_fe_multi` | integer | How many of `n_fe` list more than one agency in FE. Counted before linking, so a partner agency outside the panel still makes a death "shared". |
| `n_fe_flagged` | integer | How many of `n_fe` have an FE description mentioning a self-inflicted, accidental, or off-duty shooting (pattern in `scripts/functions.R`, `FE_FLAG_PATTERN`). These deaths may not be intentional on-duty police shootings. The keyword search also catches legitimate cases, so they are flagged, not dropped. `n_fe - n_fe_flagged` gives a conservative count. |

**Counting rules**
- In both WaPo and FE, a death involving several agencies counts once for each agency listed. Summing `n_wapo` or `n_fe` across agencies therefore overcounts.
- Within one agency, a death counts once, even if two spellings of that agency appear in the same record.

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
| `source_agreement.csv` | Pairwise comparison of the series over overlapping agency-years. Columns: correlation, total-deaths difference (%), mean absolute difference, share of agency-years with identical counts (all, and where either source > 0). Each comparison is also restricted to the common support, 2015–2021, where all three sources are observed. |
| `source_disagreements.csv` | Agency-level totals over each pair's overlap where the sources differ, largest gap first. |
| `coverage_by_year.csv` | Agencies with data in each source, by year. |
| `fe_linkage.csv` | How many qualifying FE deaths link to a panel agency. |
| `fe_top_unmatched_names.csv` | The 200 FE agency names with the most deaths that are not linked. Use these to extend the crosswalk. |

`output/fe_review/` holds the crosswalk's review queue: unresolved match candidates, hand-built agencies with no FE match, and names the matching layers disagree on. All three are empty in the current build.
