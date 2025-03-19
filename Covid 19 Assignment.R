# Load necessary libraries for data manipulation and visualization
library(ggplot2)          # For data visualization
library(patchwork)        # For arranging multiple plots
library(dplyr)            # For data manipulation
library(tidyr)            # For reshaping data
library(scales)           # For formatting numbers in plots
library(rnaturalearth)    # For world map data
library(rnaturalearthdata)
library(forecast)
library(sf)               # For handling spatial data

# Disable scientific notation globally to make numbers easier to read
options(scipen = 999)  

# Read the COVID-19 data from CSV files
# These datasets contain confirmed cases, deaths, and recoveries over time
confirmed_global <- read.csv("confirmed_global.csv", check.names = FALSE)
recovered <- read.csv("recovered.csv", check.names = FALSE)
deaths <- read.csv("deaths.csv", check.names = FALSE)
confirmed <- read.csv("confirmed.csv", check.names = FALSE)
deaths_global <- read.csv("deaths_global.csv", check.names = FALSE)
confirmed_pivot <- read.csv("confirmed_pivot.csv", check.names = FALSE)
deaths_pivot <- read.csv("deaths_pivot.csv", check.names = FALSE)

# Standardize column names to ensure consistency across datasets
# Some datasets may use "Country/Region" while others use "Country"
if ("Country/Region" %in% colnames(deaths_global)) {
  deaths_global <- deaths_global %>% rename(Country = "Country/Region")
}

# Convert wide-format data (dates as columns) into long format
# This is necessary for time series analysis and visualization
confirmed_global <- confirmed_global %>%
  pivot_longer(cols = -c(1:2), names_to = "Date", values_to = "Confirmed")

recovered <- recovered %>%
  pivot_longer(cols = -c(1:2), names_to = "Date", values_to = "Recovered")

deaths_global <- deaths_global %>%
  pivot_longer(cols = -c(1:2), names_to = "Date", values_to = "Deaths")

confirmed_pivot <- confirmed_pivot %>%
  pivot_longer(cols = -c(1:2), names_to = "Date", values_to = "Confirmed_Pivot")

deaths_pivot <- deaths_pivot %>%
  pivot_longer(cols = -c(1:2), names_to = "Date", values_to = "Deaths_Pivot")


# Convert the "Date" column to proper date format for accurate time series analysis
confirmed_global$Date <- as.Date(confirmed_global$Date, format="%m/%d/%y")
deaths_global$Date <- as.Date(deaths_global$Date, format="%m/%d/%y")
recovered$Date <- as.Date(recovered$Date, format="%m/%d/%y")
confirmed_pivot$Date <- as.Date(confirmed_pivot$Date, format="%m/%d/%y")
deaths_pivot$Date <- as.Date(deaths_pivot$Date, format="%m/%d/%y")

# Aggregate global data by summing cases for each date
# This ensures we analyze the overall trend rather than individual country trends
confirmed_global_sum <- confirmed_global %>%
  group_by(Date) %>%
  summarise(Confirmed = sum(Confirmed, na.rm = TRUE))

deaths_global_sum <- deaths_global %>%
  group_by(Date) %>%
  summarise(Deaths = sum(Deaths, na.rm = TRUE))

recovered_sum <- recovered %>%
  group_by(Date) %>%
  summarise(Recovered = sum(Recovered, na.rm = TRUE))

confirmed_pivot_sum <- confirmed_pivot %>%
  group_by(Date) %>%
  summarise(Confirmed_Pivot = sum(Confirmed_Pivot, na.rm = TRUE))

deaths_pivot_sum <- deaths_pivot %>%
  group_by(Date) %>%
  summarise(Deaths_Pivot = sum(Deaths_Pivot, na.rm = TRUE))

# Merge datasets to create a comprehensive time series dataset
covid_data <- confirmed_global_sum %>%
  left_join(confirmed_pivot_sum, by = "Date") %>%
  mutate(Confirmed = coalesce(Confirmed, Confirmed_Pivot)) %>%  
  left_join(deaths_global_sum, by = "Date") %>%
  left_join(deaths_pivot_sum, by = "Date") %>%
  mutate(Deaths = coalesce(Deaths, Deaths_Pivot)) %>%  
  left_join(recovered_sum, by = "Date") %>%
  select(Date, Confirmed, Deaths, Recovered)

# Calculate daily new cases, deaths, and recoveries to show trends
covid_data <- covid_data %>%
  arrange(Date) %>%
  mutate(
    Daily_Cases = Confirmed - lag(Confirmed, default = first(Confirmed)),
    Daily_Deaths = Deaths - lag(Deaths, default = first(Deaths)),
    Daily_Recovered = Recovered - lag(Recovered, default = first(Recovered)),
    Recovery_Rate = ifelse(!is.na(Recovered) & Confirmed > 0, (Recovered / Confirmed) * 100, NA),
    Death_Rate = ifelse(Confirmed > 0, (Deaths / Confirmed) * 100, NA)
  )

