# ---------------------------------------------------------------------------
# models.R — the model "contract" and the two baseline models.
#
# THE CONTRACT (every model, baseline or real, must follow it):
#   * A model is an R object saved as models/<river>_<horizon>.rds
#   * It has a class, and there is a make_forecast() method for that class:
#
#       make_forecast(model, obs, issue_date, target_dates)
#
#       obs          = observed flow for this river, ONLY dates < issue_date
#                      (the "as-of" rule: nothing from the future)
#       issue_date   = the day the forecast is made
#       target_dates = the dates to predict
#
#     and returns a data.frame with columns:
#       target_date, pred, lo, hi      (cfs; lo/hi = 10th/90th percentile)
#
#   * When you build a real model (e.g. random forest), give it a class like
#     "sf_rf", write make_forecast.sf_rf(), save it with the same file name,
#     and the nightly pipeline picks it up with no other changes.
#     Real models will also need features (SWE, weather) - add those as extra
#     arguments with defaults so the baselines keep working.
# ---------------------------------------------------------------------------

make_forecast <- function(model, obs, issue_date, target_dates, ...) {
  UseMethod("make_forecast")
}

# Day of year on a 365-day calendar (Feb 29 is folded into Feb 28)
doy365 <- function(d) {
  d   <- as.Date(d)
  doy <- as.integer(format(d, "%j"))
  yr  <- as.integer(format(d, "%Y"))
  leap <- (yr %% 4 == 0 & yr %% 100 != 0) | yr %% 400 == 0
  after_feb <- as.integer(format(d, "%m")) > 2
  doy[leap & after_feb] <- doy[leap & after_feb] - 1L
  doy[leap & format(d, "%m-%d") == "02-29"] <- 59L
  doy
}

# ---------------------------------------------------------------------------
# Baseline 1: CLIMATOLOGY
# "Flow on this day of the year is typically X."
# Median and 10th/90th percentiles of all flows within +/- `window` days of
# each day-of-year, using only years before `cutoff`.
# ---------------------------------------------------------------------------
fit_climatology <- function(obs, cutoff, window = 7, min_years = 3) {
  obs <- obs[obs$date < cutoff & !is.na(obs$flow_cfs), ]
  obs$doy  <- doy365(obs$date)
  obs$year <- as.integer(format(obs$date, "%Y"))

  tab <- lapply(1:365, function(d) {
    dist <- abs(obs$doy - d)
    dist <- pmin(dist, 365 - dist)                  # wrap around New Year
    v <- obs[dist <= window, ]
    n_years <- length(unique(v$year))
    if (n_years < min_years) {
      return(data.frame(doy = d, pred = NA_real_, lo = NA_real_, hi = NA_real_, n_years = n_years))
    }
    q <- quantile(v$flow_cfs, c(0.5, 0.1, 0.9), names = FALSE)
    data.frame(doy = d, pred = q[1], lo = q[2], hi = q[3], n_years = n_years)
  })

  structure(
    list(table = do.call(rbind, tab), window = window, cutoff = cutoff),
    class = c("sf_climatology", "sf_model")
  )
}

make_forecast.sf_climatology <- function(model, obs, issue_date, target_dates, ...) {
  idx <- match(doy365(target_dates), model$table$doy)
  data.frame(
    target_date = target_dates,
    pred = model$table$pred[idx],
    lo   = model$table$lo[idx],
    hi   = model$table$hi[idx]
  )
}

# ---------------------------------------------------------------------------
# Baseline 2: PERSISTENCE (used for the < 1 week horizon)
# "Flow in the next few days will be about what it is now."
# Prediction = latest observed flow. The band comes from how much flow has
# historically changed over the same number of days (10th/90th pct of ratios).
# ---------------------------------------------------------------------------
fit_persistence <- function(obs, cutoff, max_gap = 14) {
  obs <- obs[obs$date < cutoff & !is.na(obs$flow_cfs), ]
  obs <- obs[order(obs$date), ]
  f <- setNames(pmax(obs$flow_cfs, 0.1), as.character(obs$date))  # avoid log(0)

  ratios <- lapply(1:(max_gap + 6), function(L) {
    later <- as.character(obs$date + L)
    ok <- later %in% names(f)
    r <- log(f[later[ok]] / f[ok])
    q <- quantile(r, c(0.1, 0.9), names = FALSE, na.rm = TRUE)
    data.frame(lead = L, q10 = q[1], q90 = q[2])
  })

  structure(
    list(ratios = do.call(rbind, ratios), max_gap = max_gap, cutoff = cutoff),
    class = c("sf_persistence", "sf_model")
  )
}

make_forecast.sf_persistence <- function(model, obs, issue_date, target_dates, ...) {
  obs  <- obs[obs$date < issue_date & !is.na(obs$flow_cfs), ]
  last <- obs[which.max(obs$date), ]
  out  <- data.frame(target_date = target_dates, pred = NA_real_, lo = NA_real_, hi = NA_real_)

  # No recent data (e.g. seasonal gauge in winter) -> no forecast
  if (nrow(last) == 0 || as.numeric(issue_date - last$date) > model$max_gap) return(out)

  lead_from_obs <- as.integer(target_dates - last$date)
  idx <- match(lead_from_obs, model$ratios$lead)
  out$pred <- last$flow_cfs
  out$lo   <- last$flow_cfs * exp(model$ratios$q10[idx])
  out$hi   <- last$flow_cfs * exp(model$ratios$q90[idx])
  out
}
