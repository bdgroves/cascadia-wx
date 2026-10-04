"""Probe 5: basis of record for iDigBio records at IceWave's west training coordinates."""
import json, urllib.parse, urllib.request
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "fossil probe (github.com/bdgroves)"}
pts = [(47.668428, -122.350877), (47.957611, -124.366025), (47.802448, -124.104813), (47.880310, -124.180557), (47.3806, -121.6453),
       (48.073572, -123.089484), (48.610969, -122.986114), (44.9, -122.8), (45.1, -122.8), (45.2, -123.0), (42.4, -123.1), (46.6542, -120.5289)]
for lat, lon in pts:
    rq = {"geopoint": {"type": "geo_bounding_box", "top_left": {"lat": lat + 0.001, "lon": lon - 0.001}, "bottom_right": {"lat": lat - 0.001, "lon": lon + 0.001}},
          "genus": ["mammuthus", "mammut", "bison", "equus", "camelops", "paramylodon", "arctodus", "cervus"]}
    try:
        with urllib.request.urlopen(urllib.request.Request("https://search.idigbio.org/v2/search/records?" + urllib.parse.urlencode({"rq": json.dumps(rq), "limit": 50}), headers=UA), timeout=60) as r:
            d = json.loads(r.read())
    except Exception as e:
        p(lat, lon, "ERR", e); continue
    for it in d.get("items", [])[:8]:
        t, dd = it["indexTerms"], it.get("data", {})
        p(lat, lon, t.get("genus"), t.get("basisofrecord"), t.get("institutioncode"), t.get("collectioncode"), (dd.get("dwc:locality") or "")[:70], dd.get("dwc:year"), (dd.get("dwc:earliestEpochOrLowestSeries") or ""))
