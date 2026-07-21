# R/build_dataset.R
source("R/fetch_humpo.R")
library(dplyr)
library(readr)

raw <- download_humpo_raw()
obec_raw <- raw$obec
momc_raw <- raw$momc

# replikace logiky dashboardu: obce s rozpadem na MOMC (Praha, Brno, Ostrava,
# Plzen, Liberec, Opava, Pardubice, Usti nad Labem - zjisteno z dat, nikoli
# napevno) vynech z "obec", aby se nepocitaly dvakrat.
skip_ids   <- unique(momc_raw$ruian_kod_obec)
obec_clean <- obec_raw |> filter(!ruian_kod %in% skip_ids)

# vekove/genderove pole maji tri kategorie: m (muz), w (zena), x (neuvedeno/jine).
# Puvodni navrh scitani pocital jen m+w - zde pridavame i x, protoze ve schematu
# existuje a u nekterych obci (typicky velka mesta) muze byt nenulove.
#
# API vraci NULL (NA po nacteni) misto 0 pro pocty ve vrstvach cis_*/humpo_* u
# obci bez zadnych registrovanych uprchliku - nejde o chybejici data, ale o
# zpusob, jak zdroj koduje nulu. Pro cistou tabulku na urovni obci to prevadime
# na skutecnou 0, aby soucty a odvozene sloupce (vek_*, koncentrace_pct) nebyly NA.
count_cols <- names(obec_raw)[grepl("^(cis_|humpo_)", names(obec_raw)) &
                                 grepl("(_count|_sum)$", names(obec_raw))]

data_final <- bind_rows(obec_clean, momc_raw) |>
  mutate(across(all_of(count_cols), ~ replace(.x, is.na(.x), 0))) |>
  mutate(
    vek_do3     = cis_age_0_2_m_count   + cis_age_0_2_w_count   + cis_age_0_2_x_count,
    vek_3_6     = cis_age_3_5_m_count   + cis_age_3_5_w_count   + cis_age_3_5_x_count,
    vek_6_15    = cis_age_6_14_m_count  + cis_age_6_14_w_count  + cis_age_6_14_x_count,
    vek_15_18   = cis_age_15_17_m_count + cis_age_15_17_w_count + cis_age_15_17_x_count,
    vek_18_65   = cis_age_18_64_m_count + cis_age_18_64_w_count + cis_age_18_64_x_count,
    vek_65_plus = cis_age_65_m_count    + cis_age_65_w_count    + cis_age_65_x_count,
    koncentrace_pct = ceiling(cis_people_count / ruian_poc_ob * 100 * 10) / 10,
    # gis_updated prichazi jako epoch cas v milisekundach (ArcGIS esriFieldTypeDate)
    gis_updated = as.Date(as.POSIXct(gis_updated / 1000, origin = "1970-01-01", tz = "UTC"))
  )

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
write_csv(data_final, "data/processed/humpo_obce_latest.csv")

cat("Hotovo:", nrow(data_final), "radku,",
    "soucet cis_people_count =", sum(data_final$cis_people_count, na.rm = TRUE), "\n")
if ("gis_updated" %in% names(data_final)) {
  cat("Data platna k:", as.character(unique(data_final$gis_updated)[1]), "\n")
}

# rychla kontrola integrity
n_na_key <- sum(is.na(data_final$ruian_kod) | is.na(data_final$ruian_nazev) | is.na(data_final$cis_people_count))
cat("NA v klicovych sloupcich (ruian_kod/ruian_nazev/cis_people_count):", n_na_key, "\n")
