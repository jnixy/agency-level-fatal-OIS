# ==============================================================================
# Agency-level fatal OIS: run the full pipeline
# ==============================================================================
#
# Author:   Justin Nix (with Claude Code)
#
# Purpose:
#   Run scripts 01-06 in order, each in a fresh environment so no script can
#   depend on another's leftover objects.
#
# Inputs:   raw files described in data/README.md (the LEAIC must be
#           downloaded from ICPSR separately)
# Outputs:  data/clean/, output/ (see each script's header)
#
# Usage (from the project root):  Rscript scripts/00_run_all.R
# Runtime: ~1 min
# ==============================================================================

library(here)

steps <- c("01_nix_long.R", "02_wapo.R", "03_fe_crosswalk.R",
           "04_fe.R", "05_combine.R", "06_figures.R")

for (s in steps) {
  message("== ", s)
  source(here("scripts", s), local = new.env())
}
