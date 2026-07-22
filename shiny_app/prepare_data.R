# shiny_app/prepare_data.R
# Pripravi kompaktni .rds soubory pro Shiny/shinylive appku z
# data/processed/humpo_obce_mesicni.csv + data/processed/humpo_obce_latest.csv.
# Spoustet znovu pokazde, kdyz se aktualizuje hlavni pipeline
# (R/build_historical_dataset.R). RDS misto CSV kvuli velikosti/rychlosti
# nacitani uvnitr webR (shinylive bezi v prohlizeci).
#
# Hranice obci/ORP/kraju + admin. prislusnost (obec_hranice.rds,
# orp_hranice.rds, kraj_hranice.rds, obec_admin.rds) se negeneruji tady -
# viz R/fetch_obec_polygons.R (RCzechia), spousti se samostatne a jen
# zridka (hranice se meni velmi vzacne).
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

# admin. prislusnost (kraj/ORP) z RCzechia - viz R/fetch_obec_polygons.R;
# nahrazuje puvodni "kraj" sloupec z MV/HUMPO dat, aby tooltip i kategorie
# pouzivaly stejny zdroj jako hranice na mape.
obec_admin <- readRDS("data/obec_admin.rds")

# lookup: jeden radek na obec (nazev z nejnovejsiho mesice + populace + admin.)
lookup <- panel |>
  filter(cilovy_mesic == max(cilovy_mesic)) |>
  distinct(kod_obce, obec) |>
  inner_join(populace, by = "kod_obce") |>
  inner_join(obec_admin, by = "kod_obce")

nespareno <- setdiff(unique(panel$kod_obce), lookup$kod_obce)
cat("Obci bez populace/admin. udaju (vyrazeno z mapy):", length(nespareno), "\n")

# MV archiv (viz R/fetch_historical_mv.R) zverejnoval jen obce s >=1 osobou
# za dany mesic - obec, ktera v danem mesici nemela zadneho uprchlika, tak v
# `panel` pro ten mesic nema VUBEC zadny radek (ne radek s NA). Bez opravy by
# se to do mapy/agregatu promitlo jako chybejici (sede/NA) udaje mista
# skutecne nuly - hlavne u starsich mesicu na zacatku valky, kdy vetsina
# malych obci jeste zadneho uprchlika nemela. Doplnime proto explicitni
# nulove radky pro VSECHNY kombinace mesic x obec (jen pro obce z `lookup`,
# tedy ty se znamou populaci/admin. prislusnosti), aby mapa i kategoriove
# agregaty (naprilad populacni jmenovatel v `kategorie_trend` v app.R) sedely
# i pro obdobi, kdy velka cast obci mela fakticky nulu.
mesic_zdroj <- panel |> distinct(cilovy_mesic, zdroj)
kostra <- distinct(panel, cilovy_mesic) |> cross_join(distinct(lookup, kod_obce))

panel <- kostra |>
  left_join(panel |> select(-zdroj), by = c("cilovy_mesic", "kod_obce")) |>
  left_join(mesic_zdroj, by = "cilovy_mesic") |>
  mutate(across(c(celkem, vek_do3, vek_3_6, vek_6_15, vek_15_18, vek_18_65, vek_65_plus),
                ~ replace(.x, is.na(.x), 0)))

narodni_soucet <- panel |> summarise(celkem_cr = sum(celkem, na.rm = TRUE), .by = cilovy_mesic)

# prumerny vek obce/mesic - aproximace: kazde vekove kategorii z HUMPO dat
# (cis_age_0_2/3_5/6_14/15_17/18_64/65_) je prirazen reprezentativni stred,
# vazeny prumer pres poznane pocty. Volba stredu je zaznamenana v README
# (zejmena 65+ je oteviena kategorie, 70 je odhad, ne empiricky zmereny
# prumer teto skupiny).
STRED_DO3 <- 1; STRED_3_6 <- 4; STRED_6_15 <- 10
STRED_15_18 <- 16; STRED_18_65 <- 41; STRED_65_PLUS <- 70

mesicni <- panel |>
  inner_join(populace, by = "kod_obce") |>
  inner_join(narodni_soucet, by = "cilovy_mesic") |>
  mutate(
    koncentrace_pct = celkem / populace * 100,
    podil_narodni_pct = celkem / celkem_cr * 100,
    prumerny_vek = if_else(
      celkem > 0,
      (vek_do3 * STRED_DO3 + vek_3_6 * STRED_3_6 + vek_6_15 * STRED_6_15 +
         vek_15_18 * STRED_15_18 + vek_18_65 * STRED_18_65 + vek_65_plus * STRED_65_PLUS) / celkem,
      NA_real_
    )
  ) |>
  transmute(cilovy_mesic = as.character(cilovy_mesic), kod_obce, celkem,
            koncentrace_pct, podil_narodni_pct, prumerny_vek, zdroj)

# narodni vekova struktura v case (0-17 / 18-64 / 65+) - hranice 17/18 podle
# toho, jak jsou HUMPO vekove kategorie skutecne rozdelene
# (cis_age_0_2/3_5/6_14/15_17 vs. cis_age_18_64 vs. cis_age_65_), ne
# libovolne zvolena.
vekova_struktura <- panel |>
  transmute(cilovy_mesic,
            deti = vek_do3 + vek_3_6 + vek_6_15 + vek_15_18,
            produktivni = vek_18_65,
            seniori = vek_65_plus) |>
  summarise(deti = sum(deti, na.rm = TRUE),
            produktivni = sum(produktivni, na.rm = TRUE),
            seniori = sum(seniori, na.rm = TRUE),
            .by = cilovy_mesic)

saveRDS(lookup, "data/obec_lookup.rds")
saveRDS(mesicni, "data/mesicni_panel.rds")
saveRDS(vekova_struktura, "data/vekova_struktura.rds")

cat("obec_lookup.rds:", nrow(lookup), "obci\n")
cat("mesicni_panel.rds:", nrow(mesicni), "radku,",
    length(unique(mesicni$cilovy_mesic)), "mesicu\n")
cat("vekova_struktura.rds:", nrow(vekova_struktura), "mesicu\n")
cat("velikosti souboru:\n")
print(file.info(c("data/obec_lookup.rds", "data/mesicni_panel.rds", "data/vekova_struktura.rds",
                   "data/obec_hranice.rds", "data/orp_hranice.rds", "data/kraj_hranice.rds"))[, "size", drop = FALSE])
