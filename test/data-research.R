# Initial dataset research
# Goal: Identify sources, familiarize with contents, flag issues 

library(dplyr)
library(readr)
library(sf)
library(httr)
library(readxl)
library(mapview)
library(socratadata)

# Get environment vars
readRenviron(".Renviron")


### General / Background ######################################################

## Community Districts via DCP Feature server ##
url_comDist <- "https://services5.arcgis.com/GfwWNkhOj9bNBqoJ/arcgis/rest/services/NYC_Community_Districts/FeatureServer/0"
parsed_url_comDist <- parse_url(url_comDist)
parsed_url_comDist$path <- paste0(parsed_url_comDist$path, "/query")

# Joint interest areas, exlcude
jia <- c("226", "227", "228", "355", "356", "164", "480", "481", "482", "483", "484", "595")
where_clause <- paste0("BoroCD NOT IN (",
                       paste0(jia, collapse = ", "),
                       ")")

parsed_url_comDist$query <- list(
  where = where_clause,
  f = "geojson",
  outSR = 4326,
  outFields = "BoroCD"
)
request_comDist <- build_url(parsed_url_comDist)
comDist <- read_sf(request_comDist)
st_is_valid(comDist)

## Council Districts ##
url_conDist <- "https://services5.arcgis.com/GfwWNkhOj9bNBqoJ/arcgis/rest/services/NYC_City_Council_Districts/FeatureServer/0"
parsed_url_conDist <- parse_url(url_conDist)
parsed_url_conDist$path <- paste0(parsed_url_conDist$path, "/query")
parsed_url_conDist$query <- list(
  where = "0=0",
  outFields = "counDist",
  f = "geojson",
  outSR = 4326)
request_conDist <- build_url(parsed_url_conDist)
conDist <- read_sf(request_conDist)
st_is_valid(conDist)


## Community Health Profiles ##
# url: https://www.nyc.gov/assets/doh/downloads/excel/episrv/2026-chp-pud.xlsx
# All data can be joined by ID <> BoroCD
# Will need to reformat Excel sheets, ETL due to rolling time window


## DOHMHNYC Respiratory Illness Data ##
# CSVs available here, will need to be wrangled: https://github.com/nychealth/respiratory-illness-data/tree/main/data
# Spatial unit is Borough
# Will need to design an ETL as time coverage is a moving window

## Hospital Surge Capacity Sites ##
# Map from private repo shown here: https://council.nyc.gov/data/hospitals-access/
# Request data if desired

## Stormwater Flooding ## 
limited_current <- read_sf("test/flood_shp/moderate_1_77_current.shp") |> 
  st_zm() |> 
  st_transform(4326)

moderate_current <- read_sf("test/flood_shp/moderate_2_13_current.shp") |> 
  st_zm() |> 
  st_transform(4326)

moderate_2050 <- read_sf("test/flood_shp/moderate_2_13_2050.shp") |> 
  st_zm() |> 
  st_transform(4326)

extreme_2080 <- read_sf("test/flood_shp/extreme_3_66_2080.shp") |> 
  st_zm() |> 
  st_transform(4326)

## NYC Cooling Tower Registrations ## 
cooling_towers <- soc_read(
  "https://data.cityofnewyork.us/Health/NYC-Cooling-Tower-Registrations/y4fw-iqfr.json"
) |> 
  filter(!(is.na(longitude) | is.na(latitude))) |> 
  st_as_sf(coords = c("longitude", "latitude"),
           crs = 4326)

mapview(cooling_towers)

# Note that there are some nonsense coordinates

## Hurricane Evacutation Centers ##

hc_evac_centers <- soc_read(
  "https://data.cityofnewyork.us/Public-Safety/Hurricane-Evacuation-Centers-Map-/ayer-cga7.json",
  include_synthetic_cols = FALSE
)


## Hurricane Evacuation Zones ##

hc_evac_zones <- soc_read(
  "https://data.cityofnewyork.us/City-Government/Hurricane-Evacuation-Zones/epne-qv9x",
  include_synthetic_cols = FALSE
)
mapview(hc_evac_zones)

## Heat Vulnerabilility Index ##
hvi_zip <- soc_read(
  "https://data.cityofnewyork.us/Health/Heat-Vulnerability-Index-Rankings/4mhf-duep.json",
  include_synthetic_cols = FALSE
)

hvi_cdta <- read_csv("test/NYC EH Data Portal - Heat vulnerability index (full table).csv")

hvi_nta <- read_csv('test/NYC EH Data Portal - Heat vulnerability index (NTA) (full table).csv')

## Facilities Database ##

inc_sources <- c(
  "'dcla_culturalinstitutions'",
  "'dep_wwtc'",
  "'dpr_parksproperties'",
  "'dsny_specialwastedrop'",
  "'hra_snapcenters'",
  "'nysdec_solidwaste'",
  "'nysoasas_programs'",
  "'qpl_libraries'"
)

fac_db <- soc_read(
  "https://data.cityofnewyork.us/City-Government/Facilities-Database/ji82-xba5.json",
  query = soc_query(
    where = paste0(
      "datasource in (",
      paste0(inc_sources, collapse = ", "),
      ")"
    )
  ),
  include_synthetic_cols = FALSE
) |> 
  filter(!(is.na(latitude) | is.na(longitude))) |>
  filter(!(latitude == 0 | longitude == 0)) |> 
  st_as_sf(coords = c("longitude", "latitude"),
           crs = 4326)
