# Colorado Stream Flow Predictor

Daily flow forecasts (1–365 days out) for four rivers near Vail, CO, shown in a Shiny app.

| River | USGS gauge | Record in repo | Season |
|---|---|---|---|
| Gore Creek above Red Sandstone Cr. at Vail | 09066325 | Oct 1999 → | year-round |
| Eagle River below WWTP at Avon | 09067020 | Oct 1999 → | year-round |
| Colorado River at Catamount Bridge | 09060799 | Oct 2016 → | ~Mar 15 – Nov 15 |
| Arkansas River below Granite | 07087050 | 1999 → | Apr 1 – Sep 30 |

## How the data flows

```
USGS Water Data API
      │   every morning, GitHub Actions (.github/workflows/nightly.yml)
      ▼
R/ingest_usgs.R   → data/raw/usgs/<river>/<year>.parquet
      ▼
R/predict.R       → loads models/<river>_<horizon>.rds
                  → data/forecasts/<issue_date>.parquet   (permanent archive)
                  → data/app/*.parquet                     (what the app reads)
      ▼
app/app.R  (Posit Connect Cloud) downloads data/app/ files from this repo
```

The app never calls USGS or runs models. It only reads the files above,
so new forecasts appear every morning without redeploying the app.

Model **training** is separate: it runs on your laptop (`training/`), and you commit the resulting `.rds` files.

## Folders

| Path | What's in it | Who writes it |
|---|---|---|
| `R/config.R` | gauges, horizons, folder names (edit here first) | you |
| `R/models.R` | the model contract + baseline models | you |
| `R/ingest_usgs.R` | downloads daily mean flow | — |
| `R/predict.R` | runs every model, writes forecasts | — |
| `training/` | scripts that fit models (run locally) | you |
| `models/` | saved models, `<river>_<horizon>.rds` | you (via training) |
| `data/raw/usgs/` | observed flow, one file per river per year | nightly job |
| `data/forecasts/` | one file per night, never overwritten | nightly job |
| `data/app/` | small files the app downloads | nightly job |
| `app/` | the Shiny app + `manifest.json` for deployment | you |

## Forecast horizons

| Horizon | Lead days | Current (baseline) model |
|---|---|---|
| `lt1wk` | 1–6 | persistence (latest flow, with historical change range) |
| `1wk_1mo` | 7–29 | climatology (day-of-year median, ±7-day window) |
| `1_3mo` | 30–89 | climatology |
| `3_6mo` | 90–179 | climatology |
| `gt6mo` | 180–365 | climatology |

These are placeholders, and they're also the baselines your real models have to beat.
Forecasts are only written for days of the year a gauge has reported in at least 3 past years, so seasonal gauges get no winter forecasts.

## Adding a real model

1. Read the contract at the top of `R/models.R`.
2. Fit your model in a script in `training/`. Give it a class (e.g. `"sf_rf"`)
   and write a `make_forecast.sf_rf()` method in `R/models.R`.
3. Save it over the baseline file, e.g. `models/gore_1wk_1mo.rds`.
4. Commit and push. The next nightly run uses it, and `model_version` shows up in the app.

**As-of rule:** a model may only use data from *before* the issue date. Train on
lagged features that match what's available when the forecast is made.

## Running locally (RStudio)

Open `co-streamflow-forecast.Rproj`, then in the console:

```r
install.packages(c("dataRetrieval", "arrow", "dplyr", "shiny", "bslib", "plotly"))
source("R/ingest_usgs.R")          # update data
source("training/train_baseline.R")  # (re)fit baselines
source("R/predict.R")              # make today's forecast
shiny::runApp("app")               # view it (reads your local data)
```

## One-time setup

1. **USGS API key (optional, recommended):** sign up at https://api.waterdata.usgs.gov/signup/.
   In GitHub, go to **Settings → Secrets and variables → Actions → New repository secret**, name it `API_USGS_PAT`, and paste the key.
   For local runs, add `API_USGS_PAT=yourkey` to your `.Renviron` (`usethis::edit_r_environ()`).
2. **Check the nightly job:** go to the **Actions** tab → *Nightly forecast* → **Run workflow**. It should go green and commit new files to `data/`.
3. **Deploy the app:** at https://connect.posit.cloud, sign in with GitHub → **Publish** → **Shiny** →
   pick this repo, branch `main`, primary file `app/app.R`. If you edit `app.R` or add packages to the app, regenerate the manifest first:
   `rsconnect::writeManifest("app")`.

Note: GitHub pauses scheduled workflows in repos with no activity for 60 days. The nightly commits count as activity, but if the job ever stops, re-enable it in the Actions tab.
