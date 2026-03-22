library(httr2)
library(rvest)

dat <- read.csv("data/processed_data/comparator-theses/raw/Alberta_Results_Scholaris.csv")
dat$degree <- NA

for(i in 1:nrow(dat)) {
  base_url <- "https://ualberta.scholaris.ca"
  req <- paste0(base_url, dat$redirects[i])
  cat(paste0("Running record ", i, " of ", nrow(dat), "\n"))
  cat(paste0("Requesting: ", req, "\n"))
  webpage <- request(req) |>
    req_error(is_error = \(resp) FALSE) |>
    req_perform()
  cat("Status: ", resp_status(webpage), "\n")
  if(resp_status(webpage) != 200){
    dat$degree[i] <- paste0("Error: ", resp_status(webpage))
  } else {
    webpage <- webpage |>
      resp_body_html() |>
      html_elements(".dont-break-out") |>
      html_text() |>
      paste(collapse = " ")
    dat$degree[i] <- ifelse(grepl("Master's", webpage) == TRUE, "masters",
                            ifelse(grepl("Doctoral", webpage) == TRUE,"doctoral", NA))
  }
  if(i < nrow(dat)){
    pause <- sample(5:10, 1)
    cat(paste0("Pausing for ", pause, " seconds.\n\n"))
    Sys.sleep(pause)
  }
}

# Try to get missing data
missing_data <- dat[which(grepl("Error", dat$degree) | is.na(dat$degree)),]
length_missing_data <- nrow(missing_data)

counter <- 0

for(i in rownames(missing_data)){
  counter <- counter + 1
  base_url <- "https://ualberta.scholaris.ca"
  row_number <- as.integer(i)
  req <- paste0(base_url, dat$redirects[row_number])
  cat(paste0("Running record ", i, " of ", nrow(missing_data), "\n"))
  cat(paste0("Requesting: ", req, "\n"))
  webpage <- request(req) |>
    req_error(is_error = \(resp) FALSE) |>
    req_perform()
  cat("Status: ", resp_status(webpage), "\n")
  if(resp_status(webpage) != 200){
    dat$degree[row_number] <- paste0("Error: ", resp_status(webpage))
  } else {
    webpage <- webpage |>
      resp_body_html() |>
      html_elements(".dont-break-out") |>
      html_text() |>
      paste(collapse = " ")
    dat$degree[row_number] <- ifelse(grepl("Master's", webpage) == TRUE, "masters",
                            ifelse(grepl("Doctoral", webpage) == TRUE,"doctoral", NA))
  }
  if(counter < length_missing_data){
    pause <- sample(5:10, 1)
    cat(paste0("Pausing for ", pause, " seconds.\n\n"))
    Sys.sleep(pause)
  }
}

write.csv(dat, "data/processed_data/comparator-theses/raw/Alberta_Results_Scholaris_with_degrees.csv", row.names = FALSE)
