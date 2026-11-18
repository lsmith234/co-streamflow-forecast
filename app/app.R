# ---------------------------------------------------------------------------
# Colorado Stream Flow Predictor — Shiny app
#
# The app is "dumb" on purpose: it never calls USGS or runs a model.
# It just reads the small files the nightly job writes to data/app/.
#
# Where it reads from:
#   * Deployed (Posit Connect Cloud): straight from the public GitHub repo,
#     so new forecasts show up every morning without redeploying the app.
#   * Running in RStudio: from your local copy of the repo (../data/app).
#     Force either with Sys.setenv(SF_DATA = "local") or "remote".
#
# Run locally from the repo root:  shiny::runApp("app")
# ---------------------------------------------------------------------------
library(shiny)
library(bslib)
library(plotly)
library(arrow)
library(dplyr)

REPO_RAW <- "https://raw.githubusercontent.com/lsmith234/co-streamflow-forecast/main/data/app/"
LOCAL_DIR <- "../data/app"

RIVERS <- c(
  "Gore Creek at Vail"                 = "gore",
  "Eagle River at Avon"                = "eagle",
  "Colorado River at Catamount Bridge" = "colorado",
  "Arkansas River below Granite"       = "arkansas"
)
SEASONAL_NOTE <- c(
  colorado = "This gauge only reports about Mar 15 – Nov 15.",
  arkansas = "This gauge only reports Apr 1 – Sep 30."
)

COL_OBS <- "#2a78d6"   # observed
COL_FC  <- "#eb6834"   # forecast

use_local <- function() {
  src <- Sys.getenv("SF_DATA", "")
  if (src == "local")  return(TRUE)
  if (src == "remote") return(FALSE)
  interactive() && file.exists(file.path(LOCAL_DIR, "latest_forecast.parquet"))
}

read_app_file <- function(name) {
  if (use_local()) return(read_parquet(file.path(LOCAL_DIR, name)))
  tmp <- tempfile(fileext = ".parquet")
  download.file(paste0(REPO_RAW, name), tmp, mode = "wb", quiet = TRUE)
  read_parquet(tmp)
}

# Cache data for an hour so every visitor doesn't trigger a download
cache <- new.env()
get_data <- function() {
  if (is.null(cache$loaded) || difftime(Sys.time(), cache$loaded, units = "mins") > 60) {
    cache$obs <- bind_rows(read_app_file("observed_archive.parquet"),
                           read_app_file("observed_current.parquet"))
    cache$fc  <- read_app_file("latest_forecast.parquet")
    cache$loaded <- Sys.time()
  }
  list(obs = cache$obs, fc = cache$fc)
}

fmt_cfs <- function(x) ifelse(is.na(x), "—", paste(format(round(x), big.mark = ","), "cfs"))

# ---------------------------------------------------------------------------
ui <- page_sidebar(
  title = "Colorado Stream Flow Predictor",
  theme = bs_theme(version = 5, bg = "#fcfcfb", fg = "#0b0b0b", primary = COL_OBS,
                   base_font = font_google("Inter", local = FALSE)),
  sidebar = sidebar(
    width = 300,
    selectInput("river", "River", RIVERS),
    dateRangeInput("window", "Dates to show", start = Sys.Date() - 60, end = Sys.Date() + 60),
    div(
      class = "d-flex flex-wrap gap-1",
      actionButton("w_week",   "Next week",     class = "btn-sm btn-outline-secondary"),
      actionButton("w_month",  "Next month",    class = "btn-sm btn-outline-secondary"),
      actionButton("w_season", "Next 6 months", class = "btn-sm btn-outline-secondary"),
      actionButton("w_year",   "Next year",     class = "btn-sm btn-outline-secondary"),
      actionButton("w_hist",   "Last 5 years",  class = "btn-sm btn-outline-secondary")
    ),
    checkboxInput("band", "Show forecast range (10th–90th pct)", TRUE),
    hr(),
    uiOutput("about")
  ),
  layout_columns(
    fill = FALSE,
    value_box("Latest observed", uiOutput("vb_obs")),
    value_box("Forecast: 7 days out", uiOutput("vb_7")),
    value_box("Forecast: 30 days out", uiOutput("vb_30"))
  ),
  card(
    full_screen = TRUE,
    card_header(textOutput("chart_title")),
    plotlyOutput("chart", height = "100%"),
    card_footer(uiOutput("season_note"))
  )
)

