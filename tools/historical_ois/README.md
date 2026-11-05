# Historical OIS scouting

These tools look for agency counts of people shot and killed by police in the years before each hand-built series begins. They replace the January 2026 tools in `tools/data_source_scouting/archive/`. Those tools guessed city homepages, often for the wrong city. They then scanned only one page per site, and their keyword match let "ois" hit "noise".

## Workflow

1. **Rank the targets.**
   - Run `Rscript tools/historical_ois/rank_targets.R`.
   - It writes `output/tables/historical_targets.csv`, which scores each agency as WaPo deaths × the years between 1980 and the start of its series.
2. **List the agency's domains.**
   - Add the agency's current and old web domains to `agency_domains.csv`.
   - Before about 2005, city sites mostly lived at `ci.<city>.<st>.us`.
3. **Search the Wayback Machine.**
   - Run `python tools/historical_ois/wayback_find.py --slugs <slug>`.
   - It queries the archive's CDX API and writes report-like archived URLs to `output/tables/wayback_candidates.csv`.
4. **Download and read.**
   - Save the documents to a local folder outside the repo.
   - Extract their text, then read the passages that mention shootings.
5. **Log every count** in `data/historical/historical_ois_evidence.csv` with:
   - the unit (people or incidents) and the scope;
   - the source URL and SHA-256;
   - the page number and a verbatim quote.

   Only rows with `unit = people` and a fatal scope are candidates for the panel. Counts of incidents, or of everyone shot, are logged but kept out.
