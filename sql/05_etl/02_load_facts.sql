-- ============================================================================
-- Script: 02_load_facts.sql
-- Purpose: Populate all 3 fact tables using BUSINESS KEY -> SURROGATE KEY mapping
-- Schema: project_dw
-- Phase: 2 - Task 5: Fact Loading
--
-- Run AFTER (in this order):
--   03_dimensions/01_create_dimensions.sql
--   05_etl/01_load_dimensions.sql
--   04_facts/01_create_facts.sql
--   python/assign_stations_to_zones.py      (creates project_staging.stg_station_zone_map)
--
-- Business key -> surrogate key mapping used here:
--   trips.PULocationID / DOLocationID  -> dim_zone.location_id       -> zone_key
--   trips.hvfhs_license_num            -> dim_company.hvfhs_license_num -> company_key
--   trips.pickup_datetime::DATE        -> dim_date.full_date          -> date_key
--   hour(trips.pickup_datetime)        -> dim_timeofday.hour_of_day   -> time_key
--   date_trunc('hour', pickup)         -> hourly weather band         -> weather_key
--   station -> zone (spatial join)     -> dim_station / dim_zone      -> station_key, zone_key
-- ============================================================================

SET search_path TO project_dw;

-- ============================================================================
-- 0. WORK TABLES (temporary, live only for this session)
-- ============================================================================

-- 0A. Hourly weather -> weather_key (same banding rules as dim_weather load)
DROP TABLE IF EXISTS tmp_hourly_weather;

CREATE TEMP TABLE tmp_hourly_weather AS
SELECT
    sw.datetime,
    sw.precipitation_mm,
    dw.weather_key
FROM project_staging.stg_weather_clean sw
INNER JOIN dim_weather dw
    ON dw.weather_band = (
        CASE
            WHEN sw.precipitation_mm IS NULL OR sw.precipitation_mm = 0 THEN 'No Rain'
            WHEN sw.precipitation_mm < 2.5                              THEN 'Light Rain'
            WHEN sw.precipitation_mm < 10                               THEN 'Moderate Rain'
            ELSE                                                             'Heavy Rain'
        END
        || ' / ' ||
        CASE
            WHEN sw.temperature_c IS NULL OR sw.temperature_c < 0 THEN 'Freezing'
            WHEN sw.temperature_c < 10                            THEN 'Cold'
            WHEN sw.temperature_c < 20                            THEN 'Mild'
            ELSE                                                       'Warm'
        END
        || ' / ' ||
        CASE
            WHEN sw.humidity_percent IS NULL OR sw.humidity_percent < 40 THEN 'Low'
            WHEN sw.humidity_percent < 70                                THEN 'Moderate'
            ELSE                                                              'High'
        END
    );

CREATE UNIQUE INDEX ux_tmp_hourly_weather ON tmp_hourly_weather(datetime);

-- Expect 744 (31 days x 24 hours)
SELECT COUNT(*) AS hourly_weather_rows FROM tmp_hourly_weather;

-- 0B. Materialise the clean trips once (the view does a DISTINCT over 500k rows)
DROP TABLE IF EXISTS tmp_trips_clean;

CREATE TEMP TABLE tmp_trips_clean AS
SELECT * FROM project_staging.stg_trips_clean;

ANALYZE tmp_trips_clean;

-- ============================================================================
-- 1. FACT_TRIPS
-- Grain: one row per ride-hailing trip
-- ============================================================================

TRUNCATE TABLE fact_trips RESTART IDENTITY;

INSERT INTO fact_trips (
    pickup_zone_key, dropoff_zone_key, company_key, date_key, time_key, weather_key,
    dispatching_base_num,
    trip_miles, trip_time_sec, base_fare, tolls, sales_tax,
    congestion_surcharge, airport_fee, tips, driver_pay, wait_min,
    shared_request_flag, wav_request_flag,
    batch_id
)
SELECT
    pz.zone_key,
    dz.zone_key,
    co.company_key,
    dd.date_key,
    dt.time_key,
    hw.weather_key,

    t.dispatching_base_num,

    t.trip_miles,
    t.trip_time,                       -- seconds
    t.base_passenger_fare,
    t.tolls,
    t.sales_tax,
    t.congestion_surcharge,
    t.airport_fee,
    t.tips,
    t.driver_pay,

    -- Customer wait (minutes). Negative waits (pickup before request) are
    -- invalid, so they are stored as NULL instead of polluting averages.
    CASE
        WHEN t.request_datetime IS NOT NULL
         AND t.pickup_datetime  >= t.request_datetime
        THEN ROUND((EXTRACT(EPOCH FROM (t.pickup_datetime - t.request_datetime)) / 60.0)::NUMERIC, 2)
        ELSE NULL
    END,

    t.shared_request_flag,
    t.wav_request_flag,

    'ETL_FACTS_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI')
