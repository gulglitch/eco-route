SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'project_staging'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;


SELECT 'Zones' AS dataset, COUNT(*) AS raw_rows
FROM project_staging.stg_zones
UNION ALL
SELECT 'Weather', COUNT(*)
FROM project_staging.stg_weather
UNION ALL
SELECT 'Trips', COUNT(*)
FROM project_staging.stg_trips
UNION ALL
SELECT 'Charging stations', COUNT(*)
FROM project_staging.stg_charging_stations;

---------------------------------------------------------------------------------------------
--chceking missing values
SELECT
    COUNT(*) FILTER (WHERE pickup_datetime IS NULL) AS missing_pickup_time,
    COUNT(*) FILTER (WHERE dropoff_datetime IS NULL) AS missing_dropoff_time,
    COUNT(*) FILTER (WHERE pulocationid IS NULL) AS missing_pickup_zone,
    COUNT(*) FILTER (WHERE dolocationid IS NULL) AS missing_dropoff_zone,
    COUNT(*) FILTER (
        WHERE NULLIF(TRIM(hvfhs_license_num), '') IS NULL
    ) AS missing_company_code
FROM project_staging.stg_trips;

---------------------------------------------------------------------------------------------

-- Check for missing and repeated station IDs before cleaning the charging station data.
WITH station_ids AS (
    SELECT NULLIF(TRIM(station_id), '') AS clean_id
    FROM project_staging.stg_charging_stations
)
SELECT
    COUNT(*) FILTER (WHERE clean_id IS NULL) AS missing_station_ids,
    COUNT(clean_id) - COUNT(DISTINCT clean_id) AS repeated_id_rows
FROM station_ids;

---------------------------------------------------------------------------------------------

-- Count exact duplicate trip rows by comparing all 24 original CSV fields.
SELECT
    COUNT(*) AS total_trip_rows,
    COUNT(DISTINCT ROW(
        hvfhs_license_num, dispatching_base_num, originating_base_num,
        request_datetime, on_scene_datetime, pickup_datetime,
        dropoff_datetime, pulocationid, dolocationid,
        trip_miles, trip_time, base_passenger_fare, tolls, bcf,
        sales_tax, congestion_surcharge, airport_fee, tips, driver_pay,
        shared_request_flag, shared_match_flag, access_a_ride_flag,
        wav_request_flag, wav_match_flag
    )) AS distinct_trip_rows
FROM project_staging.stg_trips

---------------------------------------------------------------------------------------------

-- Standardize trip codes and flags, convert blank text to NULL, and remove identical cleaned rows.
CREATE OR REPLACE VIEW project_staging.stg_trips_clean AS
SELECT DISTINCT
    NULLIF(UPPER(TRIM(hvfhs_license_num)), '') AS hvfhs_license_num,
    NULLIF(UPPER(TRIM(dispatching_base_num)), '') AS dispatching_base_num,
    NULLIF(UPPER(TRIM(originating_base_num)), '') AS originating_base_num,
    request_datetime,
    on_scene_datetime,
    pickup_datetime,
    dropoff_datetime,
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
    driver_pay,
    NULLIF(UPPER(TRIM(shared_request_flag)), '') AS shared_request_flag,
    NULLIF(UPPER(TRIM(shared_match_flag)), '') AS shared_match_flag,
    NULLIF(UPPER(TRIM(access_a_ride_flag)), '') AS access_a_ride_flag,
    NULLIF(UPPER(TRIM(wav_request_flag)), '') AS wav_request_flag,
    NULLIF(UPPER(TRIM(wav_match_flag)), '') AS wav_match_flag
FROM project_staging.stg_trips;



---------------------------------------------------------------------------------------------


