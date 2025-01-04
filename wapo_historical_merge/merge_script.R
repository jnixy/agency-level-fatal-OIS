# Merge my historical fOIS data with WAPO's data
# Written 1.3.2025
# Last updated 1.4.2025

# Load necessary libraries
library(readr)  
library(dplyr)  
library(lubridate)
library(tidyr)
library(stringr)
library(tidyverse)

### STEP 1: LOAD AND CLEAN WAPO DATA ###

# Load WAPO agency-level data
url_agency <- "https://raw.githubusercontent.com/washingtonpost/data-police-shootings/refs/heads/master/v2/fatal-police-shootings-agencies.csv"
wapo_agency_data <- read_csv(url_agency)

# Load WAPO incident-level data
url_incident <- "https://raw.githubusercontent.com/washingtonpost/data-police-shootings/refs/heads/master/v2/fatal-police-shootings-data.csv"
wapo_ois_data <- read_csv(url_incident)

# Split `agency_ids` into individual rows
wapo_ois_data_clean <- wapo_ois_data %>%
  separate_rows(agency_ids, sep = ",\\s*") %>% # Split multiple IDs into rows
  mutate(agency_ids = as.numeric(agency_ids)) # Convert to numeric for joining

# Merge incident data with agency-level data
wapo_merged <- wapo_ois_data_clean %>%
  left_join(wapo_agency_data, by = c("agency_ids" = "id"))

# Collapse data to `agency-year` level and retain additional columns
wapo_agency_years <- wapo_merged %>%
  mutate(
    year = year(as.Date(date)) # Extract year from date
  ) %>%
  group_by(agency_ids, year) %>%
  summarise(
    total_shootings = n(), # Count shootings per agency per year
    city = first(city), # Retain the first non-NA value of city
    county = first(county), 
    state = first(state.x), 
    name = first(name.y), 
    type = first(type), 
    oricodes = first(oricodes), 
    .groups = "drop"
  )

# Ensure unique rows for agency-level details
unique_agency_details <- wapo_merged %>%
  select(agency_ids, city, county, state.x, name.y, type, oricodes) %>%
  distinct(agency_ids, .keep_all = TRUE) # Retain one unique row per agency_id

# Create a grid of all possible agency-years (2015–2024)
all_agencies <- unique(wapo_agency_years$agency_ids)
all_years <- 2015:2024

all_combinations <- expand_grid(
  agency_ids = all_agencies,
  year = all_years
)

# Merge the grid with shooting data and agency-level details
wapo_agency_years <- all_combinations %>%
  left_join(wapo_agency_years, by = c("agency_ids", "year")) %>% # Add shooting data
  left_join(unique_agency_details, by = "agency_ids") %>% # Add agency-level details
  mutate(
    total_shootings = replace_na(total_shootings, 0) # Fill missing observations with 0s
  )

# Select only the desired columns
wapo_agency_years <- wapo_agency_years %>%
  select(
    agency_ids,
    year,
    total_shootings,
    city = city.y, # Rename city.y to city
    county = county.y, 
    state = state.x, 
    name = name.y, 
    type = type.y, 
    oricodes = oricodes.y 
  )

### STEP 2: LOAD AND RESHAPE MY HISTORICAL DATA ###

# Load historical data
url_nix <- "https://raw.githubusercontent.com/jnixy/agency-level-fatal-OIS/refs/heads/main/agency-level-fatal-ois.csv"
nix_agency_data <- read_csv(url_nix)

# Reshape so that each row is an agency-year
nix_agency_long <- nix_agency_data %>%
  pivot_longer(
    cols = -year,
    names_to = "agency",
    values_to = "fatal_shootings"
  )

# Load file with ORI codes I pulled from Uniform Crime Report (2020) & merge them into the reshaped data.
ori_data <- read.csv("https://raw.githubusercontent.com/jnixy/agency-level-fatal-OIS/refs/heads/main/wapo_historical_merge/ori_codes.csv")

nix_agency_long <- nix_agency_long %>%
  left_join(ori_data, by = "agency")

missing_oricode <- nix_agency_long %>%
  filter(oricodes == "")

print(missing_oricode)

# Let's filter these 7 agencies out *for now*
nix_agency_long <- nix_agency_long %>%
  filter(oricodes != "")

# Check it worked
missing_oricode <- nix_agency_long %>%
  filter(oricodes == "")

print(missing_oricode)

# Rename fatal_shootings to total_shootings to match WAPO naming convention.
nix_agency_long <- nix_agency_long %>%
  select(
    year,
    agency,
    oricodes,
    total_shootings = fatal_shootings
  )

### STEP 3: MERGE THEM TOGETHER ON ORICODES ###

