# 01-5_scrape_mcgill_abstracts.R
#
# Purpose: Visits each individual McGill thesis record URL and extracts
#          detailed metadata (author, degree, abstract, year, URL) using
#          RSelenium. Handles server load warnings with automatic retry and
#          5-second polite delays. Extracts English abstract only, stripping
#          French text where both language versions are present.
#          Run after 01-4. Note: the loop currently starts at row 2057
#          (resumption index from a prior run); adjust for a full run.
#
# Inputs:  data/processed_data/comparator-theses/raw/McGill_redirects.csv
#
# Outputs: data/processed_data/comparator-theses/raw/McGill_abstracts.csv
#            - authors:   thesis author name
#            - degree:    degree type (Masters or Doctoral)
#            - abstract:  thesis abstract (English only)
#            - year:      year of thesis submission
#            - location:  URL of individual thesis record
#
# Author:  Mathew Vis-Dunbar
# Updated: [placeholder]

library(RSelenium)
library(magrittr)
library(rvest)
library(here)

thesis_urls <- read.csv(here::here("data", "processed_data", "comparator-theses", "raw", "McGill_redirects.csv"))
metadata <- list()

check_warning <- function(webpage){
  h2_text <- html_element(webpage, "h2") %>%
    html_text()
  is_warning <- ifelse(is.na(h2_text), FALSE, ifelse(h2_text == "This website is under heavy load (queue full)", TRUE, FALSE))
  return(is_warning)
}

get_source <- function(index){
  query <- thesis_urls[index,]
  print(query)
  driver$navigate(query)
  page_source <- driver$getPageSource()[[1]]
  webpage <- read_html(page_source)
  is_warning <- check_warning(webpage = webpage)
  if(is_warning == TRUE){
    Sys.sleep(20)
    get_source(index = i)
  }
  return(webpage)
}

# start the server
selenium_server <- rsDriver(
  browser = "firefox",
  chromever = NULL,
  phantomver = NULL
)

driver <- selenium_server$client

for (i in 2057:nrow(thesis_urls)){
  result <- get_source(index = i)
  print(i)
  # print(thesis_urls[i,])
  metadata[[i]] <- html_elements(result, "dd") %>%
    html_text2()
  Sys.sleep(5)
}

# CLOSE THE DRIVER & CONNECTION
#############################

driver$close()
selenium_server$server$stop()

## Convert list data to data frame

authors <- vector()
degree <- vector()
abstract <- vector()
year <- vector()
location <- vector()

for(i in 1:length(metadata)){
  authors <- c(authors, metadata[[i]][1])
  abstract <- c(abstract, metadata[[i]][3])
  degree <- c(degree,
              ifelse(length(metadata[[i]][grepl(pattern = "^Master|^Doct", x = metadata[[i]])]) == 0,
                     NA,
                     metadata[[i]][grepl(pattern = "^Master|^Doct", x = metadata[[i]])]))
  year <- c(year,
            ifelse(length(metadata[[i]][grepl(pattern = "^[0-9][0-9][0-9][0-9]$", x = metadata[[i]])]) == 0,
                   NA,
                   metadata[[i]][grepl(pattern = "^[0-9][0-9][0-9][0-9]$", x = metadata[[i]])]))
  location <- c(location,
                ifelse(length(metadata[[i]][grepl(pattern = "^ https", x = metadata[[i]])]) == 0,
                       NA,
                       metadata[[i]][grepl(pattern = "^ https", x = metadata[[i]])]))
}

df <- data.frame(authors = authors,
                 degree = degree,
                 abstract = abstract,
                 year = year,
                 location = location)

abstract_1 <- df[1:5, "abstract"]

for(i in 1:nrow(df)){
  df[i, "abstract"] <- ifelse(grepl("^French", df[i, "abstract"]) == TRUE,
         sub("^French.*\nRead More\n", "", df[i, "abstract"]),
         ifelse(grepl("^English", df[i, "abstract"]) == TRUE,
                sub("\nRead More\nFrench\n.*", "", df[i, "abstract"]),
         NA))
}
df$abstract <- sub("English\n", "", df$abstract)
df$abstract <- sub("\nRead More", "", df$abstract)
df$location <- sub(" ", "", df$location)

write.csv(df, here::here("data", "processed_data", "comparator-theses", "raw", "McGill_abstracts.csv"), row.names = FALSE)
