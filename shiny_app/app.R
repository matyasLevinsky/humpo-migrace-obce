# shiny_app/app.R
# Vizualizace prostorove koncentrace ukrajinskych uprchliku v CR v case -
# mesicni panel obci od brezna 2022 do soucasnosti.
#
# Zdroje dat:
#  - HUMPO (gis.humpo.cz), Ministerstvo vnitra CR / Arcdata Praha - zivy
#    snapshot pro nejnovejsi mesic a populaci obci
#  - MV CR (mv.gov.cz), archiv statistik k valce na Ukrajine - historicke
#    mesicni snapshoty brezen 2022 az kveten 2026
#  - RCzechia - hranice obci/ORP/kraju a jejich administrativni prislusnost
#    (viz R/fetch_obec_polygons.R)
# Podrobna metodika: viz README.md a R/ ve zbytku tohoto repozitare.
#
# Mapa i vsechny 3 casove grafy jsou staticke ggplot2 obrazky (ne
# leaflet/plotly) - zamerne, aby appka nepotahovala tezke geoprostorove/JS
# zavislosti. Zoom je jen u mapy, resen brush-to-zoom (Shiny brushOpts +
# reaktivni xlim/ylim). Hover tooltipy: mapa pouziva rucni point-in-polygon,
# 3 casove grafy pouzivaji primo hover$x (Shiny uz ho vraci v datovych
# jednotkach) k dohledani nejblizsiho datumu a zobrazeni hodnot vsech
# kategorii najednou - zadna nova zavislost, zadny dopad na velikost appky.

library(shiny)
library(dplyr)
library(ggplot2)
library(scales)

lookup      <- readRDS("data/obec_lookup.rds")
panel       <- readRDS("data/mesicni_panel.rds")
hranice     <- readRDS("data/obec_hranice.rds")
orp_hranice <- readRDS("data/orp_hranice.rds")
kraj_hranice <- readRDS("data/kraj_hranice.rds")
vekova_struktura <- readRDS("data/vekova_struktura.rds")

mesice <- sort(unique(panel$cilovy_mesic))
mesic_datum <- as.Date(mesice)
nazvy_mesicu <- c("leden", "únor", "březen", "duben", "květen", "červen",
                   "červenec", "srpen", "září", "říjen", "listopad", "prosinec")
mesic_label <- paste0(nazvy_mesicu[as.integer(format(mesic_datum, "%m"))],
                       " ", format(mesic_datum, "%Y"))
mesic_label_js <- paste0("[", paste(sprintf('"%s"', mesic_label), collapse = ","), "]")

posledni_zdroj <- panel |> filter(cilovy_mesic == max(cilovy_mesic)) |> pull(zdroj) |> unique()
posledni_label <- mesic_label[length(mesic_label)]
datum_generovani <- format(Sys.Date(), "%d. %m. %Y")

# --- kategorie obci pro souhrnne trendy grafy -------------------------------
KOD_PRAHA <- "554782"
KOD_BOP   <- c("582786", "554821", "554791")  # Brno, Ostrava, Plzen
PORADI_KATEGORII <- c("Praha", "Brno, Ostrava, Plzeň", "Krajská města (50–120 tis.)",
                       "Regionální centra (3–50 tis.)", "Malé obce (< 3 tis.)")

lookup <- lookup |>
  mutate(kategorie = case_when(
    kod_obce == KOD_PRAHA ~ "Praha",
    kod_obce %in% KOD_BOP ~ "Brno, Ostrava, Plzeň",
    populace >= 50000     ~ "Krajská města (50–120 tis.)",
    populace >= 3000      ~ "Regionální centra (3–50 tis.)",
    TRUE                  ~ "Malé obce (< 3 tis.)"
  ))

