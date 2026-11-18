# ---------------------------------------------------------------------------
# train_baseline.R — fit the placeholder models and save them to models/.
#
# Run this on your laptop (NOT nightly) from the repo root:
#   Rscript training/train_baseline.R
# then commit + push the models/ folder.
#
# Writes 20 files: models/<river>_<horizon>.rds
#   lt1wk          -> persistence
#   all other bins -> climatology
# When a real model beats the baseline for a river/horizon, just overwrite
# that one file (see the contract in R/models.R).
# ---------------------------------------------------------------------------
source("R/config.R")
source("R/io.R")
source("R/models.R")

MODEL_VERSION <- "baseline_v1"
cutoff <- today_local()   # train on everything observed before today

obs_all <- read_observed()
dir.create(DIR_MODELS, showWarnings = FALSE)

for (r in GAUGES$river) {
  obs <- obs_all[obs_all$river == r, ]
  clim <- fit_climatology(obs, cutoff)
  pers <- fit_persistence(obs, cutoff)

  for (h in HORIZONS$horizon) {
    m <- if (h == "lt1wk") pers else clim
    m$river   <- r
    m$horizon <- h
    m$version <- MODEL_VERSION
    m$trained <- Sys.time()
    saveRDS(m, file.path(DIR_MODELS, sprintf("%s_%s.rds", r, h)))
  }
  message(sprintf("[%s] saved %d models (climatology covers %d of 365 days)",
                  r, nrow(HORIZONS), sum(!is.na(clim$table$pred))))
}
