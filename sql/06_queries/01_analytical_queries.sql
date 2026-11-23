-- BQ1: Rank pickup zones by monthly trip count.
WITH monthly_zone_trips AS (
    SELECT
        d.year,
        d.month_num,
        d.month_name,
        z.zone_key,
        z.zone_name,
        z.borough,
        COUNT(*) AS total_trips
    FROM project_dw.fact_trips AS f
    JOIN project_dw.dim_date AS d
        ON d.date_key = f.date_key
    JOIN project_dw.dim_zone AS z
        ON z.zone_key = f.pickup_zone_key
    GROUP BY
        d.year, d.month_num, d.month_name,
        z.zone_key, z.zone_name, z.borough
)
SELECT
    *,
    DENSE_RANK() OVER (
        PARTITION BY year, month_num
        ORDER BY total_trips DESC
    ) AS monthly_rank
FROM monthly_zone_trips
ORDER BY year, month_num, monthly_rank, zone_key;


-- BQ2: Rank pickup zones by driver pay per mile using trips with positive mileage.
SELECT
    z.zone_key,
    z.zone_name,
    z.borough,
    COUNT(*) AS eligible_trips,
    ROUND(SUM(f.driver_pay), 2) AS total_driver_pay,
    ROUND(SUM(f.trip_miles), 2) AS total_miles,
    ROUND(
        SUM(f.driver_pay) / NULLIF(SUM(f.trip_miles), 0),
        2
    ) AS driver_pay_per_mile
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_zone AS z
    ON z.zone_key = f.pickup_zone_key
WHERE f.trip_miles > 0
  AND f.driver_pay IS NOT NULL
GROUP BY z.zone_key, z.zone_name, z.borough
ORDER BY driver_pay_per_mile DESC, eligible_trips DESC;


-- BQ3: Compare monthly trips, base fares, and tips between Uber and Lyft.
SELECT
    d.year,
    d.month_num,
    d.month_name,
    c.hvfhs_license_num,
    c.company_name,
    COUNT(*) AS total_trips,
    ROUND(SUM(f.base_fare), 2) AS total_base_fare,
    ROUND(AVG(f.base_fare), 2) AS avg_base_fare,
    ROUND(SUM(f.tips), 2) AS total_tips,
    ROUND(AVG(f.tips), 2) AS avg_tip
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_date AS d
    ON d.date_key = f.date_key
JOIN project_dw.dim_company AS c
    ON c.company_key = f.company_key
WHERE c.hvfhs_license_num IN ('HV0003', 'HV0005')
GROUP BY
    d.year, d.month_num, d.month_name,
    c.hvfhs_license_num, c.company_name
ORDER BY d.year, d.month_num, total_trips DESC;


-- BQ4: Identify pickup hours with the longest valid average customer wait.
SELECT
    t.hour_of_day,
    t.peak_offpeak,
    COUNT(*) AS total_trips,
    COUNT(*) FILTER (
        WHERE f.wait_min >= 0
    ) AS valid_wait_trips,
    ROUND(
        AVG(f.wait_min) FILTER (WHERE f.wait_min >= 0),
        2
    ) AS avg_wait_min
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_timeofday AS t
    ON t.time_key = f.time_key
GROUP BY t.hour_of_day, t.peak_offpeak
ORDER BY avg_wait_min DESC NULLS LAST, t.hour_of_day;


-- BQ5: Compare average sampled trips per hour across rain categories within each hour of day.
-- Aggregate zone rows to city-hour first so one hour is counted once.
WITH city_hours AS (
    SELECT
        s.date_key,
        s.time_key,
        w.rain_level,
        SUM(s.trip_count) AS sampled_trips
    FROM project_dw.fact_zone_hourly_snapshot AS s
    JOIN project_dw.dim_weather AS w
        ON w.weather_key = s.weather_key
    GROUP BY s.date_key, s.time_key, w.rain_level
)
SELECT
    t.hour_of_day,
    h.rain_level,
    COUNT(*) AS observed_hours,
    SUM(h.sampled_trips) AS total_sampled_trips,
    ROUND(AVG(h.sampled_trips), 2) AS avg_sampled_trips_per_hour
FROM city_hours AS h
JOIN project_dw.dim_timeofday AS t
    ON t.time_key = h.time_key
GROUP BY t.hour_of_day, h.rain_level
ORDER BY t.hour_of_day, h.rain_level;


-- BQ6: Compare valid average waiting time across rain categories in each pickup borough.
-- Use trip rows so missing or invalid waits are excluded from the average correctly.
SELECT
    z.borough,
    w.rain_level,
    COUNT(*) AS total_trips,
    COUNT(*) FILTER (
        WHERE f.wait_min >= 0
    ) AS valid_wait_trips,
    ROUND(
        AVG(f.wait_min) FILTER (WHERE f.wait_min >= 0),
        2
    ) AS avg_wait_min
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_zone AS z
    ON z.zone_key = f.pickup_zone_key
JOIN project_dw.dim_weather AS w
    ON w.weather_key = f.weather_key
GROUP BY z.borough, w.rain_level
ORDER BY z.borough, w.rain_level;


