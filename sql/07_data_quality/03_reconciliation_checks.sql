
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 3: Reconciliation
-- Purpose: Compare totals across related tables
-- =========================================================

-- CHECK 1 & 2: Trip count and driver pay reconciliation

WITH trip_totals AS (
    SELECT
        COUNT(*) AS total_trips,
        COALESCE(SUM(driver_pay), 0) AS total_driver_pay
    FROM project_dw.fact_trips
),
snapshot_totals AS (
    SELECT
        COALESCE(SUM(trip_count), 0) AS total_trips,
        COALESCE(SUM(total_driver_pay), 0) AS total_driver_pay
    FROM project_dw.fact_zone_hourly_snapshot
)
SELECT
    'Trip count reconciliation' AS validation_check,
    t.total_trips AS fact_trips_value,
    s.total_trips AS snapshot_value,
    t.total_trips - s.total_trips AS difference,
    CASE
        WHEN t.total_trips = s.total_trips THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM trip_totals t
CROSS JOIN snapshot_totals s

UNION ALL

SELECT
    'Driver pay reconciliation',
    t.total_driver_pay,
    s.total_driver_pay,
    t.total_driver_pay - s.total_driver_pay,
    CASE
        WHEN ABS(t.total_driver_pay - s.total_driver_pay) < 0.01
        THEN 'PASS'
        ELSE 'FAIL'
    END
FROM trip_totals t
CROSS JOIN snapshot_totals s;


-- CHECK 3: Charger coverage reconciliation

WITH expected AS (
    SELECT
        (SELECT COUNT(*)
         FROM project_staging.stg_station_zone_map)
        *
        (SELECT COUNT(*)
         FROM project_dw.dim_date) AS expected_rows
),
actual AS (
    SELECT COUNT(*) AS actual_rows
    FROM project_dw.fact_charger_coverage
)
SELECT
    'Charger coverage reconciliation' AS validation_check,
    e.expected_rows,
    a.actual_rows,
    e.expected_rows - a.actual_rows AS difference,
    CASE
        WHEN e.expected_rows = a.actual_rows THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM expected e
CROSS JOIN actual a;