# Load world map data for visualization
world_map <- ne_countries(scale = "medium", returnclass = "sf")

# Aggregate deaths per country for a global comparison
deaths_by_country <- deaths_global %>%
  group_by(Country) %>%
  summarise(TotalDeaths = sum(Deaths, na.rm = TRUE))

# Merge death data with world map data for visualization
world_map$Country <- world_map$name
deaths_by_country$Country <- trimws(deaths_by_country$Country)
deaths_map_merged <- world_map %>%
  left_join(deaths_by_country, by = "Country")
deaths_map_merged$TotalDeaths[is.na(deaths_map_merged$TotalDeaths)] <- 0


# Global COVID-19 Deaths Heatmap
# Why? This helps visualize the overall impact of COVID-19 worldwide.
map_plot <- ggplot(data = deaths_map_merged) +
  geom_sf(aes(fill = TotalDeaths), color = "black", size = 0.2) +
  scale_fill_gradient(low = "#F7FCB9", high = "#D73027", labels = scales::comma_format(), name = "Total Deaths") +  
  labs(title = "Global COVID-19 Deaths Heatmap") +
  theme_minimal(base_size = 16)

# Identify the Top 10 Countries with the Highest Total COVID-19 Deaths
# Why? Understanding which countries had the highest death toll helps identify regions most affected by the pandemic.
# This can be useful for analyzing government responses, healthcare infrastructure, and overall impact.
top_countries <- deaths_global %>% 
  group_by(Country) %>% 
  summarise(TotalDeaths = sum(Deaths, na.rm = TRUE)) %>% 
  arrange(desc(TotalDeaths)) %>% 
  head(10)

# Top 10 Countries with the Highest Total Deaths
plot2 <- ggplot(top_countries, aes(x = TotalDeaths, y = reorder(Country, TotalDeaths), fill = TotalDeaths)) +
  geom_col() +
  scale_fill_distiller(palette = "Reds", direction = 1, name = "Total Deaths") +
  labs(title = "Top 10 Countries with Highest Deaths", x = "Total Deaths", y = "Country") +
  scale_x_continuous(labels = scales::comma) +
  geom_text(aes(label = scales::comma(TotalDeaths)), 
            hjust = 0.5, color = "white", fontface = "bold", size = 2, 
            position = position_stack(vjust = 0.5)) + 
  theme_minimal(base_size = 16) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1))


# Confirmed Cases Over Time
# Why? This line plot shows the trend of COVID-19 cases over time.
plot1 <- ggplot(covid_data, aes(x = Date, y = Confirmed)) +
  geom_line(color = "#0072B2", size = 1.5) +  
  geom_point(data = covid_data %>% filter(Date %in% seq(min(na.omit(Date)), max(na.omit(Date)), by = "3 months")), 
             aes(x = Date, y = Confirmed), 
             color = "#D55E00", size = 3) +  
  geom_text(data = covid_data %>% filter(Date %in% seq(min(na.omit(Date)), max(na.omit(Date)), by = "6 months")),
            aes(x = Date, y = Confirmed, label = scales::comma(Confirmed)),
            vjust = -1, hjust = 0.5, size = 4, color = "black") + 
  geom_smooth(method = "loess", color = "#E69F00", size = 1, linetype = "dashed") +  
  scale_y_continuous(labels = scales::comma_format()) +  
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +  
  labs(title = "COVID-19 Confirmed Cases Over Time", x = "Date", y = "Total Cases") +
  theme_minimal(base_size = 16) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1))

# Daily New Cases (With Mean, Median, and SD)
# Why? This highlights daily fluctuations in new cases.
plot3 <- ggplot(covid_data, aes(x = Date, y = Daily_Cases)) +
  geom_bar(stat = "identity", fill = "#009E73", alpha = 0.7) +
  scale_y_continuous(labels = scales::comma_format()) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  labs(title = "Daily New COVID-19 Cases", x = "Date", y = "Daily Cases") +
  theme_minimal(base_size = 16) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)) +
  geom_hline(yintercept = mean(covid_data$Daily_Cases, na.rm = TRUE), color = "red", linetype = "dashed") +
  geom_hline(yintercept = median(covid_data$Daily_Cases, na.rm = TRUE), color = "blue", linetype = "dashed") +
  annotate("text", x = max(covid_data$Date), y = mean(covid_data$Daily_Cases, na.rm = TRUE), label = paste("Mean:", round(mean(covid_data$Daily_Cases, na.rm = TRUE))), vjust = -0.5, hjust = 1) +
  annotate("text", x = max(covid_data$Date), y = median(covid_data$Daily_Cases, na.rm = TRUE), label = paste("Median:", round(median(covid_data$Daily_Cases, na.rm = TRUE))), vjust = 1.5, hjust = 1)

