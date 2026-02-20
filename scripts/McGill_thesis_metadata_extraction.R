library(RSelenium)
library(magrittr)
library(rvest)

thesis_urls <- read.csv("data/McGill_redirects.csv")
metadata <- list()

check_warning <- function(webpage){
  h2_text <- html_element(webpage, "h2") %>%
    html_text()
  return(ifelse(h2_text == "This website is under heavy load (queue full)", TRUE, FALSE))
}

get_source <- function(index){
  query <- thesis_urls[index,]
  print(query)
  driver$navigate(query)
  page_source <- driver$getPageSource()[[1]]
  webpage <- read_html(page_source)
  is_warning <- check_warning(webpage = webpage)
  if(is_warning == TRUE){
    Sys.sleep(60)
    get_source()
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

driver$navigate("https://escholarship.mcgill.ca/concern/theses/tm70n204k?locale=en")

for (i in 1:nrow(thesis_urls)){
  result <- get_source(index = i)
  print(i)
  print(thesis_urls[i,])
  metadata[[i]] <- html_elements(result, "dd") %>%
    html_text2()
  Sys.sleep(20)
}






