# Credit Card Customer Churn: ML and Explainable AI in R

End-to-end churn prediction on the BankChurners dataset using `tidymodels`, `ranger`, `DALEX`/`DALEXtra` and a `shiny` + `bslib` dashboard.

## Directory structure

```
.
├── data/                  # BankChurners.csv (falls back to dataset/); processed splits go to data/processed/
├── R/
│   ├── 01_preprocessing.R # load, clean, binary target, stratified 80/20 split
│   ├── 02_model_training.R# recipe (dummy, normalise, SMOTE) + ranger RF, ROC-AUC / PR-AUC
│   ├── 03_explainability.R# DALEX global importance and local SHAP plots
│   └── 04_app.R           # Shiny dashboard
├── models/                # fitted workflow (churn_workflow.rds)
├── outputs/               # metrics, ROC/PR curves, importance and SHAP plots
├── app.sh                 # launches the dashboard
├── run_pipeline.R         # runs scripts 01-03
└── README.md
```

## Installation

Requires R >= 4.1.

```r
install.packages(c(
  "tidyverse", "tidymodels", "ranger", "DALEX", "DALEXtra",
  "themis", "shiny", "bslib", "janitor"
))
```

Place `BankChurners.csv` in `data/` (the `dataset/` folder is also detected).

## Running the pipeline

From the project root:

```bash
Rscript run_pipeline.R
```

Or run each script in order: `R/01_preprocessing.R`, `R/02_model_training.R`, `R/03_explainability.R`.

## Methodology

1. **Preprocessing**: column names cleaned with `janitor`; `CLIENTNUM` and the Naive Bayes leakage columns removed; `Attrition_Flag` becomes a factor with levels `Churned` (event) and `Active`; stratified 80/20 split with `rsample`.
2. **Modelling**: a `recipe` one-hot encodes categoricals, drops zero-variance columns, normalises numerics and applies `themis::step_smote` to balance classes (training only; skipped at prediction time). A 200-tree `ranger` random forest is fit in a `workflow`.
3. **Evaluation**: ROC-AUC and PR-AUC (the more informative metric for the ~16% churn rate) plus accuracy, precision and recall on the test set. Results are written to `outputs/`.
4. **Explainability**: `model_parts` gives permutation importance (drop in 1 - AUC loss); `predict_parts(type = "shap")` explains the three highest-risk test customers.

## Shiny app

After running the pipeline (the app needs `models/churn_workflow.rds`):

```bash
bash app.sh
```

On Windows without Git Bash or a WSL distribution, run this from PowerShell at the project root instead:

```powershell
Rscript -e "shiny::runApp(source('R/04_app.R')`$value, launch.browser = TRUE)"
```

or from R at the project root:

```r
shiny::runApp(source("R/04_app.R")$value)
```

- **Batch Predictor**: upload a CSV with the BankChurners columns to get churn probabilities and risk bands; download the results.
- **Customer Simulator**: adjust transaction count, inactive months, utilization and more to see churn risk and a SHAP breakdown update live.

## Static website (GitHub Pages)

`docs/` holds a static site: `index.html` (results, charts, high-risk customers, SHAP plots) with a button to `simulator.html` (sliders that look up pre-scored model predictions and show a what-if impact per feature).

```bash
Rscript R/05_export_web.R          # refresh docs/data and docs/img from the trained model
python -m http.server -d docs      # preview at http://localhost:8000
```

To publish, push and set Settings > Pages > Source to the `main` branch and `/docs` folder. The site contains only aggregated results and anonymous feature rows, not the raw dataset.
