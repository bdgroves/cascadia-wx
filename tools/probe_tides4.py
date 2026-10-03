"""Probe 4: Seattle's highest water, Dec 27 2022 and Jan 27 1983, in NOAA's verified data."""
import os, urllib.request, urllib.parse
OUT = "tools/probe_out_tides4"; os.makedirs(OUT, exist_ok=True)
DG = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
log = []
for name, prod, a, b in (("sea_20221227.csv", "water_level", "20221227", "20221227"),
                         ("sea_19830127.csv", "hourly_height", "19830126", "19830128"),
                         ("sea_hilo_2022.csv", "high_low", "20221226", "20221228"),
                         ("pred_20221227.csv", "predictions", "20221227", "20221227")):
    q = dict(station="9447130", product=prod, begin_date=a, end_date=b, datum="MLLW", units="english",
             time_zone="gmt", format="csv", application="puget-tides")
    try:
        t = urllib.request.urlopen(f"{DG}?{urllib.parse.urlencode(q)}", timeout=120).read().decode()
        open(f"{OUT}/{name}", "w").write(t)
        rows = [l.split(",") for l in t.splitlines()[1:] if l.strip()]
        best = max(rows, key=lambda r: float(r[1]) if r[1].strip() else -99)
        log.append(f"{name}: {len(rows)} rows, max {best[0]} {best[1]}")
    except Exception as e:  # noqa: BLE001
        log.append(f"{name}: FAILED {e}")
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n"); print("\n".join(log))
