# R/fetch_obec_polygons.R
# Jednorazove stazeni zjednodusenych hranic obci (WGS84) z verejne HUMPO
# vrstvy pro choropleth mapu v Shiny appce. Pouziva se primo ArcGIS REST
# generalizace (maxAllowableOffset), ne vlastni zjednoduseni - hranice obci
# se meni jen velmi zridka, staci stahnout jednou a commitnout jako staticky
# soubor v shiny_app/data/.
library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

OBEC_URL <- "https://gis.humpo.cz/server/rest/services/Hosted/humpo_dashboards_people_obec_public/FeatureServer/0"
MAX_ALLOWABLE_OFFSET <- 0.003  # stupne WGS84, cca 300 m - generalizace hranic pro mapu na urovni celeho statu

meta <- request(OBEC_URL) |> req_url_query(f = "json") |> req_perform() |> resp_body_json()
page <- meta$maxRecordCount

total <- request(paste0(OBEC_URL, "/query")) |>
  req_url_query(where = "1=1", returnCountOnly = "true", f = "json") |>
  req_perform() |> resp_body_json() |> pluck("count")

cat("Stahuji hranice", total, "obci (maxAllowableOffset =", MAX_ALLOWABLE_OFFSET, ")...\n")

vsechny_hranice <- map_dfr(seq(0, total - 1, by = page), function(off) {
  resp <- request(paste0(OBEC_URL, "/query")) |>
    req_url_query(where = "1=1", outFields = "ruian_kod",
                   returnGeometry = "true", outSR = "4326",
                   maxAllowableOffset = MAX_ALLOWABLE_OFFSET,
                   resultOffset = off, resultRecordCount = page, f = "json") |>
    req_perform() |> resp_body_string() |> fromJSON(simplifyVector = FALSE)

  map_dfr(resp$features, function(ft) {
    kod <- as.character(ft$attributes$ruian_kod)
    rings <- ft$geometry$rings
    map_dfr(seq_along(rings), function(ring_idx) {
      pts <- rings[[ring_idx]]
      tibble(
        kod_obce = kod,
        skupina = paste(kod, ring_idx, sep = "_"),
        poradi = seq_along(pts),
        lon = vapply(pts, `[[`, numeric(1), 1),
        lat = vapply(pts, `[[`, numeric(1), 2)
      )
    })
  })
})

dir.create("shiny_app/data", recursive = TRUE, showWarnings = FALSE)
saveRDS(vsechny_hranice, "shiny_app/data/obec_hranice.rds")
cat("Ulozeno", nrow(vsechny_hranice), "vrcholu za", length(unique(vsechny_hranice$kod_obce)), "obci do shiny_app/data/obec_hranice.rds\n")
cat("Velikost souboru:", file.info("shiny_app/data/obec_hranice.rds")$size / 1024^2, "MB\n")
