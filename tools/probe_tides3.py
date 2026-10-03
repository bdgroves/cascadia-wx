"""Probe 3: what history Bremerton has, and whether Seattle's 403s were rate limiting."""
import os, time, urllib.request, urllib.parse
OUT = "tools/probe_out_tides3"; os.makedirs(OUT, exist_ok=True)
DG = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
log = []
def dg(name, **q):
    q.update(datum="MLLW", units="english", time_zone="gmt", format="csv", application="puget-tides")
    try:
        b = urllib.request.urlopen(f"{DG}?{urllib.parse.urlencode(q)}", timeout=120).read()
        open(f"{OUT}/{name}", "wb").write(b); t = b.decode()[:160].replace("\n", " | ")
        log.append(f"{name}: {len(b)} bytes  {t}")
    except Exception as e:  # noqa: BLE001
        log.append(f"{name}: FAILED {e}")
    time.sleep(1)
for y in (1992, 1998, 2005, 2010, 2015, 2019, 2021, 2023):
    dg(f"brem_hourly_{y}.csv", station="9445958", product="hourly_height", begin_date=f"{y}0101", end_date=f"{y}0131")
    dg(f"brem_6min_{y}.csv", station="9445958", product="water_level", begin_date=f"{y}0101", end_date=f"{y}0131")
dg("brem_monthly.csv", station="9445958", product="monthly_mean", begin_date="19700101", end_date="20261001")
dg("sea_hourly_2010.csv", station="9447130", product="hourly_height", begin_date="20100101", end_date="20101231")
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n"); print("\n".join(log))
