"""
Transform step: bronze → silver → gold with DuckDB.

Everything analytical lives in the SQL files under /sql. This Python
module only handles path resolution, orchestration, and a couple of
small JSON exports that the dashboard consumes directly.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DATA_DIR = ROOT / "data"
DOCS_DATA_DIR = ROOT / "docs" / "data"


def run_sql(con: duckdb.DuckDBPyConnection, name: str) -> None:
    """Execute a numbered SQL file from /sql."""
    path = SQL_DIR / name
    print(f"[transform] running {path.name}")
    sql = path.read_text()

    # Cheap templating: replace {ROOT} with the absolute repo path so
    # SQL files can be run from anywhere without brittle relative paths.
    sql = sql.replace("{ROOT}", str(ROOT))
    con.execute(sql)


def export_dashboard_json(con: duckdb.DuckDBPyConnection) -> None:
    """
    Write the small pre-aggregated JSON files the dashboard consumes.

    We keep the dashboard dumb: no DuckDB-WASM (yet), no client-side SQL,
    just fetch() a JSON file and render. Upgrade path is left as an
    exercise — see README.
    """
    DOCS_DATA_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Latest reading per city, with computed NAQI + category.
    latest = con.execute(
        "SELECT * FROM gold_latest ORDER BY naqi_pm25 DESC"
    ).fetchall()
    latest_cols = [d[0] for d in con.description]
    (DOCS_DATA_DIR / "latest.json").write_text(
        json.dumps(
            [dict(zip(latest_cols, row)) for row in latest],
            indent=2,
            default=str,
        )
    )

    # 2. Hourly time series per city for the last 7 days.
    trend = con.execute(
        "SELECT * FROM gold_hourly_trend ORDER BY city_slug, ts_utc"
    ).fetchall()
    trend_cols = [d[0] for d in con.description]
    (DOCS_DATA_DIR / "hourly_trend.json").write_text(
        json.dumps(
            [dict(zip(trend_cols, row)) for row in trend],
            default=str,
        )
    )

    # 3. Daily summary per city — min/mean/max NAQI.
    daily = con.execute(
        "SELECT * FROM gold_daily_summary ORDER BY city_slug, day"
    ).fetchall()
    daily_cols = [d[0] for d in con.description]
    (DOCS_DATA_DIR / "daily_summary.json").write_text(
        json.dumps(
            [dict(zip(daily_cols, row)) for row in daily],
            default=str,
        )
    )

    print(f"[transform] dashboard JSON written to {DOCS_DATA_DIR.relative_to(ROOT)}")


def main() -> int:
    # In-memory DuckDB is enough — we materialise results back to
    # Parquet on disk in the SQL files themselves.
    con = duckdb.connect(":memory:")

    # Nice-to-have: reproducible thread count.
    con.execute("SET threads = 4;")

    for step in ("01_bronze.sql", "02_silver.sql", "03_gold.sql"):
        run_sql(con, step)

    export_dashboard_json(con)

    # Quick sanity summary so CI logs are useful.
    n_measurements = con.execute(
        "SELECT COUNT(*) FROM read_parquet('{ROOT}/data/silver/measurements.parquet')".replace(
            "{ROOT}", str(ROOT)
        )
    ).fetchone()[0]
    print(f"[transform] silver measurements: {n_measurements:,}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
