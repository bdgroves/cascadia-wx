"""Probe 2: geology at the known ichthyosaur records; finer Nevada map; WA mines; Macrostrat polygons."""
import json, re, urllib.parse, urllib.request, time
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "fossil rebuild probe (github.com/bdgroves)"}
def get(url, n=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            b = r.read() if n is None else r.read(n)
        return b
    except Exception as e:
        p(f"  ERR {e} {url[:160]}"); return None
def js(url):
    b = get(url)
    try: return json.loads(b) if b else None
    except Exception: p("  notjson", (b or b'')[:200]); return None
recs = json.load(open("tools/nv_ichthyo.json"))["records"]
p("=== Macrostrat (all scales) + BLM SMA at each NV ichthyosaur record")
for r in recs:
    lat, lng = float(r["lat"]), float(r["lng"])
    d = js(f"https://macrostrat.org/api/v2/geologic_units/map?lat={lat}&lng={lng}")
    units = [(u.get("source_id"), u.get("name"), u.get("strat_name"), u.get("t_int_name"), u.get("b_int_name")) for u in (d or {}).get("success", {}).get("data", [])]
    s = js(f"https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_LimitedScale/MapServer/1/query?geometry={lng},{lat}&geometryType=esriGeometryPoint&inSR=4326&outFields=ADMIN_AGENCY_CODE,ADMIN_UNIT_NAME&returnGeometry=false&f=json")
    sma = [f["attributes"] for f in (s or {}).get("features", [])]
    p(f"  {r['occurrence_no']} {r.get('formation')} {lat:.4f},{lng:.4f} prec={r.get('latlng_precision')} | {units} | {sma}")
p("=== DS249 file listing")
for u in ["https://pubs.usgs.gov/ds/2007/249/", "https://pubs.usgs.gov/ds/2007/249/downloads/", "https://pubs.usgs.gov/ds/2007/249/downloads/Geology/",
          "http://pubsdata.usgs.gov/pubs/ds/2007/249/index.html", "https://pubs.usgs.gov/ds/2007/250/downloads/", "https://pubs.usgs.gov/ds/2007/250/downloads/Geology/"]:
    b = get(u)
    if b:
        links = sorted(set(re.findall(r'href="([^"]+)"', b.decode("utf8", "ignore"))))
        p(" ", u, len(b), [l for l in links if any(x in l.lower() for x in ("zip", "shp", "download", "gdb", "geology", "e00"))][:40])
p("=== WA DNR surface mines + 24k geology + 100k geology")
for u in ["https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/Active_Surface_Mine_Permit_Sites/MapServer?f=json",
          "https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/24k_Surface_Geology/MapServer?f=json",
          "https://gis.dnr.wa.gov/site1/rest/services/Public_Geology?f=json"]:
    d = js(u)
    if d: p(" ", u.split("services/")[1][:70], [(l.get("id"), l.get("name")) for l in d.get("layers", [])][:12], [s.get("name") for s in d.get("services", [])][:40])
d = js("https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/Active_Surface_Mine_Permit_Sites/MapServer/0/query?where=1%3D1&returnCountOnly=true&f=json")
p("  mines count", d)
d = js("https://gis.dnr.wa.gov/site1/rest/services/Public_Geology/Active_Surface_Mine_Permit_Sites/MapServer/0/query?geometry=-119.266,46.159&geometryType=esriGeometryPoint&inSR=4326&distance=2000&units=esriSRUnit_Meter&outFields=*&returnGeometry=false&f=json")
p("  mines near Coyote Canyon", [f["attributes"] for f in (d or {}).get("features", [])][:3])
p("=== Macrostrat polygons by strat name")
for q in ["strat_name_id=1181", "strat_name=Luning", "strat_name_id=642"]:
    b = get(f"https://macrostrat.org/api/v2/geologic_units/map?{q}&format=geojson_bare")
    p(" ", q, (b or b"")[:300])