# nalevo: relativni koncentrace (uprchlici / populace kategorie)
kategorie_trend <- panel |>
  inner_join(lookup |> select(kod_obce, populace, kategorie), by = "kod_obce") |>
  summarise(koncentrace_kat = sum(celkem) / sum(populace) * 100, .by = c(cilovy_mesic, kategorie)) |>
  mutate(datum = as.Date(cilovy_mesic),
         kategorie = factor(kategorie, levels = PORADI_KATEGORII))

# napravo: podil kategorie na celkovem poctu uprchliku v CR (soucet = 100 %)
kategorie_podil <- panel |>
  inner_join(lookup |> select(kod_obce, kategorie), by = "kod_obce") |>
  summarise(celkem_kat = sum(celkem), .by = c(cilovy_mesic, kategorie)) |>
  mutate(celkem_cr = sum(celkem_kat), .by = cilovy_mesic) |>
  mutate(podil_pct = celkem_kat / celkem_cr * 100,
         datum = as.Date(cilovy_mesic),
         kategorie = factor(kategorie, levels = PORADI_KATEGORII))

# vpravo od narodniho vekoveho grafu: podil uprchliku v neproduktivnim veku
# (0-17 + 65+) podle stejnych 5 kategorii obci jako u koncentrace/podilu -
# soucty pres obce v kategorii, ne prumer jednotlivych obecnich hodnot
kategorie_neprod <- panel |>
  inner_join(lookup |> select(kod_obce, kategorie), by = "kod_obce") |>
  summarise(neproduktivni_kat = sum(neproduktivni), celkem_kat = sum(celkem),
            .by = c(cilovy_mesic, kategorie)) |>
  mutate(podil_neprod_pct = neproduktivni_kat / celkem_kat * 100,
         datum = as.Date(cilovy_mesic),
         kategorie = factor(kategorie, levels = PORADI_KATEGORII))

# Barvy PAQ Research (paqresearch/paqr::paq_barvy_kat("normal"), viz
# PAQ-Theme/PAQ_brand.md) - kategoricka paleta appky prevzata primo z
# vizualni identity PAQ, aby appka barevne odpovidala PAQ vystupum.
PAQ_KATEGORICKA <- c("#25357A", "#5E91FF", "#F5ABAB", "#40B884", "#F0D42E")
BARVY_KATEGORII <- setNames(PAQ_KATEGORICKA, PORADI_KATEGORII)

# --- vekova struktura v case (narodni agregat) ------------------------------
celkem_mesic_vek <- vekova_struktura |> transmute(cilovy_mesic, celkem = deti + produktivni + seniori)
PORADI_VEKU <- c("Děti a mladiství (0–17)", "Produktivní věk (18–64)", "Senioři (65+)")
vekova_dlouhy <- bind_rows(
  vekova_struktura |> transmute(cilovy_mesic, skupina_veku = "Děti a mladiství (0–17)", pocet = deti),
  vekova_struktura |> transmute(cilovy_mesic, skupina_veku = "Produktivní věk (18–64)", pocet = produktivni),
  vekova_struktura |> transmute(cilovy_mesic, skupina_veku = "Senioři (65+)", pocet = seniori)
) |>
  inner_join(celkem_mesic_vek, by = "cilovy_mesic") |>
  mutate(podil_pct = pocet / celkem * 100,
         datum = as.Date(cilovy_mesic),
         skupina_veku = factor(skupina_veku, levels = PORADI_VEKU))
# blue/green/merlot z PAQ palety - stejny zdroj jako BARVY_KATEGORII, jen
# jine 3 odstiny pro odliseni od grafu kategorii obci
BARVY_VEKU <- setNames(c("#25357A", "#40B884", "#A31F48"), PORADI_VEKU)

# --- pomocna data pro hover tooltip na mape (bbox predfiltr + point-in-polygon) --
bbox_tbl <- hranice |>
  summarise(xmin = min(lon), xmax = max(lon), ymin = min(lat), ymax = max(lat),
            .by = c(kod_obce, skupina))
hranice_by_skupina <- split(hranice[, c("lon", "lat")], hranice$skupina)

