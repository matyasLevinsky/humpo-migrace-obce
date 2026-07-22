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
  (6258) než předchozí měsíce ze zdroje `mv_archiv`. `humpo_obce_mesicni.csv`
  samotné (výstup `R/build_historical_dataset.R`) se **záměrně neopravuje**
  – zůstává věrnou kopií toho, co MV/HUMPO skutečně publikovaly.
  Chybějící řádky se na nuly doplňují až v `shiny_app/prepare_data.R` (viz
  níže), který appce dodává data.
- **Chybějící řádky ovlivňovaly appku víc, než se původně čekalo.** Prostý
  národní součet (`sum(celkem)`) chybějícími řádky zkreslený není (chybějící
  obec přispívá 0, ať už řádek existuje nebo ne). Poměrové ukazatele se
  jmenovatelem počítaným jen z **přítomných** řádků ale ano – appka v
  `app.R` počítala koncentraci pro skupiny obcí jako
  `sum(uprchlíci skupiny) / sum(populace skupiny)`, kde `sum(populace)` se
  bez opravy počítal jen přes obce, které v daném měsíci měly řádek (tj. měly
  ≥1 uprchlíka) – u starších měsíců, kdy velká část malých obcí ještě
  uprchlíky neměla, to jmenovatel uměle zmenšovalo a koncentraci pro
  kategorii "Malé obce" nadhodnocovalo. Oprava (viz níže) tohle odstraňuje;
  ověřeno, že po opravě je součet populace v kategorii konstantní napříč
  všemi 53 měsíci (dřív se lišil měsíc od měsíce).
- **Oprava (`shiny_app/prepare_data.R`):** po sestavení `lookup` (seznam obcí
  se známou populací/admin. příslušností) se panel doplní na plný obdélník
  měsíc × obec (`tidyr`-like cross join přes `dplyr::cross_join()` +
  `left_join()`), a chybějící `celkem`/věkové sloupce se nahradí nulou;
  sloupec `zdroj` se dopočítá podle měsíce (ne podle obce – zdroj je
  atribut celého měsíce, ne jednotlivé obce). Výsledek:
  `mesicni_panel.rds` má nově přesně `6258 obcí × 53 měsíců = 331 674` řádků
  (dřív 230 066 – jen řádky, které se skutečně vyskytly v archivu). Zbylé
  NA/`NaN` hodnoty koncentrace (4 obce × 53 měsíců = 212 řádků) patří
  vojenským újezdům (Libavá, Boletice, Hradiště, Březina) s nulovou civilní
  populací – tam je koncentrace matematicky nedefinovaná (0/0), ne chybějící
  data, a mapa je správně zobrazuje jako šedé (`na.value`).
- Populace obce (denominátor pro koncentraci) v historickém panelu není –
  MV XLSX populaci neobsahuje. Pro poměrové ukazatele je potřeba dopočítat
  proti aktuální populaci z `humpo_obce_latest.csv` (populace obcí se v
  řádu let mění minimálně, takže aproximace současnou populací je pro
  účely tohoto srovnání v pořádku).
- Ověřený příklad trendu koncentrace: podíl Prahy na celkovém součtu
  `celkem` vzrostl z 25,2 % (březen 2022) na cca 26,3 % (2026) – s viditelnými
  drobnými poklesy vždy kolem dubna/května každého roku (pravděpodobně
  souvislost s ročním cyklem prodlužování dočasné ochrany, ne chyba dat).

## Shiny appka (`shiny_app/`)
Interaktivní vizualizace `humpo_obce_mesicni.csv`:
- **Choropleth mapa ČR** – každá obec vybarvená podle koncentrace uprchlíků
  (`celkem / populace obce * 100`, ne podle absolutního počtu), s hranicemi
  ORP a krajů překreslenými přes ni, tooltipem na hover (obec, kraj, ORP,
  koncentrace i absolutní počet uprchlíků pro vybraný měsíc) a brush-to-zoom
  (viz níže).
- **Slider** pro výběr měsíce (2022-03 až aktuální) s popiskem "měsíc rok"
  místo číselného indexu.
