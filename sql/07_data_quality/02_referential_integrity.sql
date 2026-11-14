
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 1: Referential Integrity
-- Purpose: Identify orphan foreign keys
-- =========================================================

-- FACT_TRIPS

-- 1. Pickup zone
SELECT 'fact_trips -> dim_zone (pickup)' AS validation_check,
       COUNT(*) AS orphan_records
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_zone d
    ON f.pickup_zone_key = d.zone_key
WHERE f.pickup_zone_key IS NOT NULL
  AND d.zone_key IS NULL

UNION ALL

-- 2. Dropoff zone
SELECT 'fact_trips -> dim_zone (dropoff)',
       COUNT(*)
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_zone d
    ON f.dropoff_zone_key = d.zone_key
WHERE f.dropoff_zone_key IS NOT NULL
  AND d.zone_key IS NULL

UNION ALL

-- 3. Company
SELECT 'fact_trips -> dim_company',
       COUNT(*)
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_company d
    ON f.company_key = d.company_key
WHERE f.company_key IS NOT NULL
  AND d.company_key IS NULL

UNION ALL

-- 4. Date
SELECT 'fact_trips -> dim_date',
       COUNT(*)
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_date d
    ON f.date_key = d.date_key
WHERE f.date_key IS NOT NULL
  AND d.date_key IS NULL

UNION ALL

-- 5. Time
SELECT 'fact_trips -> dim_timeofday',
       COUNT(*)
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_timeofday d
    ON f.time_key = d.time_key
WHERE f.time_key IS NOT NULL
  AND d.time_key IS NULL

UNION ALL

-- 6. Weather
SELECT 'fact_trips -> dim_weather',
       COUNT(*)
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_weather d
    ON f.weather_key = d.weather_key
WHERE f.weather_key IS NOT NULL
  AND d.weather_key IS NULL

UNION ALL

-- FACT_ZONE_HOURLY_SNAPSHOT

-- 7. Zone
SELECT 'fact_zone_hourly_snapshot -> dim_zone',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot f
LEFT JOIN project_dw.dim_zone d
    ON f.zone_key = d.zone_key
WHERE f.zone_key IS NOT NULL
  AND d.zone_key IS NULL

UNION ALL

-- 8. Date
SELECT 'fact_zone_hourly_snapshot -> dim_date',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot f
LEFT JOIN project_dw.dim_date d
    ON f.date_key = d.date_key
WHERE f.date_key IS NOT NULL
  AND d.date_key IS NULL

UNION ALL

-- 9. Time
SELECT 'fact_zone_hourly_snapshot -> dim_timeofday',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot f
LEFT JOIN project_dw.dim_timeofday d
    ON f.time_key = d.time_key
WHERE f.time_key IS NOT NULL
  AND d.time_key IS NULL

UNION ALL

-- 10. Weather
SELECT 'fact_zone_hourly_snapshot -> dim_weather',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot f
LEFT JOIN project_dw.dim_weather d
    ON f.weather_key = d.weather_key
WHERE f.weather_key IS NOT NULL
  AND d.weather_key IS NULL

UNION ALL

-- FACT_CHARGER_COVERAGE

-- 11. Station
SELECT 'fact_charger_coverage -> dim_station',
       COUNT(*)
FROM project_dw.fact_charger_coverage f
LEFT JOIN project_dw.dim_station d
    ON f.station_key = d.station_key
WHERE f.station_key IS NOT NULL
  AND d.station_key IS NULL

UNION ALL

-- 12. Zone
SELECT 'fact_charger_coverage -> dim_zone',
       COUNT(*)
FROM project_dw.fact_charger_coverage f
LEFT JOIN project_dw.dim_zone d
    ON f.zone_key = d.zone_key
WHERE f.zone_key IS NOT NULL
  AND d.zone_key IS NULL

UNION ALL

-- 13. Date
SELECT 'fact_charger_coverage -> dim_date',
       COUNT(*)
FROM project_dw.fact_charger_coverage f
LEFT JOIN project_dw.dim_date d
    ON f.date_key = d.date_key
WHERE f.date_key IS NOT NULL
  AND d.date_key IS NULL

ORDER BY validation_check;
