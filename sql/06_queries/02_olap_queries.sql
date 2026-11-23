-- OLAP 1: Roll up trip counts and base fares from month to year to grand total.
SELECT
    CASE
        WHEN GROUPING(d.year) = 1 THEN 'All years'
        ELSE COALESCE(d.year::TEXT, 'Unknown year')
    END AS year_label,
    CASE
        WHEN GROUPING(d.month_num) = 1 THEN 'All months'
        ELSE COALESCE(d.month_num::TEXT, 'Unknown month')
    END AS month_label,
    COUNT(*) AS total_trips,
    ROUND(SUM(f.base_fare), 2) AS total_base_fare,
    ROUND(SUM(f.driver_pay), 2) AS total_driver_pay,
    GROUPING(d.year, d.month_num) AS grouping_level
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_date AS d
    ON d.date_key = f.date_key
GROUP BY ROLLUP(d.year, d.month_num)
ORDER BY
    GROUPING(d.year),
    d.year,
    GROUPING(d.month_num),
    d.month_num;


-- OLAP 2: Cube trip counts and fares by pickup borough and company.
-- Return borough-company results, borough totals, company totals, and grand total.
SELECT
    CASE
        WHEN GROUPING(z.borough) = 1 THEN 'All boroughs'
        ELSE COALESCE(z.borough, 'Unknown borough')
    END AS borough_label,
    CASE
        WHEN GROUPING(c.hvfhs_license_num) = 1 THEN 'All companies'
        ELSE COALESCE(c.hvfhs_license_num, 'Unknown company')
    END AS company_code,
    COUNT(*) AS total_trips,
    ROUND(SUM(f.base_fare), 2) AS total_base_fare,
    ROUND(SUM(f.driver_pay), 2) AS total_driver_pay,
    ROUND(
        AVG(f.wait_min) FILTER (WHERE f.wait_min >= 0),
        2
    ) AS avg_wait_min,
    GROUPING(z.borough, c.hvfhs_license_num) AS grouping_level
FROM project_dw.fact_trips AS f
JOIN project_dw.dim_zone AS z
    ON z.zone_key = f.pickup_zone_key
JOIN project_dw.dim_company AS c
    ON c.company_key = f.company_key
GROUP BY CUBE(z.borough, c.hvfhs_license_num)
ORDER BY
    GROUPING(z.borough),
    z.borough,
    GROUPING(c.hvfhs_license_num),
    c.hvfhs_license_num;