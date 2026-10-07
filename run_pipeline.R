# Run the full pipeline from the project root: Rscript run_pipeline.R
for (f in c("R/01_preprocessing.R", "R/02_model_training.R", "R/03_explainability.R")) {
  message("==== ", f, " ====")
  source(f, echo = FALSE)
}
