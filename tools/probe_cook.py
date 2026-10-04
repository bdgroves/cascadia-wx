"""Probe: find public-domain scans of Cook's 1770 chart of New Zealand and Tasman's chart on Wikimedia Commons."""
import json, os, urllib.request, urllib.parse
OUT = "tools/probe_out_cook"; os.makedirs(OUT, exist_ok=True)
API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "30DayMapChallenge-2026 (github.com/bdgroves/30DayMapChallenge; brooksgroves.com)"}
def api(**q):
    q.update(format="json")
    return json.loads(urllib.request.urlopen(urllib.request.Request(f"{API}?{urllib.parse.urlencode(q)}", headers=UA), timeout=60).read())
log = []
found = {}
for term in ("Chart of New Zealand explored in 1769 and 1770", "Cook chart New Zealand 1770 Endeavour", "Cook New Zealand chart 1772",
             "Tasman 1642 New Zealand chart", "Staten Landt Tasman", "Tasman map 1644 Bonaparte"):
    r = api(action="query", list="search", srsearch=term, srnamespace=6, srlimit=12)
    for h in r["query"]["search"]:
        found.setdefault(h["title"], term)
titles = list(found)
info = {}
for i in range(0, len(titles), 40):
    r = api(action="query", prop="imageinfo", iiprop="url|size|extmetadata|mime", iiurlwidth=1600, titles="|".join(titles[i:i+40]))
    for p in r["query"]["pages"].values():
        ii = (p.get("imageinfo") or [{}])[0]
        md = ii.get("extmetadata", {})
        info[p["title"]] = dict(url=ii.get("url"), thumb=ii.get("thumburl"), w=ii.get("width"), h=ii.get("height"), mime=ii.get("mime"),
                                license=md.get("LicenseShortName", {}).get("value"), date=md.get("DateTimeOriginal", {}).get("value", "")[:80],
                                artist=md.get("Artist", {}).get("value", "")[:120], desc=md.get("ImageDescription", {}).get("value", "")[:240], term=found[p["title"]])
json.dump(info, open(f"{OUT}/candidates.json", "w"), indent=1)
# thumbnails of the likely ones, for a look
k = 0
for t, d in sorted(info.items(), key=lambda kv: -(kv[1]["w"] or 0)):
    if not d["thumb"] or d["mime"] not in ("image/jpeg", "image/png", "image/tiff"):
        continue
    if not any(w in t.lower() for w in ("zealand", "tasman", "staten", "cook")):
        continue
    try:
        b = urllib.request.urlopen(urllib.request.Request(d["thumb"], headers=UA), timeout=120).read()
        open(f"{OUT}/thumb_{k:02d}.jpg", "wb").write(b); log.append(f"thumb_{k:02d}: {t} {d['w']}x{d['h']} {d['license']} | {d['date']}")
        k += 1
    except Exception as e:  # noqa: BLE001
        log.append(f"FAILED {t}: {e}")
    if k >= 16:
        break
open(f"{OUT}/log.txt", "w").write("\n".join(log) + "\n"); print("\n".join(log))
