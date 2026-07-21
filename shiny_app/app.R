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
# pan/zoom, takze se nikdy nejde podivat mimo pevne dany vyrez CR.

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

narodni_soucet <- panel |> group_by(cilovy_mesic) |> summarise(celkem_cr = sum(celkem), .groups = "drop")
praha_kod <- lookup$kod_obce[lookup$obec == "Praha" & lookup$kraj == "Hlavní město Praha"][1]
praha_trend <- panel |>
  filter(kod_obce == praha_kod) |>
  select(cilovy_mesic, celkem_praha = celkem) |>
  inner_join(narodni_soucet, by = "cilovy_mesic") |>
  mutate(podil = 100 * celkem_praha / celkem_cr,
         datum = as.Date(cilovy_mesic)) |>
  arrange(datum)

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
      plotOutput("mapa", height = 560),
      tags$hr(),
      fluidRow(
        column(7, plotOutput("trend_praha", height = 260)),
        column(5, plotOutput("bar_top", height = 260))
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

  output$top10 <- renderTable({
    mesic_data() |>
      slice_head(n = 10) |>
      transmute(Obec = obec, Počet = format(celkem, big.mark = " "))
  }, striped = TRUE, spacing = "xs")

  output$trend_praha <- renderPlot({
    redraw()
    ggplot(praha_trend, aes(datum, podil)) +
      geom_line(color = "#b3251e", linewidth = 1) +
      geom_point(color = "#b3251e") +
      geom_vline(xintercept = as.numeric(mesic_datum[input$mesic_idx]),
                 linetype = "dashed", color = "grey40") +
      scale_y_continuous(labels = function(x) paste0(x, " %")) +
      labs(title = "Podíl Prahy na celkovém počtu uprchlíků v ČR",
           x = NULL, y = NULL) +
      theme_minimal(base_size = 12)
  })

  output$bar_top <- renderPlot({
    redraw()
    d <- mesic_data() |> slice_head(n = 8) |> mutate(obec = factor(obec, levels = rev(obec)))
    ggplot(d, aes(obec, celkem)) +
      geom_col(fill = "#b3251e") +
      coord_flip() +
      labs(title = paste("Nejvíce uprchlíků (abs.) –", mesic_label[input$mesic_idx]),
           x = NULL, y = NULL) +
      theme_minimal(base_size = 12)
  })
}

shinyApp(ui, server)
