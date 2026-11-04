# Data Sources - NYC EV Mobility Data Warehouse

**Project:** NYC Ride-Hailing, Weather & EV Charging Access  
**Phase:** 2 - Data Source Creation  
**Date:** November 2026  

---

## Data Sources Overview

This project uses **4 primary data sources** from official government and public APIs, plus 1 reference shapefile for spatial analysis.

---

## 1. NYC TLC High Volume For-Hire Vehicle (FHV) Trip Data

### Source Information
- **Provider:** NYC Taxi & Limousne Commission (TLC)
- **Data Type:** Uber, Lyft, Via, Juno trip records
- **Period:** January 2024
- **Format:** Parquet (converted to CSV)

### Direct Download Link
```
https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_2024-01.parquet
```

### File Details
- **Original Size:** ~500 MB (parquet)
- **Processed Size:** 76.3 MB (500k sample CSV)
- **Rows:** 500,000 (sampled from 19.6M)
- **Columns:** 24

### Key Fields
- `hvfhs_license_num` - Company identifier (HV0003=Uber, HV0005=Lyft)
- `PULocationID` - Pickup zone ID
- `DOLocationID` - Dropoff zone ID
- `pickup_datetime`, `dropoff_datetime` - Trip timestamps
- `trip_miles`, `trip_time` - Trip metrics
- `base_passenger_fare`, `tips`, `driver_pay` - Financial data

### Data Dictionary
Available at: https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_hvfhs.pdf

---

## 2. NYC Taxi Zone Lookup

### Source Information
- **Provider:** NYC Taxi & Limousine Commission (TLC)
- **Data Type:** Zone reference data
- **Format:** CSV

### Direct Download Link
```
https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.csv
```

### File Details
- **Size:** < 1 MB
- **Rows:** 265 taxi zones
- **Columns:** 4

### Key Fields
- `LocationID` - Unique zone identifier (matches trip data)
- `Borough` - Manhattan, Brooklyn, Queens, Bronx, Staten Island
- `Zone` - Zone name (e.g., "Times Square", "JFK Airport")
- `service_zone` - Yellow, Green, or Boro zone

---

## 3. NYC Taxi Zone Shapefile

### Source Information
- **Provider:** NYC Taxi & Limousine Commission (TLC)
- **Data Type:** GIS polygon boundaries
- **Format:** ESRI Shapefile (ZIP)

### Direct Download Link
```
https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.zip
```

### File Details
- **Size:** 998.6 KB
- **Format:** Shapefile (SHP, SHX, DBF, PRJ)
- **Use:** Spatial join to assign EV stations to zones

### Usage
```python
import geopandas as gpd
zones = gpd.read_file('taxi_zones.zip')
```

---

## 4. Weather Data (Open-Meteo API)

### Source Information
- **Provider:** Open-Meteo Historical Weather API
- **Data Type:** Hourly weather observations
- **Period:** January 1-31, 2024
- **Location:** NYC (40.7128°N, -74.0060°W)
- **Format:** JSON/CSV

### Direct API Link
```
https://archive-api.open-meteo.com/v1/archive?latitude=40.7128&longitude=-74.0060&start_date=2024-01-01&end_date=2024-01-31&hourly=precipitation,temperature_2m,relative_humidity_2m&timezone=America/New_York
```

### File Details
- **Size:** 21.5 KB
- **Rows:** 744 hourly records (31 days × 24 hours)
- **Columns:** 4

### Key Fields
- `datetime` - Timestamp (hourly)
- `precipitation_mm` - Rainfall in millimeters
- `temperature_c` - Temperature in Celsius
- `humidity_percent` - Relative humidity

### API Documentation
https://open-meteo.com/en/docs/historical-weather-api

---

## 5. EV Charging Stations (NY State Open Data)

### Source Information
- **Provider:** New York State Open Data Portal
- **Data Type:** Electric vehicle charging station locations
- **Coverage:** All NY State (filter for NYC)
- **Format:** CSV

### Direct Download Link
```
https://data.ny.gov/api/views/7rrd-248n/rows.csv?accessType=DOWNLOAD
```

