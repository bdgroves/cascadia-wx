import time, json, urllib.request, urllib.parse
from pathlib import Path
OUT = Path("tools/probe_out"); OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "30DayMapChallenge-2026 probe"}
log = []
def t(name, url, timeout=120):
    t0 = time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
            b = r.read()
        js = json.loads(b)
        log.append(f"{name}: OK {len(b)} bytes {time.time()-t0:.1f}s count={js.get('count')} n={len(js.get('results', []))}")
    except Exception as e:
        log.append(f"{name}: ERR {e} {time.time()-t0:.1f}s")
A = "https://api.gbif.org/v1/occurrence/search?"
base = dict(genusKey=2439509, hasCoordinate="true", hasGeospatialIssue="false", occurrenceStatus="PRESENT")
t("count_all", A + urllib.parse.urlencode(dict(limit=0, **base)))
for y in ("1800,1913", "1914,2026", "1800,1960", "1961,2026"):
    t(f"count {y}", A + urllib.parse.urlencode(dict(limit=0, year=y, **base)))
for off in (0, 30000, 60000, 90000):
    t(f"page off={off}", A + urllib.parse.urlencode(dict(limit=300, offset=off, year="1914,2026", **base)))
(OUT / "timing.txt").write_text("\n".join(log) + "\n"); print("\n".join(log))
