# This script takes a CSV file of author names and finds publications
# via OpenAlex

# Load the openalexR package
library(openalexR)
library(dplyr)
library(purrr)

# Provide email to enter the "polite pool" for better rate limits

options(openalexR.mailto = "jason.pither@ubc.ca")

# Define your vector of author names (Firstname Lastname format)
author_names <- c("Jason Pither", "Richard Pither")

# Publication date filter (only works from this date onwards)
min_pub_date <- "2020-01-01"

# Rate limit delay (seconds between API calls)
# OpenAlex limit is 10 requests/second; 0.15s = ~6.7 req/s (safe margin)
api_delay <- 0.15


# -----------------------------------------------------------------------------
# Define which fields to retrieve (workaround for duplicate 'id' column bug)
# By explicitly selecting fields, we avoid the problematic 'ids' nested object
# See: https://docs.openalex.org/api-entities/works/work-object for all fields
# -----------------------------------------------------------------------------

works_fields <- c(
  "id",
  "display_name",
  "title",
  "publication_date",
  "publication_year", 
  "type",
  "doi",
  "cited_by_count",
  "is_oa",
  "oa_status",
  "authorships",
  "primary_location",
  "abstract_inverted_index"
)

author_fields <- c(
  "id",
  "display_name",
  "orcid",
  "works_count",
  "cited_by_count",
  "last_known_institutions"
)

# -----------------------------------------------------------------------------
# Function: Search for author and retrieve their works
# -----------------------------------------------------------------------------

get_author_works <- function(author_name, from_date = "2020-01-01", delay = 0.15) {
  
  cat("\n", strrep("-", 60), "\n", sep = "")
  cat("Searching for author:", author_name, "\n")
  
  # Step 1: Find author(s) matching the name
  # Using select to avoid the duplicate id column bug
  author_info <- tryCatch({
    oa_fetch(
      entity = "authors",
      search = author_name,
      options = list(select = author_fields),
      verbose = FALSE
    )
  }, error = function(e) {
    cat("  Error searching for author:", conditionMessage(e), "\n")
    return(NULL)
  })
  
  Sys.sleep(delay)
  
  if (is.null(author_info) || nrow(author_info) == 0) {
    cat("  No author found for:", author_name, "\n")
    return(NULL)
  }
  
  cat("  Found", nrow(author_info), "matching author(s)\n")
  
  # Use the first (most relevant) match
  author_id <- author_info$id[1]
  author_display <- author_info$display_name[1]
  works_count <- author_info$works_count[1]
  
  
  # Extract ORCID if available
  author_orcid <- if ("orcid" %in% names(author_info)) {
    author_info$orcid[1]
  } else {
    NA_character_
  }
  
  cat("  Using:", author_display, "\n")
  cat("  OpenAlex ID:", author_id, "\n")
  cat("  ORCID:", ifelse(is.na(author_orcid), "Not found", author_orcid), "\n")
  cat("  Total works in OpenAlex:", works_count, "\n")
  
  # Step 2: Fetch works by this author using select to avoid duplicate column bug
  works <- tryCatch({
    oa_fetch(
      entity = "works",
      author.id = author_id,
      from_publication_date = from_date,
      options = list(select = works_fields),
      verbose = FALSE
    )
  }, error = function(e) {
    # If select doesn't work, try with output = "list" as fallback
    cat("  Standard fetch failed, trying list output...\n")
    tryCatch({
      works_list <- oa_fetch(
        entity = "works",
        author.id = author_id,
        from_publication_date = from_date,
        output = "list",
        verbose = FALSE
      )
      # Manual conversion of essential fields
      if (length(works_list) == 0) return(NULL)
      
      tibble(
        id = map_chr(works_list, "id", .default = NA_character_),
        display_name = map_chr(works_list, "display_name", .default = NA_character_),
        publication_year = map_int(works_list, "publication_year", .default = NA_integer_),
        publication_date = map_chr(works_list, "publication_date", .default = NA_character_),
        doi = map_chr(works_list, "doi", .default = NA_character_),
        type = map_chr(works_list, "type", .default = NA_character_),
        cited_by_count = map_int(works_list, "cited_by_count", .default = NA_integer_),
        is_oa = map_lgl(works_list, "is_oa", .default = NA)
      )
    }, error = function(e2) {
      cat("  Error fetching works:", conditionMessage(e2), "\n")
      return(NULL)
    })
  })
  
  Sys.sleep(delay)
  
  if (is.null(works) || nrow(works) == 0) {
    cat("  No works found from", from_date, "onwards\n")
    return(NULL)
  }
  
  cat("  Found", nrow(works), "works from", from_date, "onwards\n")
  
  # Add metadata columns
  works <- works %>%
    mutate(
      searched_name = author_name,
      matched_author_id = author_id,
      matched_author_name = author_display,
      matched_author_orcid = author_orcid,
      .before = 1
    )
  
  return(works)
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

cat("\n=== OpenAlex Publication Search ===\n")
cat("Searching for", length(author_names), "author(s)\n")
cat("Publication date filter: >=", min_pub_date, "\n")

# Fetch works for all authors
results_list <- map(
  author_names,
  ~ get_author_works(.x, from_date = min_pub_date, delay = api_delay)
)

names(results_list) <- author_names
results_list <- compact(results_list)

# -----------------------------------------------------------------------------
# Combine and display results
# -----------------------------------------------------------------------------

if (length(results_list) > 0) {
  
  combined_results <- bind_rows(results_list)
  
  cat("\n=== Summary ===\n")
  cat("Total works found:", nrow(combined_results), "\n\n")
  
  # Show authors with their ORCIDs
  cat("Authors found:\n")
  combined_results %>%
    distinct(searched_name, matched_author_name, matched_author_orcid) %>%
    print()
  
  cat("\nWorks per author:\n")
  combined_results %>%
    count(searched_name, name = "n_works") %>%
    print()
  
  cat("\n=== Sample Output (first 10 works) ===\n")
  
  # Select columns that exist (handles both full and fallback data)
  available_cols <- intersect(
    c("searched_name", "matched_author_name", "matched_author_orcid",
      "publication_year", "display_name", "doi", "cited_by_count", "is_oa"),
    names(combined_results)
  )
  
  combined_results %>%
    select(all_of(available_cols)) %>%
    head(10) %>%
    print()
  
} else {
  cat("\nNo results found for any author.\n")
  combined_results <- tibble()
}

# -----------------------------------------------------------------------------
# Optional: Export to CSV
# -----------------------------------------------------------------------------

# Uncomment to save - only exports scalar columns (no list-columns)
# scalar_cols <- combined_results %>%
#   select(where(~ !is.list(.x)))
# write.csv(scalar_cols, "author_publications.csv", row.names = FALSE)