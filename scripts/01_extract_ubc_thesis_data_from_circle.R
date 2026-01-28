library(httr2)
library(rvest)

base_url <- "https://open.library.ubc.ca/collections/cIRcle/ubctheses/browse?year="
years <- c("2022", "2023", "2024")
html <- list(titles = vector(),
             links = vector())

# get thesis titles and urls by year
for (i in 1:length(years)){
  query <- paste0(base_url, years[i])
  print(query)
  response <- request(query) |>
    req_perform() |>
    resp_body_html()
  titles <- html_elements(response, ".dl-r-title") |> html_text()
  links <- html_elements(response, ".dl-r-title") |> html_attr("href")
  html$titles <- c(html$titles, titles)
  html$links <- c(html$links, links)
  if(i < length(years)){
    Sys.sleep(3)
  }
}

df <- as.data.frame(html)

# get thesis details
metadata <- list()
counter <- 0

for(i in 1:nrow(df)){
  link <- df[i, "links"]
  details <- request(link) |>
    req_perform() |>
    resp_body_html() |>
    html_element("#itemTable") |>
    html_table() |>
    t() |>
    as.data.frame()
  names(details) <- details[1,]
  metadata[[i]] <- details[-1,]
  print(metadata[[i]])
  if(i < nrow(df)){
    Sys.sleep(sample(1:10, 1))
  }
  counter <- counter + 1
  print(counter)
}

#save(metadata, file = "ubc_thesis_list_export.RData")
merged.data.frame = Reduce(function(...) merge(..., all=T), metadata)
# write.csv(merged.data.frame, file = "ubc_thesis_data.csv", row.names = FALSE)
