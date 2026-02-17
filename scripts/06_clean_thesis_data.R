# 06_apply_classifier.R

# Purpose: Reads in thesis metadata files, handling varied formats, and 
# extracts relevant fields, producing a clean CSV for each institution's data

# Inputs:  All CSV files in: data/processed_data/comparator-theses/
# Outputs: Clean CSV files (one per institution) in: data/processed_data/comparator-theses/clean/
#
# Author: Jason Pither, with help from Claude (Sonnet 4.5)
# Updated: 2026-02-16

# Required R packages
library(dplyr)
library(readr)
library(here)
library(stringr)
library(purrr)

# Create output directory if it doesn't exist
output_dir <- here::here("data", "processed_data", "comparator-theses", "clean")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get list of relevant filenames
# Exclude "Alberta_Results_Scholaris.csv" because it lacks program info
csv_files_for_import <- setdiff(
  list.files(
    here::here("data", "processed_data", "comparator-theses"),
    pattern = "\\.csv$",
    full.names = TRUE
  ),
  here::here("data", "processed_data", "comparator-theses", "Alberta_Results_Scholaris.csv")
)

# Function to extract institution name from filename
extract_institution <- function(filepath) {
  basename(filepath) %>%
    stringr::str_extract("^[^_]+")
}

# Function to detect format and read CSV appropriately
read_thesis_csv <- function(filepath) {

  # Extract institution name from filename
  institution <- extract_institution(filepath)

  # Read first line to detect format
  first_line <- readLines(filepath, n = 1, warn = FALSE)

  # Detect format based on first line
  if (stringr::str_detect(first_line, "Total number of results")) {
    # Format 1: Skip 2 lines, has header with # and quotes
    df <- suppressWarnings(readr::read_csv(filepath, skip = 2, show_col_types = FALSE))

    # Clean column names (remove # and quotes)
    names(df) <- stringr::str_remove_all(names(df), '[#"]')

    # Map to standard field names
    df_clean <- df %>%
      dplyr::select(
        title = dplyr::matches("^Title$", ignore.case = TRUE),
        abstract = dplyr::matches("^Abstract$", ignore.case = TRUE),
        author = dplyr::matches("^Author\\(s\\)$|^Authors?$", ignore.case = TRUE),
        year = dplyr::matches("^Publication date$|^Year$", ignore.case = TRUE),
        program = dplyr::matches("^Degree$|^Program$", ignore.case = TRUE)
      ) %>%
      dplyr::mutate(institution = institution)

  } else {
    # Format 2: No skip, different field names
    df <- suppressWarnings(readr::read_csv(filepath, show_col_types = FALSE))

    # Extract year from authors field (format: " (YYYY-MM) Name")
    df_clean <- df %>%
      dplyr::mutate(
        year = stringr::str_extract(authors, "\\(\\d{4}"),
        year = stringr::str_remove(year, "\\("),
        author = stringr::str_remove(authors, "^\\s*\\([^)]+\\)\\s*")
      ) %>%
      dplyr::select(
        title = dplyr::matches("^titles?$", ignore.case = TRUE),
        abstract = dplyr::matches("^abstracts?$", ignore.case = TRUE),
        author,
        year,
        program = dplyr::matches("^degree$|^program$", ignore.case = TRUE)
      ) %>%
      dplyr::mutate(institution = institution)
  }

  # Standardize program names if available
  if ("program" %in% names(df_clean)) {
    df_clean <- df_clean %>%
      dplyr::mutate(
        program = dplyr::case_when(
          stringr::str_detect(program, stringr::regex("ph\\.?d|doctor", ignore_case = TRUE)) ~ "PhD",
          stringr::str_detect(program, stringr::regex("m\\.?[as]|master", ignore_case = TRUE)) ~ "MSc",
          TRUE ~ program
        )
      )
  }

  # Convert year to numeric (some records may have missing years)
  df_clean <- df_clean %>%
    dplyr::mutate(year = suppressWarnings(as.numeric(year)))

  # Return cleaned data
  return(df_clean)
}

# Process all CSV files with error handling
cat("Processing thesis CSV files...\n")
all_results <- list()

for (i in seq_along(csv_files_for_import)) {
  filepath <- csv_files_for_import[i]
  institution <- extract_institution(filepath)

  cat(sprintf("  [%d/%d] Processing %s...\n", i, length(csv_files_for_import), institution))

  tryCatch({
    df_clean <- read_thesis_csv(filepath)
    all_results[[institution]] <- df_clean
    cat(sprintf("    -> Successfully imported %d records\n", nrow(df_clean)))
  }, error = function(e) {
    cat(sprintf("    -> ERROR: %s\n", e$message))
  })
}

# Write clean CSV files (one per institution)
cat("\nWriting clean CSV files...\n")
for (institution in names(all_results)) {
  output_file <- file.path(output_dir, paste0(institution, "_clean.csv"))

  tryCatch({
    readr::write_csv(all_results[[institution]], output_file)
    cat(sprintf("  -> Wrote %s (%d records)\n",
                basename(output_file),
                nrow(all_results[[institution]])))
  }, error = function(e) {
    cat(sprintf("  -> ERROR writing %s: %s\n", institution, e$message))
  })
}

cat("\nProcessing complete!\n")
cat(sprintf("Clean CSV files saved to: %s\n", output_dir))

# Summary statistics
cat("\n=== SUMMARY ===\n")
total_records <- sum(purrr::map_dbl(all_results, nrow))
cat(sprintf("Total institutions processed: %d\n", length(all_results)))
cat(sprintf("Total records: %d\n", total_records))
cat("\nRecords by institution:\n")
for (institution in names(all_results)) {
  cat(sprintf("  %s: %d\n", institution, nrow(all_results[[institution]])))
}
