#!/usr/bin/env python3
"""
fetch_wx.py
Fetches live NRCS SNOTEL snowpack + NOAA surface weather data
for Pacific Northwest mountain stations and writes CSVs for
processing by CASCADIA-WX.f90

NRCS AWDB API  - free, no key required
NOAA API       - free, token recommended (set NOAA_TOKEN env var)

Stations: Rainier / Olympics / Cascades massifs
"""

import urllib.request
import urllib.parse
import json
import csv
import sys
import os
from datetime import datetime, timezone, timedelta

# ── SNOTEL STATIONS ─────────────────────────────────────────────────────
# Verified active NRCS SNOTEL sites - Rainier / Olympics / Cascades
SNOTEL_SITES = [
    # (triplet_id, name, massif)
    ("1011:WA:SNTL", "Paradise (Rainier)",         "RAINIER"),
    ("909:WA:SNTL",  "Sunrise (Rainier)",           "RAINIER"),
    ("1012:WA:SNTL", "Cayuse Pass",                 "RAINIER"),
    ("366:WA:SNTL",  "Hurricane Ridge (Olympics)",  "OLYMPICS"),
    ("908:WA:SNTL",  "Waterhole (Olympics)",        "OLYMPICS"),
    ("774:WA:SNTL",  "Snoqualmie Pass",             "CASCADES"),
    ("778:WA:SNTL",  "Stevens Pass",                "CASCADES"),
    ("780:WA:SNTL",  "Stampede Pass",               "CASCADES"),
    ("910:WA:SNTL",  "White Pass",                  "CASCADES"),
    ("913:WA:SNTL",  "Crystal Mountain",            "CASCADES"),
    ("915:WA:SNTL",  "Chinook Pass",                "CASCADES"),
]

# ── VALLEY STATIONS (NOAA ASOS) for lapse rate baseline ─────────────────
VALLEY_STATIONS = [
    # (NOAA station id, name, elev_m)
    ("KSEA", "Seattle-Tacoma Airport",  131),
    ("KPWT", "Bremerton Airport",        148),
    ("KTIW", "Tacoma Narrows Airport",   93),
    ("KENW", "Enumclaw Airport",         202),
]

OUTPUT_SNOTEL = "snotel_data.csv"
OUTPUT_VALLEY = "valley_data.csv"

# NRCS AWDB API base
AWDB_BASE = "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1"


def fetch_snotel_station(triplet, name, massif, target_date):
    """Fetch current day SNOTEL data for one station via NRCS AWDB REST API."""
    date_str = target_date.strftime("%Y-%m-%d")

    # Elements to fetch:
    # WTEQ = SWE (inches), PCTMEDIAN = % of median, PREC = precip,
    # TMAX = max temp F, TMIN = min temp F
    elements = "WTEQ,PCTMEDIAN,PREC,TMAX,TMIN"

    url = (f"{AWDB_BASE}/data?"
           f"stationTriplets={urllib.parse.quote(triplet)}"
           f"&elements={elements}"
           f"&beginDate={date_str}"
           f"&endDate={date_str}"
           f"&duration=DAILY")

    print(f"  Fetching {triplet} - {name}...", end=" ")

    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "cascadia-wx/1.0 (github.com/bdgroves/cascadia-wx)"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"ERROR: {e}")
        return None

    # Parse response
    result = {
        "id":     triplet,
        "name":   name,
        "massif": massif,
        "date":   date_str,
        "swe":    None,
        "swe_pct": None,
        "precip": None,
        "tmax":   None,
        "tmin":   None,
        "elev_ft": None,
    }

    # Get station elevation from metadata
    try:
        meta_url = (f"{AWDB_BASE}/stations?"
                    f"stationTriplets={urllib.parse.quote(triplet)}")
        meta_req = urllib.request.Request(
            meta_url,
            headers={"User-Agent": "cascadia-wx/1.0"}
        )
        with urllib.request.urlopen(meta_req, timeout=15) as resp:
            meta = json.loads(resp.read().decode("utf-8"))
            if meta and len(meta) > 0:
                result["elev_ft"] = meta[0].get("elevation", 0)
    except Exception:
        pass

    # Parse element data
    for element_data in data:
        element = element_data.get("stationElement", {}).get("elementCode", "")
        values  = element_data.get("values", [])
        val     = values[0].get("value") if values else None

        if val is not None and val != "":
            try:
                fval = float(val)
                if element == "WTEQ":    result["swe"]     = fval
                if element == "PCTMEDIAN": result["swe_pct"] = fval
                if element == "PREC":    result["precip"]  = fval
                if element == "TMAX":    result["tmax"]    = fval
                if element == "TMIN":    result["tmin"]    = fval
            except (ValueError, TypeError):
                pass

    # Fill missing with defaults so FORTRAN doesn't choke
    for key, default in [("swe", 0.0), ("swe_pct", 0.0),
                          ("precip", 0.0), ("tmax", 32.0),
                          ("tmin", 28.0), ("elev_ft", 5000.0)]:
        if result[key] is None:
            result[key] = default

    print(f"SWE={result['swe']:.1f}\" ({result['swe_pct']:.0f}%) "
          f"T={result['tmax']:.0f}/{result['tmin']:.0f}F")
    return result


