# agency-level-fatal-OIS

Annual counts of people shot and killed by on-duty police, by agency, going back as far as I can find them. The hand-built series start in 1969 for Chicago and cover 414 agencies. They sit side by side with two national databases, [*The Washington Post*'s Fatal Force](https://github.com/washingtonpost/data-police-shootings) (2015–2024) and [Fatal Encounters](https://fatalencounters.org/) (2000–2021). Every series is keyed to the agency's FBI ORI code.

**If you just want the data:**

- [`output/agency_year_panel.csv`](output/agency_year_panel.csv) is the merged file: one row per agency-year, 3,648 agencies, 1969–2024. Variables are documented in [`CODEBOOK.md`](CODEBOOK.md).
- [`agency-level-fatal-ois.csv`](agency-level-fatal-ois.csv) is the original hand-built file: wide, one column per agency. It keeps the same path and format it has always had.

## November 2026 update

- **Fatal Encounters merged.** FE identifies agencies only by name, so linking it took a name → ORI crosswalk. That crosswalk is rebuilt from scratch on every run. Every match comes from one of three places:
  - a hand-checked seed;
  - an exact match on normalized name + state + agency type, accepted only when no other agency in the state (among every agency in the LEAIC and WaPo) has the same name;
  - a hand decision, with a note, recorded in [`data/crosswalks/fe_crosswalk_decisions.csv`](data/crosswalks/fe_crosswalk_decisions.csv).

  Of 18,838 FE fatal police shootings from 2000 to 2021, 16,763 (89%) link to an agency in the panel.
- **The WaPo merge was rebuilt.** Changes:
  - It reads local, checksummed copies of the archived v2 data instead of live URLs.
  - It handles agencies that WaPo lists under several ORIs. The old merge silently missed 96 of them.
  - It writes the merged file to disk.
- **Agency key fixes.**
  - Five wrong ORI codes corrected: Forsyth Co. SO, Macon-Bibb Co. SO, Richmond Co. SO, and Gwinnett Co. PD (all GA), plus Louisville Metro PD.
  - Missing ORIs filled in for Orange Co. SD (CA), Arlington Co. PD (VA), and two small Minnesota departments.
  - Every fix was confirmed by year-by-year agreement with WaPo or from the LEAIC. The reasons are recorded in [`data/agency_key.csv`](data/agency_key.csv).
- **Two pairs of columns now share an ORI** and are summed in the panel: Savannah PD and Savannah-Chatham Metro PD, and Bibb Co. SO and Macon-Bibb Co. SO. That's why 416 columns become 414 agencies.

## How the sources compare

Where they overlap, the three sources mostly agree, though FE runs higher than WaPo:

| Comparison | Years | Agency-years | Correlation | Total deaths, difference | Identical counts | Identical, where either > 0 |
|---|---|---:|---:|---:|---:|---:|
| Hand-built vs. WaPo | 2015–2022 | 2,641 | .945 | WaPo −4.0% | 95.2% | 86.8% |
| Hand-built vs. FE | 2000–2021 | 5,559 | .902 | FE −0.9% | 91.2% | 69.4% |
| WaPo vs. FE (hand-built agencies) | 2015–2021 | 2,870 | .972 | FE +9.4% | 90.1% | 71.2% |

Most agency-years are zero in both sources, so the last column, which drops agency-years where both are zero, is the tougher test. Agencies that WaPo lists under several ORIs (mostly state police) are left out of these comparisons. [`output/tables/source_agreement.csv`](output/tables/source_agreement.csv) also has each comparison restricted to the years all three sources cover (2015–2021). Agencies where the sources disagree are listed, largest gap first, in [`output/tables/source_disagreements.csv`](output/tables/source_disagreements.csv).

![Sixteen large cities, three sources](output/figures/sixteen_cities.png)

## Coverage

| Decade | Agencies with hand-built data | WaPo | FE |
|---|---:|---:|---:|
| 1969 | 1 (Chicago) | — | — |
| 1970s | 4–15 | — | — |
| 1980s | 12–14 | — | — |
| 1990s | 9–17 | — | — |
| 2000s | 110–169 | — | 2,971 |
| 2010s | 360–369 | 3,647 (2015+) | 2,971 |
| 2020s | 225–368 (through 2022) | 3,647 (through 2024) | 2,971 (through 2021) |

The WaPo and FE columns count agencies with an ORI. WaPo is a national census, so every ORI-coded agency gets a WaPo count, a zero where WaPo recorded no deaths. The FE column counts linked agencies only.

## Background

I'm building a database of fatal officer-involved shootings at the agency-year level, going back in time as far as possible. [This article in *The Lancet*](https://t.co/zDLTHrysAv) suggests police are killing more people today than they did in the 1980s, but [I remain skeptical](https://twitter.com/jnixy/status/1635677916762886149). So I'm compiling annual counts of people shot and killed by on-duty officers for as many agencies as I can.

I started with this excellent book:

- William A. Geller & Michael S. Scott (1992). *Deadly Force: What We Know.* Police Executive Research Forum.

It contains yearly counts of fatal and nonfatal police shootings for the following agencies:

| Agency | Years included |
|---|:---:|
| Chicago | 1974–91 |
| Dallas | 1970–91 |
| Philadelphia | 1986–91 |
| NYPD | 1970–91 |
| LAPD | 1980–91 |
| Houston | 1980–91 |
| Atlanta | 1980–91 |
| St. Louis | 1984–91 |
| San Diego | 1980–91 |
| Indianapolis | 1970–91 |
| Kansas City, MO | 1972–91 |

I decided, for now at least, to focus on fatal shootings, since they're more reliably reported. From there, I gathered more recent data from the sources below. I started with the largest 100 or so agencies, but added others, regardless of size, as I came across them.

| Source | Years included | Coverage |
|---|:---:|---|
| [Washington Post](https://github.com/washingtonpost/data-police-shootings) | 2015–2024 | Nationwide |
| [Fatal Encounters](https://fatalencounters.org/) | 2000–2021 | Nationwide (separate column; not used to fill gaps) |
| [Tampa Bay Times](https://projects.tampabay.com/projects/2017/investigations/florida-police-shootings/database/) | 2009–2014 | Florida |
| [Honolulu Civil Beat](https://cbmultimedia.pythonanywhere.com/) | 2010–2022 | Hawaii |
| [Salt Lake Tribune](http://local.sltrib.com/charts/shootings/policeshootings.html) | 2005–2014 | Utah |
| [Maine Attorney General's Office](https://www.pressherald.com/interactive/maine-police-deadly-force-lethal-database/) | 1990–2012 | Maine |
| [Atlanta Journal-Constitution](https://investigations.ajc.com/overtheline/database/) | 2010–2020 | Georgia |
| [Star Tribune](https://www.startribune.com/every-police-involved-death-in-minnesota-since-2000/502088871/) | 2000–2022 | Minnesota |
| [Vice News](https://news.vice.com/en_us/article/a3jjpa/nonfatal-police-shootings-data) | 2010–2016 | 50 largest local police departments |
| *The Texas Tribune's* ["Unholstered" data](https://apps.texastribune.org/unholstered/) | 2010–2015 | 36 largest cities in Texas |
| [Binder, Scharf, & Galvin (1983)](https://nij.ojp.gov/library/publications/use-deadly-force-police-officers-final-report) | 1976–1979 | Detroit, Honolulu, Newark, Oakland, San Diego, San Jose, St. Louis |
| *Washington Post* [story from 1998](https://www.washingtonpost.com/wp-srv/local/longterm/dcpolice/deadlyforce/police1page1.htm) | 1989–1997 | DC Metro PD |
| [NYPD](https://www.nyc.gov/site/nypd/stats/reports-analysis/use-of-force.page) | 1971–2022 | NYPD |
| [San Francisco PD](https://www.sanfranciscopolice.org/sites/default/files/2022-02/SFPDOISInvestigationsSheet20220215.pdf) | 2000–2022 | San Francisco PD |
| [Houston PD](https://www.houstontx.gov/police/ois/) | 2005–2022 | Houston PD |
| [Springfield (MO) PD](https://www.springfieldmo.gov/3755/Officer-Involved-Shootings) | 2008–2022 | Springfield (MO) PD |
| [Austin open data portal](https://data.austintexas.gov/Public-Safety/Officer-Involved-Shooting-2000-2014/63p6-iegi) | 2000–2014 | Austin PD |
| [Dallas open data portal](https://www.dallasopendata.com/Public-Safety/Dallas-Police-Officer-Involved-Shootings/4gmt-jyx2) | 2003–2022 | Dallas PD |
| [Cincinnati open data portal](https://data.cincinnati-oh.gov/Safety/PDI-Police-Data-Initiative-Officer-Involved-Shooti/r6q4-muts) | 1996–2019 | Cincinnati PD |
| [Vermont open data portal](https://data.vermont.gov/Public-Safety/Vermont-State-Police-Officer-Involved-Shootings-19/du86-kfnp) | 1977–2022 | Vermont State Police |
| [COPS Office report on LVMPD](https://cops.usdoj.gov/RIC/Publications/cops-p273-pub.pdf) | 1990–2011 | Las Vegas Metro PD |
| [ACLU report](https://www.aclusocal.org/sites/default/files/aclu_socal_report_on_apd_use_of_force_nov_2017.pdf) (Nov. 2017) | 2003–2016 | Anaheim PD |
| [Mike White](https://cvpcs.asu.edu/sites/default/files/content/projects/ER%20-%20external%20DF.pdf) | 1970–1992 | Philadelphia PD |
| [David Klinger](https://journals.sagepub.com/doi/10.1177/1088767911430861) | 1996–2008 | LAPD, LASD |
| [Report on police shootings in Alaska](https://scholarworks.alaska.edu/handle/11122/11933) | 2010–2020 | Anchorage PD |
| [SPD use-of-force report](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/seattlepd/UseofForce2000.PDF) | 1980–2001 | Seattle PD |
| [Denver independent monitor](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/denverpd/OIM/Annual+Reports/2006_Annual+Report.pdf) | 1996–2006 | Denver PD |
| Rojek, Nix, Wolfe, et al. (2019), [*Analysis of 2018 Use of Deadly Force by the Phoenix Police Department*](https://jnix.netlify.app/files/pdfs/report_pf_phx_ois.pdf), National Police Foundation | 2009–2018 | Phoenix PD |
| [Phoenix open data portal](https://www.phoenixopendata.com/dataset/ois) | 2017–2022 | Phoenix PD |

## Caveats

1. **Any mistakes are mine.** I did my best to make sure the data permit apples-to-apples comparisons. Each number *should* represent a person fatally shot by an on-duty officer. A few exceptions are known:
   - **Cincinnati before 2015 and all of LVMPD** count fatal and nonfatal shootings together (animal shootings excluded). That's why Cincinnati is the big outlier in [`output/figures/source_agreement.png`](output/figures/source_agreement.png).
   - **Austin 2000–2007** may be incident-level rather than person-level.
   - **Athens-Clarke 2019:** the hand-built count (5) equals WaPo's police department and sheriff's office combined. The AJC data may combine the two agencies.
2. **Blank is not zero** in the hand-built series. A blank means I have no data for that agency-year.
3. **How the national sources are counted:**
   - **WaPo zeros are real.** WaPo is a national census, so an ORI-coded agency with no WaPo record in 2015–2024 gets 0.
   - **FE zeros are real only for linked agencies.** For an agency linked to FE, 0 means no FE deaths that year. An agency never linked to FE is left NA, because a missed name match is not a zero.
   - **Pre-2013 FE is less reliable.** It was assembled after the fact from news reports, so treat the early years with more caution than WaPo.
4. **Multi-agency incidents.** In both WaPo and FE, a death involving several agencies counts once for each agency listed. `n_fe_multi` reports how many of an agency's FE deaths were shared. Don't sum `n_wapo` or `n_fe` across agencies and call it a national total.
5. **Agencies WaPo lists under several ORIs** (mostly state police and highway patrols) are each assigned one primary ORI and flagged `wapo_multi_ori`. WaPo also splits Georgia State Patrol into two records; both are assigned to GAGSP00 (see `scripts/02_wapo.R`).
6. **Mapping Police Violence** (2013+) is not merged yet.

## Reproducing the panel

Requires R (≥ 4.3) and the packages `tidyverse`, `here`, `janitor`, `digest`, and `scales`. From the project root:

```sh
Rscript scripts/00_run_all.R
```

| Script | What it does |
|---|---|
| `01_nix_long.R` | Reshapes the hand-built file to agency-year and attaches ORIs |
| `02_wapo.R` | Builds WaPo agency-year counts |
| `03_fe_crosswalk.R` | Builds the FE name → ORI crosswalk and writes the review queue to `output/fe_review/` |
| `04_fe.R` | Builds FE agency-year counts and the linkage table |
| `05_combine.R` | Builds the panel, the agreement and coverage tables |
| `06_figures.R` | Draws the figures |

The WaPo raw files are in the repo, with checksums. Two inputs are not, and you need both to rerun steps 03–04: the Fatal Encounters final release, which is linked rather than redistributed, and the Law Enforcement Agency Identifiers Crosswalk (ICPSR 35158), which ICPSR's terms don't let me redistribute. [`data/README.md`](data/README.md) says where to get each. The published outputs are already in the repo either way.

To add an FE match or correct one:
1. Check `output/fe_review/` for candidates, then add a row to `data/crosswalks/fe_crosswalk_decisions.csv`.
2. Rerun the pipeline.

## Contributing

Found an error, or a source I've missed? Open an issue. Thanks to [Ash Bruha](https://www.viprlab.org/author/ash-bruha/) of the [VIPR Lab](https://www.viprlab.org/) for the Seattle and Denver series (Nov. 2025).

`tools/data_source_scouting/` holds an experimental scraper that guesses agency websites and flags pages that may post use-of-force data. It produces leads, not data.

## Citation

See [`CITATION.cff`](CITATION.cff). Please also cite *The Washington Post* and Fatal Encounters if you use their series.

## Earlier updates

- **11.20.2025.** Ash Bruha found fatal OIS data for **Seattle PD**, 1980 through mid-2001, in [an SPD report](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/seattlepd/UseofForce2000.PDF). She also found data for **Denver PD**, 1996–2006, in an [independent monitor's report](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/denverpd/OIM/Annual+Reports/2006_Annual+Report.pdf).
- **1.4.2025.** First WaPo merge (see this [blog post](https://jnix.netlify.app/post/post27-historical-ois-update/)). It now lives in `scripts/02_wapo.R`.
