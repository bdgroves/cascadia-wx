import time, urllib.request, urllib.parse, csv, io
from pathlib import Path
OUT = Path("tools/probe_out"); OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "cascadia-wx probe"}
IEM = "https://mesonet.agron.iastate.edu/cgi-bin/request/raob.py"
log = []
for sta in ("KUIL", "KSLE", "KOTX", "KMFR"):
    for sts, ets in (("1991-01-01T00:00Z", "1991-02-01T00:00Z"), ("2005-07-01T00:00Z", "2005-08-01T00:00Z"),
                     ("2026-09-01T00:00Z", "2026-10-03T23:00Z")):
        t0 = time.time()
        try:
            url = IEM + "?" + urllib.parse.urlencode({"station": sta, "sts": sts, "ets": ets})
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r:
                b = r.read()
            rows = list(csv.DictReader(io.StringIO(b.decode())))
            keys = {x["validUTC"] for x in rows}
            tops = {}
            for x in rows:
                if x["pressure_mb"] not in ("M", ""):
                    k = x["validUTC"]; tops[k] = min(tops.get(k, 2000), float(x["pressure_mb"]))
            td = sum(1 for x in rows if x["dwpc"] not in ("M", ""))
            wd = sum(1 for x in rows if x["drct"] not in ("M", ""))
            log.append(f"{sta} {sts[:7]}: {len(b)/1e6:.1f} MB {time.time()-t0:.1f}s, {len(keys)} soundings, {len(rows)} levels, "
                       f"td {td}, wind {wd}, reaching 300 hPa: {sum(1 for v in tops.values() if v <= 300)}")
        except Exception as e:
            log.append(f"{sta} {sts[:7]}: ERR {e}")
(OUT / "timing.txt").write_text("\n".join(log) + "\n"); print("\n".join(log))