bod_v_polygonu <- function(px, py, xs, ys) {
  n <- length(xs)
  inside <- FALSE
  j <- n
  for (i in seq_len(n)) {
    if (((ys[i] > py) != (ys[j] > py)) &&
        (px < (xs[j] - xs[i]) * (py - ys[i]) / (ys[j] - ys[i]) + xs[i])) {
      inside <- !inside
    }
    j <- i
  }
  inside
}

najdi_obec <- function(px, py) {
  cand <- bbox_tbl[bbox_tbl$xmin <= px & bbox_tbl$xmax >= px &
                    bbox_tbl$ymin <= py & bbox_tbl$ymax >= py, ]
  if (nrow(cand) == 0) return(NA_character_)
  for (i in seq_len(nrow(cand))) {
    poly <- hranice_by_skupina[[cand$skupina[i]]]
    if (bod_v_polygonu(px, py, poly$lon, poly$lat)) return(cand$kod_obce[i])
  }
  NA_character_
}

# CR bounding box + korekce pomeru stran (1 stupen zem. delky je na 49.8 s.s.
# kratsi nez 1 stupen sirky) - staticka alternativa k mapove projekci bez sf
CR_XLIM <- c(12.0, 19.0)
CR_YLIM <- c(48.5, 51.2)
POMER_STRAN <- 1 / cos(49.8 * pi / 180)

# sekvencni modra skala PAQ Research (paqr::paq_barvy_ord("blue"), viz
# PAQ-Theme/PAQ_brand.md) - nahrazuje puvodni viridis/inferno, aby mapa
# odpovidala barevne identite PAQ. Puvodne razeno tmava -> svetla, pro mapu
# (nizka koncentrace = svetla, vysoka = tmava) je potreba obratit.
PAQ_MODRA_SEKVENCNI <- rev(c(
  "#25357A", "#2041A3", "#004AE7", "#3767FC", "#507DFE",
  "#5D91FF", "#75A1FF", "#97B6FF", "#B5CCFF", "#D0E2FF", "#EAF3FF"
))

# Najde nejblizsi datum v datech k pozici kurzoru na ose X (hover$x je od
# Shiny uz v datovych jednotkach - dny od 1970-01-01 - takze zadny prevod
# pres pixely neni potreba). Y pozice kurzoru se zamerne ignoruje - cilem je
# ukazat hodnoty VSECH kategorii pro dany mesic, ne jen nejblizsi krivku.
najdi_nejblizsi_datum <- function(xs, cil) {
  if (is.null(cil)) return(NA)
  xs_num <- as.numeric(xs)
  uniq <- sort(unique(xs_num))
  nej <- uniq[which.min(abs(uniq - as.numeric(cil)))]
  as.Date(nej, origin = "1970-01-01")
}

# vraci styl pro plovouci tooltip div, pozicovany podle kurzoru (CSS pixely).
# Kdyz je flip=TRUE (kurzor v prave polovine grafu), tooltip se vykresli
# NALEVO od kurzoru misto napravo - `transform: translateX(-100%)` posune
# div o jeho vlastni (skutecne vyrenderovanou) sirku, takze funguje spravne
# bez ohledu na to, jak dlouhy text tooltip zrovna ma (nemusime odhadovat
# sirku na serveru). z-index je zamerne velmi vysoke, aby tooltip nikdy
# nezapadl pod sousedni graf (viz .recalculating override v CSS hlavicce -
# spolecne resi obcasny stacking-context bug pri prekreslovani sousedniho
# grafu).
tooltip_style <- function(css_x, css_y, flip = FALSE) {
  horizontal <- if (flip) {
    paste0("left:", css_x - 12, "px; transform: translateX(-100%);")
  } else {
    paste0("left:", css_x + 12, "px;")
  }
  paste0(
    "position:absolute; ", horizontal, " top:", css_y + 12, "px; ",
    "background:white; border:1px solid #999; border-radius:4px; ",
    "padding:4px 10px; font-size:13px; box-shadow:0 1px 4px rgba(0,0,0,0.25); ",
    "pointer-events:none; z-index:100000; white-space:nowrap;"
  )
}

