-- ============================================================================
-- Script: 01_load_dimensions.sql
-- Purpose: Populate all 6 dimension tables from clean staging views
-- Schema: project_dw (reads from project_staging clean views)
-- Phase: 2 - ETL Dimension Loading
--
-- Run AFTER:
--   01_create_schemas.sql
--   02_staging/01_create_staging_tables.sql
--   02_staging/02_clean_staging.sql   (creates the _clean views)
--   03_dimensions/01_create_dimensions.sql
--   load_staging.py (data must be in staging tables)
--
-- Order matters — load in this sequence:
--   1. dim_date
--   2. dim_timeofday
--   3. dim_weather
--   4. dim_zone
--   5. dim_company
--   6. dim_station
-- ============================================================================

SET search_path TO project_dw;

-- ============================================================================
-- 1. LOAD DIM_DATE
-- Generate one row per calendar date in January 2024
-- (extend the range if your data spans more than one month)
-- ============================================================================

TRUNCATE TABLE dim_date RESTART IDENTITY CASCADE;

INSERT INTO dim_date (
    full_date, day_of_month, day_of_week, weekday_name, is_weekend,
    week_of_year, month_num, month_name, quarter, year
)
SELECT
    d::DATE                                 AS full_date,
    EXTRACT(DAY   FROM d)::SMALLINT         AS day_of_month,
    EXTRACT(DOW   FROM d)::SMALLINT + 1     AS day_of_week,     -- 1=Sunday, 7=Saturday
    TO_CHAR(d, 'Day')                       AS weekday_name,
    EXTRACT(DOW   FROM d) IN (0, 6)         AS is_weekend,
    EXTRACT(WEEK  FROM d)::SMALLINT         AS week_of_year,
    EXTRACT(MONTH FROM d)::SMALLINT         AS month_num,
    TO_CHAR(d, 'Month')                     AS month_name,
    EXTRACT(QUARTER FROM d)::SMALLINT       AS quarter,
    EXTRACT(YEAR  FROM d)::SMALLINT         AS year
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-01-31'::DATE,
    '1 day'::INTERVAL
) AS d;

SELECT 'dim_date' AS table_name, COUNT(*) AS rows_loaded FROM dim_date;

-- ============================================================================
-- 2. LOAD DIM_TIMEOFDAY
-- 24 rows — one per hour (0–23)
-- ============================================================================

TRUNCATE TABLE dim_timeofday RESTART IDENTITY CASCADE;

INSERT INTO dim_timeofday (hour_of_day, peak_offpeak, day_part)
VALUES
    -- Night
    (0,  'Off-Peak', 'Night'),
    (1,  'Off-Peak', 'Night'),
    (2,  'Off-Peak', 'Night'),
    (3,  'Off-Peak', 'Night'),
    (4,  'Off-Peak', 'Night'),
    (5,  'Off-Peak', 'Night'),
    -- Morning
    (6,  'Off-Peak', 'Morning'),
    (7,  'Peak',     'Morning'),
    (8,  'Peak',     'Morning'),
    (9,  'Peak',     'Morning'),
    (10, 'Off-Peak', 'Morning'),
    (11, 'Off-Peak', 'Morning'),
    -- Afternoon
    (12, 'Off-Peak', 'Afternoon'),
    (13, 'Off-Peak', 'Afternoon'),
    (14, 'Off-Peak', 'Afternoon'),
    (15, 'Off-Peak', 'Afternoon'),
    (16, 'Peak',     'Afternoon'),
    (17, 'Peak',     'Afternoon'),
    -- Evening
    (18, 'Peak',     'Evening'),
    (19, 'Peak',     'Evening'),
    (20, 'Off-Peak', 'Evening'),
    (21, 'Off-Peak', 'Evening'),
    (22, 'Off-Peak', 'Evening'),
    (23, 'Off-Peak', 'Night');

SELECT 'dim_timeofday' AS table_name, COUNT(*) AS rows_loaded FROM dim_timeofday;

-- ============================================================================
-- 3. LOAD DIM_WEATHER
-- Derive weather bands from actual hourly staging data
-- Each unique combination of rain_level + temp_band + humidity_band = one row
-- ============================================================================

TRUNCATE TABLE dim_weather RESTART IDENTITY CASCADE;

INSERT INTO dim_weather (weather_band, rain_level, temp_band, humidity_band)
SELECT DISTINCT
    -- Composite business key
    rain_level || ' / ' || temp_band || ' / ' || humidity_band  AS weather_band,
    rain_level,
    temp_band,
    humidity_band
FROM (
    SELECT
        CASE
            WHEN precipitation_mm IS NULL OR precipitation_mm = 0   THEN 'No Rain'
            WHEN precipitation_mm < 2.5                              THEN 'Light Rain'
            WHEN precipitation_mm < 10                               THEN 'Moderate Rain'
            ELSE                                                           'Heavy Rain'
        END AS rain_level,
        CASE
            WHEN temperature_c IS NULL OR temperature_c < 0  THEN 'Freezing'
            WHEN temperature_c < 10                          THEN 'Cold'
            WHEN temperature_c < 20                          THEN 'Mild'
            ELSE                                                   'Warm'
        END AS temp_band,
        CASE
            WHEN humidity_percent IS NULL OR humidity_percent < 40  THEN 'Low'
            WHEN humidity_percent < 70                               THEN 'Moderate'
            ELSE                                                          'High'
        END AS humidity_band
    FROM project_staging.stg_weather_clean
) bands
ORDER BY rain_level, temp_band, humidity_band;

