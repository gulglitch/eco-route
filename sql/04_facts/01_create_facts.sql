-- ============================================================================
-- Script: 01_create_facts.sql
-- Purpose: Create all 3 fact tables in project_dw (Silver Layer)
-- Schema: project_dw
-- Phase: 2 - Fact Table Implementation
--
-- Facts:
--   1. fact_trips               (Transaction fact)
--   2. fact_zone_hourly_snapshot (Periodic snapshot)
--   3. fact_charger_coverage    (Coverage fact)
-- ============================================================================

SET search_path TO project_dw;

-- ============================================================================
-- 1. FACT_TRIPS
-- Grain: One row per individual ride-hailing trip
-- Type: Transaction fact
-- ============================================================================

DROP TABLE IF EXISTS fact_trips CASCADE;

CREATE TABLE fact_trips (
    trip_id             BIGSERIAL       PRIMARY KEY,

    -- Foreign keys to dimensions
    pickup_zone_key     INTEGER         NOT NULL REFERENCES dim_zone(zone_key),
    dropoff_zone_key    INTEGER         NOT NULL REFERENCES dim_zone(zone_key),
    company_key         INTEGER         NOT NULL REFERENCES dim_company(company_key),
    date_key            INTEGER         NOT NULL REFERENCES dim_date(date_key),
    time_key            INTEGER         NOT NULL REFERENCES dim_timeofday(time_key),
    weather_key         INTEGER         NOT NULL REFERENCES dim_weather(weather_key),

    -- Degenerate dimensions (kept on fact for drill-through)
    dispatching_base_num VARCHAR(10),

    -- Measures
    trip_miles          NUMERIC(10,2),
    trip_time_sec       INTEGER,                          -- trip duration in seconds
    base_fare           NUMERIC(10,2),
    tolls               NUMERIC(10,2),
    sales_tax           NUMERIC(10,2),
    congestion_surcharge NUMERIC(10,2),
    airport_fee         NUMERIC(10,2),
    tips                NUMERIC(10,2),
    driver_pay          NUMERIC(10,2),
    wait_min            NUMERIC(10,2),                   -- minutes from request to pickup

    -- Flags (kept as measures for easy aggregation)
    shared_request_flag VARCHAR(1),
    wav_request_flag    VARCHAR(1),

    -- Audit
    load_timestamp      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    batch_id            VARCHAR(50)
);

COMMENT ON TABLE fact_trips IS 'Transaction fact — one row per NYC ride-hailing trip (Jan 2024)';

-- Performance indexes
CREATE INDEX idx_fact_trips_date       ON fact_trips(date_key);
CREATE INDEX idx_fact_trips_time       ON fact_trips(time_key);
CREATE INDEX idx_fact_trips_pickup     ON fact_trips(pickup_zone_key);
CREATE INDEX idx_fact_trips_dropoff    ON fact_trips(dropoff_zone_key);
CREATE INDEX idx_fact_trips_company    ON fact_trips(company_key);
CREATE INDEX idx_fact_trips_weather    ON fact_trips(weather_key);

-- ============================================================================
-- 2. FACT_ZONE_HOURLY_SNAPSHOT
-- Grain: One row per zone per hour (zone × date × time)
-- Type: Periodic snapshot fact
-- ============================================================================

DROP TABLE IF EXISTS fact_zone_hourly_snapshot CASCADE;

CREATE TABLE fact_zone_hourly_snapshot (
    -- Composite primary key (zone × date × hour)
    zone_key            INTEGER         NOT NULL REFERENCES dim_zone(zone_key),
    date_key            INTEGER         NOT NULL REFERENCES dim_date(date_key),
    time_key            INTEGER         NOT NULL REFERENCES dim_timeofday(time_key),
    weather_key         INTEGER         NOT NULL REFERENCES dim_weather(weather_key),

    -- Measures (aggregated per zone per hour)
    trip_count          INTEGER         DEFAULT 0,
    total_wait_min      NUMERIC(12,2),
    avg_wait_min        NUMERIC(10,2),
    total_driver_pay    NUMERIC(14,2),
    avg_trip_miles      NUMERIC(10,2),
    rainfall_mm         NUMERIC(10,2),

    -- Audit
    load_timestamp      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    batch_id            VARCHAR(50),

    PRIMARY KEY (zone_key, date_key, time_key)
);

COMMENT ON TABLE fact_zone_hourly_snapshot IS 'Periodic snapshot — trip demand aggregated per zone per hour';

CREATE INDEX idx_snapshot_date     ON fact_zone_hourly_snapshot(date_key);
CREATE INDEX idx_snapshot_zone     ON fact_zone_hourly_snapshot(zone_key);
CREATE INDEX idx_snapshot_weather  ON fact_zone_hourly_snapshot(weather_key);

-- ============================================================================
-- 3. FACT_CHARGER_COVERAGE
-- Grain: One row per EV station per taxi zone per date
-- Type: Coverage / accumulating snapshot fact
-- ============================================================================

DROP TABLE IF EXISTS fact_charger_coverage CASCADE;

CREATE TABLE fact_charger_coverage (
    -- Composite primary key
    station_key         INTEGER         NOT NULL REFERENCES dim_station(station_key),
    zone_key            INTEGER         NOT NULL REFERENCES dim_zone(zone_key),
    date_key            INTEGER         NOT NULL REFERENCES dim_date(date_key),

    -- Measures
    num_ports           INTEGER,                         -- total charger ports at station
    is_operational      BOOLEAN,                         -- TRUE if status_code = 'E'
    distance_to_zone_center_km NUMERIC(10,4),            -- spatial distance (optional)

    -- Audit
    load_timestamp      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    batch_id            VARCHAR(50),

    PRIMARY KEY (station_key, zone_key, date_key)
);

COMMENT ON TABLE fact_charger_coverage IS 'Coverage fact — EV station availability mapped to taxi zones';

CREATE INDEX idx_coverage_zone     ON fact_charger_coverage(zone_key);
CREATE INDEX idx_coverage_date     ON fact_charger_coverage(date_key);
CREATE INDEX idx_coverage_station  ON fact_charger_coverage(station_key);

-- ============================================================================
-- Verification — show all fact tables with column counts
-- ============================================================================
SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns c
     WHERE c.table_schema = 'project_dw'
       AND c.table_name   = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'project_dw'
  AND table_type   = 'BASE TABLE'
ORDER BY table_name;
