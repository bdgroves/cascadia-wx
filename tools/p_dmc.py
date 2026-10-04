"""Probe for 30DMC 2026 days 11, 19, 23: what the data endpoints answer."""
import json, os, urllib.parse, urllib.request
OUT = "tools/probe_out.txt"
os.makedirs("tools", exist_ok=True)
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "30DayMapChallenge-2026 probe (github.com/bdgroves)"}
def get(url, data=None, n=4000):
    try:
        req = urllib.request.Request(url, data=data, headers=UA)
        with urllib.request.urlopen(req, timeout=90) as r:
            b = r.read()
        return b
    except Exception as e:
        return f"ERR {e}".encode()
def j(url, data=None):
    b = get(url, data)
    try: return json.loads(b)
    except Exception: p("  not json:", b[:300]); return None

p("=== Pierce County hub search")
for q in ["siren", "AHAB", "lahar", "warning"]:
    js = j("https://gisdata-piercecowa.opendata.arcgis.com/api/search/v1/collections/all/items?" + urllib.parse.urlencode({"q": q, "limit": 25}))
    for f in (js or {}).get("features", []):
        pr = f.get("properties", {})
        p(f"  [{q}] {pr.get('title')} | {pr.get('type')} | {pr.get('url')}")
p("=== ArcGIS Online search")
for q in ["Pierce County sirens", "lahar siren", "AHAB siren", "Mount Rainier lahar hazard zones", "WSDA Agricultural Land Use", "WSDA crop", "hops Washington crop"]:
    js = j("https://www.arcgis.com/sharing/rest/search?" + urllib.parse.urlencode({"q": q, "f": "json", "num": 12}))
    for r in (js or {}).get("results", []):
        p(f"  [{q}] {r.get('title')} | {r.get('type')} | {r.get('owner')} | {r.get('url')} | id {r.get('id')}")
p("=== item e46e3932 (MtRainier_lahar_hazards)")
js = j("https://www.arcgis.com/sharing/rest/content/items/e46e3932e8b54c2b811259c5cd900e18?f=json")
if js: p("  ", js.get("title"), js.get("type"), js.get("url"), js.get("owner"), (js.get("licenseInfo") or "")[:200])
p("=== Overpass sirens, Pierce/King/Lewis")
q = '[out:json][timeout:120];(node["emergency"="siren"](46.55,-122.75,47.45,-121.3);node["siren:purpose"](46.55,-122.75,47.45,-121.3););out;'
js = j("https://overpass-api.de/api/interpreter", data=urllib.parse.urlencode({"data": q}).encode())
els = (js or {}).get("elements", [])
p(f"  {len(els)} siren nodes")
for e in els[:60]:
    p(f"  {e['lat']:.4f},{e['lon']:.4f} {json.dumps(e.get('tags', {}))[:200]}")
p("=== WSDA geoservices")
for u in ["https://geoservices.agr.wa.gov/arcgis/rest/services?f=json", "https://fortress.wa.gov/agr/gis/arcgis/rest/services?f=json",
          "https://geoservices.wa.gov/arcgis/rest/services?f=json"]:
    js = j(u)
    if js: p("  ", u, "folders", js.get("folders"), "services", [s.get("name") for s in js.get("services", [])][:40])
p("=== Open Brewery DB")
for name in ["Kings & Daughters Brewery", "Fort George Brewery", "Superflux Beer Company", "Guinness"]:
    js = j("https://api.openbrewerydb.org/v1/breweries/search?" + urllib.parse.urlencode({"query": name, "per_page": 3}))
    for b in (js or [])[:3]:
        p(f"  [{name}] {b.get('name')} | {b.get('city')}, {b.get('state_province')}, {b.get('country')} | {b.get('latitude')},{b.get('longitude')}")
log.close()
