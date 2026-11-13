-- ============================================================================
-- Script: 01_create_dimensions.sql
-- Purpose: Create all 6 dimension tables in project_dw (Silver Layer)
-- Schema: project_dw
-- Phase: 2 - Dimension Implementation
--
-- Dimensions:
--   1. dim_date
--   2. dim_timeofday
--   3. dim_weather
--   4. dim_zone
--   5. dim_company
--   6. dim_station  (SCD Type 2)
-- ============================================================================

SET search_path TO project_dw;

-- ============================================================================
-- 1. DIM_DATE
-- Grain: One row per calendar date
-- SCD Type 1 (static reference data)
-- ============================================================================

DROP TABLE IF EXISTS dim_date CASCADE;

CREATE TABLE dim_date (
    date_key        SERIAL          PRIMARY KEY,          -- Surrogate key
    full_date       DATE            NOT NULL UNIQUE,      -- Business key
    day_of_month    SMALLINT        NOT NULL,
    day_of_week     SMALLINT        NOT NULL,             -- 1=Sunday ... 7=Saturday
    weekday_name    VARCHAR(10)     NOT NULL,             -- 'Monday', 'Tuesday' ...
    is_weekend      BOOLEAN         NOT NULL,
    week_of_year    SMALLINT        NOT NULL,
    month_num       SMALLINT        NOT NULL,
    month_name      VARCHAR(10)     NOT NULL,             -- 'January' ...
    quarter         SMALLINT        NOT NULL,             -- 1–4
    year            SMALLINT        NOT NULL
);

COMMENT ON TABLE dim_date IS 'Date dimension — one row per calendar date';

-- ============================================================================
-- 2. DIM_TIMEOFDAY
-- Grain: One row per hour of the day (0–23)
-- SCD Type 1 (static reference data)
-- ============================================================================

DROP TABLE IF EXISTS dim_timeofday CASCADE;

CREATE TABLE dim_timeofday (
    time_key        SERIAL          PRIMARY KEY,          -- Surrogate key
    hour_of_day     SMALLINT        NOT NULL UNIQUE       -- Business key (0–23)
                        CHECK (hour_of_day BETWEEN 0 AND 23),
    peak_offpeak    VARCHAR(10)     NOT NULL,             -- 'Peak' | 'Off-Peak'
    day_part        VARCHAR(15)     NOT NULL              -- 'Morning' | 'Afternoon' | 'Evening' | 'Night'
);

COMMENT ON TABLE dim_timeofday IS 'Time-of-day dimension — one row per hour (0–23)';

-- ============================================================================
-- 3. DIM_WEATHER
-- Grain: One row per weather band (categorized from raw hourly data)
-- SCD Type 1
-- ============================================================================

DROP TABLE IF EXISTS dim_weather CASCADE;

CREATE TABLE dim_weather (
    weather_key         SERIAL          PRIMARY KEY,      -- Surrogate key
    weather_band        VARCHAR(50)     NOT NULL UNIQUE,  -- Business key e.g. 'Heavy Rain'
    rain_level          VARCHAR(20)     NOT NULL,         -- 'None' | 'Light' | 'Moderate' | 'Heavy'
    temp_band           VARCHAR(20)     NOT NULL,         -- 'Freezing' | 'Cold' | 'Mild' | 'Warm'
    humidity_band       VARCHAR(20)     NOT NULL          -- 'Low' | 'Moderate' | 'High'
);

COMMENT ON TABLE dim_weather IS 'Weather dimension — categorized weather bands derived from hourly observations';

-- ============================================================================
-- 4. DIM_ZONE
-- Grain: One row per NYC taxi zone
-- SCD Type 1
-- ============================================================================

DROP TABLE IF EXISTS dim_zone CASCADE;

CREATE TABLE dim_zone (
    zone_key        SERIAL          PRIMARY KEY,          -- Surrogate key
    location_id     INTEGER         NOT NULL UNIQUE,      -- Business key (from TLC)
    zone_name       VARCHAR(255),
    borough         VARCHAR(50),
    service_zone    VARCHAR(50)
);

COMMENT ON TABLE dim_zone IS 'Zone dimension — NYC taxi zones from TLC lookup table';

-- ============================================================================
-- 5. DIM_COMPANY
-- Grain: One row per ride-hailing company
-- SCD Type 1
-- ============================================================================

DROP TABLE IF EXISTS dim_company CASCADE;

CREATE TABLE dim_company (
    company_key         SERIAL          PRIMARY KEY,      -- Surrogate key
    hvfhs_license_num   VARCHAR(10)     NOT NULL UNIQUE,  -- Business key
    company_name        VARCHAR(100)    NOT NULL,
    dispatching_base_num VARCHAR(10)
);

COMMENT ON TABLE dim_company IS 'Company dimension — Uber, Lyft, and other HVFHS operators';

-- ============================================================================
-- 6. DIM_STATION  (SCD Type 2)
-- Grain: One row per version of an EV charging station
-- SCD Type 2 — tracks historical changes via effective_from / effective_to / is_current
-- ============================================================================

DROP TABLE IF EXISTS dim_station CASCADE;

CREATE TABLE dim_station (
    station_key         SERIAL          PRIMARY KEY,      -- Surrogate key
    station_id          VARCHAR(100)    NOT NULL,         -- Business key (from AFDC/NREL)
    station_name        VARCHAR(255),
    street_address      VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(2),
    zip                 VARCHAR(10),
    latitude            NUMERIC(12,8),
    longitude           NUMERIC(12,8),
    ev_network          VARCHAR(100),
    ev_connector_types  TEXT,
    num_ports           INTEGER,                          -- Total ports (L1 + L2 + DC)
    charger_level       VARCHAR(20),                      -- 'Level 1' | 'Level 2' | 'DC Fast' | 'Mixed'
    status              VARCHAR(50),                      -- 'E' (Available) | 'P' (Planned) | 'T' (Temp unavailable)
    access_code         VARCHAR(50),
    facility_type       VARCHAR(100),
    -- SCD Type 2 tracking columns
    effective_from      DATE            NOT NULL DEFAULT CURRENT_DATE,
    effective_to        DATE            NOT NULL DEFAULT '9999-12-31',
    is_current          BOOLEAN         NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE dim_station IS 'Station dimension (SCD Type 2) — EV charging stations with change history';

-- Index to quickly find the current version of a station
CREATE INDEX idx_dim_station_business_key ON dim_station(station_id, is_current);
CREATE INDEX idx_dim_zone_location ON dim_zone(location_id);
CREATE INDEX idx_dim_date_full ON dim_date(full_date);
CREATE INDEX idx_dim_company_license ON dim_company(hvfhs_license_num);

-- ============================================================================
-- Verification
-- ============================================================================
SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns c
     WHERE c.table_schema = 'project_dw'
       AND c.table_name   = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'project_dw'
  AND table_type   = 'BASE TABLE'
ORDER BY table_name;
