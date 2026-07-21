# shiny_app/prepare_data.R
# Pripravi kompaktni .rds soubory pro Shiny/shinylive appku z
# data/processed/humpo_obce_mesicni.csv + data/processed/humpo_obce_latest.csv.
# Spoustet znovu pokazde, kdyz se aktualizuje hlavni pipeline
# (R/build_historical_dataset.R). RDS misto CSV kvuli velikosti/rychlosti
# nacitani uvnitr webR (shinylive bezi v prohlizeci).
library(dplyr)
library(readr)

panel <- read_csv("../data/processed/humpo_obce_mesicni.csv", show_col_types = FALSE,
                   col_types = cols(kod_obce = col_character()))

# populace obce (denominator pro koncentraci) - historicky panel populaci
# neobsahuje (viz README), bere se z aktualniho zivého snapshotu. Populace
# obci se v radu let meni jen minimalne, takze aproximace soucasnou hodnotou
# je pro srovnani v case v poradku.
#
# humpo_obce_latest.csv nema primy radek pro obce s MOMC rozpadem (Praha,
# Brno, ...) - jejich populace se musi sectst pres jednotlive casti (stejny
# princip jako u poctu uprchliku v hlavnim pipeline).
snapshot <- read_csv("../data/processed/humpo_obce_latest.csv", show_col_types = FALSE,
                      col_types = cols(ruian_kod = col_character(), ruian_kod_obec = col_character()))
populace_primo <- snapshot |> filter(is.na(ruian_kod_obec)) |>
  transmute(kod_obce = ruian_kod, populace = ruian_poc_ob)
populace_z_momc <- snapshot |> filter(!is.na(ruian_kod_obec)) |>
  summarise(populace = sum(ruian_poc_ob, na.rm = TRUE), .by = ruian_kod_obec) |>
  rename(kod_obce = ruian_kod_obec)
populace <- bind_rows(populace_primo, populace_z_momc)

# lookup: jeden radek na obec (nazev/kraj z nejnovejsiho mesice + populace)
lookup <- panel |>
  filter(cilovy_mesic == max(cilovy_mesic)) |>
  distinct(kod_obce, obec, kraj) |>
  inner_join(populace, by = "kod_obce")

nespareno <- setdiff(unique(panel$kod_obce), lookup$kod_obce)
cat("Obci bez populace (vyrazeno z mapy):", length(nespareno), "\n")

mesicni <- panel |>
  filter(kod_obce %in% lookup$kod_obce) |>
  inner_join(populace, by = "kod_obce") |>
  mutate(koncentrace_pct = celkem / populace * 100) |>
  transmute(cilovy_mesic = as.character(cilovy_mesic), kod_obce, celkem, koncentrace_pct, zdroj)

saveRDS(lookup, "data/obec_lookup.rds")
saveRDS(mesicni, "data/mesicni_panel.rds")

cat("obec_lookup.rds:", nrow(lookup), "obci\n")
cat("mesicni_panel.rds:", nrow(mesicni), "radku,",
    length(unique(mesicni$cilovy_mesic)), "mesicu\n")
cat("velikosti souboru:\n")
print(file.info(c("data/obec_lookup.rds", "data/mesicni_panel.rds", "data/obec_hranice.rds"))[, "size", drop = FALSE])
