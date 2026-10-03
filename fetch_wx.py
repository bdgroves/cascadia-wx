#!/usr/bin/env python3
"""
fetch_wx.py - the CASCADIA-WX data fetcher. Python standard library only.

It fetches and tidies the data. All the science is done by CASCADIA-WX.f90.

  python3 fetch_wx.py            daily run

Writes:
  snotel_daily.csv    one row per station per day, from Oct 1 of last water
                      year to today: SWE, snow depth, water-year precip and
                      daily temperatures, with NRCS's 1991-2020 median SWE
                      and precip for each calendar day.
  soundings_raw.csv   every Quillayute (KUIL) weather-balloon level since the
                      last sounding CASCADIA-WX processed (on the first run,
                      since Oct 1 of last water year). Not committed.
  fetch_status.csv    what was fetched, what failed, and today's date in
                      Pacific time, so the FORTRAN can flag stale data.

Sources:
  NRCS AWDB REST API   wcc.sc.egov.usda.gov/awdbRestApi  (SNOTEL, no key)
  Iowa Environmental Mesonet RAOB archive (NWS radiosondes, no key)

If a station can't be fetched, its rows from the last good run are kept and
the failure is recorded. Nothing is ever filled in with made-up values.
"""
import csv
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

AWDB = "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/data"
IEM = "https://mesonet.agron.iastate.edu/cgi-bin/request/raob.py"
SOUNDING = "KUIL"                      # Quillayute, WA (WMO 72797)
UA = {"User-Agent": "cascadia-wx (github.com/bdgroves/cascadia-wx)"}
ELEMENTS = ["WTEQ", "SNWD", "PREC", "TAVG", "TMAX", "TMIN"]
COLS = ["date", "triplet", "swe", "swe_med", "depth", "prec", "prec_med",
        "tavg", "tmax", "tmin"]


def pacific_today(now_utc):
    """Today's date in Pacific time (DST from the second Sunday of March to
    the first Sunday of November), without needing tz data."""
    y = now_utc.year
    mar = date(y, 3, 8) + timedelta(days=(6 - date(y, 3, 8).weekday()) % 7)
    nov = date(y, 11, 1) + timedelta(days=(6 - date(y, 11, 1).weekday()) % 7)
    start = datetime(y, mar.month, mar.day, 10, tzinfo=timezone.utc)
    end = datetime(y, nov.month, nov.day, 9, tzinfo=timezone.utc)
    off = 7 if start <= now_utc < end else 8
    return (now_utc - timedelta(hours=off)).date()


def http(url, tries=3, timeout=60):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:          # noqa: BLE001
            last = e
            time.sleep(5 * (i + 1))
    raise last


def num(v):
    return f"{float(v):.2f}".rstrip("0").rstrip(".") if isinstance(
        v, (int, float)) and v > -99 else ""


def fetch_station(triplet, start, end):
    """{date: {col: value}} for one station, values and medians."""
    q = urllib.parse.urlencode({
        "stationTriplets": triplet, "elements": ",".join(ELEMENTS),
        "duration": "DAILY", "beginDate": str(start), "endDate": str(end),
        "centralTendencyType": "MEDIAN"})
    payload = json.loads(http(f"{AWDB}?{q}", tries=2, timeout=45))
    rows = {}
    blocks = payload[0].get("data", []) if payload else []
    for b in blocks:
        el = b["stationElement"]["elementCode"]
        for v in b.get("values", []):
            r = rows.setdefault(v["date"][:10], {})
            if el == "WTEQ":
                r["swe"], r["swe_med"] = num(v.get("value")), num(v.get("median"))
            elif el == "PREC":
                r["prec"], r["prec_med"] = num(v.get("value")), num(v.get("median"))
            elif el == "SNWD":
                r["depth"] = num(v.get("value"))
            else:
                r[el.lower()] = num(v.get("value"))
    if not blocks:
        raise ValueError("AWDB returned no data blocks")
    return rows


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path, cols, rows):
    tmp = path + ".tmp"
    with open(tmp, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore",
                           lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)               # atomic: never a half-written file