- **Dva grafy vedle sebe**: nalevo koncentrace (uprchlíci/populace) podle
  5 kategorií obcí v čase, napravo podíl každé kategorie na celkovém počtu
  uprchlíků v ČR daný měsíc (součet přes všech 5 kategorií = 100 %).
  Kategorie: Praha; Brno/Ostrava/Plzeň; krajská města 50–120 tis.;
  regionální centra 3–50 tis.; malé obce < 3 tis.
- **Graf věkové struktury** – podíl dětí a mladistvých (0–17), produktivního
  věku (18–64) a seniorů (65+) na celkovém počtu uprchlíků v čase (hranice
  0–17 odpovídá tomu, jak jsou HUMPO věkové kategorie skutečně rozdělené:
  `cis_age_0_2/3_5/6_14/15_17` vs. `cis_age_18_64` vs. `cis_age_65_`).
- **Dva žebříčky 10 obcí** pro vybraný měsíc – jeden podle nejvyššího
  absolutního počtu (sloupce: počet, podíl dané obce na celkovém počtu
  uprchlíků v ČR, průměrný věk), druhý podle nejvyšší relativní koncentrace
  (stejné sloupce, jen prostřední je přímo koncentrace_pct – tedy hodnota,
  podle které je tabulka řazená – místo podílu na ČR, který by tu byl
  duplicitní informací). Průměrný věk viz "Průměrný věk" níže - jde o
  aproximaci.

Zdroj dat a datum poslední aktualizace jsou vypsané přímo v postranním
panelu appky.

Mapa i všechny 3 časové grafy jsou statické `ggplot2` obrázky (ne interaktivní
widgety jako leaflet/plotly). **Zoom (brush-to-zoom) má jen mapa**: tažením
myši se vybere podoblast a mapa se překreslí na tento výřez; dvojklik vrátí na
plné zobrazení. Není možné vidět okolní státy ani vyjet mimo republiku – brush
vždy vybírá jen podmnožinu aktuálně zobrazené oblasti, která sama od začátku
nikdy nepřesahuje pevně daný výřez ČR (`CR_XLIM`/`CR_YLIM` v `app.R`). Tři
časové grafy zoom nemají (zkoušeno a zase odstraněno – přesné trefení tažením
myši nepřidávalo hodnotu, hover popisovaný níže pokrývá stejnou potřebu líp).
Všechny 4 grafy (mapa + 3 časové) mají **hover tooltip** s konkrétní hodnotou
pod kurzorem – u časových grafů navíc svislou čáru a hodnoty všech kategorií
pro dané datum najednou (viz níže).

### Průměrný věk (aproximace)
Sloupec "Prům. věk" v žebříčku obcí je vážený průměr přes věkové kategorie,
které HUMPO data skutečně obsahují (`cis_age_0_2/3_5/6_14/15_17/18_64/65_`),
s těmito reprezentativními středy (viz `STRED_*` v `prepare_data.R`):

| kategorie      | 0–2 | 3–5 | 6–14 | 15–17 | 18–64 | 65+ |
|----------------|-----|-----|------|-------|-------|-----|
| střed (roky)   | 1   | 4   | 10   | 16    | 41    | 70  |

Středy 0–17 jsou prosté středy uzavřených intervalů (bez ambice o přesnost na
měsíce). `18–64` má střed přesně uprostřed intervalu (41). `65+` je otevřená
kategorie bez horní hranice - **70 je odhad, ne empiricky změřený průměr této
skupiny** (u uprchlické populace lze čekat spíš mladší konec seniorského
pásma vzhledem k fyzické náročnosti útěku, ale bez podrobnějších dat to nejde
ověřit). Číslo v tabulce je tedy orientační aproximace, ne přesný demografický
údaj.

### Vizuální identita PAQ Research
Appka přebírá barvy, škály a část UI stylu z oficiální vizuální identity PAQ
Research – zdroj: privátní repozitáře `paqresearch/PAQ-Theme` (barvy, fonty,
`PAQ_brand.md`) a `paqresearch/paqr` (R implementace – `theme_paq()`,
`paq_barvy_kat()`, `paq_barvy_ord()` v `theme_paq.R`), oba v organizaci
`paqresearch` na GitHubu.

