"""Probe NOAA CO-OPS for a Puget Sound tides project: stations, constituents, datums, data limits."""
import json, os, time, urllib.request, urllib.parse
OUT = "tools/probe_out_tides"; os.makedirs(OUT, exist_ok=True)
log = []
def get(url, name, keep=True):
    t = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "puget-tides probe (github.com/bdgroves)"})
        b = urllib.request.urlopen(req, timeout=120).read()
        if keep: open(f"{OUT}/{name}", "wb").write(b)
        log.append(f"{name}: {len(b)} bytes {time.time()-t:.1f}s")
        return b
    except Exception as e:  # noqa: BLE001
        log.append(f"{name}: FAILED {e} {time.time()-t:.1f}s")
        return b""
MD = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi"
DG = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
b = get(f"{MD}/stations.json?type=waterlevels", "stations_all.json", keep=False)
try:
    st = json.loads(b)["stations"]
    wa = [s for s in st if s.get("state") == "WA"]
    open(f"{OUT}/stations_wa.json", "w").write(json.dumps(wa, indent=1))
    log.append(f"WA water-level stations: {len(wa)}")
except Exception as e:  # noqa: BLE001
    log.append(f"stations parse: {e}")
CAND = ["9447130", "9446484", "9444900", "9449880", "9443090", "9444090", "9449424", "9446807", "9445958", "9447659", "9446969"]
for sid in CAND:
    get(f"{MD}/stations/{sid}.json?expand=details,datums,harcon,products,disclaimers", f"st_{sid}.json")
    get(f"{MD}/stations/{sid}/harcon.json?units=english", f"harcon_{sid}.json")
    get(f"{MD}/stations/{sid}/datums.json?units=english", f"datums_{sid}.json")
def dg(name, **q):
    q.setdefault("application", "puget-tides"); q.setdefault("format", "csv"); q.setdefault("time_zone", "gmt")
    q.setdefault("units", "english"); q.setdefault("datum", "MLLW")
    return get(f"{DG}?{urllib.parse.urlencode(q)}", name)
S = "9447130"
dg("wl_6min_31d.csv", station=S, product="water_level", begin_date="20260901", end_date="20261001")
dg("wl_6min_60d.csv", station=S, product="water_level", begin_date="20260801", end_date="20261001")
dg("pred_6min_31d.csv", station=S, product="predictions", begin_date="20260901", end_date="20261001")
dg("pred_hilo_1y.csv", station=S, product="predictions", interval="hilo", begin_date="20260101", end_date="20261231")
dg("pred_hilo_2y.csv", station=S, product="predictions", interval="hilo", begin_date="20260101", end_date="20271231")
dg("hourly_1y.csv", station=S, product="hourly_height", begin_date="20200101", end_date="20201231")
dg("hourly_1991.csv", station=S, product="hourly_height", begin_date="19910101", end_date="19911231")
dg("hilo_obs_1y.csv", station=S, product="high_low", begin_date="20250101", end_date="20251231")
dg("monthly_mean_all.csv", station=S, product="monthly_mean", begin_date="18980101", end_date="20261001")
dg("monthly_mean_10y.csv", station=S, product="monthly_mean", begin_date="20160101", end_date="20261001")
dg("daily_mean.csv", station=S, product="daily_mean", begin_date="20250101", end_date="20251231")
dg("air_pressure.csv", station=S, product="air_pressure", begin_date="20260925", end_date="20261003")
dg("wind.csv", station=S, product="wind", begin_date="20260925", end_date="20261003")
dg("water_temp.csv", station=S, product="water_temperature", begin_date="20260925", end_date="20261003")
dg("latest.csv", station=S, product="water_level", date="latest")
dg("recent.csv", station=S, product="water_level", date="recent")
dg("wl_tacoma.csv", station="9446484", product="water_level", date="recent")
dg("wl_neah.csv", station="9443090", product="water_level", date="recent")
dg("wl_fh.csv", station="9449880", product="water_level", date="recent")
dg("wl_pt.csv", station="9444900", product="water_level", date="recent")
get(f"https://api.tidesandcurrents.noaa.gov/dpapi/prod/webapi/product/sealvltrends.json?station={S}", "slt.json")
get(f"https://api.tidesandcurrents.noaa.gov/dpapi/prod/webapi/htf/htf_annual.json?station={S}", "htf_annual.json")
get(f"https://api.tidesandcurrents.noaa.gov/dpapi/prod/webapi/product/toptenwaterlevels.json?station={S}", "topten.json")
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n")
print("\n".join(log))
