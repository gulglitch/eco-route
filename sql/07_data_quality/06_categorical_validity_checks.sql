
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 6: Categorical Validity
-- File: 06_categorical_validity_checks.sql
--
-- Purpose:
-- Check the distinct values and record counts for the
-- categorical flags in fact_trips.
--
-- Expected values:
-- shared_request_flag: Y or N
-- wav_request_flag:    Y or N
-- =========================================================


-- =========================================================
-- SECTION 1: Inspect Categorical Flag Values
-- Purpose:
-- Display each distinct value and its frequency.
-- This helps identify unexpected categories.
-- =========================================================

SELECT
    'shared_request_flag' AS column_name,
    shared_request_flag AS actual_value,
    COUNT(*) AS records
FROM project_dw.fact_trips
GROUP BY shared_request_flag

UNION ALL

SELECT
    'wav_request_flag',
    wav_request_flag,
    COUNT(*)
FROM project_dw.fact_trips
GROUP BY wav_request_flag

ORDER BY column_name, actual_value;


-- =========================================================
-- SECTION 2: Validate Allowed Categorical Values
-- Purpose:
-- Count records containing values other than Y or N,
-- including NULL values.
--
-- Expected result:
-- 0 invalid records for both flags.
-- =========================================================

SELECT
    'shared_request_flag' AS validation_check,
    COUNT(*) AS invalid_records
FROM project_dw.fact_trips
WHERE shared_request_flag NOT IN ('Y', 'N')
   OR shared_request_flag IS NULL

UNION ALL

SELECT
    'wav_request_flag',
    COUNT(*)
FROM project_dw.fact_trips
WHERE wav_request_flag NOT IN ('Y', 'N')
   OR wav_request_flag IS NULL;
