# 05_export_web.R ----------------------------------------------------------
# Export results and a pre-scored profile grid for the static GitHub Pages site (docs/).

library(tidyverse)
library(tidymodels)
library(ranger)
library(themis)
library(jsonlite)

if (!all(file.exists("models/churn_workflow.rds", "data/processed/test.rds",
                     "outputs/test_metrics.csv", "outputs/shap_customer_1.png"))) {
  stop("Run R/01 to R/03 first.", call. = FALSE)
}
fit <- readRDS("models/churn_workflow.rds")
train <- readRDS("data/processed/train.rds")
test <- readRDS("data/processed/test.rds")

dir.create("docs/data", recursive = TRUE, showWarnings = FALSE)
dir.create("docs/img", recursive = TRUE, showWarnings = FALSE)
save_json <- function(x, name) write_json(x, file.path("docs/data", name), auto_unbox = TRUE, digits = 4)

risk_label <- function(p) case_when(p >= 0.6 ~ "High", p >= 0.3 ~ "Medium", TRUE ~ "Low")

# Static assets for page A -------------------------------------------------
imgs <- c("roc_curve.png", "pr_curve.png", "variable_importance.png", sprintf("shap_customer_%d.png", 1:3))
file.copy(file.path("outputs", imgs), file.path("docs/img", imgs), overwrite = TRUE)

# Metrics, confusion matrix, risk bands, top-risk customers ----------------
p_test <- predict(fit, test, type = "prob")$.pred_Churned
pred_class <- if_else(p_test >= 0.5, "Churned", "Active")
truth <- as.character(test$attrition_flag)

metrics <- read_csv("outputs/test_metrics.csv", show_col_types = FALSE)
save_json(list(
  metrics = set_names(as.list(metrics$.estimate), metrics$.metric),
  confusion = list(tp = sum(pred_class == "Churned" & truth == "Churned"),
                   fp = sum(pred_class == "Churned" & truth == "Active"),
                   fn = sum(pred_class == "Active" & truth == "Churned"),
                   tn = sum(pred_class == "Active" & truth == "Active")),
  risk_bands = as.list(table(factor(risk_label(p_test), levels = c("Low", "Medium", "High")))),
  n_test = nrow(test),
  churn_rate = mean(truth == "Churned")
), "summary.json")

top <- test |>
  mutate(churn_probability = round(p_test, 3), risk = risk_label(p_test),
         actual = as.character(attrition_flag)) |>
  slice_max(churn_probability, n = 25, with_ties = FALSE) |>
  select(churn_probability, risk, actual, customer_age, total_trans_ct, total_trans_amt,
         months_inactive_12_mon, contacts_count_12_mon, total_relationship_count,
         avg_utilization_ratio, credit_limit)
save_json(top, "top_risk.json")

# Pre-scored grid for the simulator (page B) -------------------------------
predictors <- select(train, -attrition_flag)
mode_factor <- function(x) factor(names(which.max(table(x))), levels = levels(x))
baseline <- predictors |>
  summarise(across(where(is.numeric), median), across(where(is.factor), mode_factor))
baseline <- baseline[names(predictors)]

with_baseline <- function(col, values) sort(unique(c(values, baseline[[col]])))
grid_levels <- list(
  total_trans_ct = with_baseline("total_trans_ct", c(15, 30, 45, 60, 80, 100, 125)),
  total_trans_amt = with_baseline("total_trans_amt", c(1000, 2500, 4000, 6000, 9000, 14000)),
  months_inactive_12_mon = 0:6,
  avg_utilization_ratio = with_baseline("avg_utilization_ratio", c(0, 0.1, 0.3, 0.6, 0.9)),
  total_relationship_count = 1:6,
  contacts_count_12_mon = 0:6
)

# Row-major order: the first feature varies slowest, the last fastest
grid <- expand_grid(!!!grid_levels)
message("[05] Scoring ", nrow(grid), " profiles ...")

rest <- baseline[setdiff(names(baseline), names(grid_levels))]
score_chunk <- function(chunk) {
  df <- bind_cols(chunk, rest[rep(1, nrow(chunk)), ])[names(predictors)]
  for (col in names(df)) if (is.integer(predictors[[col]])) df[[col]] <- as.integer(df[[col]])
  predict(fit, df, type = "prob")$.pred_Churned
}
chunks <- split(grid, ceiling(seq_len(nrow(grid)) / 20000))
probs <- unlist(lapply(chunks, score_chunk), use.names = FALSE)

save_json(list(
  features = names(grid_levels),
  levels = unname(grid_levels),
  baseline_index = map_int(names(grid_levels), ~ match(baseline[[.x]], grid_levels[[.x]]) - 1L),
  probs = as.integer(round(probs * 1000)) # per mille, row-major (last feature fastest)
), "grid.json")

message("[05] Site data written to docs/. Preview with: python -m http.server -d docs")
