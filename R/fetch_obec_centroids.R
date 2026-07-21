# R/fetch_obec_centroids.R
# Jednorazove stazeni centroidu (WGS84 lon/lat) vsech obci z verejne HUMPO
# vrstvy - pouziva se pro mapu v Shiny appce (shiny_app/). Hranice obci se
# meni jen velmi zridka, takze se centroidy neaktualizuji pri kazdem behu
# hlavniho pipeline, ale ulozi jako staticky soubor v shiny_app/data/.
library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

OBEC_URL <- "https://gis.humpo.cz/server/rest/services/Hosted/humpo_dashboards_people_obec_public/FeatureServer/0"

meta <- request(OBEC_URL) |> req_url_query(f = "json") |> req_perform() |> resp_body_json()
page <- meta$maxRecordCount

total <- request(paste0(OBEC_URL, "/query")) |>
  req_url_query(where = "1=1", returnCountOnly = "true", f = "json") |>
  req_perform() |> resp_body_json() |> pluck("count")

centroids <- map_dfr(seq(0, total - 1, by = page), function(off) {
  request(paste0(OBEC_URL, "/query")) |>
    req_url_query(where = "1=1", outFields = "ruian_kod,ruian_nazev",
                   returnGeometry = "false", returnCentroid = "true", outSR = "4326",
                   resultOffset = off, resultRecordCount = page, f = "json") |>
    req_perform() |> resp_body_string() |> fromJSON(flatten = TRUE) |> pluck("features") |> as_tibble()
})

centroids <- centroids |>
  rename_with(~ sub("^attributes\\.", "", .x)) |>
  rename_with(~ sub("^centroid\\.", "", .x)) |>
  transmute(kod_obce = as.character(ruian_kod), lon = x, lat = y)

dir.create("shiny_app/data", recursive = TRUE, showWarnings = FALSE)
write.csv(centroids, "shiny_app/data/obec_centroids.csv", row.names = FALSE)
cat("Ulozeno", nrow(centroids), "centroidu do shiny_app/data/obec_centroids.csv\n")