- **Kategorická paleta grafů** (5 kategorií obcí i barvy krajů/kategorií)
  = `paqr::paq_barvy_kat("normal")[1:5]`:
  `#25357A` (modrá), `#5E91FF` (světle modrá), `#F5ABAB` (růžová),
  `#40B884` (zelená), `#F0D42E` (žlutá).
- **Věková struktura** (3 skupiny) používá stejnou paletu, jiné 3 odstíny
  pro odlišení od grafu kategorií: `#25357A` (modrá – děti), `#40B884`
  (zelená – produktivní věk), `#A31F48` (merlot – senioři).
- **Mapa** – sekvenční škála nahrazuje původní `viridis`/`inferno`:
  11 odstínů modré z `paqr::paq_barvy_ord("blue")`, obráceně (světlá =
  nízká koncentrace, tmavá `#25357A` = vysoká). Hranice krajů kreslené
  `#001056` (night blue), ORP `#757581` (paq_grey).
- **Mřížka grafů** `#CDD1D9`, **nadpisy grafů/mapy** `#001056` tučně – podle
  utility barev zdokumentovaných v `PAQ_brand.md` (grid lines/caption text).
- **UI appky** (mimo grafy): font `Source Sans 3` (nadpisy/tabulky/UI) a
  `Source Serif 4` (běžný text) přes Google Fonts – to jsou přesně
  zdokumentované webové fallbacky pro `Haffer`/`Source Serif 4` v
  `paq-typography.sty` (Haffer je komerční font bez webové distribuce,
  proto se nepoužívá přímo). Barva textu `#001056`, odkazy `#004ae7`,
  záhlaví tabulek podtržené `#00cc74` (zelená) – odpovídá LaTeX schématu
  `\colorschemWhite` v `paq-colors.sty` (bílé pozadí, night blue text,
  zelené akcenty, modré odkazy).
- **Font se NEaplikuje do samotných ggplot2 grafů/mapy** (ty zůstávají
  systémovým sans/serif R grafického zařízení) – vložení `Source Sans
  3`/`Source Serif 4` do staticky vykreslovaných PNG by ve webR vyžadovalo
  balíček pro font rendering (`systemfonts`/`showtext` apod.), jehož
  dostupnost jako WASM binárky nebyla ověřená, a riskovalo by to zbytečné
  zvětšení appky – barvy (hlavní nositel vizuální identity v grafech) jsou
  ale plně aplikované.

