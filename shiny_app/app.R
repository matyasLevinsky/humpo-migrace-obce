# shiny_app/app.R
# Vizualizace prostorove koncentrace ukrajinskych uprchliku v CR v case -
# mesicni panel obci od brezna 2022 do soucasnosti.
#
# Zdroje dat:
#  - HUMPO (gis.humpo.cz), Ministerstvo vnitra CR / Arcdata Praha - zivy
#    snapshot pro nejnovejsi mesic
#  - MV CR (mv.gov.cz), archiv statistik k valce na Ukrajine - historicke
#    mesicni snapshoty brezen 2022 az kveten 2026
# Podrobna metodika: viz README.md a R/ ve zbytku tohoto repozitare.

library(shiny)
library(leaflet)
library(dplyr)
library(ggplot2)
library(scales)

lookup <- readRDS("data/obec_lookup.rds")
panel  <- readRDS("data/mesicni_panel.rds")

mesice <- sort(unique(panel$cilovy_mesic))
mesic_datum <- as.Date(mesice)
nazvy_mesicu <- c("led", "úno", "bře", "dub", "kvě", "čvn",
                   "čvc", "srp", "zář", "říj", "lis", "pro")
mesic_label <- paste0(nazvy_mesicu[as.integer(format(mesic_datum, "%m"))],
                       " ", format(mesic_datum, "%Y"))

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

barva_domena <- log1p(panel$celkem)
paleta <- colorNumeric("YlOrRd", domain = barva_domena)

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; }
    .zdroj-info { font-size: 12px; color: #666; margin-top: 10px; }
  "))),
  titlePanel("Ukrajinská migrace v ČR: od plošného rozptýlení ke koncentraci ve městech"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      sliderInput("mesic_idx", "Měsíc:",
                  min = 1, max = length(mesice), value = length(mesice), step = 1,
                  ticks = FALSE, animate = animationOptions(interval = 900, loop = FALSE)),
      h4(textOutput("vybrany_mesic")),
      tags$hr(),
      h5("Top 10 obcí"),
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
      leafletOutput("mapa", height = 520),
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
  # prvni zmeny slideru.
  # nekolik pokusu s rostoucim odstupem - ve webR (shinylive) trva
  # inicializace o dost dele nez v klasickem Shiny, jeden pevny cas nestacil
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

  output$mapa <- renderLeaflet({
    leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = 15.5, lat = 49.8, zoom = 7)
  })

  observe({
    redraw()
    d <- mesic_data()
    leafletProxy("mapa", data = d) |>
      clearMarkers() |>
      addCircleMarkers(
        lng = ~lon, lat = ~lat,
        radius = ~pmax(2, sqrt(celkem) * 0.55),
        color = ~paleta(log1p(celkem)),
        stroke = FALSE, fillOpacity = 0.75,
        label = ~paste0(obec, ": ", format(celkem, big.mark = " "), " osob")
      )
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
      labs(title = paste("Nejvíce uprchlíků –", mesic_label[input$mesic_idx]),
           x = NULL, y = NULL) +
      theme_minimal(base_size = 12)
  })
}

shinyApp(ui, server)
