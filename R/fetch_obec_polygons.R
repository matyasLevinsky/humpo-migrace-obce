# R/fetch_obec_polygons.R
# Jednorazove stazeni hranic obci (WGS84) z verejne HUMPO vrstvy pro
# choropleth mapu v Shiny appce. Hranice obci se meni jen velmi zridka,
# staci stahnout jednou a commitnout jako staticky soubor v shiny_app/data/.
#
# DULEZITE: server-side generalizace (ArcGIS maxAllowableOffset) simplifikuje
# kazdy polygon NEZAVISLE, coz mezi sousednimi obcemi vytvari mezery (jejich
# spolecna hranice se po zjednoduseni jinak posune na kazde strane). Misto
# toho se stahuje PLNE rozliseni a zjednodusuje se topologicky pres
# rmapshaper::ms_simplify(keep_shapes = TRUE), ktery zachovava sdilene
# vrcholy/hrany mezi sousedy - vysledek je bezmezerovy.
library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)
library(sf)
library(rmapshaper)
library(sfheaders)

OBEC_URL <- "https://gis.humpo.cz/server/rest/services/Hosted/humpo_dashboards_people_obec_public/FeatureServer/0"
KEEP_RATIO <- 0.07  # podil vrcholu ponechany po topologickem zjednoduseni

meta <- request(OBEC_URL) |> req_url_query(f = "json") |> req_perform() |> resp_body_json()
page <- meta$maxRecordCount

total <- request(paste0(OBEC_URL, "/query")) |>
  req_url_query(where = "1=1", returnCountOnly = "true", f = "json") |>
  req_perform() |> resp_body_json() |> pluck("count")

cat("Stahuji hranice", total, "obci v plnem rozliseni...\n")
hranice_plne <- map_dfr(seq(0, total - 1, by = page), function(off) {
  resp <- request(paste0(OBEC_URL, "/query")) |>
    req_url_query(where = "1=1", outFields = "ruian_kod",
                   returnGeometry = "true", outSR = "4326",
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
cat("Plne rozliseni:", nrow(hranice_plne), "vrcholu,", length(unique(hranice_plne$kod_obce)), "obci\n")

cat("Prevod na sf (jeden prstenec = jeden polygon)...\n")
sf_obj <- sfheaders::sf_polygon(hranice_plne, x = "lon", y = "lat", polygon_id = "skupina", keep = TRUE)
sf::st_crs(sf_obj) <- 4326

cat("Topologicky zjednodusuji (keep =", KEEP_RATIO, ")...\n")
t0 <- Sys.time()
sf_simpl <- rmapshaper::ms_simplify(sf_obj, keep = KEEP_RATIO, keep_shapes = TRUE, sys = FALSE)
cat("cas zjednoduseni:", as.numeric(Sys.time() - t0, units = "secs"), "s\n")

cat("Zpet na plochou tabulku lon/lat...\n")
coords <- sf::st_coordinates(sf_simpl)
flat <- tibble(
  lon = coords[, "X"],
  lat = coords[, "Y"],
  radek_polygonu = coords[, "L2"]
)
flat$skupina <- sf_simpl$skupina[flat$radek_polygonu]
flat$kod_obce <- sf_simpl$kod_obce[flat$radek_polygonu]
flat <- flat |>
  group_by(skupina) |>
  mutate(poradi = row_number()) |>
  ungroup() |>
  select(kod_obce, skupina, poradi, lon, lat)

dir.create("shiny_app/data", recursive = TRUE, showWarnings = FALSE)
saveRDS(flat, "shiny_app/data/obec_hranice.rds")
cat("Ulozeno", nrow(flat), "vrcholu za", length(unique(flat$kod_obce)), "obci do shiny_app/data/obec_hranice.rds\n")
cat("Velikost souboru:", file.info("shiny_app/data/obec_hranice.rds")$size / 1024^2, "MB\n")
