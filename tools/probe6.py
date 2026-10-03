"""Probe 6: are the recent KOTX/KMFR launch times real? Compare IEM with Wyoming and IEM's JSON."""
import json
import os
import urllib.request

OUT = "tools/probe_out6"
os.makedirs(OUT, exist_ok=True)


def get(url, name):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "cascadia-wx probe (github.com/bdgroves/cascadia-wx)"})
        b = urllib.request.urlopen(req, timeout=90).read()
        open(f"{OUT}/{name}", "wb").write(b)
        return f"{name}: {len(b)} bytes"
    except Exception as e:  # noqa: BLE001
        return f"{name}: FAILED {e}"


log = []
IEM = "https://mesonet.agron.iastate.edu"
for st, wmo in (("KOTX", "72786"), ("KMFR", "72597"), ("KSLE", "72694"), ("KUIL", "72797")):
    # IEM CSV, one recent day and one day in 2020 and 2024
    for d0, d1 in (("2026-09-29T00:00Z", "2026-09-30T00:00Z"), ("2024-07-15T00:00Z", "2024-07-16T00:00Z"),
                   ("2025-06-15T00:00Z", "2025-06-16T00:00Z")):
        log.append(get(f"{IEM}/cgi-bin/request/raob.py?station={st}&sts={d0}&ets={d1}", f"iem_{st}_{d0[:10]}.csv"))
    # IEM JSON for each synoptic hour on Sep 29
    for h in ("00", "06", "12", "18"):
        log.append(get(f"{IEM}/json/raob.py?station={st}&ts=2026-09-29T{h}:00:00Z", f"iemjson_{st}_{h}.json"))
    # University of Wyoming
    for h in ("00", "12", "18"):
        log.append(get(f"https://weather.uwyo.edu/wsgi/sounding?datetime=2026-09-29%20{h}:00:00&id={wmo}&src=UNKNOWN&type=TEXT:LIST",
                       f"uwyo_{st}_{h}.txt"))
# NWS/NCEI IGRA2 recent-data file list for Spokane
log.append(get("https://www.ncei.noaa.gov/data/integrated-global-radiosonde-archive/access/data-y2d/", "igra_y2d_index.html"))
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n")
print("\n".join(log))
