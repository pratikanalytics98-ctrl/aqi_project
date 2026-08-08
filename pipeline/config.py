"""
Configuration for the AQI India pipeline.

Cities tracked and the India NAQI (National Air Quality Index)
sub-index breakpoints for PM2.5.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class City:
    slug: str          # stable id used in filenames and dashboard
    name: str          # display name
    state: str
    latitude: float
    longitude: float


# The set of cities is intentionally small so the free GitHub Actions minutes
# and the repo size stay comfortable. Add or remove as you like.
CITIES: list[City] = [
    City("delhi",      "Delhi",      "Delhi",         28.6139, 77.2090),
    City("mumbai",     "Mumbai",     "Maharashtra",   19.0760, 72.8777),
    City("kolkata",    "Kolkata",    "West Bengal",   22.5726, 88.3639),
    City("bengaluru",  "Bengaluru",  "Karnataka",     12.9716, 77.5946),
    City("chennai",    "Chennai",    "Tamil Nadu",    13.0827, 80.2707),
    City("hyderabad",  "Hyderabad",  "Telangana",     17.3850, 78.4867),
]


# India NAQI PM2.5 sub-index breakpoints.
# Reference: CPCB (Central Pollution Control Board), Govt of India.
# Each tuple is (concentration_low, concentration_high, index_low, index_high, category).
NAQI_PM25_BREAKPOINTS = [
    (0.0,   30.0,   0,   50,  "Good"),
    (30.1,  60.0,   51,  100, "Satisfactory"),
    (60.1,  90.0,   101, 200, "Moderate"),
    (90.1,  120.0,  201, 300, "Poor"),
    (120.1, 250.0,  301, 400, "Very Poor"),
    (250.1, 1000.0, 401, 500, "Severe"),
]


# Colour codes for each category (used by the dashboard).
NAQI_CATEGORY_COLORS = {
    "Good":         "#8FBF3B",
    "Satisfactory": "#B8D651",
    "Moderate":     "#F5C24F",
    "Poor":         "#EE8A3A",
    "Very Poor":    "#D3492A",
    "Severe":       "#7A1A1A",
    "Unknown":      "#9AA0A6",
}
