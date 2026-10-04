"""Probe: which data sources answer for the fossil rebuild."""
import json, urllib.parse, urllib.request, time
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "fossil rebuild probe (github.com/bdgroves)"}
def get(url, n=600):
    t=time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            b = r.read()
        p(f"  OK {len(b)}B {time.time()-t:.1f}s {url[:140]}"); return b
    except Exception as e:
        p(f"  ERR {e} {url[:140]}"); return None
def js(url):
    b = get(url); 
    try: return json.loads(b) if b else None
    except Exception as e: p("  notjson", b[:200]); return None
p("=== Macrostrat: units at points (Berlin-Ichthyosaur SP area; Favret Canyon; Coyote Canyon; Touchet)")
for lat, lng in [(38.877,-117.606),(40.06,-117.70),(46.159,-119.266),(46.04,-118.68)]:
    d = js(f"https://macrostrat.org/api/v2/geologic_units/map?lat={lat}&lng={lng}&scale=large")
    for u in (d or {}).get("success", {}).get("data", [])[:3]:
        p("   ", {k: u.get(k) for k in ("map_id","name","strat_name","lith","age","t_int_name","b_int_name","descrip","ref_id","source_id")})
    d = js(f"https://macrostrat.org/api/v2/geologic_units/map?lat={lat}&lng={lng}&scale=medium")
    for u in (d or {}).get("success", {}).get("data", [])[:2]:
        p("    med", {k: u.get(k) for k in ("name","strat_name","lith","t_int_name","b_int_name")})
p("=== Macrostrat sources (scale) in a NV bbox")
d = js("https://macrostrat.org/api/v2/defs/sources?lat=38.877&lng=-117.606")
for s in (d or {}).get("success", {}).get("data", [])[:10]:
    p("   ", {k: s.get(k) for k in ("source_id","name","scale","ref_title","ref_year","url")})
p("=== Macrostrat map geometry in a box (geojson)")
d = js("https://macrostrat.org/api/v2/geologic_units/map?lat=38.877&lng=-117.606&scale=large&format=geojson_bare&adjacents=true")
p("  features", len((d or {}).get("features", [])) if isinstance(d, dict) else type(d))
get("https://tiles.macrostrat.org/carto/10/185/391.mvt")
p("=== Macrostrat columns/units by strat name")
for nm in ["Luning","Favret","Prida","Touchet"]:
    d = js(f"https://macrostrat.org/api/v2/defs/strat_names?strat_name_like={nm}")
    for s in (d or {}).get("success", {}).get("data", [])[:3]:
        p("   ", {k: s.get(k) for k in ("strat_name_id","strat_name_long","b_age","t_age")})
p("=== USGS PAD-US / BLM surface management")
js("https://services.arcgis.com/v01gqwM5QqNysAAi/arcgis/rest/services/Manager_Name/FeatureServer?f=json")
js("https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_Cached_without_PriUnk/MapServer?f=json")
js("https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_LimitedScale/MapServer?f=json")
d = js("https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_LimitedScale/MapServer/1/query?geometry=-117.606,38.877&geometryType=esriGeometryPoint&inSR=4326&outFields=*&returnGeometry=false&f=json")
p("   sma", (d or {}).get("features", [])[:2])
p("=== 3DEP ImageServer, 10 m export")
get("https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?bbox=-117.62,38.87,-117.59,38.89&bboxSR=4326&size=300,300&imageSR=4326&format=tiff&pixelType=F32&f=image")
p("=== Earth Search Sentinel-2")
get("https://earth-search.aws.element84.com/v1/search?collections=sentinel-2-l2a&bbox=-117.62,38.87,-117.59,38.89&limit=1&query=%7B%22eo%3Acloud_cover%22%3A%7B%22lt%22%3A5%7D%7D")
p("=== PBDB occurrence precision for NV ichthyosaurs")
d = js("https://paleobiodb.org/data1.2/occs/list.json?base_name=Ichthyosauria&state=Nevada&show=coords,loc,prec&vocab=pbdb&limit=all")
from collections import Counter
p("  precision", Counter((r.get("latlng_precision"), r.get("geogscale")) for r in (d or {}).get("records", [])))
d = js("https://paleobiodb.org/data1.2/occs/list.json?base_name=Mammalia&state=Washington&interval=Pleistocene&show=coords,loc,prec&vocab=pbdb&limit=all")
p("  WA mammal precision", Counter((r.get("latlng_precision"), r.get("geogscale")) for r in (d or {}).get("records", [])), len((d or {}).get("records", [])))
p("=== iDigBio WA Pleistocene proboscideans")
d = js("https://search.idigbio.org/v2/search/records?rq=" + urllib.parse.quote(json.dumps({"order":"proboscidea","stateprovince":"washington","geopoint":{"type":"exists"}})) + "&limit=5")
p("  idigbio count", (d or {}).get("itemCount"))
