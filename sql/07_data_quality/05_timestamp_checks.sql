
-- =========================================================
-- Task 6: Data Quality Validation
-- Check 5: Timestamp Validity
-- File: 05_timestamp_checks.sql
--
-- Purpose:
-- Identify missing timestamps and records where the
-- chronological order of trip events is incorrect.
--
-- Expected order:
-- Request -> On Scene -> Pickup -> Dropoff
--
-- Note:
-- These checks are performed on cleaned staging data.
-- Missing timestamps and chronology exceptions are
-- reported separately.
-- =========================================================


-- =========================================================
-- SECTION 1: Overall Timestamp Validation
-- Purpose:
-- Count records where timestamps violate the expected
-- chronological order and records with missing timestamps.
-- =========================================================

SELECT
    COUNT(*) FILTER (
        WHERE pickup_datetime > dropoff_datetime
    ) AS pickup_after_dropoff,

    COUNT(*) FILTER (
        WHERE request_datetime > on_scene_datetime
    ) AS request_after_onscene,

    COUNT(*) FILTER (
        WHERE on_scene_datetime > pickup_datetime
    ) AS onscene_after_pickup,

    COUNT(*) FILTER (
        WHERE request_datetime IS NULL
           OR on_scene_datetime IS NULL
           OR pickup_datetime IS NULL
           OR dropoff_datetime IS NULL
    ) AS records_with_missing_timestamps

FROM project_staging.stg_trips_clean;


-- =========================================================
-- SECTION 2: Missing Timestamp Counts
-- Purpose:
-- Count missing values separately for each timestamp column.
-- This helps identify which timestamp contributes to
-- incomplete trip records.
-- =========================================================

SELECT
    COUNT(*) FILTER (
        WHERE request_datetime IS NULL
    ) AS missing_request,

    COUNT(*) FILTER (
        WHERE on_scene_datetime IS NULL
    ) AS missing_on_scene,

    COUNT(*) FILTER (
        WHERE pickup_datetime IS NULL
    ) AS missing_pickup,

    COUNT(*) FILTER (
        WHERE dropoff_datetime IS NULL
    ) AS missing_dropoff

FROM project_staging.stg_trips_clean;


-- =========================================================
-- SECTION 3: Sample Chronology Exceptions
-- Purpose:
-- Display up to 10 records where:
-- 1. Request time is later than on-scene time, OR
-- 2. On-scene time is later than pickup time.
--
-- This helps inspect actual records behind the exceptions.
-- =========================================================

SELECT
    dispatching_base_num,
    request_datetime,
    on_scene_datetime,
    pickup_datetime,
    dropoff_datetime
FROM project_staging.stg_trips_clean
WHERE
    (request_datetime > on_scene_datetime)
    OR
    (on_scene_datetime > pickup_datetime)
LIMIT 10;


-- =========================================================
-- SECTION 4: Separate and Count Chronology Exceptions
-- Purpose:
-- Determine whether the two chronology conditions occur
-- together or independently.
--
-- This avoids double-counting records when calculating
-- the total number of distinct chronology exceptions.
-- =========================================================

SELECT
    COUNT(*) FILTER (
        WHERE request_datetime > on_scene_datetime
          AND on_scene_datetime > pickup_datetime
    ) AS both_conditions,

    COUNT(*) FILTER (
        WHERE request_datetime > on_scene_datetime
          AND on_scene_datetime <= pickup_datetime
    ) AS request_after_onscene_only,

    COUNT(*) FILTER (
        WHERE request_datetime <= on_scene_datetime
          AND on_scene_datetime > pickup_datetime
    ) AS onscene_after_pickup_only

FROM project_staging.stg_trips_clean;