FROM tmp_trips_clean t
INNER JOIN dim_zone      pz ON pz.location_id       = t.pulocationid
INNER JOIN dim_zone      dz ON dz.location_id       = t.dolocationid
INNER JOIN dim_company   co ON co.hvfhs_license_num = t.hvfhs_license_num
INNER JOIN dim_date      dd ON dd.full_date         = t.pickup_datetime::DATE
INNER JOIN dim_timeofday dt ON dt.hour_of_day       = EXTRACT(HOUR FROM t.pickup_datetime)::SMALLINT
INNER JOIN tmp_hourly_weather hw
        ON hw.datetime = DATE_TRUNC('hour', t.pickup_datetime)
WHERE t.pickup_datetime   IS NOT NULL
  AND t.pulocationid      IS NOT NULL
  AND t.dolocationid      IS NOT NULL
  AND t.hvfhs_license_num IS NOT NULL;

ANALYZE fact_trips;

SELECT 'fact_trips' AS table_name, COUNT(*) AS rows_loaded FROM fact_trips;

-- Where did rows go? (clean staging rows that did not reach the fact table)
SELECT
    COUNT(*)                                                                    AS clean_trip_rows,
    (SELECT COUNT(*) FROM fact_trips)                                           AS fact_trip_rows,
    COUNT(*) - (SELECT COUNT(*) FROM fact_trips)                                AS rows_not_loaded,
    COUNT(*) FILTER (WHERE pickup_datetime IS NULL OR pulocationid IS NULL
                        OR dolocationid IS NULL OR hvfhs_license_num IS NULL)   AS missing_mandatory_key,
    COUNT(*) FILTER (WHERE pickup_datetime < '2024-01-01'
                        OR pickup_datetime >= '2024-02-01')                     AS pickup_outside_jan_2024,
    COUNT(*) FILTER (WHERE hvfhs_license_num IS NOT NULL
                       AND hvfhs_license_num NOT IN
                           (SELECT hvfhs_license_num FROM dim_company))         AS unknown_company,
    COUNT(*) FILTER (WHERE request_datetime IS NOT NULL
                       AND pickup_datetime < request_datetime)                  AS negative_wait_set_to_null
FROM tmp_trips_clean;

-- ============================================================================
-- 2. FACT_ZONE_HOURLY_SNAPSHOT
-- Grain: one row per zone per hour  (265 zones x 744 hours = 197,160 rows)
-- Periodic snapshot: every zone-hour gets a row, including hours with ZERO
-- trips (trip_count = 0), so demand/weather analysis is not biased.
-- ============================================================================

TRUNCATE TABLE fact_zone_hourly_snapshot;

INSERT INTO fact_zone_hourly_snapshot (
    zone_key, date_key, time_key, weather_key,
    trip_count, total_wait_min, avg_wait_min,
    total_driver_pay, avg_trip_miles, rainfall_mm,
    batch_id
)
SELECT
    z.zone_key,
    dd.date_key,
    dt.time_key,
    hw.weather_key,

    COALESCE(a.trip_count, 0),
    COALESCE(a.total_wait_min, 0),
    a.avg_wait_min,                         -- NULL when no trips / no valid waits
    COALESCE(a.total_driver_pay, 0),
    a.avg_trip_miles,
    hw.precipitation_mm,

    'ETL_SNAPSHOT_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI')
FROM dim_zone z
CROSS JOIN tmp_hourly_weather hw
INNER JOIN dim_date      dd ON dd.full_date   = hw.datetime::DATE
INNER JOIN dim_timeofday dt ON dt.hour_of_day = EXTRACT(HOUR FROM hw.datetime)::SMALLINT
LEFT JOIN (
    SELECT
        pickup_zone_key,
        date_key,
        time_key,
        COUNT(*)                    AS trip_count,
        SUM(wait_min)               AS total_wait_min,
        ROUND(AVG(wait_min), 2)     AS avg_wait_min,
        SUM(driver_pay)             AS total_driver_pay,
        ROUND(AVG(trip_miles), 2)   AS avg_trip_miles
    FROM fact_trips
    GROUP BY pickup_zone_key, date_key, time_key
) a
    ON  a.pickup_zone_key = z.zone_key
    AND a.date_key        = dd.date_key
    AND a.time_key        = dt.time_key;

ANALYZE fact_zone_hourly_snapshot;

SELECT 'fact_zone_hourly_snapshot' AS table_name, COUNT(*) AS rows_loaded
FROM fact_zone_hourly_snapshot;

-- ============================================================================
-- 3. FACT_CHARGER_COVERAGE
-- Grain: one row per EV station per taxi zone per date (Jan 2024)
-- Each station is assigned to the taxi zone that contains it (spatial join done
-- in python/assign_stations_to_zones.py). Stations outside NYC are not mapped.
-- ============================================================================