# rozhoduje, jestli je kurzor v prave polovine grafu (pak se tooltip flipne
# nalevo) - pouziva stejny hov$range, jaky Shiny dava pro kazdy hover event
tooltip_flip <- function(hov) {
  !is.null(hov$range) && !is.null(hov$coords_css) &&
    hov$coords_css$x > (hov$range$left + hov$range$right) / 2
}

# UI blok pro jeden hoverovatelny casovy graf (bez zoomu - jen mapa se
# zoomuje). Hover kdekoliv nad grafem ukazuje svislou caru + hodnoty vsech
# kategorii pro dane datum. Pouzito 3x (koncentrace/podil/vek). Cara i
# tooltip jsou samostatne pozicovane HTML divy NAD staticym PNG grafem -
# schvalne se NEresi prekreslenim ggplot obrazku pri kazdem hoveru (viz
# komentar u registruj_graf() nize, proc by to zpusobilo zpetnou vazbu).
zoom_chart_ui <- function(id, height) {
  div(
    style = "position: relative;",
    plotOutput(id, height = height,
               hover = hoverOpts(paste0(id, "_hover"), delay = 60, delayType = "throttle", nullOutside = TRUE)),
    uiOutput(paste0(id, "_crosshair")),
    uiOutput(paste0(id, "_tooltip"))
  )
}

