# 01-6_merge_mcgill_theses.R
#
# Purpose: Merges McGill thesis titles and record URLs (from 01-4) with
#          per-record metadata including abstracts (from 01-5), joining on
#          the thesis record URL after stripping query parameters. Produces
#          the final McGill thesis CSV used as input to 02_clean_theses.R.
#
# Inputs:  data/processed_data/comparator-theses/raw/McGill_redirects.csv
#          data/processed_data/comparator-theses/raw/McGill_abstracts.csv
#
# Outputs: data/processed_data/comparator-theses/raw/McGill_theses.csv
#
# Author:  Jason Pither
# Updated: 2026-02-22

library(dplyr)
library(readr)
library(here)

mcgill_urls_titles <- readr::read_csv(here::here("data", "processed_data", "comparator-theses", "raw", "McGill_redirects.csv"), show_col_types = FALSE)
mcgill_abstracts <- readr::read_csv(here::here("data", "processed_data", "comparator-theses", "raw", "McGill_abstracts.csv"), show_col_types = FALSE)

# rename URL field
mcgill_urls_titles <- dplyr::rename(mcgill_urls_titles, location = redirects)
# strip the "?locale=en" off the end of the URLs
mcgill_urls_titles$location <- sub("\\?.*", "", mcgill_urls_titles$location)

# now join the abstracts and titles
mcgill_abstracts_titles <- dplyr::left_join(mcgill_abstracts, mcgill_urls_titles)

# export
readr::write_csv(mcgill_abstracts_titles, here::here("data", "processed_data", "comparator-theses", "raw", "McGill_theses.csv"))