TRUNCATE TABLE fact_charger_coverage;

INSERT INTO fact_charger_coverage (
    station_key, zone_key, date_key,
    num_ports, is_operational, distance_to_zone_center_km,
    batch_id
)
SELECT
    ds.station_key,
    dz.zone_key,
    dd.date_key,
    ds.num_ports,
    COALESCE(ds.status = 'E', FALSE),           -- 'E' = open/available
    m.distance_to_zone_center_km,
    'ETL_COVERAGE_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI')
FROM project_staging.stg_station_zone_map m
INNER JOIN dim_station ds ON ds.station_key = m.station_key
                         AND ds.is_current  = TRUE
INNER JOIN dim_zone    dz ON dz.location_id = m.location_id
CROSS JOIN dim_date    dd;

ANALYZE fact_charger_coverage;

SELECT 'fact_charger_coverage' AS table_name, COUNT(*) AS rows_loaded
FROM fact_charger_coverage;

-- ============================================================================
-- 4. LOAD VERIFICATION (quick sanity checks; full DQ report is Task 6)
-- ============================================================================

-- 4A. Row counts
SELECT 'fact_trips'                AS fact, COUNT(*) AS row_count FROM fact_trips                UNION ALL
SELECT 'fact_zone_hourly_snapshot',          COUNT(*)              FROM fact_zone_hourly_snapshot UNION ALL
SELECT 'fact_charger_coverage',              COUNT(*)              FROM fact_charger_coverage
ORDER BY fact;

-- 4B. Facts without a matching dimension row (all must be 0)
SELECT 'fact_trips.pickup_zone_key'  AS check_name, COUNT(*) AS orphan_rows
FROM fact_trips f LEFT JOIN dim_zone d ON d.zone_key = f.pickup_zone_key       WHERE d.zone_key IS NULL
UNION ALL SELECT 'fact_trips.dropoff_zone_key', COUNT(*)
FROM fact_trips f LEFT JOIN dim_zone d ON d.zone_key = f.dropoff_zone_key      WHERE d.zone_key IS NULL
UNION ALL SELECT 'fact_trips.company_key', COUNT(*)
FROM fact_trips f LEFT JOIN dim_company d ON d.company_key = f.company_key     WHERE d.company_key IS NULL
UNION ALL SELECT 'fact_trips.date_key', COUNT(*)
FROM fact_trips f LEFT JOIN dim_date d ON d.date_key = f.date_key              WHERE d.date_key IS NULL
UNION ALL SELECT 'fact_trips.time_key', COUNT(*)
FROM fact_trips f LEFT JOIN dim_timeofday d ON d.time_key = f.time_key         WHERE d.time_key IS NULL
UNION ALL SELECT 'fact_trips.weather_key', COUNT(*)
FROM fact_trips f LEFT JOIN dim_weather d ON d.weather_key = f.weather_key     WHERE d.weather_key IS NULL
UNION ALL SELECT 'fact_zone_hourly_snapshot.zone_key', COUNT(*)
FROM fact_zone_hourly_snapshot f LEFT JOIN dim_zone d ON d.zone_key = f.zone_key WHERE d.zone_key IS NULL
UNION ALL SELECT 'fact_zone_hourly_snapshot.weather_key', COUNT(*)
FROM fact_zone_hourly_snapshot f LEFT JOIN dim_weather d ON d.weather_key = f.weather_key WHERE d.weather_key IS NULL
UNION ALL SELECT 'fact_charger_coverage.station_key', COUNT(*)
FROM fact_charger_coverage f LEFT JOIN dim_station d ON d.station_key = f.station_key WHERE d.station_key IS NULL
UNION ALL SELECT 'fact_charger_coverage.zone_key', COUNT(*)
FROM fact_charger_coverage f LEFT JOIN dim_zone d ON d.zone_key = f.zone_key   WHERE d.zone_key IS NULL;

-- 4C. Cross-fact reconciliation: snapshot must add up to the transaction fact
SELECT
    'trip count: fact_trips vs snapshot'                AS check_name,
    (SELECT COUNT(*) FROM fact_trips)                   AS expected,
    (SELECT SUM(trip_count) FROM fact_zone_hourly_snapshot) AS actual
UNION ALL
SELECT
    'driver pay: fact_trips vs snapshot',
    (SELECT ROUND(SUM(driver_pay), 2) FROM fact_trips),
    (SELECT ROUND(SUM(total_driver_pay), 2) FROM fact_zone_hourly_snapshot);

-- 4D. Trips per company (surrogate key resolved back to the business name)
SELECT co.company_name, COUNT(*) AS trips
FROM fact_trips f
JOIN dim_company co ON co.company_key = f.company_key
GROUP BY co.company_name
ORDER BY trips DESC;