ui <- fluidPage(
  tags$head(
    # Vizualni identita PAQ Research (paqresearch/PAQ-Theme,
    # paqresearch/paqr) - barvy podle PAQ_brand.md, font podle
    # dokumentovaneho fallback retezce (Haffer je komercni font bez
    # webove distribuce, proto Source Sans 3 / Source Serif 4 z Google
    # Fonts - presne fallbacky uvedene v paq-typography.sty). Barvy grafu
    # a mapy (ggplot2 PNG) jsou nastavene primo v R kodu nize - font se do
    # statickych PNG grafu NEvkladal (vyzadovalo by to systemfonts/showtext
    # jako dalsi WASM zavislost, coz by appku zbytecne zvetsilo).
    tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
    tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = "anonymous"),
    tags$link(rel = "stylesheet", href = paste0(
      "https://fonts.googleapis.com/css2?",
      "family=Source+Sans+3:wght@400;600;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap"
    )),
    tags$style(HTML("
    body { font-family: 'Source Serif 4', Georgia, serif; color: #001056; background: #ffffff; }
    h1, h2, h3, h4, h5, .zdroj-info b {
      font-family: 'Source Sans 3', -apple-system, Segoe UI, Roboto, sans-serif;
      color: #001056;
    }
    a { color: #004ae7; }
    .zdroj-info { font-size: 12px; color: #757581; margin-top: 10px; }
    .graf-hint { font-size: 12px; color: #757581; margin: 4px 0 10px 0; }
    .graf-hint b { color: #001056; }
    table { font-family: 'Source Sans 3', sans-serif; }
    table > thead > tr > th {
      color: #001056; border-bottom: 2px solid #00cc74 !important;
    }
    .irs-bar, .irs-bar-edge, .irs-from, .irs-to, .irs-single { background: #004ae7 !important; border-color: #004ae7 !important; }
    .irs-slider { border-color: #004ae7; background: #ffffff; }
    .irs-line { background: #cfe2ff; }
    .title-podbarveni { border-bottom: 3px solid #00cc74; padding-bottom: 12px; margin-bottom: 16px; }
    /* Shiny ztlumuje opacitu grafu behem prekreslovani (.recalculating) -
       opacity < 1 na ELEMENTU VYTVARI NOVY STACKING CONTEXT, coz obcas
       zpusobilo, ze tooltip/crosshair sousedniho grafu na chvili zapadl
       pod prave prekreslovany graf vedle. Vypnuti teto opacity odstranuje
       i tenhle vedlejsi efekt (a navic appka behem prekreslovani nebliká). */
    .shiny-plot-output.recalculating { opacity: 1 !important; }
  "))),
  tags$script(HTML(sprintf('
    (function() {
      // Nahradi cislo zobrazene v ion.rangeSlider textem mesice/roku - jen
      // uprava zobrazovaneho textu (MutationObserver), NEsaha na konfiguraci
      // slideru pres jeho .update() - to by resetovalo interni stav a
      // rozbilo Shiny vlastni change-event vazbu na hodnotu slideru.
      var labels = %s;
      var wrapper = null;
      function applyLabel() {
        var span = wrapper && wrapper.querySelector(".irs-single");
        if (!span) return;
        var idx = parseInt(span.textContent, 10);
        if (!isNaN(idx) && labels[idx - 1] && span.textContent !== labels[idx - 1]) {
          span.textContent = labels[idx - 1];
        }
      }
      function tryInit() {
        var container = document.getElementById("mesic_idx");
        wrapper = container && container.parentElement;
        if (wrapper && wrapper.querySelector(".irs-single")) {
          applyLabel();
          new MutationObserver(applyLabel)
            .observe(wrapper, {childList: true, characterData: true, subtree: true});
        } else {
          setTimeout(tryInit, 200);
        }
      }
      tryInit();
    })();
  ', mesic_label_js))),
  div(class = "title-podbarveni",
      titlePanel("Ukrajinská migrace v ČR: od plošného rozptýlení ke koncentraci ve městech")),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      sliderInput("mesic_idx", "Měsíc:",
                  min = 1, max = length(mesice), value = length(mesice), step = 1,
                  ticks = FALSE, animate = animationOptions(interval = 900, loop = FALSE)),
      h4(textOutput("vybrany_mesic")),
      tags$hr(),
      h5("Top 10 obcí (absolutní počet)"),
      tableOutput("top10"),
      tags$hr(),
      h5("Top 10 obcí (relativní koncentrace)"),
      tableOutput("top10_konc"),
      tags$hr(),
      tags$div(
        class = "zdroj-info",
        tags$b("Zdroj dat:"), tags$br(),
        "HUMPO (", tags$a(href = "https://gis.humpo.cz", "gis.humpo.cz"),
        "), Ministerstvo vnitra ČR / Arcdata Praha - živý snapshot.", tags$br(),
        "MV ČR (mv.gov.cz), archiv statistik k válce na Ukrajině - historická data 03/2022-05/2026.", tags$br(),
        "RCzechia - hranice obcí/ORP/krajů.",
        tags$br(), tags$br(),
        tags$b("Poslední měsíc v datech:"), " ", posledni_label,
        " (zdroj: ", posledni_zdroj, ")", tags$br(),
        tags$b("Aplikace vygenerována:"), " ", datum_generovani
      )
    ),
    mainPanel(
      width = 9,
      div(class = "graf-hint", "🔍 ", tags$b("Tip:"), " tažením myši přes mapu přiblížíte vybranou oblast (jen v rámci ČR), dvojklikem se vrátíte na celou republiku."),
      div(
        style = "position: relative;",
        plotOutput("mapa", height = 560,
                   hover = hoverOpts("mapa_hover", delay = 100, delayType = "throttle", nullOutside = TRUE),
                   brush = brushOpts("mapa_brush", resetOnNew = TRUE),
                   dblclick = "mapa_dblclick"),
        uiOutput("mapa_tooltip")
      ),
      tags$hr(),
      div(class = "graf-hint", "📈 ", tags$b("Tip:"), " najetím myší kdekoliv nad grafem zobrazíte svislou čáru a hodnoty všech kategorií pro dané datum."),
      fluidRow(
        column(6, zoom_chart_ui("trend_koncentrace", 300)),
        column(6, zoom_chart_ui("trend_podil", 300))
      ),
      tags$hr(),
      fluidRow(
        column(6, zoom_chart_ui("trend_vek", 280)),
        column(6, zoom_chart_ui("trend_neprod", 280))
      )
    )
  )
)

server <- function(input, output, session) {

  # jednorazovy vynuceny prekresleni kratce po startu - pri prvnim vykresleni
  # muze byt sirka kontejneru grafu jeste 0 (CSS layout jeste neni hotovy),
  # coz by jinak zpusobilo trvalou chybu "invalid width or height" az do
  # prvni zmeny slideru. Nekolik pokusu s rostoucim odstupem - ve webR
  # (shinylive) trva inicializace o dost dele nez v klasickem Shiny.
  redraw <- reactiveVal(0)
  observe({
    n <- isolate(redraw())
    if (n < 4) {
      invalidateLater(500 * (n + 1))
      isolate(redraw(n + 1))
    }
  })

  vybrany_mesic <- reactive(mesice[input$mesic_idx])

  output$vybrany_mesic <- renderText(paste("Zobrazený měsíc:", mesic_label[input$mesic_idx]))

  mesic_data <- reactive({
    panel |>
      filter(cilovy_mesic == vybrany_mesic()) |>
      inner_join(lookup, by = "kod_obce") |>
      arrange(desc(celkem))
  })

  mapa_data <- reactive({
    konc <- panel |> filter(cilovy_mesic == vybrany_mesic()) |> select(kod_obce, koncentrace_pct)
    hranice |> left_join(konc, by = "kod_obce")
  })

  # --- zoom mapy: brush vybere podoblast (vzdy podmnozina aktualniho
  # vyrezu, ktery od zacatku nikdy nepresahuje CR), dvojklik vraci na cely
  # stat. Zadny pan/zoom mimo CR neni mozny.
  mapa_rozsah <- reactiveValues(x = CR_XLIM, y = CR_YLIM)

  observeEvent(input$mapa_brush, {
    b <- input$mapa_brush
    mapa_rozsah$x <- c(b$xmin, b$xmax)
    mapa_rozsah$y <- c(b$ymin, b$ymax)
  })

  observeEvent(input$mapa_dblclick, {
    mapa_rozsah$x <- CR_XLIM
    mapa_rozsah$y <- CR_YLIM
  })

  output$mapa <- renderPlot({
    redraw()
    ggplot() +
      geom_polygon(data = mapa_data(), aes(lon, lat, group = skupina, fill = koncentrace_pct), color = NA) +
      geom_polygon(data = orp_hranice, aes(lon, lat, group = skupina), fill = NA, color = "#757581", linewidth = 0.25) +
      geom_polygon(data = kraj_hranice, aes(lon, lat, group = skupina), fill = NA, color = "#001056", linewidth = 0.7) +
      coord_fixed(ratio = POMER_STRAN, xlim = mapa_rozsah$x, ylim = mapa_rozsah$y, expand = FALSE) +
      scale_fill_gradientn(name = "Koncentrace\nuprchlíků (%)", colours = PAQ_MODRA_SEKVENCNI,
                            limits = c(0, 10), oob = scales::squish, na.value = "grey85") +
      labs(title = paste("Koncentrace uprchlíků podle obcí –", mesic_label[input$mesic_idx])) +
      theme_void(base_size = 13) +
      theme(plot.title = element_text(hjust = 0.5, margin = margin(b = 10), colour = "#001056", face = "bold"))
  })

  output$mapa_tooltip <- renderUI({
    h <- input$mapa_hover
    req(h)
    kod <- najdi_obec(h$x, h$y)
    if (is.na(kod)) return(NULL)
    radek <- mesic_data() |> filter(kod_obce == kod)
    if (nrow(radek) == 0 || is.na(radek$koncentrace_pct[1])) return(NULL)
    css_x <- if (!is.null(h$coords_css)) h$coords_css$x else 20
    css_y <- if (!is.null(h$coords_css)) h$coords_css$y else 20
    div(
      style = tooltip_style(css_x, css_y, flip = tooltip_flip(h)),
      tags$b(radek$obec[1]), tags$br(),
      sprintf("Kraj: %s", radek$kraj_nazev[1]), tags$br(),
      sprintf("ORP: %s", radek$orp_nazev[1]), tags$br(),
      sprintf("Koncentrace: %.2f %%", radek$koncentrace_pct[1]), tags$br(),
      sprintf("Počet uprchlíků: %s", format(radek$celkem[1], big.mark = " "))
    )
  })

  output$top10 <- renderTable({
    mesic_data() |>
      slice_head(n = 10) |>
      transmute(Obec = obec,
                Počet = format(celkem, big.mark = " "),
                `Podíl ČR` = sprintf("%.1f %%", podil_narodni_pct),
                `Prům. věk` = ifelse(is.na(prumerny_vek), "–", sprintf("%.0f", prumerny_vek)))
  }, striped = TRUE, spacing = "xs")

  output$top10_konc <- renderTable({
    mesic_data() |>
      arrange(desc(koncentrace_pct)) |>
      slice_head(n = 10) |>
      transmute(Obec = obec,
                Počet = format(celkem, big.mark = " "),
                Koncentrace = sprintf("%.2f %%", koncentrace_pct),
                `Prům. věk` = ifelse(is.na(prumerny_vek), "–", sprintf("%.0f", prumerny_vek)))
  }, striped = TRUE, spacing = "xs")

  # --- spolecna registrace hover chovani pro jeden z casovych grafu (bez
  # zoomu). Hover kdekoliv nad grafem (jakekoliv Y) najde nejblizsi datum na
  # ose X a ukaze svislou caru + hodnoty vsech kategorii pro ten mesic naraz
  # - snazsi trefit nez cilit na konkretni (treba nejnizsi) krivku.
  #
  # Cara i tooltip se kresli jako pozicovane HTML divy pres output$..._hover,
  # NE jako soucast renderPlot() - kdyby renderPlot zavisel na hoveru,
  # kazdy pohyb mysi by vyvolal prekresleni PNG (vymenu <img> elementu) a
  # Shiny sam si po vymene elementu, na ktery je hover binding pripojeny,
  # interne resetuje hover stav na null (overeno primym ctenim
  # Shiny.shinyapp.$inputValues v prohlizeci - hodnota zmizela do ~200 ms
  # po nastaveni). Timhle zpusobem (graf reaguje jen na redraw()/slider,
  # hover jen na prekresleni HTML overlay) se teto zpetne vazbe predejde.
  registruj_graf <- function(id, data, xvar, yvar, barva_var, paleta, nazev, height, jednotka = " %") {

    output[[id]] <- renderPlot({
      redraw()
      ggplot(data, aes(.data[[xvar]], .data[[yvar]], color = .data[[barva_var]])) +
        geom_line(linewidth = 1) +
        geom_vline(xintercept = as.numeric(mesic_datum[input$mesic_idx]),
                   linetype = "dashed", color = "#757581") +
        scale_y_continuous(labels = function(x) paste0(x, jednotka)) +
        scale_color_manual(values = paleta) +
        labs(title = nazev, x = NULL, y = NULL, color = NULL) +
        theme_minimal(base_size = 12) +
        theme(legend.position = "bottom",
              plot.title = element_text(colour = "#001056", face = "bold"),
              panel.grid.major = element_line(colour = "#CDD1D9"),
              panel.grid.minor = element_blank())
    })

    # najde nejblizsi datum k pozici kurzoru + jeho pixelovou pozici na ose X.
    #
    # Puvodni verze pocitala px primo z absolutnich hov$range/hov$domain
    # hranic (`r$left + (nej - d$left)/(d$right - d$left) * (r$right -
    # r$left)`), coz vedlo k realnemu bugu: crosshair byl systematicky vic
    # vpravo nez kurzor, s chybou rostouci doprava - klasicky prizna
    # spatneho meritka mezi CSS pixely (`coords_css`, ve kterych se
    # crosshair vykresluje) a pixely podkladoveho PNG (ktere `range`/`domain`
    # občas odrazeji misto CSS pixelu, hlavne pri vyssim devicePixelRatio -
    # `hov$img_css_ratio` existuje presne pro prevod mezi temito dvema
    # soustavami). Oprava: mereni pouzije jen POMER sirky range/domain
    # (prevedeny pres img_css_ratio na CSS pixely) jako sklon, ale jako KOTVU
    # pouzije aktualni pozici kurzoru (hov$coords_css$x <-> hov$x), ktera je
    # vzdy spravne v CSS pixelech - takze i kdyby byly absolutni hranice
    # range$left/right v jinych jednotkach, vysledna pozice crosshairu sedi
    # presne pod kurzorem nezavisle na tom, jak daleko vpravo/vlevo je.
    najdi_pozici <- function(hov) {
      nej <- najdi_nejblizsi_datum(data[[xvar]], hov$x)
      d <- hov$domain; r <- hov$range
      if (is.null(d) || is.null(r) || is.null(hov$coords_css)) return(NULL)
      pomer <- if (!is.null(hov$img_css_ratio)) hov$img_css_ratio$x else 1
      css_na_jednotku <- (r$right - r$left) / (d$right - d$left) * pomer
      px <- hov$coords_css$x + (as.numeric(nej) - hov$x) * css_na_jednotku
      list(nej = nej, px = px)
    }

    output[[paste0(id, "_crosshair")]] <- renderUI({
      hov <- input[[paste0(id, "_hover")]]
      req(hov, hov$x)
      poz <- najdi_pozici(hov)
      req(poz, poz$px)
      div(style = sprintf(
        "position:absolute; left:%.1fpx; top:0; height:%dpx; width:0; border-left:1px dashed #666; pointer-events:none; z-index:99999;",
        poz$px, height
      ))
    })

    output[[paste0(id, "_tooltip")]] <- renderUI({
      hov <- input[[paste0(id, "_hover")]]
      req(hov, hov$x)
      poz <- najdi_pozici(hov)
      req(poz)
      radky <- data[data[[xvar]] == poz$nej, ]
      radky <- radky[order(-radky[[yvar]]), ]
      if (nrow(radky) == 0) return(NULL)
      css_x <- if (!is.null(hov$coords_css)) hov$coords_css$x else 20
      css_y <- if (!is.null(hov$coords_css)) hov$coords_css$y else 20
      div(
        style = tooltip_style(css_x, css_y, flip = tooltip_flip(hov)),
        tags$b(format(poz$nej, "%m/%Y")), tags$br(),
        lapply(seq_len(nrow(radky)), function(i) {
          tags$div(
            tags$span(style = sprintf(
              "display:inline-block;width:9px;height:9px;border-radius:50%%;background:%s;margin-right:5px;",
              paleta[[as.character(radky[[barva_var]][i])]]
            )),
            sprintf("%s: %.2f%s", as.character(radky[[barva_var]][i]), radky[[yvar]][i], jednotka)
          )
        })
      )
    })
  }

  registruj_graf("trend_koncentrace", kategorie_trend, "datum", "koncentrace_kat", "kategorie",
                 BARVY_KATEGORII, "Koncentrace (uprchlíci / populace kategorie)", height = 300)
  registruj_graf("trend_podil", kategorie_podil, "datum", "podil_pct", "kategorie",
                 BARVY_KATEGORII, "Podíl na celkovém počtu uprchlíků v ČR", height = 300)
  registruj_graf("trend_vek", vekova_dlouhy, "datum", "podil_pct", "skupina_veku",
                 BARVY_VEKU, "Věková struktura uprchlíků v ČR v čase", height = 280)
  registruj_graf("trend_neprod", kategorie_neprod, "datum", "podil_neprod_pct", "kategorie",
                 BARVY_KATEGORII, "Podíl v neproduktivním věku (0–17 a 65+) podle kategorií obcí", height = 280)
}

shinyApp(ui, server)
