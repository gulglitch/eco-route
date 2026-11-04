-- ============================================================================
-- Script: 01_create_staging_tables.sql
-- Purpose: Create staging tables for raw data ingestion (Bronze Layer)
-- Schema: project_staging
-- Phase: 2 - Staging Layer Implementation
-- ============================================================================

SET search_path TO project_staging;

-- ============================================================================
-- 1. STAGING: Trips
-- Source: nyc_fhv_trips_jan2024.csv (500k rows)
-- ============================================================================

DROP TABLE IF EXISTS stg_trips CASCADE;

CREATE TABLE stg_trips (
    -- Source columns from NYC TLC
    hvfhs_license_num VARCHAR(10),
    dispatching_base_num VARCHAR(10),
    originating_base_num VARCHAR(10),
    request_datetime TIMESTAMP,
    on_scene_datetime TIMESTAMP,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    PULocationID INTEGER,
    DOLocationID INTEGER,
    trip_miles NUMERIC(10,2),
    trip_time INTEGER,
    base_passenger_fare NUMERIC(10,2),
    tolls NUMERIC(10,2),
    bcf NUMERIC(10,2),
    sales_tax NUMERIC(10,2),
    congestion_surcharge NUMERIC(10,2),
    airport_fee NUMERIC(10,2),
    tips NUMERIC(10,2),
    driver_pay NUMERIC(10,2),
    shared_request_flag VARCHAR(1),
    shared_match_flag VARCHAR(1),
    access_a_ride_flag VARCHAR(1),
    wav_request_flag VARCHAR(1),
    wav_match_flag VARCHAR(1),
    
    -- Audit columns
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch_id VARCHAR(50),
    source_file VARCHAR(255)
);

COMMENT ON TABLE stg_trips IS 'Staging: NYC TLC High Volume For-Hire Vehicle trips (Uber/Lyft) - January 2024';

-- ============================================================================
-- 2. STAGING: Weather
-- Source: nyc_weather_jan2024.csv (744 hourly records)
-- ============================================================================

DROP TABLE IF EXISTS stg_weather CASCADE;

CREATE TABLE stg_weather (
    datetime TIMESTAMP NOT NULL,
    precipitation_mm NUMERIC(10,2),
    temperature_c NUMERIC(10,2),
    humidity_percent NUMERIC(10,2),
    
    -- Audit columns
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch_id VARCHAR(50),
    source_file VARCHAR(255)
);

COMMENT ON TABLE stg_weather IS 'Staging: Hourly weather data from Open-Meteo API for NYC - January 2024';

-- ============================================================================
-- 3. STAGING: Zones
-- Source: taxi+_zone_lookup.csv (265 zones)
-- ============================================================================

DROP TABLE IF EXISTS stg_zones CASCADE;

CREATE TABLE stg_zones (
    LocationID INTEGER NOT NULL,
    Borough VARCHAR(50),
    Zone VARCHAR(255),
    service_zone VARCHAR(50),
    
    -- Audit columns
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch_id VARCHAR(50),
    source_file VARCHAR(255)
);

COMMENT ON TABLE stg_zones IS 'Staging: NYC Taxi Zone lookup data';

-- ============================================================================
-- 4. STAGING: Charging Stations
-- Source: Electric_Vehicle_Charging_Stations_in_New_York.csv (5,552 total, 389 NYC)
-- ============================================================================

DROP TABLE IF EXISTS stg_charging_stations CASCADE;

CREATE TABLE stg_charging_stations (
    -- Core identification
    station_id VARCHAR(100),
    station_name VARCHAR(255),
    
    -- Location
    street_address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(2),
    zip VARCHAR(10),
    latitude NUMERIC(12,8),
    longitude NUMERIC(12,8),
    
    -- Network & charging details
    ev_network VARCHAR(100),
    ev_connector_types TEXT,
    ev_level1_evse_num INTEGER,
    ev_level2_evse_num INTEGER,
    ev_dc_fast_num INTEGER,
    
    -- Status & dates
    status_code VARCHAR(50),
    open_date DATE,
    date_last_confirmed DATE,
    
    -- Additional fields (to be mapped during exploration)
    fuel_type_code VARCHAR(10),
    intersection_directions TEXT,
    access_code VARCHAR(50),
    facility_type VARCHAR(100),
    
    -- Audit columns
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch_id VARCHAR(50),
    source_file VARCHAR(255)
);

COMMENT ON TABLE stg_charging_stations IS 'Staging: EV Charging Stations from NY State Open Data (will filter for NYC)';

-- ============================================================================
-- 5. STAGING: Data Quality Reject Table
-- Purpose: Store rows that fail data quality checks
-- ============================================================================

DROP TABLE IF EXISTS stg_data_quality_rejects CASCADE;

CREATE TABLE stg_data_quality_rejects (
    reject_id SERIAL PRIMARY KEY,
    source_table VARCHAR(100) NOT NULL,
    reject_reason VARCHAR(500) NOT NULL,
    rejected_row TEXT,
    reject_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch_id VARCHAR(50)
);

COMMENT ON TABLE stg_data_quality_rejects IS 'Bad rows rejected during data quality checks';

-- ============================================================================
-- Create Indexes for Performance
-- ============================================================================

-- Trips staging indexes
CREATE INDEX idx_stg_trips_pu_location ON stg_trips(PULocationID);
CREATE INDEX idx_stg_trips_do_location ON stg_trips(DOLocationID);
CREATE INDEX idx_stg_trips_pickup_datetime ON stg_trips(pickup_datetime);
CREATE INDEX idx_stg_trips_company ON stg_trips(hvfhs_license_num);

-- Weather staging indexes
CREATE INDEX idx_stg_weather_datetime ON stg_weather(datetime);

-- Zones staging indexes
CREATE INDEX idx_stg_zones_location_id ON stg_zones(LocationID);

-- Charging stations staging indexes
CREATE INDEX idx_stg_stations_city ON stg_charging_stations(city);
CREATE INDEX idx_stg_stations_lat_lng ON stg_charging_stations(latitude, longitude);
CREATE INDEX idx_stg_stations_id ON stg_charging_stations(station_id);

-- ============================================================================
-- Verification Query
-- ============================================================================

SELECT 
    table_name,
    pg_size_pretty(pg_total_relation_size('project_staging.' || table_name)) AS table_size
FROM information_schema.tables
WHERE table_schema = 'project_staging'
AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- ============================================================================
-- Expected Output: 5 empty staging tables created
-- ============================================================================

SELECT 'SUCCESS: All staging tables created!' AS status;
