# ---------------------------------------------------------------------------
# predict.R — the nightly forecast step.
#
# 1. Loads each saved model (models/<river>_<horizon>.rds)
# 2. Forecasts every day from tomorrow to 365 days out
# 3. Writes data/forecasts/<issue_date>.parquet   (the permanent archive -
#    one new small file per night, never overwritten on later days)
# 4. Writes the small files the app reads, in data/app/
#
# Run from the repo root:  Rscript R/predict.R
# ---------------------------------------------------------------------------
source("R/config.R")
source("R/io.R")
source("R/models.R")

issue_date <- today_local()
obs_all <- read_observed()
if (is.null(obs_all)) stop("No observed data - run R/ingest_usgs.R first")

out <- list()
for (r in GAUGES$river) {
  # As-of rule: the model only sees data from before the issue date
  obs <- obs_all[obs_all$river == r & obs_all$date < issue_date, ]

  for (i in seq_len(nrow(HORIZONS))) {
    h <- HORIZONS[i, ]
    path <- file.path(DIR_MODELS, sprintf("%s_%s.rds", r, h$horizon))
    if (!file.exists(path)) stop("Missing model file: ", path)
    model <- readRDS(path)

    leads <- h$min_lead:h$max_lead
    fc <- make_forecast(model, obs, issue_date, issue_date + leads)
    fc$lead_days     <- leads
    fc$river         <- r
    fc$horizon       <- h$horizon
    fc$model_version <- if (is.null(model$version)) class(model)[1] else model$version
    out[[length(out) + 1]] <- fc
  }
}

# Seasonal gauges (Colorado at Catamount, Arkansas below Granite) only report
# part of the year. Only keep forecasts for days of the year that the gauge
# has reported in at least 3 past years.
in_season <- obs_all |>
  mutate(doy = doy365(date), year = format(date, "%Y")) |>
  distinct(river, doy, year) |>
  count(river, doy, name = "n_years") |>
  filter(n_years >= 3)

fc <- bind_rows(out) |>
  mutate(doy = doy365(target_date)) |>
  semi_join(in_season, by = c("river", "doy")) |>
  filter(!is.na(pred)) |>
  mutate(issue_date = issue_date,
         across(c(pred, lo, hi), ~ round(.x, 1))) |>
  select(issue_date, river, horizon, lead_days, target_date, pred, lo, hi, model_version) |>
  arrange(river, target_date)

# 1) Permanent archive: one file per issue date
dir.create(DIR_FORECASTS, recursive = TRUE, showWarnings = FALSE)
archive_path <- file.path(DIR_FORECASTS, paste0(issue_date, ".parquet"))
write_parquet(fc, archive_path)
message(sprintf("Wrote %d forecast rows to %s", nrow(fc), archive_path))

# 2) Small files the Shiny app downloads
dir.create(DIR_APP, recursive = TRUE, showWarnings = FALSE)
write_parquet(fc, file.path(DIR_APP, "latest_forecast.parquet"))

obs_app <- obs_all |> select(river, date, flow_cfs, approval_status)
this_year <- as.integer(format(issue_date, "%Y"))
yr <- as.integer(format(obs_app$date, "%Y"))
# Past years rarely change, so this file is only rewritten when it does
write_if_changed(obs_app[yr <  this_year, ], file.path(DIR_APP, "observed_archive.parquet"))
write_if_changed(obs_app[yr >= this_year, ], file.path(DIR_APP, "observed_current.parquet"))
message("Updated app data in ", DIR_APP)
