-- =============================================================
-- GOLD: business-ready views.
--
-- Three deliverables:
--   * gold_latest         — one row per city with the most recent reading
--                           and its NAQI + category
--   * gold_hourly_trend   — last 7 days of hourly readings per city
--   * gold_daily_summary  — per-day min / mean / max NAQI per city
--
-- The India NAQI PM2.5 sub-index is computed with piecewise linear
-- interpolation over the CPCB breakpoints. See pipeline/config.py for
-- the reference table.
-- =============================================================


-- Piecewise NAQI PM2.5 sub-index. Kept as a macro so the same logic
-- can be reused wherever we need it.
CREATE OR REPLACE MACRO naqi_pm25(c) AS
    CASE
        WHEN c IS NULL         THEN NULL
        WHEN c <= 30           THEN            c        * 50.0  / 30
        WHEN c <= 60           THEN  50 + (c -  30)     * 50.0  / 30
        WHEN c <= 90           THEN 100 + (c -  60)     * 100.0 / 30
        WHEN c <= 120          THEN 200 + (c -  90)     * 100.0 / 30
        WHEN c <= 250          THEN 300 + (c - 120)     * 100.0 / 130
        ELSE                        400 + LEAST(c - 250, 250) * 100.0 / 130
    END;

CREATE OR REPLACE MACRO naqi_category(i) AS
    CASE
        WHEN i IS NULL   THEN 'Unknown'
        WHEN i <=  50    THEN 'Good'
        WHEN i <= 100    THEN 'Satisfactory'
        WHEN i <= 200    THEN 'Moderate'
        WHEN i <= 300    THEN 'Poor'
        WHEN i <= 400    THEN 'Very Poor'
        ELSE                  'Severe'
    END;


-- -------- Latest reading per city --------
CREATE OR REPLACE TABLE gold_latest AS
WITH ranked AS (
    SELECT
        s.*,
        naqi_pm25(pm2_5) AS naqi_pm25,
        ROW_NUMBER() OVER (
            PARTITION BY city_slug
            ORDER BY ts_utc DESC
        ) AS rn
    FROM silver_measurements s
    WHERE quality_flag = 'OK'
)
SELECT
    city_slug,
    city_name,
    state,
    latitude,
    longitude,
    ts_utc,
    ROUND(pm2_5, 1)     AS pm2_5,
    ROUND(pm10, 1)      AS pm10,
    ROUND(o3, 1)        AS o3,
    ROUND(no2, 1)       AS no2,
    ROUND(so2, 1)       AS so2,
    ROUND(co, 1)        AS co,
    ROUND(naqi_pm25, 0) AS naqi_pm25,
    naqi_category(naqi_pm25) AS category
FROM ranked
WHERE rn = 1;


-- -------- Last 7 days of hourly readings --------
CREATE OR REPLACE TABLE gold_hourly_trend AS
SELECT
    city_slug,
    city_name,
    ts_utc,
    ROUND(pm2_5, 1)                     AS pm2_5,
    ROUND(naqi_pm25(pm2_5), 0)          AS naqi_pm25,
    naqi_category(naqi_pm25(pm2_5))     AS category
FROM silver_measurements
WHERE quality_flag = 'OK'
  AND ts_utc >= NOW() - INTERVAL 7 DAY;


-- -------- Daily rollup --------
CREATE OR REPLACE TABLE gold_daily_summary AS
SELECT
    city_slug,
    city_name,
    CAST(ts_utc AS DATE)                 AS day,
    ROUND(MIN(naqi_pm25(pm2_5)), 0)      AS naqi_min,
    ROUND(AVG(naqi_pm25(pm2_5)), 0)      AS naqi_mean,
    ROUND(MAX(naqi_pm25(pm2_5)), 0)      AS naqi_max,
    ROUND(AVG(pm2_5), 1)                 AS pm2_5_mean,
    COUNT(*)                             AS n_readings
FROM silver_measurements
WHERE quality_flag = 'OK'
GROUP BY city_slug, city_name, CAST(ts_utc AS DATE);


-- -------- Persist gold to Parquet --------
COPY gold_latest         TO '{ROOT}/data/gold/latest.parquet'         (FORMAT PARQUET, COMPRESSION ZSTD);
COPY gold_hourly_trend   TO '{ROOT}/data/gold/hourly_trend.parquet'   (FORMAT PARQUET, COMPRESSION ZSTD);
COPY gold_daily_summary  TO '{ROOT}/data/gold/daily_summary.parquet'  (FORMAT PARQUET, COMPRESSION ZSTD);
