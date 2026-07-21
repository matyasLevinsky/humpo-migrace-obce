# HUMPO – migrace obce

Zpracování dat o ukrajinské migraci na úrovni obcí z portálu HUMPO (gis.humpo.cz),
který spravuje Ministerstvo vnitra ČR ve spolupráci s Arcdata Praha. Vzniklo jako
podklad pro analytický text PAQ Research (téma: Ukrajinská migrace na úrovni obcí,
komunální volby).

## Zdroje dat
- HUMPO ArcGIS FeatureServery (veřejné, dashboard č. 2 "Registrovaní uprchlíci z UA"),
  bez přihlášení:
  - obce: `.../humpo_dashboards_people_obec_public/FeatureServer/0`
  - MOMC (městské obvody/části – Praha, Brno, Ostrava, Plzeň a další): `.../humpo_dashboards_people_momc_public/FeatureServer/0`
- Doplňkově (mimo tento pipeline, pro křížovou kontrolu): MV ČR, denní XLS/XLSX počtů
  osob s dočasnou ochranou po obcích –
  https://mv.gov.cz/soubor/pocty-osob-s-udelenym-pobytovym-opravnenim-v-souvislosti-s-valkou-na-ukrajine-xlsx.aspx
  (jiná metodika než HUMPO, needownloaduje se automaticky tímto skriptem).

Projekt záměrně nepoužívá dashboardy č. 3 (adresy pobytu) a č. 4 (ubytovací kapacity) –
vyžadují přihlášení a obsahují citlivá adresní data konkrétních lidí.

## Spuštění
Potřebné balíčky: httr2, jsonlite, dplyr, purrr, readr.

    Rscript R/build_dataset.R

Vytvoří `data/processed/humpo_obce_latest.csv`. Syrová stažená data (`data/raw/*.rds`)
jsou gitignored, generují se při každém běhu znovu.

## Metodika (replikace logiky dashboardu)
- Obě vrstvy (obce + MOMC) se sečtou dohromady, ale z vrstvy „obec“ se napřed vyřadí
  ty obce, které mají rozpad na městské části/obvody (jejich `ruian_kod` se objevuje
  jako `ruian_kod_obec` ve vrstvě MOMC) – aby se velká města nepočítala dvakrát.
  Skip-list se odvozuje z dat, ne napevno; aktuálně (2026-07) jde o 8 obcí: Praha,
  Brno, Ostrava, Plzeň, Liberec, Opava, Pardubice, Ústí nad Labem.
- Hlavní ukazatel je `cis_people_count` (zdroj: Cizinecký informační systém –
  registrovaní uprchlíci). Vrstvy obsahují i paralelní sadu polí s prefixem `humpo_*`
  se stejnou strukturou, ale řádově nižšími hodnotami (jednotky/desítky na obec) –
  jde o jiný, mnohem užší ukazatel (patrně evidence přes HUMPO ubytovací modul), a
  tento pipeline ho nepoužívá jako hlavní číslo.
- Věkové/genderové rozpady (`cis_age_*_m/w/x_count`) mají tři kategorie (muž/žena/
  neuvedeno). Agregované sloupce `vek_do3` … `vek_65_plus` sčítají všechny tři.
- `koncentrace_pct` = zaokrouhlení nahoru na 1 desetinné místo:
  `ceiling(cis_people_count / ruian_poc_ob * 100 * 10) / 10`.
- `gis_updated` přichází z ArcGIS jako epoch čas v milisekundách – skript ho převádí
  na datum (`as.Date`).

### Co se lišilo od původního předpokladu
- Pole `ruian_kod_obec` existuje jen ve vrstvě MOMC (v obecní vrstvě dává smysl jen
  tam) – logika joinu s tím počítala už v původním návrhu, jen pro upřesnění.
- Věkové kategorie mají navíc `_x_count` (vedle `_m_count`/`_w_count`), který původní
  návrh sčítání opomíjel – doplněno.
- `access` v metadatech vrstvy není doslova `"public"`, ale prázdný string; vrstvy
  nicméně odpovídají na dotazy bez přihlášení (HTTP 200), takže jsou fakticky veřejné.
- `maxRecordCount` obou vrstev je 1000 (ne 2000), stránkování v `fetch_arcgis_layer()`
  je ale dynamické a bere hodnotu z metadat vrstvy, takže to nevadí.

## Poznámka k datům
HUMPO data se aktualizují denně; sloupec `gis_updated` říká, k jakému datu je
stažený snapshot platný.
