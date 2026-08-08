-- =============================================================
-- BRONZE: raw JSON snapshots -> a single append-friendly Parquet.
--
-- Design:
--   * We use DuckDB's read_json_auto to walk every raw file at once.
--     Since Open-Meteo returns hourly arrays inside a payload object,
--     we UNNEST them into one row per (city, timestamp, pollutant).
--   * We keep the shape intentionally close to the source so any
--     recovery / re-processing can start here without re-fetching.
-- =============================================================

CREATE OR REPLACE TABLE bronze_measurements AS
WITH raw AS (
    SELECT
        city_slug,
        city_name,
        state,
        latitude,
        longitude,
        fetched_at_utc,
        source,
        payload,
        filename
    FROM read_json_auto(
        '{ROOT}/data/raw/**/*.json',
        filename = true,
        maximum_object_size = 33554432
    )
),
exploded AS (
    SELECT
        r.city_slug,
        r.city_name,
        r.state,
        r.latitude,
        r.longitude,
        r.fetched_at_utc,
        r.source,
        r.filename,
        -- Open-Meteo returns parallel arrays: time[], pm2_5[], pm10[], ...
        -- UNNEST all of them together with generate_subscripts to zip them.
        UNNEST(r.payload.hourly.time)              AS ts_str,
        UNNEST(r.payload.hourly.pm2_5)             AS pm2_5,
        UNNEST(r.payload.hourly.pm10)              AS pm10,
        UNNEST(r.payload.hourly.carbon_monoxide)   AS co,
        UNNEST(r.payload.hourly.nitrogen_dioxide)  AS no2,
        UNNEST(r.payload.hourly.sulphur_dioxide)   AS so2,
        UNNEST(r.payload.hourly.ozone)             AS o3
    FROM raw r
)
SELECT
    city_slug,
    city_name,
    state,
    latitude,
    longitude,
    -- Open-Meteo gives ISO strings without timezone when we ask for UTC.
    CAST(ts_str AS TIMESTAMP) AS ts_utc,
    pm2_5,
    pm10,
    co,
    no2,
    so2,
    o3,
    CAST(fetched_at_utc AS TIMESTAMP) AS fetched_at_utc,
    source,
    filename
FROM exploded;


-- Materialise bronze to Parquet so it's queryable by anything, not
-- just this session, and so the dashboard could point at it later
-- via DuckDB-WASM.
COPY bronze_measurements
TO '{ROOT}/data/bronze/measurements.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
