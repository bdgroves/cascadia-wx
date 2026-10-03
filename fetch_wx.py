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


M = lambda v: "" if v in ("M", "", None) else v   # noqa: E731
RAW_COLS = ["key", "station", "p", "z", "t", "td", "dir", "kt"]


def iem_levels(station, start, stop):
    """Every level of every sounding at station between start and stop (UTC), as raw rows."""
    q = urllib.parse.urlencode({"station": station, "sts": start.strftime("%Y-%m-%dT%H:%MZ"),
                                "ets": stop.strftime("%Y-%m-%dT%H:%MZ")})
    text = http(f"{IEM}?{q}", timeout=120).decode()
    rows = []
    for r in csv.DictReader(text.splitlines()):
        t = r["validUTC"]                      # 2026-10-02 12:00:00
        rows.append(dict(key=t[0:4] + t[5:7] + t[8:10] + t[11:13], station=station,
                         p=M(r["pressure_mb"]), z=M(r["height_m"]), t=M(r["tmpc"]),
                         td=M(r["dwpc"]), dir=M(r["drct"]), kt=M(r["speed_kts"])))
    return rows


def soundings(today, status):
    """Every sounding at each balloon site since the last one in sounding_series.csv."""
    series = read_csv("sounding_series.csv")
    last = {}
    for r in series:
        if r.get("station"):
            last[r["station"]] = max(last.get(r["station"], ""), r["key"])
    wy = today.year + 1 if today.month >= 10 else today.year
    first = datetime(wy - 2, 10, 1, tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    rows, failed, counts = [], [], {}
    for b in read_csv("balloons.csv"):
        st = b["id"]
        k = last.get(st)
        since = datetime(int(k[:4]), int(k[4:6]), int(k[6:8]), int(k[8:10]), tzinfo=timezone.utc) if k else first
        got, chunk = [], since
        try:
            while chunk < now:
                stop = min(chunk + timedelta(days=31), now + timedelta(hours=1))
                got += iem_levels(st, chunk, stop)
                chunk = stop
        except Exception as e:           # noqa: BLE001
            failed.append(st)
            print(f"  {st:<5} {b['name']:<11} FAILED: {str(e)[:80]}")
        got = [r for r in got if r["key"] >= since.strftime("%Y%m%d%H")]
        keys = {r["key"] for r in got}
        counts[st] = len(keys)
        rows += got
        print(f"  {st:<5} {b['name']:<11} {len(keys):4d} soundings since {since:%Y-%m-%d %HZ}"
              + (f", latest {max(keys)}" if keys else ""))
    rows.sort(key=lambda r: (r["station"], r["key"], -float(r["p"] or 0)))
    write_csv("soundings_raw.csv", RAW_COLS, rows)
    status["soundings_fetched"] = sum(counts.values())
    if failed:
        status["sounding_error"] = " ".join(failed)


def history(y0=1991, y1=2020):
    """Thirty years of soundings for NORMALS.f90: history/<site>_<year>.csv, listed in files.txt.
    00Z and 12Z launches only; about 720 MB, so it is downloaded only to rebuild the normals."""
    from concurrent.futures import ThreadPoolExecutor
    os.makedirs("history", exist_ok=True)
    jobs = [(b["id"], y) for b in read_csv("balloons.csv") for y in range(y0, y1 + 1)]

    def one(job):
        st, y = job
        path = f"history/{st}_{y}.csv"
        if os.path.exists(path):
            return path, "cached"
        rows = []
        for m in range(1, 13):
            a = datetime(y, m, 1, tzinfo=timezone.utc)
            z = datetime(y + (m == 12), m % 12 + 1, 1, tzinfo=timezone.utc)
            rows += [r for r in iem_levels(st, a, z) if r["key"][8:10] in ("00", "12")]
        rows.sort(key=lambda r: (r["key"], -float(r["p"] or 0)))
        write_csv(path, RAW_COLS, rows)
        return path, f"{len({r['key'] for r in rows})} soundings"

    with ThreadPoolExecutor(4) as pool:
        done = list(pool.map(one, jobs))
    for path, note in done:
        print(f"  {path}: {note}")
    with open("history/files.txt", "w") as f:
        f.write("\n".join(os.path.basename(p) for p, _ in done) + "\n")


def main():
    if "--history" in sys.argv:
        print("CASCADIA-WX HISTORY  NWS soundings 1991-2020")
        history()
        return
    now = datetime.now(timezone.utc)
    today = pacific_today(now)
    print(f"CASCADIA-WX FETCH  {now:%Y-%m-%d %H:%M} UTC  (Pacific date {today})")
    status = {"run_utc": now.strftime("%Y-%m-%d %H:%M"),
              "pacific_date": str(today)}
    print("NRCS SNOTEL")
    snotel(today, status)
    print("NWS radiosondes")
    soundings(today, status)
    with open("fetch_status.csv", "w", newline="") as f:
        f.write("key,value\n")
        for k, v in status.items():
            f.write(f"{k},{v}\n")
    # exit 4 = some data missing (the job carries on and flags it)
    sys.exit(4 if status.get("snotel_failed") or status.get("sounding_error") else 0)


if __name__ == "__main__":
    main()
