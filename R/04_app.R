# 04_app.R -----------------------------------------------------------------
# Shiny dashboard. Launch from the project root via app.sh (or see README).

library(tidyverse)
library(tidymodels)
library(ranger)
library(themis)
library(DALEX)
library(DALEXtra)
library(shiny)
library(bslib)
library(janitor)

if (!all(file.exists("models/churn_workflow.rds", "data/processed/train.rds"))) {
  stop("Model not found. Run R/01, R/02 first.", call. = FALSE)
}
churn_fit <- readRDS("models/churn_workflow.rds")
train <- readRDS("data/processed/train.rds")
predictors <- train |> select(-attrition_flag)

explainer <- explain_tidymodels(
  churn_fit,
  data = predictors,
  y = as.integer(train$attrition_flag == "Churned"),
  label = "Random Forest",
  verbose = FALSE
)

# Baseline customer: median for numerics, most common level for factors
mode_factor <- function(x) factor(names(which.max(table(x))), levels = levels(x))
baseline <- predictors |>
  summarise(across(where(is.numeric), median), across(where(is.factor), mode_factor))
baseline <- baseline[names(predictors)]
# Keep integer columns integer, matching the training data
int_cols <- names(predictors)[map_lgl(predictors, is.integer)]
baseline <- baseline |> mutate(across(all_of(int_cols), as.integer))

# Score a data frame of cleaned predictors
score <- function(df) predict(churn_fit, df, type = "prob")$.pred_Churned

risk_label <- function(p) {
  case_when(p >= 0.6 ~ "High", p >= 0.3 ~ "Medium", TRUE ~ "Low")
}

# UI -----------------------------------------------------------------------
slider <- function(id, label, col, step = 1) {
  r <- range(predictors[[col]])
  sliderInput(id, label, min = floor(r[1]), max = ceiling(r[2]),
              value = baseline[[col]], step = step)
}

ui <- page_navbar(
  title = "Credit Card Churn Dashboard",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  nav_panel(
    "Batch Predictor",
    layout_sidebar(
      sidebar = sidebar(
        fileInput("upload", "Upload customer CSV", accept = ".csv"),
        helpText("Use the same columns as BankChurners.csv. CLIENTNUM and Attrition_Flag are optional."),
        downloadButton("download", "Download predictions")
      ),
      uiOutput("batch_summary"),
      card(card_header("Predictions"), tableOutput("batch_table"))
    )
  ),
  nav_panel(
    "Customer Simulator",
    layout_sidebar(
      sidebar = sidebar(
        width = 340,
        slider("total_trans_ct", "Total transaction count", "total_trans_ct"),
        slider("total_trans_amt", "Total transaction amount", "total_trans_amt", 50),
        slider("months_inactive_12_mon", "Inactive months (12 mo)", "months_inactive_12_mon"),
        slider("contacts_count_12_mon", "Contacts (12 mo)", "contacts_count_12_mon"),
        slider("total_relationship_count", "Products held", "total_relationship_count"),
        slider("customer_age", "Customer age", "customer_age"),
        sliderInput("avg_utilization_ratio", "Credit utilization ratio",
                    min = 0, max = 1, value = round(baseline$avg_utilization_ratio, 2), step = 0.01),
        sliderInput("total_ct_chng_q4_q1", "Transaction count change Q4/Q1",
                    min = 0, max = 4, value = round(baseline$total_ct_chng_q4_q1, 2), step = 0.01)
      ),
      layout_columns(
        col_widths = c(4, 8),
        value_box("Churn probability", textOutput("sim_prob"), textOutput("sim_level")),
        card(card_header("Local SHAP explanation"), plotOutput("sim_shap", height = 380))
      )
    )
  )
)

# Server -------------------------------------------------------------------
server <- function(input, output, session) {

  # Batch predictor
  batch <- reactive({
    req(input$upload)
    raw <- tryCatch(
      readr::read_csv(input$upload$datapath, show_col_types = FALSE),
      error = function(e) NULL
    )
    validate(need(!is.null(raw), "Could not read the uploaded file as CSV."))
    df <- clean_names(raw)
    missing <- setdiff(names(predictors), names(df))
    validate(need(length(missing) == 0,
                  paste("Missing columns:", paste(missing, collapse = ", "))))

    x <- df[names(predictors)]
    # Align types and factor levels with the training data
    for (col in names(predictors)) {
      x[[col]] <- if (is.factor(predictors[[col]])) {
        factor(as.character(x[[col]]), levels = levels(predictors[[col]]))
      } else if (is.integer(predictors[[col]])) {
        as.integer(x[[col]])
      } else {
        as.numeric(x[[col]])
      }
    }
    validate(need(!anyNA(x), "Uploaded data has missing or unrecognised values."))

    p <- score(x)
    bind_cols(select(df, any_of("clientnum")), churn_probability = round(p, 4),
              risk = risk_label(p), x)
  })

  output$batch_summary <- renderUI({
    d <- batch()
    layout_columns(
      value_box("Customers scored", nrow(d)),
      value_box("High risk", sum(d$risk == "High")),
      value_box("Mean churn probability", sprintf("%.1f%%", 100 * mean(d$churn_probability)))
    )
  })
  output$batch_table <- renderTable(arrange(batch(), desc(churn_probability)) |> head(200))
  output$download <- downloadHandler(
    filename = "churn_predictions.csv",
    content = function(file) readr::write_csv(batch(), file)
  )

  # Simulator
  profile <- reactive({
    p <- baseline
    for (id in c("total_trans_ct", "total_trans_amt", "months_inactive_12_mon",
                 "contacts_count_12_mon", "total_relationship_count", "customer_age",
                 "avg_utilization_ratio", "total_ct_chng_q4_q1")) {
      p[[id]] <- if (is.integer(p[[id]])) as.integer(input[[id]]) else as.numeric(input[[id]])
    }
    p
  })

  output$sim_prob <- renderText(sprintf("%.1f%%", 100 * score(profile())))
  output$sim_level <- renderText(paste(risk_label(score(profile())), "risk"))

  # SHAP is slower, so debounce slider movement
  profile_slow <- debounce(profile, 600)
  output$sim_shap <- renderPlot({
    shap <- predict_parts(explainer, new_observation = profile_slow(), type = "shap", B = 15)
    plot(shap, max_features = 10)
  })
}

shinyApp(ui, server)
