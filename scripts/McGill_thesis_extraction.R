library(RSelenium)
library(magrittr)
library(rvest)

# start the server
selenium_server <- rsDriver(
  browser = "firefox",
  chromever = NULL,
  phantomver = NULL
)

driver <- selenium_server$client

thesis_dates <- c(2022, 2023, 2024)
url_1 <- "https://escholarship.mcgill.ca/catalog?f%5Bdate_sim%5D%5B%5D="
url_2 <- "&f_inclusive%5Brtype_sim%5D%5B%5D=Thesis&locale=en&per_page=100&page="
redirects <- vector()

for(i in 1:length(thesis_dates)){
  counter <- 0
  url_base <- paste0(url_1, thesis_dates[i], url_2)
  query <- paste0(url_base, 1)
  driver$navigate(query)
  page_source <- driver$getPageSource()[[1]]
  webpage <- read_html(page_source)
  response_count <- html_elements(webpage, ".page_entries") %>%
    html_text() %>%
    gsub("^.*of ", "", .) %>%
    gsub("\n.*", "", .) %>%
    gsub(",", "", .) %>%
    as.integer()
  number_of_pages <- ceiling(response_count/100)
  new_redirects <- html_elements(webpage, ".search-result-title a") %>%
    html_attr("href") %>%
    paste0("https://escholarship.mcgill.ca", .)
  redirects <- c(redirects, new_redirects)
  Sys.sleep(30)
  for(i in 2:number_of_pages){
    query <- paste(url_base, i)
    driver$navigate(query)
    page_source <- driver$getPageSource()[[1]]
    webpage <- read_html(page_source)
    new_redirects <- html_elements(webpage, ".search-result-title a") %>%
      html_attr("href") %>%
      paste0("https://escholarship.mcgill.ca", .)
    redirects <- c(redirects, new_redirects)
    counter <- counter + 1
    print(counter)
    Sys.sleep(30)
  }
}

# Neede for page errors. Will fix for individual pulls
# driver$navigate("https://escholarship.mcgill.ca/catalog?f%5Bdate_sim%5D%5B%5D=2024&f_inclusive%5Brtype_sim%5D%5B%5D=Thesis&locale=en&per_page=100&page=15")
# 
# page_source <- driver$getPageSource()[[1]]
# webpage <- read_html(page_source)
# new_redirects <- html_elements(webpage, ".search-result-title a") %>%
#   html_attr("href") %>%
#   paste0("https://escholarship.mcgill.ca", .)
# redirects <- c(redirects, new_redirects)
# redirects[duplicated(redirects)]


write.csv(redirects, "data/McGill_redirects.csv", row.names = FALSE)


