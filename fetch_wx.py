#!/usr/bin/env python3
"""
fetch_wx.py  -  CASCADIA-WX data fetcher
Fetches NRCS SNOTEL snowpack + NOAA surface temperatures.
Uses NRCS Report Generator CSV endpoint (stable, no API key).
Station IDs verified from wcc.sc.egov.usda.gov/nwcc/sntlsites.jsp

Elements fetched: WTEQ (SWE in), TMAX (F), TMIN (F), PREC (in)
% of median computed locally from baselines.csv
"""

import urllib.request, urllib.parse, csv, sys, os, io, json
from datetime import datetime, timezone, timedelta

# ── VERIFIED SNOTEL STATION IDs ───────────────────────────────────────
# Source: https://wcc.sc.egov.usda.gov/nwcc/sntlsites.jsp?state=WA
SNOTEL_SITES = [
    # (site_num, state, display_name,              massif,    elev_ft)
    (679,  "WA", "Paradise",                       "RAINIER",  5150),
    (1085, "WA", "Cayuse Pass",                    "RAINIER",  5260),
    (942,  "WA", "Burnt Mountain",                 "RAINIER",  4160),
    (943,  "WA", "Dungeness",                      "OLYMPICS", 3990),
    (1107, "WA", "Buckinghorse",                   "OLYMPICS", 4850),
    (774,  "WA", "Snoqualmie Pass",                "CASCADES", 3000),
    (778,  "WA", "Stevens Pass",                   "CASCADES", 4061),
    (780,  "WA", "Stampede Pass",                  "CASCADES", 3960),
    (910,  "WA", "Elbow Lake",                     "CASCADES", 3050),
    (375,  "WA", "Bumping Ridge",                  "CASCADES", 4600),
    (418,  "WA", "Corral Pass",                    "RAINIER",  5810),
]

# ── VALLEY STATIONS (NOAA) ────────────────────────────────────────────
VALLEY_STATIONS = [
    ("KSEA", "Seattle-Tacoma Airport",  131),
    ("KPWT", "Bremerton Airport",       148),
    ("KTIW", "Tacoma Narrows Airport",   93),
    ("KENW", "Enumclaw Airport",        202),
]

# ── BASELINES for % of normal (30-year median SWE at Apr 1) ──────────
BASELINES = {
    679:  50.3,   # Paradise
    1085: 46.0,   # Cayuse Pass
    942:  28.0,   # Burnt Mountain
    943:  36.0,   # Dungeness
    1107: 42.0,   # Buckinghorse
    774:  25.4,   # Snoqualmie Pass
    778:  40.8,   # Stevens Pass
    780:  40.9,   # Stampede Pass
    910:  22.0,   # Elbow Lake
    375:  38.0,   # Bumping Ridge
    418:  52.0,   # Corral Pass
}

OUTPUT_SNOTEL = "snotel_data.csv"
OUTPUT_VALLEY = "valley_data.csv"
REPORT_BASE   = "https://wcc.sc.egov.usda.gov/reportGenerator/view_csv/customSingleStationReport/daily"


def fetch_snotel(site_num, state, name, massif, elev_ft, target_date):
    date_str = target_date.strftime("%Y-%m-%d")
    triplet  = f"{site_num}:{state}:SNTL"
    # Fetch SWE, Tmax, Tmin, Precip (PCTMEDIAN is invalid — compute locally)
    elements = "WTEQ::value,TMAX::value,TMIN::value,PREC::value"
    url = (f"{REPORT_BASE}/"
           f"{urllib.parse.quote(triplet, safe=':')}"
           f"/{date_str},{date_str}/{elements}")

    print(f"  {triplet} - {name}...", end=" ", flush=True)

    result = {
        "id": triplet, "name": name, "massif": massif,
        "elev_ft": elev_ft, "date": date_str,
        "swe": 0.0, "swe_pct": 0.0,
        "tmax": 32.0, "tmin": 28.0, "precip": 0.0,
    }

    try:
        req = urllib.request.Request(url,
            headers={"User-Agent": "cascadia-wx/1.0 (github.com/bdgroves/cascadia-wx)"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"ERROR: {e}")
        return result

    # Parse CSV — skip # comment lines, find data row
    def safe(v, default=0.0):
        try: return float(v.strip()) if v.strip() else default
        except: return default

    for line in raw.split('\n'):
        if line.startswith('#') or not line.strip():
            continue
        parts = line.split(',')
        if len(parts) >= 2 and '-' in parts[0]:
            # Date, WTEQ, TMAX, TMIN, PREC
            result["swe"]    = safe(parts[1] if len(parts) > 1 else '', 0.0)
            result["tmax"]   = safe(parts[2] if len(parts) > 2 else '', 32.0)
            result["tmin"]   = safe(parts[3] if len(parts) > 3 else '', 28.0)
            result["precip"] = safe(parts[4] if len(parts) > 4 else '', 0.0)
            break

    # Compute % of normal from local baselines
    median = BASELINES.get(site_num, 0.0)
    if median > 0 and result["swe"] > 0:
        result["swe_pct"] = (result["swe"] / median) * 100.0

    print(f"SWE={result['swe']:.1f}\" ({result['swe_pct']:.0f}%) "
          f"T={result['tmax']:.0f}/{result['tmin']:.0f}F")
    return result


def fetch_noaa(station_id, name, elev_m):
    url = f"https://api.weather.gov/stations/{station_id}/observations/latest"
    print(f"  {station_id} - {name}...", end=" ", flush=True)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "cascadia-wx/1.0",
            "Accept": "application/geo+json"})
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read())
        temp = data["properties"]["temperature"]["value"]
        if temp is None: raise ValueError("null temp")
        print(f"{float(temp):.1f}C")
        return {"name": name, "elev_m": elev_m, "temp_c": float(temp)}
    except Exception as e:
        default = 10.0 - elev_m * 0.0065
        print(f"ERROR ({e}) — using {default:.1f}C estimate")
        return {"name": name, "elev_m": elev_m, "temp_c": default}


def main():
    now    = datetime.now(timezone.utc)
    target = now - timedelta(days=1)
    print(f"CASCADIA-WX FETCH  //  {now.strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"Target date: {target.strftime('%Y-%m-%d')}\n")
    print(f"Fetching {len(SNOTEL_SITES)} SNOTEL stations...\n")

    records = []
    for site_num, state, name, massif, elev_ft in SNOTEL_SITES:
        r = fetch_snotel(site_num, state, name, massif, elev_ft, target)
        records.append(r)

    fields = ["id","name","massif","elev_ft","swe","swe_pct","tmax","tmin","precip","date"]
    with open(OUTPUT_SNOTEL, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader(); w.writerows(records)
    print(f"\nWrote {len(records)} records to {OUTPUT_SNOTEL}")

    print(f"\nFetching {len(VALLEY_STATIONS)} valley stations...\n")
    valley = [fetch_noaa(s, n, e) for s, n, e in VALLEY_STATIONS]
    with open(OUTPUT_VALLEY, "w", newline="") as f:
        f.write("name,elev_m,temp_c\n")
        for r in valley:
            f.write(f"{r['name']},{r['elev_m']},{r['temp_c']:.1f}\n")
    print(f"Wrote {len(valley)} records to {OUTPUT_VALLEY}")
    print("Fetch complete. Ready for CASCADIA-WX.")

if __name__ == "__main__":
    main()
