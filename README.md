# India Air Quality Monitor

A public, always-on data pipeline that fetches hourly air-quality readings for six major Indian cities, transforms them into a lakehouse-style medallion architecture with DuckDB, and serves a live dashboard — all from a single GitHub repo, at $0 running cost.

<!-- Replace with a real screenshot once the site is live -->
> **Live dashboard:** `https://YOUR_USERNAME.github.io/aqi-india/`

---

## What this is

Every hour, a GitHub Action:

1. Pulls the last 48 hours of hourly PM2.5, PM10, NO₂, SO₂, O₃, and CO for Delhi, Mumbai, Kolkata, Bengaluru, Chennai, and Hyderabad from the free [Open-Meteo Air Quality API](https://open-meteo.com/en/docs/air-quality-api).
2. Runs a three-stage DuckDB pipeline — bronze → silver → gold — computing the India NAQI (National Air Quality Index) PM2.5 sub-index per [CPCB](https://cpcb.nic.in/) breakpoints.
3. Commits raw JSON and processed Parquet back to the repo, so git history *is* the audit log for the entire pipeline.
4. Publishes a static dashboard on GitHub Pages that reads pre-computed JSON.

No servers. No databases. No API keys. No cloud bills.

## Why this exists

Government air-quality dashboards show *current* readings but rarely let you answer questions like:

- How much worse did Delhi get during Diwali week compared to the two weeks before?
- Which city has the most stable air quality across the year?
- What's the actual correlation between PM2.5 and O₃ in a coastal city like Chennai?

To answer these questions you need archived, structured, granular data. This repo builds that archive continuously and makes it queryable by anyone with DuckDB installed:

```python
import duckdb
duckdb.sql("""
    SELECT city_name, AVG(pm2_5) AS avg_pm25
    FROM 'https://raw.githubusercontent.com/YOUR_USERNAME/aqi-india/main/data/silver/measurements.parquet'
    WHERE ts_utc >= NOW() - INTERVAL 30 DAY
    GROUP BY city_name
    ORDER BY avg_pm25 DESC
""").show()
```

## Architecture

```
       ┌─────────────────────┐
       │ Open-Meteo API      │  (free, no key)
       └──────────┬──────────┘
                  │  hourly cron
                  ▼
       ┌─────────────────────┐
       │ GitHub Actions      │  fetch.py → data/raw/YYYY-MM-DD/*.json
       └──────────┬──────────┘
                  │
                  ▼
       ┌─────────────────────┐
       │ DuckDB (in-process) │  three SQL steps
       │                     │
       │  01_bronze.sql  ──► data/bronze/measurements.parquet
       │  02_silver.sql  ──► data/silver/measurements.parquet
       │  03_gold.sql    ──► data/gold/{latest, hourly_trend, daily_summary}.parquet
       │                     + docs/data/*.json  (dashboard payload)
       └──────────┬──────────┘
                  │  git commit + push
                  ▼
       ┌─────────────────────┐
       │ GitHub Pages        │  docs/index.html + docs/data/*.json
       └─────────────────────┘
```

## Why DuckDB

For a dataset this size (hundreds of thousands of rows per year across six cities), Spark or Databricks would be architectural overkill. DuckDB is:

- **Embedded** — runs inside the same Python process as `fetch.py`. No cluster, no daemon, no config.
- **Columnar + vectorized** — handles millions of rows on a single core faster than most warehouses do on distributed clusters, provided the data fits on one machine.
- **Parquet-native** — reads and writes Parquet directly, so bronze/silver/gold layers are ordinary files, queryable by anything (pandas, Polars, Spark, DuckDB-WASM in the browser).
- **Free and MIT-licensed** — no vendor, no seat costs.

If the dataset ever outgrows a single machine, the SQL translates almost line-for-line to Spark or Databricks. Nothing here is locked in.

## Medallion architecture, in DuckDB

| Layer   | What lives here                                   | Path                                | Written by         |
|---------|---------------------------------------------------|-------------------------------------|--------------------|
| **Raw** | Immutable JSON snapshots, exactly as fetched      | `data/raw/YYYY-MM-DD/*.json`        | `pipeline/fetch.py` |
| **Bronze** | UNNESTed to one row per (city, hour, pollutant), typed | `data/bronze/measurements.parquet`  | `sql/01_bronze.sql`  |
| **Silver** | Deduped on (city, ts), quality-flagged, filtered  | `data/silver/measurements.parquet`  | `sql/02_silver.sql`  |
| **Gold**   | NAQI computed, aggregations for the dashboard     | `data/gold/*.parquet`               | `sql/03_gold.sql`    |

Quality checks in silver flag readings where PM2.5 exceeds PM10 (physically impossible), where values are negative, or where they exceed 1000 µg/m³ (implausible). Flagged rows are kept but excluded from gold — so nothing is lost and issues are auditable.

## Repo layout

```
aqi-india/
├── .github/workflows/
│   ├── pipeline.yml          Hourly ingest + transform
│   └── pages.yml             Deploy dashboard on push to docs/
├── pipeline/
│   ├── config.py             City list, NAQI breakpoints, colour codes
│   ├── fetch.py              Open-Meteo → data/raw/
│   ├── transform.py          Orchestrates the three SQL files
│   └── requirements.txt      duckdb, requests
├── sql/
│   ├── 01_bronze.sql
│   ├── 02_silver.sql
│   └── 03_gold.sql
├── data/                     Populated by the pipeline (git-tracked)
├── docs/                     Static dashboard (GitHub Pages source)
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   └── data/                 Pre-computed JSON payloads
├── Makefile
└── README.md
```

## Running it locally

Requirements: Python 3.10+ and `make` (optional).

```bash
git clone https://github.com/YOUR_USERNAME/aqi-india
cd aqi-india

make install          # pip install -r pipeline/requirements.txt
make run              # fetch once + run the full DuckDB transform
make serve            # preview the dashboard at http://localhost:8000
```

Or without Make:

```bash
pip install -r pipeline/requirements.txt
cd pipeline && python fetch.py && python transform.py && cd ..
python -m http.server 8000 --directory docs
```

The first run takes about 20 seconds — most of that is the initial `pip install`. Subsequent runs are under 3 seconds.

## Deploying your own copy

1. Fork this repo (or [use it as a template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)).
2. Edit `pipeline/config.py` to change or add cities.
3. In your fork, go to **Settings → Pages** and set **Source** to **GitHub Actions**.
4. In **Settings → Actions → General**, under "Workflow permissions", pick **Read and write permissions** so the ingest workflow can commit results.
5. Trigger the first run manually: **Actions → Ingest and transform → Run workflow**.

After ~30 seconds the first data files appear, the Pages workflow deploys, and your dashboard is live at `https://YOUR_USERNAME.github.io/aqi-india/`. From there the hourly cron takes over.

## Extending it

**Add a city.** Append a new `City(...)` entry to `pipeline/config.py`. Nothing else changes.

**Add a pollutant.** Add it to `HOURLY_VARS` in `pipeline/fetch.py`, then reference it in `sql/01_bronze.sql`'s `UNNEST` block. It flows through silver and gold automatically once you decide how to use it.

**Query the archive from anywhere.** Everything under `data/` is Parquet or JSON on a public HTTPS URL. Point DuckDB, pandas, Polars, Spark, or even DuckDB-WASM at `https://raw.githubusercontent.com/YOUR_USERNAME/aqi-india/main/data/silver/measurements.parquet` and it just works.

**Upgrade the dashboard.** The current build uses Chart.js and pre-computed JSON. If you want the dashboard to run SQL directly against the Parquet files in the browser, swap in [DuckDB-WASM](https://duckdb.org/docs/api/wasm/overview.html) — it's a drop-in for the `fetch()` calls in `docs/app.js`.

## Cost breakdown

| Item                       | Cost        |
|----------------------------|-------------|
| Open-Meteo API             | Free        |
| GitHub Actions             | Free (2,000 min/month on public repos; this uses ~30) |
| GitHub Pages hosting       | Free        |
| DuckDB                     | Free (MIT)  |
| **Total**                  | **$0**      |

The bottleneck is repo size, not compute. At the current cadence (six cities, six pollutants, hourly), the repo grows about 4 MB per month. A tidy-up script that rotates raw JSON older than 90 days out to a release asset would extend this indefinitely if you care to add one.

## Data sources and licensing

- Air quality data: [Open-Meteo Air Quality API](https://open-meteo.com/en/docs/air-quality-api), CC-BY 4.0. Attribution is shown in the dashboard footer.
- NAQI breakpoints and category names: [Central Pollution Control Board (CPCB), Government of India](https://cpcb.nic.in/).
- Code in this repo: MIT (see `LICENSE`).

## Acknowledgements

The overall pattern here — a GitHub repo acting as a scheduler, database, and CDN all at once — is a form of "git-scraping", popularised by [Simon Willison](https://simonwillison.net/2020/Oct/9/git-scraping/). The medallion architecture terminology is from Databricks. DuckDB is by the DuckDB Foundation and CWI Amsterdam.
