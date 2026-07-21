# R/fetch_historical_mv.R
# Historicke mesicni snapshoty poctu ukrajinskych uprchliku na urovni obci.
#
# HUMPO ArcGIS FeatureServer (viz fetch_humpo.R) je jen zivy snapshot -
# nema timeInfo, isDataArchived=FALSE, isDataVersioned=FALSE, zadny
# historicMoment dotaz nepodporuje. Zadnou historii z nej ziskat nejde.
#
# MV CR ale archivuje starsi tydenni XLSX soubory "statistika-obce-*" na
# strankach mv.gov.cz/clanek/statistika-v-souvislosti-s-valkou-na-ukrajine-
# archiv[-ROK].aspx, a to od 28. 3. 2022 (nejstarsi nalezeny soubor) do
# 31. 5. 2026 (posledni publikovany soubor - pak MV tuto konkretni tabulku
# prestalo vydavat, patrne v souvislosti s prechodem na verejny HUMPO
# dashboard). Format (24 sloupcu: kraj, okres, obec, kod_obce, obec_mc,
# celkem + vek/pohlavi rozpady) je za cele obdobi identicky - overeno na
# vzorcich z 2022, 2023, 2025 a 2026.
#
# Archivni stranky jsou strankovane pres query parametr q = base64("chnum=N"),
# kde N je pocet mesicu zpet od aktualne zobrazeneho mesice teto rocni
# stranky (N=1 = vychozi zobrazeni bez parametru).

library(httr2)
library(readxl)
library(dplyr)
library(purrr)

ARCHIVE_BASE <- "https://mv.gov.cz/clanek/statistika-v-souvislosti-s-valkou-na-ukrajine-archiv"

chnum_query <- function(n) {
  if (n <= 1) return(NULL)
  jsonlite::base64_enc(charToRaw(paste0("chnum=", n)))
}

archive_page_url <- function(year, chnum) {
  # rok 2024 nema v URL adrese rocni sufix (archiv.aspx bez "-2024") - jde o
  # puvodni jednu archivni stranku, pozdeji rozdelenou po rocich; ostatni
  # roky maji sufix "-ROK" (napr. archiv-2025.aspx).
  suffix <- if (year == 2024) "" else paste0("-", year)
  url <- paste0(ARCHIVE_BASE, suffix, ".aspx")
  q <- chnum_query(chnum)
  if (!is.null(q)) url <- paste0(url, "?q=", utils::URLencode(q, reserved = TRUE))
  url
}

# vytahne odkazy + data z "statistika-obce-*-DD-MM-YYYY-xlsx.aspx" hrefu
extract_obce_links <- function(html) {
  pattern <- 'href="(soubor/statistika-obce[^"]*-([0-9]{2})-([0-9]{2})-([0-9]{4})-xlsx\\.aspx)"'
  loc <- gregexpr(pattern, html, perl = TRUE)
  matches <- regmatches(html, loc)[[1]]
  if (length(matches) == 0) return(tibble(date = as.Date(character()), url = character()))
  map_dfr(matches, function(x) {
    g <- regmatches(x, regexec(pattern, x, perl = TRUE))[[1]]
    tibble(
      date = as.Date(paste(g[5], g[4], g[3], sep = "-")),
      url  = paste0("https://mv.gov.cz/", g[2])
    )
  })
}

#' Projde archivni stranky MV CR za dane roky (vychozi = 2022 az aktualni
#' rok) a sestavi seznam vsech dostupnych "statistika-obce" snapshotu.
build_mv_archive_index <- function(years = 2022:as.integer(format(Sys.Date(), "%Y"))) {
  map_dfr(years, function(y) {
    map_dfr(1:12, function(n) {
      url <- archive_page_url(y, n)
      resp <- tryCatch(request(url) |> req_perform(), error = function(e) NULL)
      if (is.null(resp) || resp_status(resp) != 200) return(tibble())
      extract_obce_links(resp_body_string(resp))
    })
  }) |> distinct(date, .keep_all = TRUE) |> arrange(date)
}

MV_COLS <- c("kraj", "okres", "obec", "kod_obce", "obec_mc", "celkem",
             "m_do3", "z_do3", "x_do3", "m_do6", "z_do6", "x_do6",
             "m_do15", "z_do15", "x_do15", "m_do18", "z_do18", "x_do18",
             "m_do65", "z_do65", "x_do65", "m_sen", "z_sen", "x_sen")

#' Stahne (s cache v cache_dir) a naparsuje jeden MV XLSX soubor, agreguje
#' castecne obce (obec_mc, napr. "Praha 1") na urovnovou obec - stejnou
#' granularitu jako obec-level cast ziveho HUMPO snapshotu.
fetch_mv_obce_snapshot <- function(url, snapshot_date, cache_dir = "data/raw/mv_archiv") {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(cache_dir, paste0(snapshot_date, ".xlsx"))
  if (!file.exists(dest)) {
    download.file(url, dest, mode = "wb", quiet = TRUE)
  }
  d <- suppressMessages(read_excel(dest, sheet = 1, skip = 1, col_names = FALSE))
  names(d) <- MV_COLS

  d |>
    filter(!is.na(kod_obce)) |>
    mutate(across(celkem:x_sen, as.numeric)) |>
    group_by(kraj, obec, kod_obce = as.character(kod_obce)) |>
    summarise(
      celkem      = sum(celkem, na.rm = TRUE),
      vek_do3     = sum(m_do3 + z_do3 + x_do3, na.rm = TRUE),
      vek_3_6     = sum(m_do6 + z_do6 + x_do6, na.rm = TRUE),
      vek_6_15    = sum(m_do15 + z_do15 + x_do15, na.rm = TRUE),
      vek_15_18   = sum(m_do18 + z_do18 + x_do18, na.rm = TRUE),
      vek_18_65   = sum(m_do65 + z_do65 + x_do65, na.rm = TRUE),
      vek_65_plus = sum(m_sen + z_sen + x_sen, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(snapshot_datum = snapshot_date, zdroj = "mv_archiv")
}
