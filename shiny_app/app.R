# shiny_app/app.R
# Vizualizace prostorove koncentrace ukrajinskych uprchliku v CR v case -
# mesicni panel obci od brezna 2022 do soucasnosti.
#
# Zdroje dat:
#  - HUMPO (gis.humpo.cz), Ministerstvo vnitra CR / Arcdata Praha - zivy
#    snapshot pro nejnovejsi mesic a hranice/populace obci
#  - MV CR (mv.gov.cz), archiv statistik k valce na Ukrajine - historicke
#    mesicni snapshoty brezen 2022 az kveten 2026
# Podrobna metodika: viz README.md a R/ ve zbytku tohoto repozitare.
#
# Mapa je staticky ggplot2 choropleth (ne leaflet) - zamerne: (a) nepotahuje
# tim cely geoprostorovy R stack (sf/terra/sp/raster/s2), ktery leaflet
# vyzaduje jen kvuli Imports, a (b) staticky obrazek nema zadny interaktivni
# pan/zoom, takze se nikdy nejde podivat mimo pevne dany vyrez CR. Tooltip na
# hover se resi rucne (bez plotly/leaflet) pres Shiny hoverOpts + bounding-box
# predfiltr + point-in-polygon nad stejnymi lon/lat daty jako kresli mapu.

library(shiny)
library(dplyr)
library(ggplot2)
library(scales)

lookup  <- readRDS("data/obec_lookup.rds")
panel   <- readRDS("data/mesicni_panel.rds")
hranice <- readRDS("data/obec_hranice.rds")

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

# --- kategorie obci pro souhrnny trend graf ---------------------------------
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

kategorie_trend <- panel |>
  inner_join(lookup |> select(kod_obce, populace, kategorie), by = "kod_obce") |>
  summarise(koncentrace_kat = sum(celkem) / sum(populace) * 100, .by = c(cilovy_mesic, kategorie)) |>
  mutate(datum = as.Date(cilovy_mesic),
         kategorie = factor(kategorie, levels = PORADI_KATEGORII))

# --- pomocna data pro hover tooltip (bbox predfiltr + point-in-polygon) -----
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

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; }
    .zdroj-info { font-size: 12px; color: #666; margin-top: 10px; }
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
          // subtree:true - ion.rangeSlider muze pri update() prekreslit cely
          // vnitrni <span>, ne jen zmenit text; sledujeme proto cely wrapper
          // a .irs-single pri kazde zmene znovu dohledame, ne pevny odkaz.
          new MutationObserver(applyLabel)
            .observe(wrapper, {childList: true, characterData: true, subtree: true});
        } else {
          setTimeout(tryInit, 200);
        }
      }
      tryInit();
    })();
  ', mesic_label_js))),
  titlePanel("Ukrajinská migrace v ČR: od plošného rozptýlení ke koncentraci ve městech"),
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
      tags$div(
        class = "zdroj-info",
        tags$b("Zdroj dat:"), tags$br(),
        "HUMPO (", tags$a(href = "https://gis.humpo.cz", "gis.humpo.cz"),
        "), Ministerstvo vnitra ČR / Arcdata Praha - živý snapshot.", tags$br(),
        "MV ČR (mv.gov.cz), archiv statistik k válce na Ukrajině - historická data 03/2022-05/2026.",
        tags$br(), tags$br(),
        tags$b("Poslední měsíc v datech:"), " ", posledni_label,
        " (zdroj: ", posledni_zdroj, ")", tags$br(),
        tags$b("Aplikace vygenerována:"), " ", datum_generovani
      )
    ),
    mainPanel(
      width = 9,
      div(
        style = "position: relative;",
        plotOutput("mapa", height = 560,
                   hover = hoverOpts("mapa_hover", delay = 100, delayType = "throttle", nullOutside = TRUE)),
        uiOutput("mapa_tooltip")
      ),
      tags$hr(),
      plotOutput("trend_kategorie", height = 320)
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

  output$mapa <- renderPlot({
    redraw()
    ggplot(mapa_data(), aes(lon, lat, group = skupina, fill = koncentrace_pct)) +
      geom_polygon(color = NA) +
      coord_fixed(ratio = POMER_STRAN, xlim = CR_XLIM, ylim = CR_YLIM, expand = FALSE) +
      scale_fill_viridis_c(name = "Koncentrace\nuprchlíků (%)", option = "inferno",
                            limits = c(0, 10), oob = scales::squish, na.value = "grey85") +
      labs(title = paste("Koncentrace uprchlíků podle obcí –", mesic_label[input$mesic_idx])) +
      theme_void(base_size = 13) +
      theme(plot.title = element_text(hjust = 0.5, margin = margin(b = 10)))
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
      style = paste0(
        "position:absolute; left:", css_x + 12, "px; top:", css_y + 12, "px; ",
        "background:white; border:1px solid #999; border-radius:4px; ",
        "padding:4px 10px; font-size:13px; box-shadow:0 1px 4px rgba(0,0,0,0.25); ",
        "pointer-events:none; z-index:1000; white-space:nowrap;"
      ),
      tags$b(radek$obec[1]), tags$br(),
      sprintf("Koncentrace: %.2f %%", radek$koncentrace_pct[1])
    )
  })

  output$top10 <- renderTable({
    mesic_data() |>
      slice_head(n = 10) |>
      transmute(Obec = obec, Počet = format(celkem, big.mark = " "))
  }, striped = TRUE, spacing = "xs")

  output$trend_kategorie <- renderPlot({
    redraw()
    ggplot(kategorie_trend, aes(datum, koncentrace_kat, color = kategorie)) +
      geom_line(linewidth = 1) +
      geom_vline(xintercept = as.numeric(mesic_datum[input$mesic_idx]),
                 linetype = "dashed", color = "grey40") +
      scale_y_continuous(labels = function(x) paste0(x, " %")) +
      scale_color_brewer(palette = "Set1") +
      labs(title = "Koncentrace uprchlíků podle typu obce v čase",
           x = NULL, y = NULL, color = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")
  })
}

shinyApp(ui, server)
