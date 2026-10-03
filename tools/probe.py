"""Probe NRCS AWDB, the old report generator, NWS obs and IEM soundings. Writes tools/probe_out/."""
import json, urllib.request, urllib.parse, traceback
from pathlib import Path
OUT = Path("tools/probe_out"); OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "cascadia-wx probe (github.com/bdgroves/cascadia-wx)"}
AW = "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1"
IDS = [679, 1085, 942, 943, 1107, 774, 778, 780, 910, 375, 418]

def get(url, name, accept=None):
    h = dict(UA)
    if accept: h["Accept"] = accept
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=90) as r:
            b = r.read()
        (OUT / name).write_bytes(b)
        print("OK", name, len(b))
        return b
    except Exception as e:
        (OUT / (name + ".err")).write_text(f"{url}\n{traceback.format_exc()}")
        print("ERR", name, e)

# all WA + OR SNOTEL station metadata
get(f"{AW}/stations?stationTriplets=*:WA:SNTL&returnStationElements=false", "stations_wa.json")
trip = ",".join(f"{i}:WA:SNTL" for i in IDS)
get(f"{AW}/stations?stationTriplets={trip}&returnStationElements=true", "stations_ours.json")
# recent data with medians
get(f"{AW}/data?stationTriplets={trip}&elements=WTEQ,PREC,TAVG,TMAX,TMIN,SNWD&duration=DAILY"
    f"&beginDate=2026-09-25&endDate=2026-10-03&centralTendencyType=MEDIAN", "data_recent.json")
# what April 2 2026 really looked like
get(f"{AW}/data?stationTriplets={trip}&elements=WTEQ&duration=DAILY&beginDate=2026-03-25&endDate=2026-04-05"
    f"&centralTendencyType=MEDIAN", "data_april.json")
# period of record for one station (size check)
get(f"{AW}/data?stationTriplets=679:WA:SNTL&elements=WTEQ&duration=DAILY&beginDate=1990-10-01&endDate=2026-10-02",
    "data_paradise_por.json")
# the old endpoint for a 'bad' station
for i in (774, 778, 780, 679):
    get(f"https://wcc.sc.egov.usda.gov/reportGenerator/view_csv/customSingleStationReport/daily/{i}:WA:SNTL"
        f"/2026-04-02,2026-04-02/WTEQ::value,TMAX::value,TMIN::value,PREC::value", f"rg_{i}.csv")
# NWS latest obs
for s in ("KSEA", "KPWT", "KTIW", "KENW"):
    get(f"https://api.weather.gov/stations/{s}/observations/latest", f"nws_{s}.json", "application/geo+json")
# soundings: IEM RAOB json, Quillayute and Salem
for s, ts in (("KUIL", "202610021200"), ("KUIL", "202610030000"), ("KSLE", "202610021200")):
    get(f"https://mesonet.agron.iastate.edu/json/raob.py?station={s}&ts={ts}", f"raob_{s}_{ts}.json")
get("https://mesonet.agron.iastate.edu/cgi-bin/request/raob.py?station=KUIL&sts=2026-10-01T00:00Z&ets=2026-10-03T00:00Z",
    "raob_csv_KUIL.csv")
get("https://weather.uwyo.edu/wsgi/sounding?datetime=2026-10-02%2012:00:00&id=72797&src=UNKNOWN&type=TEXT:LIST",
    "uwyo_72797.txt")
