# ---------------------------------------------------------------------------
# io.R — small helpers for reading/writing the Parquet data store.
# ---------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

# Observed flow is stored one file per river per year:
#   data/raw/usgs/<river>/<year>.parquet
# so a nightly update only rewrites the current year's small file
# (keeps git history from bloating).

read_observed <- function(river = NULL) {
  rivers <- if (is.null(river)) list.dirs(DIR_RAW_USGS, full.names = FALSE, recursive = FALSE) else river
  files <- unlist(lapply(rivers, function(r) {
    list.files(file.path(DIR_RAW_USGS, r), pattern = "\\.parquet$", full.names = TRUE)
  }))
  if (length(files) == 0) return(NULL)
  bind_rows(lapply(files, read_parquet)) |> arrange(river, date)
}

# Write a data frame only if it differs from what's on disk.
# Unchanged files => no git diff => no commit noise.
write_if_changed <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    old <- as.data.frame(read_parquet(path))
    if (isTRUE(all.equal(old, as.data.frame(df), check.attributes = FALSE))) {
      return(invisible(FALSE))
    }
  }
  write_parquet(df, path)
  invisible(TRUE)
}

write_observed_years <- function(df, river) {
  df$year <- as.integer(format(df$date, "%Y"))
  n_written <- 0
  for (yr in sort(unique(df$year))) {
    chunk <- df[df$year == yr, setdiff(names(df), "year")]
    path <- file.path(DIR_RAW_USGS, river, paste0(yr, ".parquet"))
    if (write_if_changed(chunk, path)) n_written <- n_written + 1
  }
  n_written
}