-- BQ7: Compare monthly driver pay per mile across rain categories.
-- Use exact trip mileage and matching pay from eligible trips.
SELECT
    d.year,
    d.month_num,
    w.rain_level,
    COUNT(*) AS eligible_trips,
    ROUND(SUM(f.driver_pay), 2) AS total_driver_pay,
    ROUND(SUM(f.trip_miles), 2) AS total_miles,
    ROUND(
        SUM(f.driver_pay) / NULLIF(SUM(f.trip_miles), 0),
        2
    ) AS driver_pay_per_mile
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_date AS d
    ON d.date_key = f.date_key
JOIN project_dw.dim_weather AS w
    ON w.weather_key = f.weather_key
WHERE f.trip_miles > 0
  AND f.driver_pay IS NOT NULL
GROUP BY d.year, d.month_num, w.rain_level
ORDER BY d.year, d.month_num, w.rain_level;


-- BQ8a: Count distinct charging stations represented in coverage data by borough.
SELECT
    z.borough,
    COUNT(DISTINCT st.station_id) AS distinct_stations
FROM project_dw.fact_charger_coverage AS f
JOIN project_dw.dim_zone AS z
    ON z.zone_key = f.zone_key
JOIN project_dw.dim_station AS st
    ON st.station_key = f.station_key
GROUP BY z.borough
ORDER BY distinct_stations DESC;


-- BQ8b: Count stations by the year they first appear in recorded coverage.
-- Treat this as opening-year growth only if coverage date_key stores station opening date.
WITH first_coverage AS (
    SELECT
        z.borough,
        st.station_id,
        MIN(d.full_date) AS first_recorded_date
    FROM project_dw.fact_charger_coverage AS f
    JOIN project_dw.dim_zone AS z
        ON z.zone_key = f.zone_key
    JOIN project_dw.dim_station AS st
        ON st.station_key = f.station_key
    JOIN project_dw.dim_date AS d
        ON d.date_key = f.date_key
    GROUP BY z.borough, st.station_id
),
annual_counts AS (
    SELECT
        borough,
        EXTRACT(YEAR FROM first_recorded_date)::INTEGER AS recorded_year,
        COUNT(*) AS stations_first_recorded
    FROM first_coverage
    GROUP BY
        borough,
        EXTRACT(YEAR FROM first_recorded_date)::INTEGER
)
SELECT
    borough,
    recorded_year,
    stations_first_recorded,
    SUM(stations_first_recorded) OVER (
        PARTITION BY borough
        ORDER BY recorded_year
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_recorded_stations
FROM annual_counts
ORDER BY borough, recorded_year;


-- BQ9: Find NYC taxi zones with no matching charging coverage record.
SELECT
    z.zone_key,
    z.location_id,
    z.zone_name,
    z.borough
FROM project_dw.dim_zone AS z
WHERE z.borough IN (
    'Manhattan', 'Brooklyn', 'Queens', 'Bronx', 'Staten Island'
)
AND NOT EXISTS (
    SELECT 1
    FROM project_dw.fact_charger_coverage AS f
    WHERE f.zone_key = z.zone_key
)
ORDER BY z.borough, z.zone_name;


-- BQ10: Rank busy NYC zones with few or no recorded charging stations.
-- Aggregate each fact separately before joining to prevent duplicated trip counts.
-- Few chargers is defined here as at most two distinct stations.
WITH zone_demand AS (
    SELECT
        zone_key,
        SUM(trip_count) AS total_trips
    FROM project_dw.fact_zone_hourly_snapshot
    GROUP BY zone_key
),
zone_chargers AS (
    SELECT
        f.zone_key,
        COUNT(DISTINCT st.station_id) AS station_count
    FROM project_dw.fact_charger_coverage AS f
    JOIN project_dw.dim_station AS st
        ON st.station_key = f.station_key
    GROUP BY f.zone_key
)
SELECT
    z.zone_key,
    z.zone_name,
    z.borough,
    d.total_trips,
    COALESCE(c.station_count, 0) AS station_count
FROM zone_demand AS d
JOIN project_dw.dim_zone AS z
    ON z.zone_key = d.zone_key
LEFT JOIN zone_chargers AS c
    ON c.zone_key = d.zone_key
WHERE z.borough IN (
    'Manhattan', 'Brooklyn', 'Queens', 'Bronx', 'Staten Island'
)
  AND COALESCE(c.station_count, 0) <= 2
ORDER BY d.total_trips DESC, z.zone_key;


-- EXTRA 1: Show monthly trip totals, base fares, driver pay, and valid average wait.
SELECT
    d.year,
    d.month_num,
    d.month_name,
    COUNT(*) AS total_trips,
    ROUND(SUM(f.base_fare), 2) AS total_base_fare,
    ROUND(SUM(f.driver_pay), 2) AS total_driver_pay,
    ROUND(
        AVG(f.wait_min) FILTER (WHERE f.wait_min >= 0),
        2
    ) AS avg_wait_min
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_date AS d
    ON d.date_key = f.date_key
GROUP BY d.year, d.month_num, d.month_name
ORDER BY d.year, d.month_num;


-- EXTRA 2: Compare trip demand and valid average wait on weekdays and weekends.
SELECT
    d.is_weekend,
    COUNT(DISTINCT d.full_date) AS observed_dates,
    COUNT(*) AS total_trips,
    ROUND(
        COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT d.full_date), 0),
        2
    ) AS avg_sampled_trips_per_observed_day,
    ROUND(
        AVG(f.wait_min) FILTER (WHERE f.wait_min >= 0),
        2
    ) AS avg_wait_min
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_date AS d
    ON d.date_key = f.date_key
GROUP BY d.is_weekend
ORDER BY d.is_weekend;