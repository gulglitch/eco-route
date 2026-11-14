
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 4: Numerical Validity
-- File: 04_validity_checks.sql
--
-- Purpose:
-- Identify logically invalid negative numerical values
-- in the three fact tables.
--
-- Note:
-- Negative financial values are investigated separately
-- because they may require business-rule clarification.
-- =========================================================


-- =========================================================
-- SECTION 1: Negative Values in FACT_TRIPS
-- =========================================================

SELECT 'Negative trip miles' AS validation_check,
       COUNT(*) AS invalid_records
FROM project_dw.fact_trips
WHERE trip_miles < 0

UNION ALL

SELECT 'Negative trip duration',
       COUNT(*)
FROM project_dw.fact_trips
WHERE trip_time_sec < 0

UNION ALL

SELECT 'Negative base fare',
       COUNT(*)
FROM project_dw.fact_trips
WHERE base_fare < 0

UNION ALL

SELECT 'Negative driver pay',
       COUNT(*)
FROM project_dw.fact_trips
WHERE driver_pay < 0

UNION ALL

SELECT 'Negative tolls',
       COUNT(*)
FROM project_dw.fact_trips
WHERE tolls < 0

UNION ALL

SELECT 'Negative sales tax',
       COUNT(*)
FROM project_dw.fact_trips
WHERE sales_tax < 0

UNION ALL

SELECT 'Negative wait minutes',
       COUNT(*)
FROM project_dw.fact_trips
WHERE wait_min < 0

UNION ALL

SELECT 'Negative tips',
       COUNT(*)
FROM project_dw.fact_trips
WHERE tips < 0

UNION ALL

SELECT 'Negative congestion surcharge',
       COUNT(*)
FROM project_dw.fact_trips
WHERE congestion_surcharge < 0

UNION ALL

SELECT 'Negative airport fee',
       COUNT(*)
FROM project_dw.fact_trips
WHERE airport_fee < 0

UNION ALL


-- =========================================================
-- SECTION 2: Negative Values in FACT_ZONE_HOURLY_SNAPSHOT
-- =========================================================

SELECT 'Negative trip count',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot
WHERE trip_count < 0

UNION ALL

SELECT 'Negative total wait',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot
WHERE total_wait_min < 0

UNION ALL

SELECT 'Negative average trip miles',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot
WHERE avg_trip_miles < 0

UNION ALL

SELECT 'Negative rainfall',
       COUNT(*)
FROM project_dw.fact_zone_hourly_snapshot
WHERE rainfall_mm < 0

UNION ALL


-- =========================================================
-- SECTION 3: Negative Values in FACT_CHARGER_COVERAGE
-- =========================================================

SELECT 'Negative number of ports',
       COUNT(*)
FROM project_dw.fact_charger_coverage
WHERE num_ports < 0

UNION ALL

SELECT 'Negative distance to zone center',
       COUNT(*)
FROM project_dw.fact_charger_coverage
WHERE distance_to_zone_center_km < 0

ORDER BY validation_check;


-- =========================================================
-- SECTION 4: Investigate Negative Financial Values
-- Purpose:
-- Display individual fact records with negative base fare
-- or negative driver payment.
-- =========================================================

SELECT
    trip_id,
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
    batch_id
FROM project_dw.fact_trips
WHERE base_fare < 0
   OR driver_pay < 0
ORDER BY trip_id;


-- =========================================================
-- SECTION 5: Inspect Staging Table Structure
-- Purpose:
-- Check the available columns and data types in the cleaned
-- staging table before investigating the source records.
-- This is an investigation query, not a validity test.
-- =========================================================

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'project_staging'
  AND table_name = 'stg_trips_clean'
ORDER BY ordinal_position;


-- =========================================================
-- SECTION 6: Investigate Negative Financial Values in Staging
-- Purpose:
-- Check whether negative financial values were already
-- present in cleaned staging data before fact-table loading.
-- =========================================================

SELECT
    dispatching_base_num,
    pulocationid,
    dolocationid,
    trip_miles,
    trip_time,
    base_passenger_fare,
    tolls,
    bcf,
    sales_tax,
    congestion_surcharge,
    airport_fee,
    tips,
    driver_pay
FROM project_staging.stg_trips_clean
WHERE base_passenger_fare < 0
   OR driver_pay < 0
ORDER BY dispatching_base_num;


-- =========================================================
-- SECTION 7: Summarize Negative Financial Values in Staging
-- Purpose:
-- Count negative base fares, negative driver payments,
-- and records where both values are negative.
-- =========================================================

SELECT
    COUNT(*) FILTER (
        WHERE base_passenger_fare < 0
    ) AS negative_base_fares,

    COUNT(*) FILTER (
        WHERE driver_pay < 0
    ) AS negative_driver_payments,

    COUNT(*) FILTER (
        WHERE base_passenger_fare < 0
          AND driver_pay < 0
    ) AS both_negative

FROM project_staging.stg_trips_clean;
