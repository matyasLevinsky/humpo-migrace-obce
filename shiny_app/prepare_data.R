# shiny_app/prepare_data.R
# Pripravi kompaktni .rds soubory pro Shiny/shinylive appku z
# data/processed/humpo_obce_mesicni.csv. Spoustet znovu pokazde, kdyz se
# aktualizuje hlavni pipeline (R/build_historical_dataset.R). RDS misto CSV
# kvuli velikosti/rychlosti nacitani uvnitr webR (shinylive bezi v prohlizeci).
library(dplyr)
library(readr)

panel <- read_csv("../data/processed/humpo_obce_mesicni.csv", show_col_types = FALSE,
                   col_types = cols(kod_obce = col_character()))
centroids <- read_csv("data/obec_centroids.csv", show_col_types = FALSE,
                       col_types = cols(kod_obce = col_character()))

# lookup: jeden radek na obec (nazev/kraj z nejnovejsiho mesice + centroid)
lookup <- panel |>
  filter(cilovy_mesic == max(cilovy_mesic)) |>
  distinct(kod_obce, obec, kraj) |>
  inner_join(centroids, by = "kod_obce")

nespareno <- setdiff(unique(panel$kod_obce), lookup$kod_obce)
cat("Obci bez centroidu (vyrazeno z mapy):", length(nespareno), "\n")

mesicni <- panel |>
  filter(kod_obce %in% lookup$kod_obce) |>
  transmute(cilovy_mesic = as.character(cilovy_mesic), kod_obce, celkem, zdroj)

saveRDS(lookup, "data/obec_lookup.rds")
saveRDS(mesicni, "data/mesicni_panel.rds")

cat("obec_lookup.rds:", nrow(lookup), "obci\n")
cat("mesicni_panel.rds:", nrow(mesicni), "radku,",
    length(unique(mesicni$cilovy_mesic)), "mesicu\n")
cat("velikosti souboru:\n")
print(file.info(c("data/obec_lookup.rds", "data/mesicni_panel.rds"))[, "size", drop = FALSE])
