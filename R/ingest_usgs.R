# ---------------------------------------------------------------------------
# ingest_usgs.R — download daily mean discharge for the 4 gauges.
#
# First run (no data on disk): pulls the full period of record.
# Later runs: re-pulls the last REFRESH_DAYS days and merges them in, so
# USGS revisions to provisional data are picked up.
#
# Uses the NEW USGS Water Data API via dataRetrieval::read_waterdata_daily().
# (The old readNWISdv() / waterservices.usgs.gov is retired in early 2027.)
#
# Optional: set API_USGS_PAT (free key from https://api.waterdata.usgs.gov/signup/)
# to get higher rate limits. In GitHub Actions it comes from a repo secret.
#
# Run from the repo root:  Rscript R/ingest_usgs.R
# ---------------------------------------------------------------------------
source("R/config.R")
source("R/io.R")
suppressPackageStartupMessages(library(dataRetrieval))

fetch_daily <- function(site_id, start, end) {
  x <- read_waterdata_daily(
    monitoring_location_id = site_id,
    parameter_code = USGS_PARAM,
    statistic_id   = USGS_STAT,
    time           = c(format(start), format(end)),
    skipGeometry   = TRUE
  )
  if (is.null(x) || nrow(x) == 0) return(NULL)
  data.frame(
    date            = as.Date(x$time),
    flow_cfs        = as.numeric(x$value),
    approval_status = as.character(x$approval_status),
    qualifier       = as.character(x$qualifier),
    stringsAsFactors = FALSE
  )
}

today <- today_local()

for (i in seq_len(nrow(GAUGES))) {
  g <- GAUGES[i, ]
  existing <- read_observed(g$river)

  if (is.null(existing)) {
    start <- as.Date("1900-01-01")
    message(sprintf("[%s] no local data - downloading full record", g$river))
  } else {
    start <- max(existing$date) - REFRESH_DAYS
    message(sprintf("[%s] refreshing from %s", g$river, start))
  }

  new <- tryCatch(fetch_daily(g$site_id, start, today), error = function(e) {
    message(sprintf("[%s] DOWNLOAD FAILED: %s", g$river, conditionMessage(e)))
    NULL
  })
  if (is.null(new)) next

  new$river   <- g$river
  new$site_id <- g$site_id
  new <- new[!is.na(new$flow_cfs), c("river", "site_id", "date", "flow_cfs", "approval_status", "qualifier")]

  # New rows replace any existing rows for the same dates
  combined <- if (is.null(existing)) new else
    bind_rows(filter(existing, !date %in% new$date), new)
  combined <- arrange(combined, date)

  n <- write_observed_years(combined, g$river)
  message(sprintf("[%s] %d rows (%s to %s); %d year-file(s) updated",
                  g$river, nrow(combined), min(combined$date), max(combined$date), n))
}
