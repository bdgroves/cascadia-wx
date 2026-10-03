"""Probe 2: a year of NOAA hourly predictions at two stations and two years, to check M1 and the rest."""
import os, urllib.request, urllib.parse
OUT = "tools/probe_out_tides2"; os.makedirs(OUT, exist_ok=True)
DG = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
log = []
for sid in ("9447130", "9443090"):
    for y in (2026, 2020):
        q = dict(station=sid, product="predictions", interval="h", begin_date=f"{y}0101", end_date=f"{y}1231 23:00",
                 datum="MLLW", units="english", time_zone="gmt", format="csv", application="puget-tides")
        try:
            b = urllib.request.urlopen(f"{DG}?{urllib.parse.urlencode(q)}", timeout=120).read()
            open(f"{OUT}/pred_h_{sid}_{y}.csv", "wb").write(b); log.append(f"{sid} {y}: {len(b)}")
        except Exception as e:  # noqa: BLE001
            log.append(f"{sid} {y}: FAILED {e}")
q = dict(station="9447130", product="predictions", interval="hilo", begin_date="20260101", end_date="20261231",
         datum="MLLW", units="english", time_zone="gmt", format="csv", application="puget-tides")
open(f"{OUT}/hilo_9447130_2026.csv", "wb").write(urllib.request.urlopen(f"{DG}?{urllib.parse.urlencode(q)}", timeout=120).read())
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n"); print("\n".join(log))