**Nasazení:** appka běží čistě v prohlížeči přes [shinylive](https://posit-dev.github.io/r-shinylive/)
(R zkompilované do WebAssembly přes webR) – žádný live R server není potřeba.
`.github/workflows/deploy-shinylive.yml` appku při každé změně v `shiny_app/`
nebo `data/processed/*.csv` sestaví a nasadí na GitHub Pages (zdrojový
repozitář zůstává privátní, výsledná statická stránka na Pages je ale
veřejně dostupná komukoliv s odkazem – GitHub Pages jinak nefunguje).

**Lokální vývoj:**

    Rscript shiny_app/prepare_data.R      # z data/processed/*.csv sestaví kompaktní shiny_app/data/*.rds
    Rscript shiny_app/run_local_test.R    # spustí appku na http://127.0.0.1:7861 (klasický Shiny, ne shinylive)

Export do statické shinylive podoby (stejné, co dělá i CI):

    Rscript export_shinylive.R            # vytvoří docs/ (gitignored, jen pro lokální test)
    Rscript serve_docs.R                  # obslouží docs/ na http://127.0.0.1:7862

### Na co si dát pozor (shinylive)
- Balíčky pro webR (shiny, dplyr, ggplot2, scales, readr, shinylive) jsou
  dostupné jako předkompilované WASM binárky v `repo.r-wasm.org` – ověřeno
  před implementací. Instalace balíčku ze zdrojáku ve webR možná není,
  funguje jen to, co má hotovou WASM binárku.
- Mapa původně používala `leaflet`, který má v Imports `sf`/`raster` a do
  appky tím přitahoval celý geoprostorový R stack (`sf`, `terra`, `sp`,
  `raster`, `s2`, ~31 MB) i přesto, že appka žádný z nich přímo nepoužívala.
  Přechodem na statický `ggplot2` choropleth (bez `sf` – hranice obcí se
  kreslí přímo z prostých lon/lat vrcholů přes `geom_polygon`, ne přes `sf`
  objekty) tahle závislost úplně odpadla, což zmenšilo `docs/` zhruba o
  třetinu a zároveň (jako vedlejší efekt) vyřešilo požadavek na omezení
  mapy jen na území ČR – statický obrázek nemá žádný pan/zoom.
- Prvotní vykreslení `renderPlot` výstupů může ve webR (běží citelně
  pomaleji než nativní R) selhat na "invalid width or height", protože
  kontejner v DOM ještě nemá ustálenou velikost. Appka to řeší vlastním
  mechanismem (`redraw()` v `app.R`) – několik vynucených překreslení s
  rostoucím odstupem (500 ms až ~2,5 s) krátce po startu.
- Popisek slideru (měsíc/rok místo čísla) se řeší čistě úpravou
  zobrazovaného textu přes `MutationObserver` v injektovaném JS, NE voláním
  `.data('ionRangeSlider').update({prettify: ...})` – to by resetovalo
  vnitřní stav slideru a rozbilo Shiny vlastní vazbu na change event
  (zjištěno při implementaci: `update()` přegeneruje vnitřní `<span>`, takže
  i "bezpečný" pozorovatel musí sledovat celý wrapper, ne konkrétní uzel).
- **Zdroj hranic obcí/ORP/krajů: balíček `RCzechia`**, ne ruční stahování z
  ArcGIS (původní řešení). `RCzechia::obce_polygony()` má přesné RUIAN kódy
  (`KOD_OBEC`) – ověřeno před implementací: 6258/6258 (100 %) shoda s kódy
  použitými v HUMPO/MV datech – a rovnou obsahuje i `KOD_ORP`/`NAZ_ORP`/
  `KOD_KRAJ`/`NAZ_CZNUTS3` u každé obce, takže odpadá samostatný join na
  kraj/ORP pro tooltip. `RCzechia::orp_polygony()` a `RCzechia::kraje()`
  dodávají hranice ORP a krajů pro obrysové linie na mapě.
- Hranice (`shiny_app/data/obec_hranice.rds`, `orp_hranice.rds`,
  `kraj_hranice.rds`) i admin. příslušnost (`obec_admin.rds`) se stahují a
  zjednodušují přes `R/fetch_obec_polygons.R` a commitují se do repozitáře
  jako hotové soubory - hranice se mění jen zřídka, není potřeba
  přegenerovávat při každém běhu hlavního pipeline. **Server-side
  generalizace ArcGIS (`maxAllowableOffset`), použitá v úplně první verzi,
  byla zavrhnuta** - zjednodušuje každý polygon nezávisle, takže mezi
  sousedícími obcemi vznikaly bílé mezery (jejich společná hranice se po
  zjednodušení posunula jinak na každé straně). Řešení: stáhne se plné
  rozlišení (obce: 1,05 mil. vrcholů) a zjednoduší se topologicky přes
  `rmapshaper::ms_simplify(keep_shapes = TRUE, sys = FALSE)` (V8 JS engine,
  ne systémový Node.js/mapshaper - žádná externí závislost navíc), který
  sdílené vrcholy/hrany mezi sousedy zachovává - výsledek je beze mezer
  (obce: 114 tis. vrcholů/1,5 MB; ORP: 26 tis./0,27 MB; kraje: 14,5 tis./
  0,17 MB). `sf`/`RCzechia`/`rmapshaper`/`sfheaders` se používají jen v
  tomto jednorázovém fetch skriptu (spouští se lokálně/manuálně), ne v
  appce samotné ani v CI, takže velikost nasazené appky neovlivňují.
  Zjednodušení nerozlišuje díry/enklávy (každý prstenec geometrie je
  samostatný polygon) – u českých obcí/ORP/krajů jde o zanedbatelnou
  odchylku.
- Populace pro obce s MOMC rozpadem (Praha, Brno, ...) se v
  `humpo_obce_latest.csv` nedá najít přímo (ten soubor má jen rozpad po
  městských částech) – `prepare_data.R` ji tam dopočítává součtem populace
  přes jednotlivé části.
- **Tooltip na hover** se řeší bez plotly/leaflet (kvůli velikosti appky) -
  `plotOutput` má nativní `hoverOpts`, který ze Shiny dostane pozici kurzoru
  rovnou v datových souřadnicích (lon/lat), takže stačí bounding-box
  předfiltr (`bbox_tbl`) + ruční point-in-polygon test (ray casting) nad
  stejnými lon/lat daty, která kreslí mapu - žádná nová závislost. Pozice
  tooltipu (CSS pixely) se bere z `input$mapa_hover$coords_css`.
- **Zoom mapy** se řeší nativním Shiny `brushOpts`/`dblclick` (oficiálně
  zdokumentovaný postup "zooming with brushing") – bez plotly/leaflet, tedy
  bez dopadu na velikost appky. `input$mapa_brush` dává vybraný výřez rovnou
  v datových souřadnicích (lon/lat), takže stačí uložit do
  `reactiveValues` a použít jako nové `xlim`/`ylim` v `coord_fixed()`;
  dvojklik vrací na `CR_XLIM`/`CR_YLIM`. Ověřeno přímo přes
  `Shiny.setInputValue()` (simulace tažení myši přes syntetické DOM
  události se ukázala nespolehlivá pro Shiny brush binding, přímý zápis
  vstupní hodnoty ale spolehlivě ověří, že reaktivní logika funguje).
- Grafy kategorií obcí agregují koncentraci/podíl jako `sum(uprchlíci) /
  sum(populace)` resp. `sum(uprchlíci kategorie) / sum(uprchlíci ČR)` za
  celou kategorii a měsíc (ne průměr jednotlivých obecních hodnot) - dává
  tak skutečné "kolik % lidí v této skupině obcí jsou uprchlíci" resp.
  "jaký podíl všech uprchlíků v ČR na tuto skupinu připadá", správně váženo
  podle velikosti obce.
- **Hover na časových grafech** (`registruj_graf()` v `app.R`, použito 3x):
  žádný brush/zoom, jen `hoverOpts`. Původně měly tyto grafy i brush-to-zoom
  a hover hledal jen nejbližší jednotlivý bod (podle X i Y pozice kurzoru
  zároveň) – v praxi šlo těžko trefit konkrétní (hlavně nejnižší) křivku.
  Zoom byl proto odstraněn a hover přepracován: hledá jen nejbližší **datum**
  na ose X (Y pozice kurzoru se ignoruje úplně) a zobrazí svislou čáru u
  tohoto data plus tooltip s hodnotami všech kategorií najednou – snazší
  cílení, protože stačí trefit správný sloupec dat, ne konkrétní pixel na
  konkrétní křivce.
- **`shiny::nearPoints()` se v `app.R` nepoužívá** - v klasickém Shiny
  funguje, ale ve shinylive/webR tiše nevracel žádnou shodu i při rozumných
  hover datech (ověřeno přímým čtením `input$..._hover` na serveru). Součástí
  přechodu na hledání "nejbližšího data" to přestalo být relevantní: `hover$x`
  je od Shiny už v datových jednotkách (dny od 1970-01-01), takže
  `najdi_nejblizsi_datum()` v `app.R` jen porovná `hover$x` s unikátními
  daty ve sloupci a nepotřebuje žádný přepočet přes pixely/domain/range
  (na rozdíl od dřívějšího `najdi_nejblizsi_bod()`, který takhle nahrazoval
  `nearPoints()` pro hledání jednotlivého bodu - to bylo nahrazeno spolu se
  zoomem, protože hledání podle data samo o sobě žádnou pixelovou vzdálenost
  nepotřebuje).
- Testování hoveru na časových grafech ve webR vyžaduje trpělivost -
  reaktivní round-trip je citelně pomalejší než klasický Shiny; ověření
  přes `Shiny.setInputValue()` (viz výše) občas potřebovalo druhý pokus
  po delší prodlevě (~8-10 s), než se stav skutečně projevil.
