-- ============================================================================
-- Script: 02_load_facts.sql
-- Purpose: Populate all 3 fact tables by joining staging data to dimension keys
-- Schema: project_dw
-- Phase: 2 - ETL Fact Loading
--
-- Run AFTER:
--   05_etl/01_load_dimensions.sql
-- ============================================================================

SET search_path TO project_dw;

-- ============================================================================
-- 1. LOAD FACT_TRIPS
-- Join each cleaned trip row to its dimension surrogate keys
-- ============================================================================

TRUNCATE TABLE fact_trips RESTART IDENTITY CASCADE;

INSERT INTO fact_trips (
    pickup_zone_key,
    dropoff_zone_key,
    company_key,
    date_key,
    time_key,
    weather_key,
    dispatching_base_num,
    trip_miles,
    trip_time_sec,
    base_fare,
    tolls,
    sales_tax,
    congestion_surcharge,
    airport_fee,
    tips,
    driver_pay,
    wait_min,
    shared_request_flag,
    wav_request_flag,
    batch_id
)
SELECT
    -- Pickup zone surrogate key
    pz.zone_key                                                 AS pickup_zone_key,

    -- Dropoff zone surrogate key
    dz.zone_key                                                 AS dropoff_zone_key,

    -- Company surrogate key
    co.company_key                                              AS company_key,

    -- Date surrogate key (from pickup datetime)
    dd.date_key                                                 AS date_key,

    -- Time surrogate key (hour of pickup)
    dt.time_key                                                 AS time_key,

    -- Weather surrogate key — match the weather band to the pickup hour
    dw.weather_key                                              AS weather_key,

    -- Degenerate dimension
    t.dispatching_base_num,

    -- Measures
    t.trip_miles,
    t.trip_time                                                 AS trip_time_sec,
    t.base_passenger_fare                                       AS base_fare,
    t.tolls,
    t.sales_tax,
    t.congestion_surcharge,
    t.airport_fee,
    t.tips,
    t.driver_pay,

    -- Wait time: minutes from request to actual pickup
    CASE
        WHEN t.request_datetime IS NOT NULL AND t.pickup_datetime IS NOT NULL
        THEN ROUND(
            EXTRACT(EPOCH FROM (t.pickup_datetime - t.request_datetime)) / 60.0,
            2
        )
        ELSE NULL
    END                                                         AS wait_min,

    t.shared_request_flag,
    t.wav_request_flag,

    'ETL_FACTS_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI')  AS batch_id

FROM project_staging.stg_trips_clean t

-- Zone lookups
INNER JOIN dim_zone pz  ON pz.location_id = t.pulocationid
INNER JOIN dim_zone dz  ON dz.location_id = t.dolocationid

-- Company lookup
INNER JOIN dim_company co ON co.hvfhs_license_num = t.hvfhs_license_num

-- Date lookup (from pickup date)
INNER JOIN dim_date dd   ON dd.full_date = t.pickup_datetime::DATE

-- Time lookup (from pickup hour)
INNER JOIN dim_timeofday dt ON dt.hour_of_day = EXTRACT(HOUR FROM t.pickup_datetime)::SMALLINT

-- Weather lookup — find the weather record for the same hour as pickup
INNER JOIN (
    -- Map each raw hourly weather row to its dim_weather surrogate key
    SELECT
        sw.datetime,
        dw2.weather_key
    FROM project_staging.stg_weather_clean sw
    INNER JOIN dim_weather dw2 ON dw2.weather_band = (
        CASE
            WHEN sw.precipitation_mm IS NULL OR sw.precipitation_mm = 0   THEN 'No Rain'
            WHEN sw.precipitation_mm < 2.5                                 THEN 'Light Rain'
            WHEN sw.precipitation_mm < 10                                  THEN 'Moderate Rain'
            ELSE                                                                 'Heavy Rain'
        END
        || ' / ' ||
        CASE
            WHEN sw.temperature_c IS NULL OR sw.temperature_c < 0  THEN 'Freezing'
            WHEN sw.temperature_c < 10                              THEN 'Cold'
            WHEN sw.temperature_c < 20                              THEN 'Mild'
            ELSE                                                          'Warm'
        END
        || ' / ' ||
        CASE
            WHEN sw.humidity_percent IS NULL OR sw.humidity_percent < 40  THEN 'Low'
            WHEN sw.humidity_percent < 70                                   THEN 'Moderate'
            ELSE                                                                 'High'
        END
    )
) weather_map
    ON weather_map.datetime = DATE_TRUNC('hour', t.pickup_datetime)

-- Only join to current station records for SCD Type 2
LEFT JOIN dim_station ds ON ds.station_id IS NOT NULL AND ds.is_current = TRUE

