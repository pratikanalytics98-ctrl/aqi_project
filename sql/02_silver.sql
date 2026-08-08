-- =============================================================
-- SILVER: clean, dedupe, and enforce quality on the bronze data.
--
-- Rules:
--   * A single (city_slug, ts_utc) tuple is the natural key.
--   * We keep the *latest* fetched_at_utc for any duplicate, so re-runs
--     and back-fills always win over older versions of the same hour.
--   * We drop rows with a NULL pm2_5 (the primary metric for NAQI)
--     and any rows in the future — Open-Meteo returned a stale
--     forecast_days once and it took a while to notice.
-- =============================================================

CREATE OR REPLACE TABLE silver_measurements AS
WITH deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY city_slug, ts_utc
            ORDER BY fetched_at_utc DESC
        ) AS rn
    FROM bronze_measurements
    WHERE pm2_5 IS NOT NULL
      AND ts_utc <= NOW()
)
SELECT
    city_slug,
    city_name,
    state,
    latitude,
    longitude,
    ts_utc,
    pm2_5,
    pm10,
    co,
    no2,
    so2,
    o3,
    fetched_at_utc,
    -- Simple quality flag; extend this with more rules over time.
    CASE
        WHEN pm2_5 < 0            THEN 'NEGATIVE_VALUE'
        WHEN pm2_5 > 1000         THEN 'IMPLAUSIBLE_HIGH'
        WHEN pm10  IS NOT NULL
             AND pm2_5 > pm10     THEN 'PM25_EXCEEDS_PM10'
        ELSE 'OK'
    END AS quality_flag
FROM deduped
WHERE rn = 1
  AND pm2_5 >= 0
  AND pm2_5 <= 1000;


COPY silver_measurements
TO '{ROOT}/data/silver/measurements.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