### Alternative API Link (with more fields)
```
https://developer.nrel.gov/api/alt-fuel-stations/v1.json?fuel_type=ELEC&state=NY&city=New+York&api_key=DEMO_KEY&limit=all
```
*Note: Get free API key at https://developer.nrel.gov/signup/*

### File Details
- **Size:** 1.4 MB
- **Total Rows:** 5,552 stations (all NY State)
- **NYC Rows:** 389 stations
- **Columns:** 31

### Key Fields
- `Station Name` - Charging station name
- `Street Address`, `City`, `State`, `ZIP` - Location
- `Latitude`, `Longitude` - Coordinates for spatial join
- `EV Network` - ChargePoint, Tesla Supercharger, etc.
- `EV Level1/Level2 EVSE Num` - Number of Level 1/2 ports
- `EV DC Fast Num` - Number of DC fast chargers
- `Status Code` - Available, Planned, Temporarily Unavailable
- `Open Date` - Station opening date

---

## Data Download Summary

| # | Data Source | Size | Rows | Download Link |
|---|-------------|------|------|---------------|
| 1 | NYC FHV Trips | 76 MB | 500k | [Download](https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_2024-01.parquet) |
| 2 | Taxi Zones | <1 MB | 265 | [Download](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.csv) |
| 3 | Zone Shapefile | 1 MB | N/A | [Download](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.zip) |
| 4 | Weather Data | 22 KB | 744 | [API Link](https://archive-api.open-meteo.com/v1/archive?latitude=40.7128&longitude=-74.0060&start_date=2024-01-01&end_date=2024-01-31&hourly=precipitation,temperature_2m,relative_humidity_2m&timezone=America/New_York) |
| 5 | EV Stations | 1.4 MB | 5,552 | [Download](https://data.ny.gov/api/views/7rrd-248n/rows.csv?accessType=DOWNLOAD) |

---

## Phase 2 Requirements Met

✅ **Option A - Public Datasets:**
- NYC TLC (Government)
- Open-Meteo (Public API)
- NY State Open Data (Government)

✅ **Minimum Size:**
- Dimension records: 654 (265 zones + 389 stations) > 100 ✓
- Fact records: 500,000 trips > 10,000 ✓

---

## Data Storage Structure

```
data/
├── raw/
│   ├── fhvhv_tripdata_2024-01.parquet      (original download)
│   ├── nyc_fhv_trips_jan2024.csv           (500k sample)
│   ├── taxi_zones.csv                      (zone lookup)
│   ├── taxi_zones.zip                      (shapefiles)
│   ├── nyc_weather_jan2024.csv             (weather data)
│   ├── nyc_weather_jan2024.json            (weather backup)
│   └── Electric_Vehicle_Charging_Stations_in_New_York.csv
│
├── processed/
│   └── (cleaned data after ETL)
│
└── sample/
    └── (small samples for testing)
```

---

## How Data Was Obtained

All data sources were manually downloaded from official public sources:

1. **NYC TLC Trip Data:** Downloaded directly from NYC Open Data CloudFront CDN
2. **Taxi Zones:** Downloaded from NYC TLC reference data
3. **Shapefiles:** Downloaded from NYC TLC GIS repository
4. **Weather:** Fetched from Open-Meteo Historical Weather API
5. **EV Stations:** Downloaded from NY State Open Data Portal

**Date Downloaded:** November 2026  
**Downloaded By:** [Your Name]  

---

## Data Usage & Citations

### NYC TLC Data
- **Source:** NYC Taxi & Limousine Commission
- **License:** Public Domain
- **URL:** https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page

### Open-Meteo Weather Data
- **Source:** Open-Meteo.com
- **License:** CC BY 4.0
- **URL:** https://open-meteo.com

### NY State EV Charging Data
- **Source:** New York State Open Data
- **Original Source:** U.S. Department of Energy - Alternative Fuels Data Center (AFDC)
- **License:** Public Domain
- **URL:** https://data.ny.gov/Energy-Environment/Electric-Vehicle-Charging-Stations-in-New-York/7rrd-248n

---

**Document Version:** 1.0  
**Last Updated:** November 2026  
**Project Phase:** 2 - Data Source Creation
