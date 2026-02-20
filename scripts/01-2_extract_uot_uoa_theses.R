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
base_url_uot <- "https://utoronto.scholaris.ca/collections/"
collections_uot <- c("68d2b06c-86d1-4923-8545-66abbd105d96/", "d2508dbb-089d-44a3-86fd-16ab4b824231/")
attr(collections_uot, "collection") <- c("doctoral", "masters")

base_url_uoa <- "https://ualberta.scholaris.ca/collections/"
collections_uoa <- "f3d69d6d-203b-4472-a862-535e749ab216/"
attr(collections_uoa, "collection") <- c("all theses")

search_param <- "search?f.dateIssued.min=2022&f.dateIssued.max=2024&spc.rpp=100&spc.page="

search_string_uot <- paste0(base_url_uot, collections_uot, search_param)
search_string_uoa <- paste0(base_url_uoa, collections_uoa, search_param)

get_results <- function(search_string){
  ## LOADNG THE FIRST PAGE AND STARTING THE PROCESS
  # load the relevant page
  driver$navigate(paste0(search_string, "1"))
  # There's a delay in the script making the content available, so wait a bit.
  Sys.sleep(15)
  
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
    cat(paste0("Loading data from page ", counter, " of ", number_of_pages, "\n"))
    if(i == 1){
      titles <- get_title(webpage, ".lead")
      authors <- get_authors_abstract(webpage, ".content", 1)
      abstracts <- get_authors_abstract(webpage, ".content", 2)
      redirects <- get_redirects(webpage, ".lead")
    } else {
      driver$navigate(paste0(search_string, i))
      # lengthy delay instead of trycatch statement testing for element presence
      cat("Pausing for 20 seconds before parsing source.\n\n")
      Sys.sleep(20)
      page_source <- driver$getPageSource()[[1]]
      webpage <- read_html(page_source)
      titles <- c(titles, get_title(webpage, ".lead"))
      authors <- c(authors, get_authors_abstract(webpage, ".content", 1))
      abstracts <- c(abstracts, get_authors_abstract(webpage, ".content", 2))
      redirects <- c(redirects, get_redirects(webpage, ".lead"))
      # if(!identical(length(titles), length(authors), length(abstracts), length(redirects))){
      #   return_object <- list(titles = titles,
      #                         authors = authors,
      #                         abstracts = abstracts,
      #                         redirects = redirects)
      #   return(return_object)
      # }
    }
  }
  return_object <- list(titles = titles,
                        authors = authors,
                        abstracts = abstracts,
                        redirects = redirects)
  return(return_object)
}

uot_doctorals <- get_results(search_string = search_string_uot[1])
# the mark up is not ideal for scraping, some records for title and redirects, pulled from the
# same element(s) have strenuous data. Removing these.
uot_doctorals$titles <- uot_doctorals$titles[-grep("No Thumbnail Available", uot_doctorals$titles)]
uot_doctorals$redirects <- uot_doctorals$redirects[-which(is.na(uot_doctorals$redirects))]

uot_masters <- get_results(search_string = search_string_uot[2])
uot_masters$titles <- uot_masters$titles[-grep("No Thumbnail Available", uot_masters$titles)]
uot_masters$redirects <- uot_masters$redirects[-which(is.na(uot_masters$redirects))]

uoa_theses <- get_results(search_string = search_string_uoa)
uoa_theses_test$titles <- uoa_theses_test$titles[-grep("No Thumbnail Available", uoa_theses_test$titles)]
uoa_theses_test$redirects <- uoa_theses_test$redirects[-which(is.na(uoa_theses_test$redirects))]

uot_doctorals_df <- as.data.frame(uot_doctorals)
uot_masters_df <- as.data.frame(uot_masters)
uoa_theses_df <- as.data.frame(uoa_theses)
uot_doctorals_df$degree <- "doctoral"
uot_masters_df$degree <- "masters"
uot_theses_df <- rbind(uot_doctorals_df, uot_masters_df)

write.csv(x = uoa_theses_df, file = "data/processed_data/comparator-theses/Alberta_Results_Scholaris.csv", row.names = FALSE)
write.csv(x = uot_theses_df, file = "data/processed_data/comparator-theses/Toronto_Results_Scholaris.csv", row.names = FALSE)

# CLOSE THE DRIVER & CONNECTION
#############################

driver$close()
selenium_server$server$stop()