# Merge with all=TRUE to keep all rows from both datasets.
# suffixes=c("_nix","_wapo") will rename the overlapping columns (i.e., total_shootings).
merged_data <- merge(
  nix_agency_long, 
  wapo_agency_years,
  by = c("year", "oricodes"),
  all = TRUE,
  suffixes = c("_nix", "_wapo")
)

# Reorder columns
merged_data <- merged_data[, c(
  "year", 
  "oricodes",
  "agency_ids",
  "city",
  "county",
  "state",
  "name",
  "type",
  "agency",
  "total_shootings_nix",
  "total_shootings_wapo"
)]

# Check over everything
view(merged_data)


### STEP 4: BASIC SUMMARY PLOT ###
# Keep in mind...
# This drops shootings where there was no ORI code (usually federal task forces as far as I can tell)

# Transform merged_data to long format
df_long <- merged_data %>%
  select(year, oricodes, total_shootings_nix, total_shootings_wapo) %>%
  pivot_longer(
    cols = c("total_shootings_nix", "total_shootings_wapo"),
    names_to = "dataset",
    values_to = "total_shootings"
  )

# Filter out WaPo data before 2015 and where oricodes = NA
df_long_filtered <- df_long %>%
  filter(
    # Keep all rows EXCEPT where dataset is WaPo & (year < 2015 OR oricodes=NA)
    !(
      dataset == "total_shootings_wapo" &
        (year < 2015 | is.na(oricodes))
    ) &
      
      # Keep all rows EXCEPT where dataset is Nix & year > 2022
      !(
        dataset == "total_shootings_nix" &
          (year > 2022)
      )
  )

# Add agency count and categorize based on thresholds
df_yearly_summary <- df_long_filtered %>%
  filter(!is.na(total_shootings)) %>%  # Exclude rows where total_shootings is NA
  group_by(year, dataset) %>%
  summarize(
    avg_shootings = mean(total_shootings, na.rm = TRUE),
    min_shootings = min(total_shootings, na.rm = TRUE),
    max_shootings = max(total_shootings, na.rm = TRUE),
    num_agencies = n(),  # Count of agencies with non-NA total_shootings
    .groups = "drop"
  ) %>%
  mutate(
    agency_category = case_when(
      num_agencies < 100 ~ "< 100 agencies",
      num_agencies <= 400 ~ "100-400 agencies",
      num_agencies > 3000 ~ "> 3000 agencies",
      TRUE ~ "Other"
    )
  )

df_yearly_summary <- df_yearly_summary %>%
  mutate(
    agency_category = factor(
      agency_category,
      levels = c("< 100 agencies", "100-400 agencies", "> 3000 agencies")
    )
  )

# Combined visualization
my_plot <- ggplot(df_yearly_summary, aes(x = year, y = avg_shootings, color = dataset)) +
  
  # Ribbon for min/max bands
  geom_ribbon(
    aes(ymin = min_shootings, ymax = max_shootings, fill = dataset),
    alpha = 0.2,
    color = NA
  ) +
  
  # Line with explicit grouping and ordered size categories
  geom_line(aes(linewidth = agency_category, group = dataset)) +
  scale_linewidth_manual(
    values = c("< 100 agencies" = 0.5, "100-400 agencies" = 1.5, "> 3000 agencies" = 3),
    name = "Number of Agencies"
  ) +
  
  # Annotations for major changes
  annotate("text", x = 1970, y = 110, label = "1970-1999: Agency N fluctuates from 4 to 16", hjust = 0, size = 4) +
  annotate("segment", x = 1970, xend = 1970, y = 90, yend = 107, arrow = arrow()) +
  annotate("text", x = 1993, y = 40, label = "2000: Agency N spikes to 107, rises to 357 by 2014", hjust = 0, size = 4) +
  annotate("segment", x = 2000, xend = 2000, y = 20, yend = 37, arrow = arrow()) +
  annotate("text", x = 2009, y = 55, label = "2015: WAPO data includes >3,100 agencies", hjust = 0, size = 4) +
  annotate("segment", x = 2015, xend = 2015, y = 28, yend = 52, arrow = arrow()) +
  
  # Plot labels and theme
  labs(
    title = "Fatal OIS per year, 1970-2024 (sources: WAPO, my agency-level-fatal-OIS Github repo)",
    x = "Year",
    y = "Total Shootings"
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.title = element_text(size = 16, face = "bold"),         # Title font size
    axis.title = element_text(size = 14),                      # Axis labels font size
    axis.text = element_text(size = 12),                       # Axis ticks font size
    legend.title = element_text(size = 14, face = "bold"),     # Legend title font size
    legend.text = element_text(size = 12)                      # Legend text font size
  )

# Save the plot with scaling
ggsave(
  filename = "yearly_fois_trends.png",
  plot = my_plot,
  width = 10,    # Base width
  height = 6,    # Base height
  dpi = 300,
  scale = 1.5    # Enlarge everything by 1.5x
)

