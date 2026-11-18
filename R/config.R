# ---------------------------------------------------------------------------
# config.R — one place for everything the pipeline needs to know.
# Every other script starts with source("R/config.R").
# ---------------------------------------------------------------------------

# The four gauges. `river` is the short name used in file names everywhere.
GAUGES <- data.frame(
  river   = c("gore", "eagle", "colorado", "arkansas"),
  site_id = c("USGS-09066325", "USGS-09067020", "USGS-09060799", "USGS-07087050"),
  label   = c(
    "Gore Creek above Red Sandstone Creek at Vail",
    "Eagle River below WWTP at Avon",
    "Colorado River at Catamount Bridge",
    "Arkansas River below Granite"
  ),
  stringsAsFactors = FALSE
)

# Forecast horizons, in days ahead of the issue date (inclusive ranges).
# Each river gets one model per horizon: models/<river>_<horizon>.rds
HORIZONS <- data.frame(
  horizon  = c("lt1wk", "1wk_1mo", "1_3mo", "3_6mo", "gt6mo"),
  min_lead = c(1, 7, 30, 90, 180),
  max_lead = c(6, 29, 89, 179, 365),
  stringsAsFactors = FALSE
)

MAX_LEAD <- max(HORIZONS$max_lead)

# USGS codes: 00060 = discharge (cfs), 00003 = daily mean
USGS_PARAM <- "00060"
USGS_STAT  <- "00003"

# How many recent days to re-download each night. USGS revises provisional
# data, so we refresh this window instead of only grabbing "yesterday".
REFRESH_DAYS <- 60

# Folders
DIR_RAW_USGS  <- "data/raw/usgs"
DIR_FORECASTS <- "data/forecasts"
DIR_APP       <- "data/app"
DIR_MODELS    <- "models"

# Forecasts are issued on the Colorado calendar day.
LOCAL_TZ <- "America/Denver"
today_local <- function() as.Date(format(Sys.time(), tz = LOCAL_TZ))

# Map a lead time (days) to its horizon name
lead_to_horizon <- function(lead) {
  out <- rep(NA_character_, length(lead))
  for (i in seq_len(nrow(HORIZONS))) {
    hit <- lead >= HORIZONS$min_lead[i] & lead <= HORIZONS$max_lead[i]
    out[hit] <- HORIZONS$horizon[i]
  }
  out
}