def snotel(today, status):
    wy = today.year + 1 if today.month >= 10 else today.year
    start = date(wy - 2, 10, 1)          # Oct 1 of last water year
    stations = read_csv("stations.csv")
    old = {}
    for r in read_csv("snotel_daily.csv"):
        old.setdefault(r["triplet"], []).append(r)
    out, ok, failed = [], 0, []
    for s in stations:
        t = s["triplet"]
        try:
            if not ok and len(failed) >= 3:
                # three in a row failed: NRCS is down, don't wait on the rest
                raise RuntimeError("skipped, NRCS not answering")
            rows = fetch_station(t, start, today)
            got = [dict(date=d, triplet=t, **v) for d, v in sorted(rows.items())
                   if any(v.get(k) for k in ("swe", "prec", "tavg", "depth"))]
            if not got:
                raise ValueError("no values in the date range")
            out += got
            ok += 1
            print(f"  {t:<12} {s['name']:<16} {len(got):4d} days, "
                  f"last {got[-1]['date']}")
        except Exception as e:           # noqa: BLE001
            kept = [r for r in old.get(t, []) if r["date"] >= str(start)]
            out += kept
            last = kept[-1]["date"] if kept else "none"
            failed.append(t)
            print(f"  {t:<12} {s['name']:<16} FAILED ({str(e)[:60]}); "
                  f"kept {len(kept)} days from the last run, last {last}")
    write_csv("snotel_daily.csv", COLS, out)
    status["snotel_ok"] = ok
    status["snotel_failed"] = " ".join(failed)
    print(f"  wrote {len(out)} station-days to snotel_daily.csv")


def soundings(today, status):
    """Fetch every KUIL sounding since the last one in sounding_series.csv."""
    series = read_csv("sounding_series.csv")
    if series:
        k = series[-1]["key"]
        since = datetime(int(k[:4]), int(k[4:6]), int(k[6:8]), int(k[8:10]),
                         tzinfo=timezone.utc)
    else:
        wy = today.year + 1 if today.month >= 10 else today.year
        since = datetime(wy - 2, 10, 1, tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    levels, chunk = [], since
    try:
        while chunk < now:
            stop = min(chunk + timedelta(days=31), now + timedelta(hours=1))
            q = urllib.parse.urlencode({
                "station": SOUNDING, "sts": chunk.strftime("%Y-%m-%dT%H:%MZ"),
                "ets": stop.strftime("%Y-%m-%dT%H:%MZ")})
            text = http(f"{IEM}?{q}", timeout=120).decode()
            for r in csv.DictReader(text.splitlines()):
                levels.append(r)
            chunk = stop
    except Exception as e:               # noqa: BLE001
        status["sounding_error"] = str(e)[:80]
        print(f"  {SOUNDING} soundings FAILED: {str(e)[:80]}")
    m = lambda v: "" if v in ("M", "", None) else v   # noqa: E731
    rows, keys = [], set()
    for r in levels:
        t = r["validUTC"]                      # 2026-10-02 12:00:00
        key = t[0:4] + t[5:7] + t[8:10] + t[11:13]
        if key < since.strftime("%Y%m%d%H"):
            continue
        keys.add(key)
        rows.append(dict(key=key, p=m(r["pressure_mb"]), z=m(r["height_m"]),
                         t=m(r["tmpc"]), td=m(r["dwpc"]), dir=m(r["drct"]),
                         kt=m(r["speed_kts"])))
    rows.sort(key=lambda r: (r["key"], -float(r["p"] or 0)))
    write_csv("soundings_raw.csv", ["key", "p", "z", "t", "td", "dir", "kt"], rows)
    status["soundings_fetched"] = len(keys)
    status["sounding_latest"] = max(keys) if keys else ""
    print(f"  {SOUNDING}: {len(keys)} soundings since "
          f"{since:%Y-%m-%d %HZ}, {len(rows)} levels")


def main():
    now = datetime.now(timezone.utc)
    today = pacific_today(now)
    print(f"CASCADIA-WX FETCH  {now:%Y-%m-%d %H:%M} UTC  (Pacific date {today})")
    status = {"run_utc": now.strftime("%Y-%m-%d %H:%M"),
              "pacific_date": str(today)}
    print("NRCS SNOTEL")
    snotel(today, status)
    print("NWS radiosonde, Quillayute")
    soundings(today, status)
    with open("fetch_status.csv", "w", newline="") as f:
        f.write("key,value\n")
        for k, v in status.items():
            f.write(f"{k},{v}\n")
    bad = status["snotel_ok"] == 0
    # exit 4 = some data missing (the job carries on and flags it)
    sys.exit(4 if bad or status.get("snotel_failed") or
             status.get("sounding_error") else 0)


if __name__ == "__main__":
    main()
