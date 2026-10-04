"""Probe 3: WA DNR 100k geology (GeMS), aggregate resources, mine fields; iDigBio WA megafauna precision."""
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
B = "https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/"
for svc in ["100K_Surface_Geology_WA_GeMS/MapServer", "Aggregate_Resources/MapServer", "Active_Surface_Mine_Permit_Sites/MapServer/0"]:
    d = js(B + svc + "?f=json")
    if not d: continue
    p("==", svc, [(l["id"], l["name"]) for l in d.get("layers", [])][:30], [f["name"] for f in d.get("fields", []) or []])
d = js(B + "100K_Surface_Geology_WA_GeMS/MapServer/identify?" + urllib.parse.urlencode({"geometry": "-119.266,46.159", "geometryType": "esriGeometryPoint", "sr": 4326, "layers": "all", "tolerance": 2, "mapExtent": "-119.3,46.1,-119.2,46.2", "imageDisplay": "400,400,96", "returnGeometry": "false", "f": "json"}))
for r in (d or {}).get("results", [])[:8]:
    p("  identify Coyote Canyon:", r.get("layerId"), r.get("layerName"), {k: v for k, v in r.get("attributes", {}).items() if v not in (None, "", "Null")})
for lid in range(0, 12):
    d = js(B + f"100K_Surface_Geology_WA_GeMS/MapServer/{lid}?f=json")
    if d and d.get("type") in ("Feature Layer",):
        p("  layer", lid, d.get("name"), d.get("geometryType"), [f["name"] for f in d.get("fields", [])][:25], "maxRec", d.get("maxRecordCount"))
d = js(B + "Active_Surface_Mine_Permit_Sites/MapServer/0/query?where=1%3D1&outFields=COMMODITY_DESC,COUNTY_NAME&returnGeometry=false&f=json&resultRecordCount=2000")
p("  mine commodities", Counter(f["attributes"]["COMMODITY_DESC"] for f in (d or {}).get("features", [])).most_common(12))
p("  mine counties", Counter(f["attributes"]["COUNTY_NAME"] for f in (d or {}).get("features", [])).most_common(40))
q = {"stateprovince": "washington", "geopoint": {"type": "exists"}, "genus": ["mammuthus", "mammut", "bison", "equus", "camelops", "paramylodon", "megalonyx", "arctodus", "bootherium", "cervus", "rangifer", "ovibos"]}
d = js("https://search.idigbio.org/v2/search/records?" + urllib.parse.urlencode({"rq": json.dumps(q), "limit": 500, "fields": json.dumps(["genus", "geopoint", "coordinateuncertaintyinmeters", "locality", "county", "institutioncode", "occurrenceid", "verbatimlocality"])}))
items = (d or {}).get("items", [])
p("  idigbio WA megafauna", (d or {}).get("itemCount"), len(items))
p("  genus", Counter(i["indexTerms"].get("genus") for i in items).most_common())
p("  uncertainty", Counter(str(i["indexTerms"].get("coordinateuncertaintyinmeters")) for i in items).most_common(10))
p("  distinct points", len({(round(i["indexTerms"]["geopoint"]["lat"], 4), round(i["indexTerms"]["geopoint"]["lon"], 4)) for i in items}))
for i in items[:60]:
    t = i["indexTerms"]
    p("   ", t.get("genus"), t["geopoint"], t.get("county"), t.get("institutioncode"), (t.get("locality") or "")[:90])
