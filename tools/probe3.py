import time, urllib.request, urllib.parse, json
from pathlib import Path
OUT = Path("tools/probe_out"); OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "cascadia-wx probe (github.com/bdgroves/cascadia-wx)"}
log = []
def t(name, url, timeout=600):
    t0 = time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
            b = r.read()
        log.append(f"{name}: OK {len(b)} bytes in {time.time()-t0:.1f}s")
        return b
    except Exception as e:
        log.append(f"{name}: ERR {e} after {time.time()-t0:.1f}s")
IEM = "https://mesonet.agron.iastate.edu/cgi-bin/request/raob.py"
t("iem_7d", IEM + "?" + urllib.parse.urlencode({"station":"KUIL","sts":"2026-09-26T00:00Z","ets":"2026-10-03T00:00Z"}))
t("iem_31d", IEM + "?" + urllib.parse.urlencode({"station":"KUIL","sts":"2026-01-01T00:00Z","ets":"2026-02-01T00:00Z"}))
AW = "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/data"
t("awdb_paradise", AW + "?" + urllib.parse.urlencode({"stationTriplets":"679:WA:SNTL","elements":"WTEQ","duration":"DAILY","beginDate":"2026-09-25","endDate":"2026-10-03"}), 60)
(OUT / "timing.txt").write_text("\n".join(log) + "\n")
print("\n".join(log))
