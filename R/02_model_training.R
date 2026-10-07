# 02_model_training.R ------------------------------------------------------
# Train a SMOTE-balanced random forest and evaluate it on the test set.

library(tidyverse)
library(tidymodels)
library(ranger)
library(themis)

set.seed(42)

if (!all(file.exists("data/processed/train.rds", "data/processed/test.rds"))) {
  stop("Processed data not found. Run R/01_preprocessing.R first.", call. = FALSE)
}
train <- readRDS("data/processed/train.rds")
test <- readRDS("data/processed/test.rds")

# Recipe: encode, normalise, rebalance -------------------------------------
# step_smote() is skipped automatically when predicting on new data.
churn_recipe <- recipe(attrition_flag ~ ., data = train) |>
  step_dummy(all_nominal_predictors(), one_hot = TRUE) |>
  step_zv(all_predictors()) |>
  step_normalize(all_numeric_predictors()) |>
  step_smote(attrition_flag, over_ratio = 1)

rf_spec <- rand_forest(trees = 200, mtry = 6, min_n = 10) |>
  set_engine("ranger", importance = "impurity", num.threads = parallel::detectCores() - 1) |>
  set_mode("classification")

churn_wf <- workflow() |>
  add_recipe(churn_recipe) |>
  add_model(rf_spec)

message("[02] Training random forest ...")
churn_fit <- tryCatch(
  fit(churn_wf, data = train),
  error = function(e) stop("[02] Training failed: ", conditionMessage(e), call. = FALSE)
)
message("[02] Training complete")

# Evaluate on the held-out test set ----------------------------------------
preds <- predict(churn_fit, test, type = "prob") |>
  bind_cols(predict(churn_fit, test, type = "class")) |>
  bind_cols(test |> select(attrition_flag))

# Event level defaults to the first factor level ("Churned")
metrics <- bind_rows(
  roc_auc(preds, truth = attrition_flag, .pred_Churned),
  pr_auc(preds, truth = attrition_flag, .pred_Churned),
  accuracy(preds, truth = attrition_flag, estimate = .pred_class),
  recall(preds, truth = attrition_flag, estimate = .pred_class),
  precision(preds, truth = attrition_flag, estimate = .pred_class)
)
print(metrics)
print(conf_mat(preds, truth = attrition_flag, estimate = .pred_class))

# Save artefacts -----------------------------------------------------------
dir.create("models", showWarnings = FALSE)
dir.create("outputs", showWarnings = FALSE)
saveRDS(churn_fit, "models/churn_workflow.rds")
write_csv(metrics, "outputs/test_metrics.csv")

roc_plot <- roc_curve(preds, truth = attrition_flag, .pred_Churned) |> autoplot()
pr_plot <- pr_curve(preds, truth = attrition_flag, .pred_Churned) |> autoplot()
ggsave("outputs/roc_curve.png", roc_plot, width = 5, height = 5, dpi = 150)
ggsave("outputs/pr_curve.png", pr_plot, width = 5, height = 5, dpi = 150)

message("[02] Model saved to models/churn_workflow.rds; metrics and curves in outputs/")
