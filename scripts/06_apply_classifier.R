# 06_apply_classifier.R
#
# Purpose: Reads cleaned thesis CSV files and applies the v2 EEE text classifier
#          to categorize each thesis as EEE (ecology, evolution, environment) or
#          Other, based on title and abstract text. Writes one classified CSV per
#          institution.
#
# Inputs:  All CSV files in: data/processed_data/comparator-theses/clean/
#          data/processed_data/comparator-theses/training-data/eee_text_classifier_v2.rds
# Outputs: data/processed_data/comparator-theses/classified/[Institution]_classified.csv
#
# Author:  Jason Pither, with help from Claude (Sonnet 4.5)
# Updated: 2026-02-19

# Required R packages
library(tidymodels)
library(textrecipes)  # Required for text preprocessing steps in the model
library(dplyr)
library(readr)
library(here)
library(stringr)
library(purrr)

# Load the saved classifier model
# now using updated model 
classifier_model <- readRDS(
  here::here("data", "processed_data", "comparator-theses",
             "training-data", "eee_text_classifier_v2.rds")
)

# Create output directory if it doesn't exist
output_dir <- here::here("data", "processed_data", "comparator-theses", "classified")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get list of clean CSV files
clean_csv_files <- list.files(
  here::here("data", "processed_data", "comparator-theses", "clean"),
  pattern = "\\.csv$",
  full.names = TRUE
)

# Function to extract institution name from filename
extract_institution <- function(filepath) {
  basename(filepath) %>%
    stringr::str_remove("_clean\\.csv$")
}

# Process each CSV file
cat("Applying classifier to thesis data...\n")
all_results <- list()

for (i in seq_along(clean_csv_files)) {
  filepath <- clean_csv_files[i]
  institution <- extract_institution(filepath)

  cat(sprintf("  [%d/%d] Processing %s...\n", i, length(clean_csv_files), institution))

  tryCatch({
    # Read the clean CSV and create combined text field (title + abstract)
    # Handle missing titles (e.g. McGill) and missing abstracts gracefully:
    # coalesce replaces NA with "" so combined_text is just the abstract when
    # title is absent, and just the title when abstract is absent.
    df <- readr::read_csv(filepath, show_col_types = FALSE) %>%
      dplyr::mutate(
        title    = dplyr::coalesce(title, ""),
        abstract = dplyr::coalesce(abstract, ""),
        combined_text = trimws(paste(title, abstract, sep = " "))
      )

    # Generate predictions using the classifier model (tidymodels workflow)
    # Following tidymodels pattern: workflow %>% predict(data)
    df_classified <- classifier_model %>%
      predict(df, type = "prob") %>%
      dplyr::bind_cols(classifier_model %>% predict(df, type = "class")) %>%
      dplyr::bind_cols(df) %>%
      dplyr::mutate(Category = as.character(.pred_class)) %>%
      dplyr::select(institution, institution_fullname, title, abstract, author,
                    firstname_lastname, year, program, Category,
                    prob_EEE = .pred_EEE)

    # Store result
    all_results[[institution]] <- df_classified

    # Summary of classifications
    # Debug: check unique category values
    unique_cats <- unique(df_classified$Category)
    cat(sprintf("    -> Unique categories found: %s\n", paste(unique_cats, collapse = ", ")))

    n_eee <- sum(df_classified$Category == "EEE", na.rm = TRUE)
    n_other <- sum(df_classified$Category == "other", na.rm = TRUE)
    cat(sprintf("    -> Classified %d records (EEE: %d, Other: %d)\n",
                nrow(df_classified), n_eee, n_other))

  }, error = function(e) {
    cat(sprintf("    -> ERROR: %s\n", e$message))
  })
}

# Write classified CSV files (one per institution)
cat("\nWriting classified CSV files...\n")
for (institution in names(all_results)) {
  output_file <- file.path(output_dir, paste0(institution, "_classified.csv"))

  tryCatch({
    readr::write_csv(all_results[[institution]], output_file)
    cat(sprintf("  -> Wrote %s (%d records)\n",
                basename(output_file),
                nrow(all_results[[institution]])))
  }, error = function(e) {
    cat(sprintf("  -> ERROR writing %s: %s\n", institution, e$message))
  })
}

cat("\nClassification complete!\n")
cat(sprintf("Classified CSV files saved to: %s\n", output_dir))

# Summary statistics
cat("\n=== SUMMARY ===\n")
total_records <- sum(purrr::map_dbl(all_results, nrow))
total_eee <- sum(purrr::map_dbl(all_results, ~ sum(.x$Category == "EEE")))
total_other <- sum(purrr::map_dbl(all_results, ~ sum(.x$Category == "other")))

cat(sprintf("Total institutions processed: %d\n", length(all_results)))
cat(sprintf("Total records: %d\n", total_records))
cat(sprintf("Total EEE classifications: %d (%.1f%%)\n",
            total_eee, 100 * total_eee / total_records))
cat(sprintf("Total Other classifications: %d (%.1f%%)\n",
            total_other, 100 * total_other / total_records))

cat("\nRecords by institution:\n")
for (institution in names(all_results)) {
  n_total <- nrow(all_results[[institution]])
  n_eee <- sum(all_results[[institution]]$Category == "EEE")
  n_other <- sum(all_results[[institution]]$Category == "other")
  cat(sprintf("  %s: %d total (EEE: %d, Other: %d)\n",
              institution, n_total, n_eee, n_other))
}