def fetch_noaa_surface(station_id, name, elev_m):
    """Fetch current temperature from NOAA ASOS station."""
    token = os.environ.get("NOAA_TOKEN", "")
    headers = {"User-Agent": "cascadia-wx/1.0"}
    if token:
        headers["token"] = token

    today = datetime.now(timezone.utc).strftime("%Y-%m-%dT00:00:00")
    url = (f"https://api.weather.gov/stations/{station_id}/observations/latest")

    print(f"  Fetching valley station {station_id} - {name}...", end=" ")

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        props = data.get("properties", {})
        temp  = props.get("temperature", {}).get("value")
        if temp is None:
            raise ValueError("No temperature value")
        print(f"{temp:.1f}C")
        return {"name": name, "elev_m": elev_m, "temp_c": float(temp)}
    except Exception as e:
        print(f"ERROR: {e} — using default")
        # Use standard atmosphere approximation
        temp_default = 15.0 - (elev_m * 0.0065)
        return {"name": name, "elev_m": elev_m, "temp_c": temp_default}


def write_snotel_csv(records):
    """Write snotel_data.csv for FORTRAN."""
    fieldnames = ["id", "name", "massif", "elev_ft", "swe", "swe_pct",
                  "tmax", "tmin", "precip", "date"]
    with open(OUTPUT_SNOTEL, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(records)
    print(f"\nWrote {len(records)} SNOTEL records to {OUTPUT_SNOTEL}")


def write_valley_csv(records):
    """Write valley_data.csv for FORTRAN lapse rate computation."""
    with open(OUTPUT_VALLEY, "w", newline="", encoding="utf-8") as f:
        f.write("name,elev_m,temp_c\n")
        for r in records:
            f.write(f"{r['name']},{r['elev_m']},{r['temp_c']:.1f}\n")
    print(f"Wrote {len(records)} valley records to {OUTPUT_VALLEY}")


def main():
    now = datetime.now(timezone.utc)
    # Use yesterday if today's data may not be posted yet (SNOTEL updates ~8AM PT)
    target = now - timedelta(days=1)

    print(f"CASCADIA-WX FETCH  //  {now.strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"Target date: {target.strftime('%Y-%m-%d')}")
    print(f"Fetching {len(SNOTEL_SITES)} SNOTEL stations...\n")

    snotel_records = []
    failed = []

    for triplet, name, massif in SNOTEL_SITES:
        rec = fetch_snotel_station(triplet, name, massif, target)
        if rec:
            snotel_records.append(rec)
        else:
            failed.append(triplet)

    if not snotel_records:
        print("ERROR: No SNOTEL data fetched. Exiting.")
        sys.exit(1)

    print(f"\nFetching {len(VALLEY_STATIONS)} valley stations...\n")
    valley_records = []
    for station_id, name, elev_m in VALLEY_STATIONS:
        rec = fetch_noaa_surface(station_id, name, elev_m)
        valley_records.append(rec)

    write_snotel_csv(snotel_records)
    write_valley_csv(valley_records)

    if failed:
        print(f"\nWARNING: No data for: {', '.join(failed)}")

    print("Fetch complete. Ready for CASCADIA-WX.")


if __name__ == "__main__":
    main()