# Recovery vs Death Rate
# Why? This compares how recovery and death rates changed over time.
plot4 <- ggplot(covid_data, aes(x = Date)) +
  geom_area(aes(y = Recovery_Rate, fill = "Recovery Rate"), alpha = 0.6) +
  geom_area(aes(y = Death_Rate, fill = "Death Rate"), alpha = 0.6) +
  scale_fill_manual(values = c("Recovery Rate" = "#66C2A5", "Death Rate" = "#FC8D62")) +
  scale_y_continuous(labels = scales::comma_format()) +  
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +  
  labs(title = "Recovery vs Death Rate Over Time", x = "Date", y = "Rate (%)", fill = "Rate Type") +
  theme_minimal(base_size = 16) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)) 


# Plot: ARIMA Forecast vs Actual  
# Why? This plot visually compares the ARIMA model's predictions with the actual COVID-19 daily cases.  
# Check if covid_data is loaded properly
if (!exists("covid_data")) {
  stop("Error: covid_data is not loaded. Please load the dataset first.")
}

# Check available column names
print(colnames(covid_data))  

# Ensure Date is in proper date format
covid_data$Date <- as.Date(covid_data$Date, format = "%Y-%m-%d")

# Select the correct column for cases
if (!"Daily_Cases" %in% colnames(covid_data)) {
  stop("Error: Column 'Daily_Cases' not found in covid_data.")
}

# Handle missing values
covid_data <- covid_data %>% filter(!is.na(Daily_Cases))

# Convert to time series
ts_data <- ts(covid_data$Daily_Cases, frequency = 7)  # Weekly seasonality

# Check if ts_data has enough observations
if (length(ts_data) < 2) {
  stop("Error: Time series data has less than 2 observations. Please check data.")
}

# Define training and test split (80% train, 20% test)
train_size <- floor(0.8 * length(ts_data))
train_data <- ts_data[1:train_size]
test_data <- ts_data[(train_size + 1):length(ts_data)]

# Fit ARIMA model
arima_model <- auto.arima(train_data)  # Automatically selects best ARIMA model

# Summary of the model
summary(arima_model)

# Forecast the next values
arima_forecast <- forecast(arima_model, h = length(test_data))  # Forecast same length as test set

# Extract predicted values
predicted_values <- arima_forecast$mean

# Print actual vs forecasted values
forecast_results <- data.frame(Actual = test_data, Forecasted = predicted_values)
print(forecast_results)

# Plot actual vs forecast
plot(arima_forecast, main="ARIMA Forecast vs Actual", col="blue")
lines(test_data, col="red", lwd=2)  # Actual data in red
legend("topright", legend=c("Forecasted", "Actual"), col=c("blue", "red"), lty=1)


arima_model <- arima(train_data, order = c(3,1,4))
arima_residuals <- residuals(arima_model)

# Check residuals length
print(length(arima_residuals))

# Convert residuals to a data frame
residuals_df <- data.frame( Date = covid_data$Date[1:length(arima_residuals)],  
  Residuals = arima_residuals
)


residual_plot <- ggplot(residuals_df, aes(x = Date, y = Residuals)) +
  geom_line(color = "darkgreen") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  labs(title = "ARIMA(3,1,4) Residuals", x = "Date", y = "Residuals") +
  theme_minimal(base_size = 16)

# Show plot
print(residual_plot)

acf_plot <- ggAcf(arima_residuals, main = "Residuals ACF (ARIMA 3,1,4)")

print(acf_plot)

# Arrange the Storytelling Layout with Borders
final_plot <- (map_plot + plot2 + 
                 plot_layout(ncol = 2) & theme(panel.border = element_rect(color = "black", fill = NA, size = 1.2))) /
  (plot1 + plot3 + plot4 + residual_plot + acf_plot +
     plot_layout(ncol = 3) & theme(panel.border = element_rect(color = "black", fill = NA, size = 1.2))) +
  plot_annotation(title = "Comprehensive Analysis of COVID-19: Global Impact, Trends, and Recovery Patterns", 
                  theme = theme(plot.title = element_text(size = 20, hjust = 0.5)))


print(final_plot)
ggsave("Comprehensive_Analysis_of_COVID-19-Global_Impact_Trends_and_Recovery_Patterns.png", final_plot, width = 24, height = 14, dpi = 300)
# Save each visualization separately
ggsave("map_plot.png", map_plot, width = 10, height = 6, dpi = 300)
ggsave("top_10_countries.png", plot2, width = 10, height = 6, dpi = 300)
ggsave("confirmed_cases_trend.png", plot1, width = 10, height = 6, dpi = 300)
ggsave("daily_cases.png", plot3, width = 10, height = 6, dpi = 300)
ggsave("recovery_vs_death_rate.png", plot4, width = 10, height = 6, dpi = 300)
ggsave("ARIMA_Residuals.png", residual_plot, width = 10, height = 6, dpi = 300)
ggsave("ARIMA_Residuals_ACF.png", acf_plot, width = 10, height = 6, dpi = 300)