-- Trim station text, standardize state and status codes, and convert blank text to NULL.
CREATE OR REPLACE VIEW project_staging.stg_charging_stations_clean AS
SELECT DISTINCT
    NULLIF(TRIM(station_id), '') AS station_id,
    NULLIF(TRIM(station_name), '') AS station_name,
    NULLIF(TRIM(street_address), '') AS street_address,
    NULLIF(TRIM(city), '') AS city,
    NULLIF(UPPER(TRIM(state)), '') AS state,
    NULLIF(TRIM(zip), '') AS zip,
    latitude,
    longitude,
    NULLIF(TRIM(ev_network), '') AS ev_network,
    NULLIF(TRIM(ev_connector_types), '') AS ev_connector_types,
    ev_level1_evse_num,
    ev_level2_evse_num,
    ev_dc_fast_num,
    NULLIF(UPPER(TRIM(status_code)), '') AS status_code,
    open_date,
    date_last_confirmed,
    NULLIF(UPPER(TRIM(fuel_type_code)), '') AS fuel_type_code,
    NULLIF(TRIM(intersection_directions), '') AS intersection_directions,
    NULLIF(TRIM(access_code), '') AS access_code,
    NULLIF(TRIM(facility_type), '') AS facility_type
FROM project_staging.stg_charging_stations;

-----------------------------------------------------------------------------------------------

-- Standardize zone text, convert N/A and blanks to NULL, and remove identical rows.
CREATE OR REPLACE VIEW project_staging.stg_zones_clean AS
SELECT DISTINCT
    locationid,
    CASE UPPER(TRIM(borough))
        WHEN 'N/A' THEN NULL
        WHEN 'EWR' THEN 'EWR'
        ELSE NULLIF(INITCAP(TRIM(borough)), '')
    END AS borough,
    CASE
        WHEN UPPER(TRIM(zone)) = 'N/A' THEN NULL
        ELSE NULLIF(TRIM(zone), '')
    END AS zone,
    CASE UPPER(TRIM(service_zone))
        WHEN 'N/A' THEN NULL
        WHEN 'EWR' THEN 'EWR'
        ELSE NULLIF(INITCAP(TRIM(service_zone)), '')
    END AS service_zone
FROM project_staging.stg_zones;


-----------------------------------------------------------------------------------------------


-- Remove identical weather rows while preserving missing measurements as NULL.
CREATE OR REPLACE VIEW project_staging.stg_weather_clean AS
SELECT DISTINCT
    datetime,
    precipitation_mm,
    temperature_c,
    humidity_percent
FROM project_staging.stg_weather;


-----------------------------------------------------------------------------------------------
-- Compare raw and clean row counts for all four staging sources.
SELECT 'Zones' AS dataset,
       (SELECT COUNT(*) FROM project_staging.stg_zones) AS raw_rows,
       (SELECT COUNT(*) FROM project_staging.stg_zones_clean) AS clean_rows
UNION ALL
SELECT 'Weather',
       (SELECT COUNT(*) FROM project_staging.stg_weather),
       (SELECT COUNT(*) FROM project_staging.stg_weather_clean)
UNION ALL
SELECT 'Trips',
       (SELECT COUNT(*) FROM project_staging.stg_trips),
       (SELECT COUNT(*) FROM project_staging.stg_trips_clean)
UNION ALL
SELECT 'Charging stations',
       (SELECT COUNT(*) FROM project_staging.stg_charging_stations),
       (SELECT COUNT(*) FROM project_staging.stg_charging_stations_clean);

	   
-----------------------------------------------------------------------------------------------

-- Check which clean staging views have been created.
SELECT table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'project_staging'
ORDER BY table_name;	   


-----------------------------------------------------------------------------------------------

-- Show how the zone cleaning rule converts N/A to SQL NULL.
SELECT
    raw.locationid,
    raw.zone AS zone_before,
    clean.zone AS zone_after,
    raw.service_zone AS service_zone_before,
    clean.service_zone AS service_zone_after
FROM project_staging.stg_zones AS raw
JOIN project_staging.stg_zones_clean AS clean
    ON clean.locationid = raw.locationid
WHERE raw.locationid = 264;