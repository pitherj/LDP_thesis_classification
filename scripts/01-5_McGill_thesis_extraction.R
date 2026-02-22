library(RSelenium)
library(magrittr)
library(rvest)

# in case of server load issues
check_warning <- function(webpage){
  h2_text <- html_element(webpage, "h2") %>%
    html_text()
  is_warning <- ifelse(is.na(h2_text),
                       FALSE,
                       ifelse(h2_text == "This website is under heavy load (queue full)",
                              TRUE,
                              FALSE))
  return(is_warning)
}

# page source code
get_source <- function(query){
  print(query)
  driver$navigate(query)
  page_source <- driver$getPageSource()[[1]]
  webpage <- read_html(page_source)
  is_warning <- check_warning(webpage = webpage)
  if(is_warning == TRUE){
    Sys.sleep(20)
    get_source(query = query)
  }
  return(webpage)
}

# gather requisite metadata
get_redirects <- function(){
  new_redirects <- html_elements(webpage, ".search-result-title a") %>%
    html_attr("href") %>%
    paste0("https://escholarship.mcgill.ca", .)
  return(new_redirects)
}
get_titles <- function(){
  new_titles <- html_elements(webpage, ".search-result-title") %>%
    html_text()
  return(new_titles)
}

# variables
thesis_dates <- c(2022, 2023, 2024)
url_1 <- "https://escholarship.mcgill.ca/catalog?f%5Bdate_sim%5D%5B%5D="
url_2 <- "&f_inclusive%5Brtype_sim%5D%5B%5D=Thesis&locale=en&per_page=100&page="

# place holders
redirects <- vector()
titles <- vector()

# start the server
selenium_server <- rsDriver(
  browser = "firefox",
  chromever = NULL,
  phantomver = NULL
)

driver <- selenium_server$client

# get the data
for(i in 1:length(thesis_dates)){
  counter <- 0
  url_base <- paste0(url_1, thesis_dates[i], url_2)
  query <- paste0(url_base, 1)
  webpage <- get_source(query = query)
  response_count <- html_elements(webpage, ".page_entries") %>%
    html_text() %>%
    gsub("^.*of ", "", .) %>%
    gsub("\n.*", "", .) %>%
    gsub(",", "", .) %>%
    as.integer()
  number_of_pages <- ceiling(response_count/100)
  redirects <- c(redirects, get_redirects())
  titles <- c(titles, get_titles())
  Sys.sleep(10)
  for(i in 2:number_of_pages){
    query <- paste(url_base, i)
    webpage <- get_source(query = query)
    redirects <- c(redirects, get_redirects())
    titles <- c(titles, get_titles())
    counter <- counter + 1
    print(counter)
    Sys.sleep(10)
  }
}

# CLOSE THE DRIVER & CONNECTION
#############################

driver$close()
selenium_server$server$stop()

# create data frame
df <- data.frame(redirects = redirects,
                 titles = titles)

# export
write.csv(df, "data/McGill_redirects.csv", row.names = FALSE)