# ---------------------------------------------------------------------------
server <- function(input, output, session) {
  d <- get_data()
  issue <- max(d$fc$issue_date)

  set_window <- function(start, end) updateDateRangeInput(session, "window", start = start, end = end)
  observeEvent(TRUE, set_window(issue - 60, issue + 60), once = TRUE)
  observeEvent(input$w_week,   set_window(issue - 14, issue + 7))
  observeEvent(input$w_month,  set_window(issue - 30, issue + 30))
  observeEvent(input$w_season, set_window(issue - 30, issue + 183))
  observeEvent(input$w_year,   set_window(issue - 30, issue + 365))
  observeEvent(input$w_hist,   set_window(issue - 5 * 365, issue + 30))

  obs_r <- reactive(filter(d$obs, river == input$river))
  fc_r  <- reactive(filter(d$fc,  river == input$river))

  output$chart_title <- renderText(names(RIVERS)[RIVERS == input$river])

  output$vb_obs <- renderUI({
    o <- obs_r(); last <- o[which.max(o$date), ]
    tagList(fmt_cfs(last$flow_cfs), tags$small(class = "d-block text-muted", format(last$date, "%b %d, %Y")))
  })
  fc_at <- function(lead) {
    f <- filter(fc_r(), lead_days == lead)
    if (nrow(f) == 0) return(tagList("Off-season"))
    tagList(fmt_cfs(f$pred), tags$small(class = "d-block text-muted",
            sprintf("range %s – %s", round(f$lo), round(f$hi))))
  }
  output$vb_7  <- renderUI(fc_at(7))
  output$vb_30 <- renderUI(fc_at(30))

  output$season_note <- renderUI({
    note <- SEASONAL_NOTE[input$river]
    tags$small(class = "text-muted",
      sprintf("Forecast issued %s. ", format(issue, "%b %d, %Y")),
      if (!is.na(note)) note)
  })

  output$about <- renderUI({
    v <- unique(fc_r()$model_version)
    tags$small(class = "text-muted",
      "Observed: USGS daily mean discharge. ",
      "Forecast model: ", paste(v, collapse = ", "),
      if (any(grepl("baseline", v)))
        " (placeholder — persistence for < 1 week, historical day-of-year median beyond).")
  })

  output$chart <- renderPlotly({
    rng <- input$window
    req(rng[1] < rng[2])

    # Fill in missing dates with NA so off-season gaps show as gaps
    o <- obs_r() |> filter(date >= rng[1], date <= rng[2])
    if (nrow(o) > 0) {
      o <- data.frame(date = seq(min(o$date), max(o$date), by = "day")) |>
        left_join(o, by = "date")
    }
    f <- fc_r() |> filter(target_date >= rng[1], target_date <= rng[2])
    if (nrow(f) > 0) {
      f <- data.frame(target_date = seq(min(f$target_date), max(f$target_date), by = "day")) |>
        left_join(f, by = "target_date")
    }

    p <- plot_ly()
    if (nrow(f) > 0 && isTRUE(input$band)) {
      p <- p |>
        add_ribbons(data = f, x = ~target_date, ymin = ~lo, ymax = ~hi,
                    name = "Forecast range", line = list(width = 0),
                    fillcolor = "rgba(235,104,52,0.18)",
                    hovertemplate = "Range: %{y:,.0f}<extra></extra>")
    }
    if (nrow(f) > 0) {
      p <- p |>
        add_lines(data = f, x = ~target_date, y = ~pred, name = "Forecast",
                  line = list(color = COL_FC, width = 2, dash = "dash"),
                  hovertemplate = "Forecast: %{y:,.0f} cfs<extra></extra>")
    }
    if (nrow(o) > 0) {
      p <- p |>
        add_lines(data = o, x = ~date, y = ~flow_cfs, name = "Observed",
                  line = list(color = COL_OBS, width = 2),
                  hovertemplate = "Observed: %{y:,.0f} cfs<extra></extra>")
    }

    show_issue <- issue >= rng[1] && issue <= rng[2]
    p |>
      layout(
        hovermode = "x unified",
        paper_bgcolor = "#fcfcfb", plot_bgcolor = "#fcfcfb",
        font = list(color = "#52514e"),
        xaxis = list(title = "", gridcolor = "#ecebe7", range = rng),
        yaxis = list(title = "Flow (cfs)", gridcolor = "#ecebe7", rangemode = "tozero"),
        legend = list(orientation = "h", y = 1.08, x = 0),
        margin = list(t = 30),
        shapes = if (show_issue) list(list(
          type = "line", x0 = issue, x1 = issue, yref = "paper", y0 = 0, y1 = 1,
          line = list(color = "#9b9a95", width = 1, dash = "dot"))),
        annotations = if (show_issue) list(list(
          x = issue, y = 1, yref = "paper", text = "Today", showarrow = FALSE,
          xanchor = "left", yanchor = "top", font = list(size = 11, color = "#52514e")))
      ) |>
      config(displaylogo = FALSE, modeBarButtonsToRemove = c("lasso2d", "select2d"))
  })
}

shinyApp(ui, server)
