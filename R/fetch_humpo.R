# R/fetch_humpo.R
# Stazeni dat z verejnych HUMPO FeatureServeru (gis.humpo.cz)
# Overeno: obe vrstvy odpovidaji bez prihlaseni (HTTP 200, zadny login token).

library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

OBEC_URL <- "https://gis.humpo.cz/server/rest/services/Hosted/humpo_dashboards_people_obec_public/FeatureServer/0"
MOMC_URL <- "https://gis.humpo.cz/server/rest/services/Hosted/humpo_dashboards_people_momc_public/FeatureServer/0"

#' Stahne kompletni obsah ArcGIS FeatureServer vrstvy (se strankovanim)
fetch_arcgis_layer <- function(layer_url, where = "1=1", out_fields = "*") {
  meta <- request(layer_url) |> req_url_query(f = "json") |> req_perform() |> resp_body_json()
  page <- if (is.null(meta$maxRecordCount)) 1000 else meta$maxRecordCount

  total <- request(paste0(layer_url, "/query")) |>
    req_url_query(where = where, returnCountOnly = "true", f = "json") |>
    req_perform() |> resp_body_json() |> pluck("count")

  out <- map_dfr(seq(0, max(total - 1, 0), by = page), function(off) {
    request(paste0(layer_url, "/query")) |>
      req_url_query(where = where, outFields = out_fields,
                     resultOffset = off, resultRecordCount = page, f = "json") |>
      req_perform() |> resp_body_string() |> fromJSON(flatten = TRUE) |> pluck("features") |> as_tibble()
  })
  rename_with(out, ~ sub("^attributes\\.", "", .x))
}

download_humpo_raw <- function(save_dir = "data/raw") {
  dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
  obec_raw <- fetch_arcgis_layer(OBEC_URL)
  momc_raw <- fetch_arcgis_layer(MOMC_URL)
  saveRDS(obec_raw, file.path(save_dir, "obec_raw.rds"))
  saveRDS(momc_raw, file.path(save_dir, "momc_raw.rds"))
  list(obec = obec_raw, momc = momc_raw)
}
