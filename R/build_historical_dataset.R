# R/build_historical_dataset.R
# Mesicni panel poctu ukrajinskych uprchliku na urovni obci od zacatku
# valky (breznu 2022, kdy zacina dostupna obecni granularita) do soucasnosti.
#
# Zdroj do kvetna 2026: tydenni XLSX archiv MV CR (statistika-obce-*), viz
# R/fetch_historical_mv.R - MV tuto tabulku od 31. 5. 2026 dal nepublikuje.
# Zdroj od cervna 2026: zivy HUMPO ArcGIS snapshot (cis_people_count), viz
# R/fetch_humpo.R - jedina dostupna data pro nejnovejsi mesice.
#
# Pro kazdy cilovy mesic (vzdy 1. den) se pouzije casove nejblizsi dostupny
# snapshot; sloupec `dny_od_1_dne` rika, jak daleko od 1. dne mesice skutecne
# stazena data jsou (u brezna/dubna 2022 muze byt vetsi, protoze nejstarsi
# dostupny soubor je az z 28. 3. 2022).

source("R/fetch_historical_mv.R")
source("R/fetch_humpo.R")
library(dplyr)
library(purrr)
library(readr)

cat("Stahuji seznam historickych snapshotu z archivu MV CR...\n")
mv_index <- build_mv_archive_index()
cat("Nalezeno", nrow(mv_index), "MV snapshotu, od", as.character(min(mv_index$date)),
    "do", as.character(max(mv_index$date)), "\n")
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
write_csv(mv_index, "data/raw/mv_archiv_index.csv")

cat("Stahuji aktualni zivy HUMPO snapshot (obec-level)...\n")
obec_raw <- fetch_arcgis_layer(OBEC_URL)
dnes <- Sys.Date()

humpo_live <- obec_raw |>
  mutate(across(matches("^cis_age_.*_count$"), ~ replace(as.numeric(.x), is.na(.x), 0))) |>
  transmute(
    kraj = ruian_nazev_kraj,
    obec = ruian_nazev,
    kod_obce = as.character(ruian_kod),
    celkem = replace(as.numeric(cis_people_count), is.na(cis_people_count), 0),
    vek_do3     = cis_age_0_2_m_count   + cis_age_0_2_w_count   + cis_age_0_2_x_count,
    vek_3_6     = cis_age_3_5_m_count   + cis_age_3_5_w_count   + cis_age_3_5_x_count,
    vek_6_15    = cis_age_6_14_m_count  + cis_age_6_14_w_count  + cis_age_6_14_x_count,
    vek_15_18   = cis_age_15_17_m_count + cis_age_15_17_w_count + cis_age_15_17_x_count,
    vek_18_65   = cis_age_18_64_m_count + cis_age_18_64_w_count + cis_age_18_64_x_count,
    vek_65_plus = cis_age_65_m_count    + cis_age_65_w_count    + cis_age_65_x_count,
    snapshot_datum = dnes,
    zdroj = "humpo_gis_live"
  )

# jednotny seznam dostupnych snapshotu (MV archiv + jeden zivy HUMPO bod)
sources <- bind_rows(
  mv_index |> transmute(date, url, zdroj = "mv_archiv"),
  tibble(date = dnes, url = NA_character_, zdroj = "humpo_gis_live")
)

first_target <- as.Date("2022-03-01")
last_target  <- as.Date(format(dnes, "%Y-%m-01"))
target_months <- seq(first_target, last_target, by = "month")

pick_nearest <- function(target) {
  diffs <- abs(as.numeric(sources$date - target))
  sources[which.min(diffs), ]
}

picks <- map_dfr(target_months, function(tm) {
  s <- pick_nearest(tm)
  tibble(cilovy_mesic = tm, snapshot_datum = s$date, zdroj = s$zdroj, url = s$url)
})

cat("Stahuji a parsuji", nrow(picks), "mesicnich snapshotu...\n")
panel <- map_dfr(seq_len(nrow(picks)), function(i) {
  p <- picks[i, ]
  cat(" ", format(p$cilovy_mesic, "%Y-%m"), "->", as.character(p$snapshot_datum),
      paste0("(", p$zdroj, ")"), "\n")
  d <- if (p$zdroj == "mv_archiv") {
    fetch_mv_obce_snapshot(p$url, p$snapshot_datum)
  } else {
    humpo_live
  }
  d |>
    mutate(cilovy_mesic = p$cilovy_mesic,
           dny_od_1_dne = as.integer(snapshot_datum - cilovy_mesic)) |>
    select(cilovy_mesic, snapshot_datum, dny_od_1_dne, zdroj,
           kraj, obec, kod_obce, celkem,
           vek_do3, vek_3_6, vek_6_15, vek_15_18, vek_18_65, vek_65_plus)
})

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
write_csv(panel, "data/processed/humpo_obce_mesicni.csv")

cat("\nHotovo:", nrow(panel), "radku,", length(unique(panel$cilovy_mesic)), "mesicu",
    "(", format(min(panel$cilovy_mesic), "%Y-%m"), "az", format(max(panel$cilovy_mesic), "%Y-%m"), ")\n")

# rychla kontrola trendu - narodni soucet cis_people_count/celkem po mesicich
trend <- panel |> summarise(celkem = sum(celkem, na.rm = TRUE), .by = cilovy_mesic) |> arrange(cilovy_mesic)
cat("\nNarodni soucet podle mesice (prvnich 5 a poslednich 5):\n")
print(head(trend, 5))
print(tail(trend, 5))
