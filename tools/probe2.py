import json, urllib.request, traceback
from pathlib import Path
OUT = Path("tools/probe_out"); OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "cascadia-wx probe (github.com/bdgroves/cascadia-wx)", "Origin": "https://brooksgroves.com"}
AW = "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1"
IDS = [679, 1085, 942, 943, 1107, 672, 791, 788, 910, 375, 418, 899]
trip = ",".join(f"{i}:WA:SNTL" for i in IDS)
def get(url, name):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            b = r.read(); hdr = dict(r.headers)
        (OUT / name).write_bytes(b); (OUT / (name + ".hdr")).write_text(json.dumps(hdr, indent=1))
        print("OK", name, len(b))
    except Exception as e:
        body = getattr(e, "read", lambda: b"")()
        (OUT / (name + ".err")).write_text(f"{url}\n{e}\n{body[:3000]!r}")
        print("ERR", name, e)
get(f"{AW}/data?stationTriplets={trip}&elements=WTEQ,PREC,TAVG,TMAX,TMIN,SNWD&duration=DAILY&beginDate=2026-09-25&endDate=2026-10-03", "d_plain.json")
get(f"{AW}/data?stationTriplets={trip}&elements=WTEQ,PREC&duration=DAILY&beginDate=2026-09-25&endDate=2026-10-03&centralTendencyType=MEDIAN", "d_median.json")
get(f"{AW}/data?stationTriplets={trip}&elements=WTEQ,PREC&duration=DAILY&beginDate=2025-10-01&endDate=2026-09-30&centralTendencyType=MEDIAN", "d_wy2026.json")
get(f"{AW}/data?stationTriplets=679:WA:SNTL&elements=WTEQ&duration=DAILY&beginDate=1980-10-01&endDate=2026-10-02", "d_paradise_por.json")
get(f"{AW}/reference-data?referenceLists=elements", "ref.json")
for ts in ("202610030000", "202610031200", "202610021200"):
    get(f"https://mesonet.agron.iastate.edu/json/raob.py?station=KSLE&ts={ts}", f"raob_KSLE_{ts}.json")
get("https://mesonet.agron.iastate.edu/json/raob.py?station=KUIL&ts=202610031200", "raob_KUIL_202610031200.json")