-- Drop trips where mandatory dimension keys couldn't be resolved
WHERE t.pickup_datetime IS NOT NULL
  AND t.pulocationid    IS NOT NULL
  AND t.dolocationid    IS NOT NULL
  AND t.hvfhs_license_num IS NOT NULL;

SELECT 'fact_trips' AS table_name, COUNT(*) AS rows_loaded FROM fact_trips;

-- ============================================================================
-- 2. LOAD FACT_ZONE_HOURLY_SNAPSHOT
-- Aggregate trip counts and financial measures per zone per hour
-- ============================================================================

TRUNCATE TABLE fact_zone_hourly_snapshot CASCADE;

INSERT INTO fact_zone_hourly_snapshot (
    zone_key,
    date_key,
    time_key,
    weather_key,
    trip_count,
    total_wait_min,
    avg_wait_min,
    total_driver_pay,
    avg_trip_miles,
    rainfall_mm,
    batch_id
)
SELECT
    ft.pickup_zone_key                          AS zone_key,
    ft.date_key,
    ft.time_key,
    ft.weather_key,

    COUNT(*)                                    AS trip_count,
    SUM(ft.wait_min)                            AS total_wait_min,
    ROUND(AVG(ft.wait_min), 2)                  AS avg_wait_min,
    ROUND(SUM(ft.driver_pay), 2)                AS total_driver_pay,
    ROUND(AVG(ft.trip_miles), 2)                AS avg_trip_miles,

    -- Pull rainfall from the weather dimension via weather_key
    MAX(sw.precipitation_mm)                    AS rainfall_mm,

    'ETL_SNAPSHOT_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI') AS batch_id

FROM fact_trips ft

-- Re-join to weather staging to get the actual rainfall value
INNER JOIN dim_timeofday dt  ON dt.time_key = ft.time_key
INNER JOIN dim_date      dd  ON dd.date_key = ft.date_key
LEFT JOIN project_staging.stg_weather_clean sw
    ON sw.datetime = (dd.full_date + (dt.hour_of_day || ' hours')::INTERVAL)

GROUP BY
    ft.pickup_zone_key,
    ft.date_key,
    ft.time_key,
    ft.weather_key;

SELECT 'fact_zone_hourly_snapshot' AS table_name, COUNT(*) AS rows_loaded
FROM fact_zone_hourly_snapshot;

-- ============================================================================
-- 3. LOAD FACT_CHARGER_COVERAGE
-- One row per EV station per zone per date (Jan 2024)
-- Uses the spatial proximity: stations are matched to their closest taxi zone
-- (For a simple approach we match on zone name or use known city → borough mapping)
-- ============================================================================

TRUNCATE TABLE fact_charger_coverage CASCADE;

INSERT INTO fact_charger_coverage (
    station_key,
    zone_key,
    date_key,
    num_ports,
    is_operational,
    batch_id
)
SELECT
    ds.station_key,
    dz.zone_key,

    -- One record per date in January 2024
    dd.date_key,

    ds.num_ports,
    ds.status = 'E'                                 AS is_operational,

    'ETL_COVERAGE_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI') AS batch_id

FROM dim_station ds

-- Match station to zone by borough (simple city-to-borough approach)
INNER JOIN dim_zone dz ON UPPER(TRIM(dz.borough)) = UPPER(TRIM(
    CASE ds.city
        WHEN 'New York'   THEN 'Manhattan'
        WHEN 'Brooklyn'   THEN 'Brooklyn'
        WHEN 'Bronx'      THEN 'Bronx'
        WHEN 'Queens'     THEN 'Queens'
        WHEN 'Staten Island' THEN 'Staten Island'
        ELSE ds.city
    END
))

-- Only include stations in NYC (5 boroughs)
-- Cross with all January 2024 dates
CROSS JOIN dim_date dd

WHERE ds.is_current = TRUE
  AND ds.city IN ('New York', 'Brooklyn', 'Bronx', 'Queens', 'Staten Island',
                  'Manhattan', 'New York City')
  AND dd.year = 2024
  AND dd.month_num = 1;

SELECT 'fact_charger_coverage' AS table_name, COUNT(*) AS rows_loaded
FROM fact_charger_coverage;

-- ============================================================================
-- FINAL VERIFICATION — all fact row counts
-- ============================================================================
SELECT 'fact_trips'                AS fact,  COUNT(*) AS rows FROM fact_trips               UNION ALL
SELECT 'fact_zone_hourly_snapshot',           COUNT(*)        FROM fact_zone_hourly_snapshot UNION ALL
SELECT 'fact_charger_coverage',               COUNT(*)        FROM fact_charger_coverage
ORDER BY fact;
