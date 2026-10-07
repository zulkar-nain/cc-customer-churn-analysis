# 03_explainability.R ------------------------------------------------------
# Global (permutation importance) and local (SHAP) explanations with DALEX.

library(tidyverse)
library(tidymodels)
library(DALEX)
library(DALEXtra)

set.seed(42)

if (!all(file.exists("models/churn_workflow.rds", "data/processed/test.rds"))) {
  stop("Model or data missing. Run R/01 and R/02 first.", call. = FALSE)
}
churn_fit <- readRDS("models/churn_workflow.rds")
train <- readRDS("data/processed/train.rds")
test <- readRDS("data/processed/test.rds")
dir.create("outputs", showWarnings = FALSE)

# Explainer built on the test set (y = 1 for churned customers) ------------
explainer <- explain_tidymodels(
  churn_fit,
  data = select(test, -attrition_flag),
  y = as.integer(test$attrition_flag == "Churned"),
  label = "Random Forest",
  verbose = FALSE
)

# Global: permutation variable importance ----------------------------------
message("[03] Computing permutation importance ...")
vi <- model_parts(explainer, loss_function = loss_one_minus_auc, B = 10, type = "difference")
vi_plot <- plot(vi, max_vars = 15) +
  labs(title = "Global variable importance", subtitle = "Drop in AUC after permutation")
ggsave("outputs/variable_importance.png", vi_plot, width = 8, height = 6, dpi = 150)

# Local: SHAP for the highest-risk test customers --------------------------
risk <- predict(churn_fit, test, type = "prob")$.pred_Churned
top_idx <- order(risk, decreasing = TRUE)[1:3]
high_risk <- select(test, -attrition_flag)[top_idx, ]

message("[03] Computing SHAP values for ", nrow(high_risk), " high-risk customers ...")
for (i in seq_len(nrow(high_risk))) {
  shap <- predict_parts(explainer, new_observation = high_risk[i, ], type = "shap", B = 10)
  p <- plot(shap, max_features = 10) +
    labs(title = sprintf("Customer %d: churn probability %.2f", i, risk[top_idx[i]]))
  ggsave(sprintf("outputs/shap_customer_%d.png", i), p, width = 8, height = 5, dpi = 150)
}

message("[03] Plots saved to outputs/")
