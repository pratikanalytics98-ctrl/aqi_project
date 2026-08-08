"""
Fetch step: hourly ingestion from Open-Meteo Air Quality API.

Design notes
------------
* We use Open-Meteo because it has a truly free tier with no API key
  required. Attribution is added to the dashboard.
* Each run fetches the last 2 days of hourly readings for every city
  and dumps one raw JSON file per city per run. The silver step
  dedupes on (city, timestamp), so overlapping windows are safe and
  the pipeline is self-healing if a cron misses.
* Raw files are committed to git — the point of git-scraping is that
  git history *is* the audit log for the ingestion step.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

from config import CITIES, City

API_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"

# Pollutants we care about. Open-Meteo returns µg/m³ for particulates,
# and µg/m³ for gases too (their unit convention, not ppb).
HOURLY_VARS = [
    "pm10",
    "pm2_5",
    "carbon_monoxide",
    "nitrogen_dioxide",
    "sulphur_dioxide",
    "ozone",
]


def fetch_city(city: City) -> dict:
    """Fetch the last 2 days of hourly air quality data for one city."""
    params = {
        "latitude":      city.latitude,
        "longitude":     city.longitude,
        "hourly":        ",".join(HOURLY_VARS),
        "past_days":     2,
        "forecast_days": 0,
        "timezone":      "UTC",
    }
    response = requests.get(API_URL, params=params, timeout=30)
    response.raise_for_status()
    payload = response.json()

    # Attach our own metadata so the bronze step has everything it needs
    # without cross-referencing the config.
    return {
        "city_slug":      city.slug,
        "city_name":      city.name,
        "state":          city.state,
        "latitude":       city.latitude,
        "longitude":      city.longitude,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
        "source":         "open-meteo",
        "payload":        payload,
    }


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    now = datetime.now(timezone.utc)

    # Partition raw files by day so directory listings stay manageable.
    # Filename includes the exact fetch timestamp so multiple runs in
    # the same hour don't collide.
    day_dir = root / "data" / "raw" / now.strftime("%Y-%m-%d")
    day_dir.mkdir(parents=True, exist_ok=True)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    failures: list[str] = []
    for city in CITIES:
        try:
            record = fetch_city(city)
        except Exception as exc:  # noqa: BLE001 — we want to keep going
            print(f"[fetch] {city.slug}: FAILED — {exc}", file=sys.stderr)
            failures.append(city.slug)
            continue

        out_path = day_dir / f"{city.slug}_{stamp}.json"
        out_path.write_text(json.dumps(record, indent=2))
        print(f"[fetch] {city.slug}: wrote {out_path.relative_to(root)}")

    if failures:
        print(f"[fetch] {len(failures)} cities failed: {failures}", file=sys.stderr)
        # Exit non-zero only if *every* city failed — one flaky city
        # shouldn't tank the whole run.
        if len(failures) == len(CITIES):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
