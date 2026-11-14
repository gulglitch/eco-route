
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 2: Completeness
-- Purpose: Count NULL values in important fact columns
-- =========================================================

-- FACT_TRIPS

SELECT 'fact_trips' AS table_name,
       'pickup_zone_key' AS column_name,
       COUNT(*) FILTER (WHERE pickup_zone_key IS NULL) AS null_count
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'dropoff_zone_key',
       COUNT(*) FILTER (WHERE dropoff_zone_key IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'company_key',
       COUNT(*) FILTER (WHERE company_key IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'date_key',
       COUNT(*) FILTER (WHERE date_key IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'time_key',
       COUNT(*) FILTER (WHERE time_key IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'weather_key',
       COUNT(*) FILTER (WHERE weather_key IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'trip_miles',
       COUNT(*) FILTER (WHERE trip_miles IS NULL)
FROM project_dw.fact_trips

UNION ALL

SELECT 'fact_trips', 'driver_pay',
       COUNT(*) FILTER (WHERE driver_pay IS NULL)
FROM project_dw.fact_trips

UNION ALL

-- FACT_ZONE_HOURLY_SNAPSHOT

SELECT 'fact_zone_hourly_snapshot', 'zone_key',
       COUNT(*) FILTER (WHERE zone_key IS NULL)
FROM project_dw.fact_zone_hourly_snapshot

UNION ALL

SELECT 'fact_zone_hourly_snapshot', 'date_key',
       COUNT(*) FILTER (WHERE date_key IS NULL)
FROM project_dw.fact_zone_hourly_snapshot

UNION ALL

SELECT 'fact_zone_hourly_snapshot', 'time_key',
       COUNT(*) FILTER (WHERE time_key IS NULL)
FROM project_dw.fact_zone_hourly_snapshot

UNION ALL

SELECT 'fact_zone_hourly_snapshot', 'weather_key',
       COUNT(*) FILTER (WHERE weather_key IS NULL)
FROM project_dw.fact_zone_hourly_snapshot

UNION ALL

SELECT 'fact_zone_hourly_snapshot', 'trip_count',
       COUNT(*) FILTER (WHERE trip_count IS NULL)
FROM project_dw.fact_zone_hourly_snapshot

UNION ALL

-- FACT_CHARGER_COVERAGE

SELECT 'fact_charger_coverage', 'station_key',
       COUNT(*) FILTER (WHERE station_key IS NULL)
FROM project_dw.fact_charger_coverage

UNION ALL

SELECT 'fact_charger_coverage', 'zone_key',
       COUNT(*) FILTER (WHERE zone_key IS NULL)
FROM project_dw.fact_charger_coverage

UNION ALL

SELECT 'fact_charger_coverage', 'date_key',
       COUNT(*) FILTER (WHERE date_key IS NULL)
FROM project_dw.fact_charger_coverage

UNION ALL

SELECT 'fact_charger_coverage', 'num_ports',
       COUNT(*) FILTER (WHERE num_ports IS NULL)
FROM project_dw.fact_charger_coverage

UNION ALL

SELECT 'fact_charger_coverage', 'is_operational',
       COUNT(*) FILTER (WHERE is_operational IS NULL)
FROM project_dw.fact_charger_coverage

ORDER BY table_name, column_name;
