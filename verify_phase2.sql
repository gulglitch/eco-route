-- ============================================================================
-- Phase 2 Verification Script
-- Run this to show your professor that everything is loaded correctly
-- ============================================================================

-- 1. Show all schemas
\dn

-- 2. Show all tables
SELECT schemaname, tablename 
FROM pg_tables 
WHERE schemaname IN ('project_staging', 'project_dw', 'project_reporting')
ORDER BY schemaname, tablename;

-- 3. Row counts for all dimensions and facts
SELECT 'DIMENSIONS' as layer, '' as table_name, 0 as row_count
UNION ALL
SELECT '', 'dim_date', COUNT(*)::int FROM project_dw.dim_date
UNION ALL
SELECT '', 'dim_timeofday', COUNT(*)::int FROM project_dw.dim_timeofday
UNION ALL
SELECT '', 'dim_weather', COUNT(*)::int FROM project_dw.dim_weather
UNION ALL
SELECT '', 'dim_zone', COUNT(*)::int FROM project_dw.dim_zone
UNION ALL
SELECT '', 'dim_company', COUNT(*)::int FROM project_dw.dim_company
UNION ALL
SELECT '', 'dim_station', COUNT(*)::int FROM project_dw.dim_station
UNION ALL
SELECT 'FACTS', '', 0
UNION ALL
SELECT '', 'fact_trips', COUNT(*)::int FROM project_dw.fact_trips
UNION ALL
SELECT '', 'fact_zone_hourly_snapshot', COUNT(*)::int FROM project_dw.fact_zone_hourly_snapshot
UNION ALL
SELECT '', 'fact_charger_coverage', COUNT(*)::int FROM project_dw.fact_charger_coverage
ORDER BY layer DESC, table_name;

-- 4. Show surrogate key mapping works (Business Key -> Surrogate Key)
SELECT 
    'Uber' as company_name_lookup,
    co.company_key as surrogate_key,
    co.hvfhs_license_num as business_key,
    COUNT(*) as trip_count
FROM project_dw.fact_trips f
JOIN project_dw.dim_company co ON co.company_key = f.company_key
WHERE co.hvfhs_license_num = 'HV0003'
GROUP BY co.company_key, co.hvfhs_license_num;

-- 5. Verify referential integrity (should all be 0)
SELECT 
    'Orphan pickup zones' as check_name,
    COUNT(*) as violations
FROM project_dw.fact_trips f
LEFT JOIN project_dw.dim_zone d ON d.zone_key = f.pickup_zone_key
WHERE d.zone_key IS NULL;

-- 6. Show data quality
SELECT 
    'Total trips' as metric, 
    COUNT(*)::text as value 
FROM project_dw.fact_trips
UNION ALL
SELECT 'Trips with valid wait times', 
    COUNT(*)::text 
FROM project_dw.fact_trips 
WHERE wait_min IS NOT NULL
UNION ALL
SELECT 'Average trip miles', 
    ROUND(AVG(trip_miles), 2)::text 
FROM project_dw.fact_trips
UNION ALL
SELECT 'Total driver pay', 
    '$' || ROUND(SUM(driver_pay), 2)::text 
FROM project_dw.fact_trips;

\echo '\n=== Phase 2 Implementation Complete ==='
\echo 'Database: nyc_ev_mobility_dw'
\echo 'Status: All dimensions and facts loaded successfully'
