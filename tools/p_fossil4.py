"""Probe 4: WA DNR 100k fossil points; iDigBio WA megafauna; PBDB WA/OR large mammals with precision."""
import json, urllib.parse, urllib.request
from collections import Counter
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "fossil rebuild probe (github.com/bdgroves)"}
def js(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            return json.loads(r.read())
    except Exception as e:
        p("  ERR", e, url[:150]); return None
B = "https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/100K_Surface_Geology_WA_GeMS/MapServer/4/query?"
d = js(B + "where=1%3D1&returnCountOnly=true&f=json"); p("fossil points", d)
d = js(B + urllib.parse.urlencode({"where": "1=1", "outFields": "*", "returnGeometry": "true", "outSR": 4326, "f": "json", "resultRecordCount": 2000}))
feats = (d or {}).get("features", [])
p("got", len(feats))
p("types", Counter(f["attributes"].get("FOSSIL_100K_TYPE") for f in feats).most_common(20))
kw = ("mammoth", "mammuthus", "bison", "horse", "equus", "camel", "mastodon", "sloth", "vertebrate", "bone", "tooth", "tusk", "mammal", "elephant", "proboscid")
for f in feats:
    a = f["attributes"]; txt = json.dumps(a).lower()
    if any(k in txt for k in kw):
        p("  ", f["geometry"], {k: v for k, v in a.items() if v not in (None, "", " ") and k in ("FOSSIL_100K_TYPE", "FOSSIL_100K_DESC", "FOSSIL_100K_MAP_UNIT", "FOSSIL_100K_LOC_CONFIDENCE_M", "FOSSIL_100K_NOTES", "FOSSIL_100K_TAXA", "FOSSIL_100K_AGE")})
p("fields", list(feats[0]["attributes"].keys()) if feats else None)
q = {"stateprovince": "washington", "geopoint": {"type": "exists"}, "genus": ["mammuthus", "mammut", "bison", "equus", "camelops", "paramylodon", "megalonyx", "arctodus", "bootherium", "cervus", "rangifer"]}
d = js("https://search.idigbio.org/v2/search/records?" + urllib.parse.urlencode({"rq": json.dumps(q), "limit": 500}))
items = (d or {}).get("items", [])
p("idigbio WA megafauna", (d or {}).get("itemCount"), len(items))
p("  genus", Counter(i["indexTerms"].get("genus") for i in items).most_common())
p("  uncertainty", Counter(str(i["indexTerms"].get("coordinateuncertaintyinmeters")) for i in items).most_common(10))
pts = Counter((round(i["indexTerms"]["geopoint"]["lat"], 3), round(i["indexTerms"]["geopoint"]["lon"], 3)) for i in items)
p("  distinct points", len(pts), pts.most_common(10))
for i in items[:400]:
    t = i["indexTerms"]; dd = i.get("data", {})
    p("   ", t.get("genus"), round(t["geopoint"]["lat"], 4), round(t["geopoint"]["lon"], 4), t.get("county"), t.get("institutioncode"), t.get("coordinateuncertaintyinmeters"), (dd.get("dwc:locality") or "")[:80])
d = js("https://paleobiodb.org/data1.2/occs/list.json?" + urllib.parse.urlencode({"state": "Washington", "interval": "Pleistocene", "base_name": "Mammalia", "show": "coords,loc,prec,strat", "vocab": "pbdb", "limit": "all"}))
for r in (d or {}).get("records", []):
    p("  pbdb", r.get("accepted_name"), r.get("lat"), r.get("lng"), r.get("latlng_precision"), r.get("county"), r.get("formation"), r.get("geogscale"))