SELECT 'dim_weather' AS table_name, COUNT(*) AS rows_loaded FROM dim_weather;

-- ============================================================================
-- 4. LOAD DIM_ZONE
-- Source: project_staging.stg_zones_clean (265 rows)
-- ============================================================================

TRUNCATE TABLE dim_zone RESTART IDENTITY CASCADE;

INSERT INTO dim_zone (location_id, zone_name, borough, service_zone)
SELECT
    locationid,
    zone,
    borough,
    service_zone
FROM project_staging.stg_zones_clean
ORDER BY locationid;

SELECT 'dim_zone' AS table_name, COUNT(*) AS rows_loaded FROM dim_zone;

-- ============================================================================
-- 5. LOAD DIM_COMPANY
-- Derived from trip data — maps license codes to company names
-- ============================================================================

TRUNCATE TABLE dim_company RESTART IDENTITY CASCADE;

INSERT INTO dim_company (hvfhs_license_num, company_name, dispatching_base_num)
VALUES
    ('HV0003', 'Uber',  'B03404'),
    ('HV0005', 'Lyft',  'B03406'),
    ('HV0004', 'Via',   NULL),
    ('HV0043', 'Juno',  NULL);

-- Also insert any codes found in trips that aren't in the list above
INSERT INTO dim_company (hvfhs_license_num, company_name, dispatching_base_num)
SELECT DISTINCT
    hvfhs_license_num,
    'Unknown (' || hvfhs_license_num || ')',
    dispatching_base_num
FROM project_staging.stg_trips_clean
WHERE hvfhs_license_num IS NOT NULL
  AND hvfhs_license_num NOT IN (SELECT hvfhs_license_num FROM dim_company);

SELECT 'dim_company' AS table_name, COUNT(*) AS rows_loaded FROM dim_company;

-- ============================================================================
-- 6. LOAD DIM_STATION (SCD Type 2 — initial load, all rows are "current")
-- Source: project_staging.stg_charging_stations_clean
-- num_ports = sum of all port types; charger_level derived from available ports
-- ============================================================================

TRUNCATE TABLE dim_station RESTART IDENTITY CASCADE;

INSERT INTO dim_station (
    station_id, station_name, street_address, city, state, zip,
    latitude, longitude, ev_network, ev_connector_types,
    num_ports, charger_level, status,
    access_code, facility_type,
    effective_from, effective_to, is_current
)
SELECT
    station_id,
    station_name,
    street_address,
    city,
    state,
    zip,
    latitude,
    longitude,
    ev_network,
    ev_connector_types,

    -- Total ports
    COALESCE(ev_level1_evse_num, 0)
        + COALESCE(ev_level2_evse_num, 0)
        + COALESCE(ev_dc_fast_num, 0)                       AS num_ports,

    -- Charger level classification
    CASE
        WHEN COALESCE(ev_dc_fast_num, 0) > 0
         AND COALESCE(ev_level2_evse_num, 0) = 0
         AND COALESCE(ev_level1_evse_num, 0) = 0  THEN 'DC Fast'
        WHEN COALESCE(ev_level2_evse_num, 0) > 0
         AND COALESCE(ev_dc_fast_num, 0) = 0
         AND COALESCE(ev_level1_evse_num, 0) = 0  THEN 'Level 2'
        WHEN COALESCE(ev_level1_evse_num, 0) > 0
         AND COALESCE(ev_level2_evse_num, 0) = 0
         AND COALESCE(ev_dc_fast_num, 0) = 0      THEN 'Level 1'
        ELSE 'Mixed'
    END                                                      AS charger_level,

    status_code                                              AS status,
    access_code,
    facility_type,

    -- SCD Type 2 — initial load: effective from open_date or today
    COALESCE(open_date, CURRENT_DATE)                        AS effective_from,
    '9999-12-31'::DATE                                       AS effective_to,
    TRUE                                                     AS is_current

FROM project_staging.stg_charging_stations_clean
WHERE station_id IS NOT NULL
ORDER BY station_id;

SELECT 'dim_station' AS table_name, COUNT(*) AS rows_loaded FROM dim_station;

-- ============================================================================
-- FINAL VERIFICATION — row counts for all dimensions
-- ============================================================================
SELECT 'dim_date'      AS dim, COUNT(*) AS rows FROM dim_date      UNION ALL
SELECT 'dim_timeofday',         COUNT(*)        FROM dim_timeofday UNION ALL
SELECT 'dim_weather',           COUNT(*)        FROM dim_weather   UNION ALL
SELECT 'dim_zone',              COUNT(*)        FROM dim_zone      UNION ALL
SELECT 'dim_company',           COUNT(*)        FROM dim_company   UNION ALL
SELECT 'dim_station',           COUNT(*)        FROM dim_station
ORDER BY dim;
