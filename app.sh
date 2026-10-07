#!/usr/bin/env bash
# Launch the Shiny dashboard from the project root.
cd "$(dirname "$0")" || exit 1
Rscript -e "shiny::runApp(source('R/04_app.R')\$value, launch.browser = TRUE)"
