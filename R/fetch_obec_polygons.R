# R/fetch_obec_polygons.R
# Jednorazove stazeni hranic obci, ORP a kraju z balicku RCzechia pro
# choropleth mapu v Shiny appce. Hranice se meni jen velmi zridka, staci
# stahnout jednou a commitnout jako staticke soubory v shiny_app/data/.
#
# Proc RCzechia mista rucniho stahovani z ArcGIS/HUMPO (puvodni reseni):
# RCzechia::obce_polygony() ma presne RUIAN kody obci (KOD_OBEC, overeno:
# 6258/6258 - 100% shoda s kody pouzitymi v HUMPO/MV datech), a navic uz ma
# u kazde obce rovnou pripojene KOD_ORP/NAZ_ORP/KOD_KRAJ/NAZ_CZNUTS3 - takze
# odpada potreba samostatneho joinu na kraj/ORP pro tooltip.
#
# DULEZITE: topologicke zjednoduseni (ne server-side generalizace nezavisle
# na kazdem polygonu) - viz puvodni komentar v historii souboru: nezavisla
# generalizace vytvari mezery mezi sousedy. rmapshaper::ms_simplify(
# keep_shapes = TRUE) zachovava sdilene vrcholy/hrany mezi sousedy.
library(RCzechia)
library(sf)
library(rmapshaper)
library(dplyr)

#' Prevede (pripadne zjednodusene) sf polygony na plochou tabulku
#' kod/skupina/poradi/lon/lat pouzitelnou primo v ggplot2::geom_polygon.
flatten_sf <- function(sf_obj, kod_col) {
  mp <- sf::st_cast(sf::st_geometry(sf_obj), "MULTIPOLYGON")
  coords <- sf::st_coordinates(mp)
  kod <- sf_obj[[kod_col]][coords[, "L3"]]
  tibble(
    kod = as.character(kod),
    skupina = paste(kod, coords[, "L3"], coords[, "L2"], coords[, "L1"], sep = "_"),
    poradi = seq_len(nrow(coords)),
    lon = coords[, "X"],
    lat = coords[, "Y"]
  )
}

dir.create("shiny_app/data", recursive = TRUE, showWarnings = FALSE)

# --- obce: hlavni choropleth vrstva + admin. prislusnost pro tooltip -------
cat("Stahuji hranice obci (RCzechia::obce_polygony)...\n")
obce_sf <- obce_polygony()

obec_admin <- obce_sf |>
  sf::st_drop_geometry() |>
  transmute(kod_obce = as.character(KOD_OBEC),
            orp_nazev = NAZ_ORP,
            kraj_nazev = NAZ_CZNUTS3)
saveRDS(obec_admin, "shiny_app/data/obec_admin.rds")
cat("obec_admin.rds:", nrow(obec_admin), "obci\n")

cat("Topologicky zjednodusuji obce (keep = 0.07)...\n")
obce_simpl <- rmapshaper::ms_simplify(obce_sf, keep = 0.07, keep_shapes = TRUE, sys = FALSE)
obec_hranice <- flatten_sf(obce_simpl, "KOD_OBEC") |> rename(kod_obce = kod)
saveRDS(obec_hranice, "shiny_app/data/obec_hranice.rds")
cat("obec_hranice.rds:", nrow(obec_hranice), "vrcholu,",
    length(unique(obec_hranice$kod_obce)), "obci,",
    file.info("shiny_app/data/obec_hranice.rds")$size / 1024^2, "MB\n")

# --- ORP hranice (jen obrysove linie, kresli se pres choropleth) -----------
cat("Stahuji hranice ORP (RCzechia::orp_polygony)...\n")
orp_sf <- orp_polygony()
cat("Topologicky zjednodusuji ORP (keep = 0.1)...\n")
orp_simpl <- rmapshaper::ms_simplify(orp_sf, keep = 0.1, keep_shapes = TRUE, sys = FALSE)
orp_hranice <- flatten_sf(orp_simpl, "KOD_ORP") |> rename(kod_orp = kod)
saveRDS(orp_hranice, "shiny_app/data/orp_hranice.rds")
cat("orp_hranice.rds:", nrow(orp_hranice), "vrcholu,",
    file.info("shiny_app/data/orp_hranice.rds")$size / 1024^2, "MB\n")

# --- kraje hranice (jen obrysove linie) ------------------------------------
cat("Stahuji hranice kraju (RCzechia::kraje)...\n")
kraj_sf <- kraje()
cat("Topologicky zjednodusuji kraje (keep = 0.15)...\n")
kraj_simpl <- rmapshaper::ms_simplify(kraj_sf, keep = 0.15, keep_shapes = TRUE, sys = FALSE)
kraj_hranice <- flatten_sf(kraj_simpl, "KOD_KRAJ") |> rename(kod_kraj = kod)
saveRDS(kraj_hranice, "shiny_app/data/kraj_hranice.rds")
cat("kraj_hranice.rds:", nrow(kraj_hranice), "vrcholu,",
    file.info("shiny_app/data/kraj_hranice.rds")$size / 1024^2, "MB\n")

cat("\nHotovo.\n")
