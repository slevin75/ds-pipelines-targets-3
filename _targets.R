
library(targets)
library(tarchetypes)
library(tidyverse)
library(lubridate)
library(retry)
suppressPackageStartupMessages(library(dplyr))

options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse", "dataRetrieval", "urbnmapr", "rnaturalearth", "cowplot",
                            "leaflet","leafpop","htmlwidgets"))

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/map_sites.R")
source("3_visualize/src/plot_site_data.R")
source("3_visualize/src/plot_data_coverage.R")
source("3_visualize/src/map_timeseries.R")

# Configuration
states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')
parameter <- c('00060')

mapped_by_state_targets<- tar_map(
  values = tibble(state_abb = states) %>%
    mutate(state_plot_files = sprintf("3_visualize/out/timeseries_%s.png", state_abb)),
  names=state_abb,
  tar_target(nwis_inventory,subset_sites(oldest_active_sites,state_abb)),
  tar_target(nwis_data, retry(get_site_data(nwis_inventory, state_abb, parameter),when="Ugh, the internet data transfer failed!",max_tries=30)),
  tar_target(tally,tally_site_obs(nwis_data)),
  tar_target(timeseries_png,plot_site_data(state_plot_files,nwis_data,parameter),format="file"),
  unlist=FALSE
)

# Targets
list(
  # Identify oldest sites
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  mapped_by_state_targets,

  tar_combine(obs_tallies,mapped_by_state_targets[[3]],command=combine_obs_tallies(!!!.x)),

  tar_target(plot_data_coverage_png,plot_data_coverage(obs_tallies,"3_visualize/out/data_coverage.png",parameter),
             format="file"),
  # Map oldest sites
  tar_target(
    site_map_png,
    map_sites("3_visualize/out/site_map.png", oldest_active_sites),
    format = "file"
  ),
  tar_combine(
    summary_state_timeseries_csv,
    mapped_by_state_targets[[4]],
    command=summarize_targets('3_visualize/log/summary_state_timeseries.csv',!!!.x),
    format="file"
  ),
  tar_target(map_timeseries_html,
             map_timeseries(oldest_active_sites,summary_state_timeseries_csv,'3_visualize/out/timeseries_map.html'),
             format="file"
             )
)
