library(RSelenium)
library(magrittr)
library(rvest)

# start the server
selenium_server <- rsDriver(
  browser = "firefox",
  chromever = NULL,
  phantomver = NULL
)

# selenium_server <- rsDriver(
#   browser = "chrome",
#   chromever = "142.0.7444.162",
#   geckover = NULL,
#   phantomver = NULL
# )

# initiate the driver; will launch Firefox
driver <- selenium_server$client

# url and search paramters
base_url <- "https://utoronto.scholaris.ca/communities/a5728795-6703-4676-a4aa-64db5dc6a017/"
search_param <- "search?f.dateIssued.min=2022&f.dateIssued.max=2024&spc.rpp=100&spc.page="

## LOADNG THE FIRST PAGE AND STARTING THE PROCESS

# load the relevant page
driver$navigate(paste0(base_url, search_param, "1"))
# There's a delay in the script making the content available, so wait a bit.
Sys.sleep(10)

# get the page source
page_source <- driver$getPageSource()[[1]]
webpage <- read_html(page_source)

# Do some math to figure out how many pages need to be parsed
response_count <- html_elements(webpage, ".pagination-info") %>%
  html_text() %>%
  gsub("^.*of ", "", .) %>%
  as.integer()
number_of_pages <- ceiling(response_count/100)

# FUNCTIONS TO EXTRACT DATA
get_title <- function(source, attribute){
  return(html_elements(source, attribute) %>%
    html_text())
}
get_authors_abstract <- function(source, attribute, item){
  # author and abstract info is lumped together, odd index for authors, even for abstract
  authors_abstracts <- html_elements(source, attribute) %>%
    html_text()
  if(item == 1){
    return(authors_abstracts[c(TRUE, FALSE)])
  } else {
    return(authors_abstracts[c(FALSE, TRUE)])
  }
}
get_redirects <- function(source, attribute) {
  return(html_elements(source, attribute) %>%
           html_attr("href"))
}

counter = 0

for(i in 1:number_of_pages){
  counter = counter + 1
  print(counter)
  if(i == 1){
    titles <- get_title(webpage, ".lead")
    authors <- get_authors_abstract(webpage, ".content", 1)
    abstracts <- get_authors_abstract(webpage, ".content", 2)
    redirects <- get_redirects(webpage, ".lead")
  } else {
    driver$navigate(paste0(base_url, search_param, i))
    Sys.sleep(10)
    page_source <- driver$getPageSource()[[1]]
    webpage <- read_html(page_source)
    titles <- c(titles, get_title(webpage, ".lead"))
    authors <- c(authors, get_authors_abstract(webpage, ".content", 1))
    abstracts <- c(abstracts, get_authors_abstract(webpage, ".content", 2))
    redirects <- c(redirects, get_redirects(webpage, ".lead"))
  }
}

# CLOSE THE DRIVER & CONNECTION
#############################

driver$close()
selenium_server$server$stop()
