# 02_clean_theses.R
#
# Purpose: Reads in raw thesis metadata CSV files (varied formats per institution),
#          extracts and standardizes relevant fields, and writes one clean CSV per
#          institution. Institutions not represented in the LDP publication data
#          are routed to a not_used/ subdirectory automatically.
#
# Inputs:  All CSV files in: data/processed_data/comparator-theses/raw/
#          data/institution_names.csv
# Outputs: data/processed_data/comparator-theses/clean/[Institution]_clean.csv
#
# Author:  Jason Pither, with help from Claude (Sonnet 4.5)
# Updated: 2026-02-19

# Required R packages
library(dplyr)
library(readr)
library(here)
library(stringr)
library(purrr)

# Load institution full names for joining
institution_names <- readr::read_csv(
  here::here("data", "institution_names.csv"),
  show_col_types = FALSE
)

# Create output directory if it doesn't exist
output_dir <- here::here("data", "processed_data", "comparator-theses", "clean")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get list of relevant filenames
# Exclude "Alberta_Results_Scholaris.csv" because it lacks program info
csv_files_for_import <- setdiff(
  list.files(
    here::here("data", "processed_data", "comparator-theses", "raw"),
    pattern = "\\.csv$",
    full.names = TRUE
  ),
  here::here("data", "processed_data", "comparator-theses", "raw", "Alberta_Results_Scholaris.csv")
)

# Function to extract institution name from filename
# Stops at the first underscore or hyphen, so both "McGill-abstracts.csv"
# and "UBC_Results_*.csv" style names are handled correctly
extract_institution <- function(filepath) {
  basename(filepath) %>%
    stringr::str_extract("^[^-_]+")
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

    # If no title column present, add NA placeholder before selecting
    if (!any(stringr::str_detect(names(df), "(?i)^Title$"))) {
      df <- df %>% dplyr::mutate(title = NA_character_)
      cat(sprintf("    Note: no 'title' field found in %s source data; title set to NA\n", institution))
    }

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

    # If no title column present, add NA placeholder before selecting
    if (!any(stringr::str_detect(names(df), "(?i)^titles?$"))) {
      df <- df %>% dplyr::mutate(title = NA_character_)
      cat(sprintf("    Note: no 'title' field found in %s source data; title set to NA\n", institution))
    }

    # Extract year from authors field (format: " (YYYY-MM) Name").
    # If a standalone year column already exists (e.g. McGill), use it in
    # preference to the authors-field extraction.
    year_from_authors <- stringr::str_extract(df$authors, "\\d{4}")
    year_col          <- if ("year" %in% names(df)) as.character(df$year) else NA_character_

    df_clean <- df %>%
      dplyr::mutate(
        year   = dplyr::coalesce(year_col, year_from_authors),
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

  # Standardize program names if available.
  # Regex is intentionally specific to avoid mapping non-science degrees
  # (e.g. Master of Arts, Doctor of Civil Law) to MSc/PhD.
  if ("program" %in% names(df_clean)) {
    df_clean <- df_clean %>%
      dplyr::mutate(
        program = dplyr::case_when(
          stringr::str_detect(program, stringr::regex("\\bph\\.?d\\.?\\b|^doctoral$|doctor of philosophy", ignore_case = TRUE)) ~ "PhD",
          stringr::str_detect(program, stringr::regex("\\bm\\.?sc?\\b|^masters?$|master of science",       ignore_case = TRUE)) ~ "MSc",
          TRUE ~ program
        )
      )
  }

  # Retain only MSc and PhD records; drop any that did not resolve to a
  # target degree (e.g. Master of Arts, Doctor of Civil Law from McGill)
  n_before <- nrow(df_clean)
  df_clean <- df_clean %>% dplyr::filter(program %in% c("MSc", "PhD"))
  n_dropped <- n_before - nrow(df_clean)
  if (n_dropped > 0) {
    cat(sprintf("    Note: %d record(s) dropped — non-MSc/PhD program\n", n_dropped))
  }

  # Convert year to integer.
  # Strategy: (1) extract first 4-digit run from whatever the year column contains
  # (handles "2023", "Fall 2023", "2023-11", etc.); (2) if still NA, fall back to
  # extracting the 4-digit year embedded in the author field (e.g. "(Fall 2023) Hill, Sara")
  df_clean <- df_clean %>%
    dplyr::mutate(
      year = dplyr::coalesce(
        suppressWarnings(as.integer(stringr::str_extract(as.character(year), "\\d{4}"))),
        suppressWarnings(as.integer(stringr::str_extract(author,            "\\d{4}")))
      )
    )

  # Extract firstname_lastname from author field
  # Handles three extraneous-info formats before parsing:
  #   Alberta:  "Lastname, Firstname|Department"  -> strip after |
  #   Toronto:  "Lastname, Firstname; Supervisor"  -> strip after first ;
  #   Others:   "Lastname, Firstname."             -> strip trailing period
  # Then reverses "Lastname, Firstname" to "Firstname Lastname" (first word only as firstname)
  df_clean <- df_clean %>%
    dplyr::mutate(
      author_clean = author %>%
        stringr::str_remove("^\\s*\\([^)]+\\)\\s*") %>%  # strip leading (date) prefix e.g. "(Fall 2023) "
        stringr::str_remove("\\|.*$") %>%                 # strip Alberta-style dept info
        stringr::str_remove(";.*$") %>%                   # strip Toronto-style supervisor/dept info
        stringr::str_trim() %>%
        stringr::str_remove("\\.+$") %>%                  # strip trailing period(s)
        stringr::str_trim(),
      firstname_lastname = dplyr::if_else(
        stringr::str_detect(author_clean, ","),
        stringr::str_trim(paste(
          stringr::word(stringr::str_remove(author_clean, "^[^,]+,\\s*"), 1),  # firstname
          stringr::str_extract(author_clean, "^[^,]+")                          # lastname
        )),
        author_clean  # fallback: use as-is if no comma found
      )
    ) %>%
    dplyr::select(-author_clean)

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
    df_out <- all_results[[institution]] %>%
      dplyr::left_join(institution_names, by = c("institution" = "institution_abbrev")) %>%
      dplyr::rename(institution_fullname = institution_name)
    readr::write_csv(df_out, output_file)
    cat(sprintf("  -> Wrote %s (%d records)\n",
                basename(output_file),
                nrow(df_out)))
  }, error = function(e) {
    cat(sprintf("  -> ERROR writing %s: %s\n", institution, e$message))
  })
}

# -----------------------------------------------------------------------------
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
