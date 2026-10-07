# 01_preprocessing.R -------------------------------------------------------
# Load, clean and split the BankChurners data. Run from the project root.

library(tidyverse)
library(tidymodels)
library(janitor)

set.seed(42)

# Locate the raw data (data/ preferred, dataset/ as fallback) --------------
candidates <- c("data/BankChurners.csv", "dataset/BankChurners.csv")
data_path <- candidates[file.exists(candidates)][1]

if (is.na(data_path)) {
  stop("BankChurners.csv not found. Place it in data/ and re-run.", call. = FALSE)
}
message("[01] Reading ", data_path)

raw <- tryCatch(
  read_csv(data_path, show_col_types = FALSE),
  error = function(e) stop("[01] Failed to read CSV: ", conditionMessage(e), call. = FALSE)
)

required <- c("CLIENTNUM", "Attrition_Flag")
missing_cols <- setdiff(required, names(raw))
if (length(missing_cols) > 0) {
  stop("[01] Missing expected columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
}

# Clean --------------------------------------------------------------------
churn <- raw |>
  clean_names() |>
  # Drop the identifier and the pre-computed Naive Bayes leakage columns
  select(-clientnum, -starts_with("naive_bayes")) |>
  mutate(
    # First level is the event of interest for yardstick metrics
    attrition_flag = factor(
      if_else(attrition_flag == "Attrited Customer", "Churned", "Active"),
      levels = c("Churned", "Active")
    ),
    across(where(is.character), as.factor)
  ) |>
  drop_na()

message("[01] ", nrow(churn), " rows, ", ncol(churn) - 1, " predictors")
print(churn |> count(attrition_flag) |> mutate(share = round(n / sum(n), 3)))

# Stratified 80/20 split ---------------------------------------------------
split <- initial_split(churn, prop = 0.8, strata = attrition_flag)
train <- training(split)
test <- testing(split)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
saveRDS(train, "data/processed/train.rds")
saveRDS(test, "data/processed/test.rds")

message("[01] Saved train (", nrow(train), ") and test (", nrow(test), ") sets to data/processed/")
