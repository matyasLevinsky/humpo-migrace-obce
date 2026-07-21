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
Potřebné balíčky: httr2, jsonlite, dplyr, purrr, readr, readxl.

Aktuální snapshot (obce + MOMC, jeden den):

    Rscript R/build_dataset.R

Vytvoří `data/processed/humpo_obce_latest.csv`.

Historický měsíční panel (viz níže):

    Rscript R/build_historical_dataset.R

Vytvoří `data/processed/humpo_obce_mesicni.csv`. Syrová stažená data
(`data/raw/*.rds`, `data/raw/mv_archiv/*.xlsx`) jsou gitignored, generují se
při každém běhu znovu.

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

## Poznámka k datům (aktuální snapshot)
HUMPO data se aktualizují denně; sloupec `gis_updated` říká, k jakému datu je
stažený snapshot platný.

## Historický měsíční panel (`humpo_obce_mesicni.csv`)
Cíl: ukázat, jak se uprchlíci v čase přesouvali z plošného rozptýlení po celé
ČR do velkých měst (koncentrace do měst za prací / do ubytovacích zařízení).

### Je vůbec historie dostupná?
Živý HUMPO ArcGIS FeatureServer (viz výše) je jen aktuální snapshot – v
metadatech vrstvy nemá `timeInfo`, `isDataArchived: false`,
`isDataVersioned: false`, žádný `historicMoment` dotaz nepodporuje. Žádnou
historii z něj získat nejde.

Historie ale existuje jinde: MV ČR archivuje starší týdenní XLSX soubory
(`statistika-obce-suk-vek-vse-DD-MM-RRRR.xlsx`) na stránkách
`mv.gov.cz/clanek/statistika-v-souvislosti-s-valkou-na-ukrajine-archiv[-ROK].aspx`,
a to od **28. 3. 2022** (nejstarší dohledaný soubor, cca měsíc po začátku
invaze) do **31. 5. 2026** – pak MV tuto konkrétní tabulku přestalo vydávat
(patrně v souvislosti s přechodem na veřejný HUMPO dashboard). Formát (24
sloupců: kraj, okres, obec, `kod_obce` [RUIAN kód – stejný jako `ruian_kod` v
živé HUMPO vrstvě], obec_mc [městská část], celkem + rozpad věk×pohlaví) je
za celé období 2022–2026 beze změny, ověřeno na vzorcích z 2022, 2023, 2025 a
2026.

### Jak je panel sestavený
- `R/fetch_historical_mv.R` projde archivní stránky MV ČR za roky 2022 až
  aktuální rok a sestaví seznam všech dostupných snapshotů (161 k 2026-07).
  Stránkování používá query parametr `q = base64("chnum=N")` (N = počet
  měsíců zpět).
- Pro každý kalendářní měsíc od 2022-03 do aktuálního měsíce se vybere časově
  nejbližší dostupný snapshot. Sloupec `dny_od_1_dne` říká, o kolik dní se
  skutečně použitá data liší od 1. dne cílového měsíce (u některých měsíců,
  kde MV nevydalo soubor blízko k 1. dni, to může být 1–3 týdny).
- Od června 2026 (kdy MV archiv končí) se použije živý HUMPO snapshot
  (`zdroj = "humpo_gis_live"`) místo MV archivu (`zdroj = "mv_archiv"`) –
  jediný dostupný zdroj pro nejnovější měsíce. Národní součet za 2026-07 z
  obou zdrojů vychází identicky (386 655), což slouží jako konzistenční
  kontrola napojení.
- Data z MV XLSX (dílčí městské části, např. "Praha 1") se agregují na
  úroveň celé obce (součet přes `kod_obce`) – stejná granularita jako
  obecní část živého snapshotu.

### Na co si dát pozor
- **MV archivní soubory obsahují jen obce, kde bylo hlášeno alespoň 1
  registrované osoby** (cca 4100–4700 řádků/měsíc) – zbylé obce v daném
  měsíci v datech chybí, což je potřeba interpretovat jako 0, ne jako NA.
  Živý HUMPO snapshot naopak obsahuje všech 6258 obcí explicitně (i s
  nulami) – proto poslední měsíc (2026-07) v panelu má výrazně víc řádků
  (6258) než předchozí měsíce ze zdroje `mv_archiv`. Součty a průměry to
  neovlivní, ale počítání "kolik obcí mělo uprchlíky" by bez tohoto vědomí
  zavádělo.
- Populace obce (denominátor pro koncentraci) v historickém panelu není –
  MV XLSX populaci neobsahuje. Pro poměrové ukazatele je potřeba dopočítat
  proti aktuální populaci z `humpo_obce_latest.csv` (populace obcí se v
  řádu let mění minimálně, takže aproximace současnou populací je pro
  účely tohoto srovnání v pořádku).
- Ověřený příklad trendu koncentrace: podíl Prahy na celkovém součtu
  `celkem` vzrostl z 25,2 % (březen 2022) na cca 26,3 % (2026) – s viditelnými
  drobnými poklesy vždy kolem dubna/května každého roku (pravděpodobně
  souvislost s ročním cyklem prodlužování dočasné ochrany, ne chyba dat).
