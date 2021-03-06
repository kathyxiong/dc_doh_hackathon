###########################################################################
# Issue: #17 Extract 'Overdue Inspections' Feature from Restaurant Inspection Data
# Author: Kathy Xiong
# Last Updated: 2017-01-04
#
# Description: 
# This script summarises the restaurant inspections data by year, week, census block,
# establishment type, and risk category, and creates two features: number of 
# overdue inspections and average number of days since last inspection (inspection frequency).
# The second output is added as an alternative feature to test even though it was
# not part of the original issue.
# 
# Instructions:
# Update paths in section labeled "UPDATE PATHS" below before running script
# 
# Inputs:
# - cleaned restaurant inspections and geocoding files:
#   - dc_restaurant_inspections/potential_inspection_summary_data.csv
#   - dc_restaurant_inspections/restaurant_inspections_geocoded.csv
#
# Outputs:
# - CSV files with features:
#   - restaurant_inspections_overdue.csv
#   - restaurant_inspections_frequency.csv
# - Quick visualisations by week by risk category:
#   - restaurant_inspections_overdue.png
#   - restaurant_inspections_frequency.png
#
# Open issues:
# - Update inspection frequency requirements with official DOH values
# - Decide what to do about the 'bias' towards fewer overdue inspections &
#   more frequent inspections in earlier time periods. In the earlier time periods,
#   most establishment would have an "NA" for days since last inspection, because
#   their last inspection is not in the data set; only those that have had inspections
#   very recently (i.e. since start of data set) would have a value and be 
#   included in the aggregate calculations.
#   
###############################################################################


# Set up ------------------------------------------------------------------

library(tidyverse)
library(lubridate)
#library(tictoc)

#### UPDATE PATHS ####
path_proj <- "/Users/kathy/Documents/_projects/dc_doh_hackathon"
path_data <- paste0(path_proj, "/issue_17/data")
path_out <- paste0(path_proj, "/issue_17/output")
######################

# Read in data ------------------------------------------------------------

inspection_geocode <- read_csv(paste0(path_data, "/restaurant_inspections_geocoded.csv"))
inspection_summary <- read_csv(paste0(path_data, "/potential_inspection_summary_data.csv"))


# Clean data sets ---------------------------------------------------------

# remove duplicates
inspection_summary <- distinct(inspection_summary, inspection_id, .keep_all = TRUE)
inspection_geocode <- distinct(inspection_geocode, inspection_id, .keep_all = TRUE)

# remove dates that fall outside of target date range
start_date <- as.Date("2008-01-01")
end_date <- as.Date("2017-12-31")

inspection_summary <- inspection_summary %>% 
  filter(inspection_date >= start_date & inspection_date <= end_date)

# add required frequencies
inspection_summary <- inspection_summary %>% 
  mutate(required_inspection_freq = case_when(
    risk_category == 1 ~ 900,
    risk_category == 2 ~ 600,
    risk_category == 3 ~ 600,
    risk_category == 4 ~ 600,
    risk_category == 5 ~ 600
  ))

# merge in geo code
inspection_summary <- inspection_summary %>% 
  left_join(inspection_geocode, by = "inspection_id")


# Extract features --------------------------------------------------------

# create a vector of dates
days <- seq(start_date, end_date, by = "days")
mondays <- days[weekdays(days) == "Monday"]

# arrange data with most recent inspection first
inspection_summary <- inspection_summary %>% 
  arrange(establishment_name, address, desc(inspection_date))

# create a function to select last inspection prior to given date
select_last_inspect <- function(monday) {
  inspection_summary %>% 
    filter(inspection_date <= monday) %>% 
    distinct(establishment_name, address, .keep_all = TRUE)
}

# apply function to each date
#tic("map")
all_dates <- map(mondays, select_last_inspect)
#toc()
# map: 21.643 sec elapsed

# expand into large data frame
all_dates_df <- enframe(all_dates)
all_dates_df <- bind_cols(monday = mondays, all_dates_df) %>% 
  select(monday, value) %>% 
  unnest()

# aggregate by date, establishment type, risk category, and census block
#tic("summarize")
all_dates_summary <- all_dates_df %>% 
  mutate(days_since_last_inspect = monday - inspection_date,
         inspection_overdue = days_since_last_inspect > required_inspection_freq) %>% 
  group_by(monday, establishment_type, risk_category, census_block_2010) %>% 
  summarise(days_since_last_inspect = mean(days_since_last_inspect, na.rm = TRUE),
            inspections_overdue = sum(inspection_overdue, na.rm = TRUE))
#toc()
# summarize: 76.215 sec elapsed


# Clean up and export -----------------------------------------------------

inspections_overdue <- all_dates_summary %>% 
  ungroup() %>% 
  mutate(feature_id = "restaurant_inspections_overdue",
         feature_type = establishment_type,
         feature_subtype = risk_category,
         year = year(monday),
         week = isoweek(monday),
         census_block_2010 = as.character(census_block_2010),
         value = inspections_overdue) %>% 
  select(feature_id,
         feature_type,
         feature_subtype,
         year,
         week,
         census_block_2010,
         value)

days_since_last_inspect <- all_dates_summary %>% 
  ungroup() %>% 
  mutate(feature_id = "restaurant_inspections_frequency",
         feature_type = establishment_type,
         feature_subtype = risk_category,
         year = year(monday),
         week = isoweek(monday),
         census_block_2010 = as.character(census_block_2010),
         value = as.numeric(days_since_last_inspect)) %>% 
  select(feature_id,
         feature_type,
         feature_subtype,
         year,
         week,
         census_block_2010,
         value)
  
write_csv(inspections_overdue, paste0(path_out, "/restaurant_inspections_overdue.csv"))
write_csv(days_since_last_inspect, paste0(path_out,"/restaurant_inspections_frequency.csv"))


# Visualize ---------------------------------------------------------------

summary_gg <- all_dates_summary %>% 
  ungroup() %>% 
  group_by(risk_category, monday) %>% 
  summarise(frequency = mean(days_since_last_inspect, na.rm = TRUE),
            num_overdue = mean(inspections_overdue, na.rm = TRUE))

ggplot(summary_gg) +
  geom_bar(aes(x = monday, y = num_overdue), stat = "identity") +
  facet_wrap(~risk_category)

ggsave(paste0(path_out, "/restaurant_inspections_overdue.png"))

ggplot(summary_gg) +
  geom_bar(aes(x = monday, y = frequency), stat = "identity") +
  facet_wrap(~risk_category)

ggsave(paste0(path_out, "/restaurant_inspections_frequency.png"))
