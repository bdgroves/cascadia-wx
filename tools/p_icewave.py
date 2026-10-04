"""Probe for project-ice-wave audit: what is at each target, and where is the Coyote Canyon mammoth site."""
import json, time, urllib.parse, urllib.request
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "project-ice-wave audit (github.com/bdgroves)"}
OVP = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
def ovp(q):
    for u in OVP:
        for _ in range(3):
            try:
                req = urllib.request.Request(u, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
                with urllib.request.urlopen(req, timeout=180) as r:
                    return json.loads(r.read())
            except Exception as e:
                p("  ERR", u, e); time.sleep(10)
    return None
def j(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            return json.loads(r.read())
    except Exception as e:
        p("  ERR", url, e); return None
pts = json.load(open("tools/icewave_targets.json"))
res = {}
for rank, eco, lat, lon in pts:
    q = f"""[out:json][timeout:60];
is_in({lat},{lon})->.a;
area.a[~"natural|water|waterway|landuse|leisure|boundary|protect_class"~"."]->.b;
.b out tags;
(way(around:40,{lat},{lon})[~"natural|waterway|water"~"."];relation(around:40,{lat},{lon})[~"natural|waterway|water"~"."];);
out tags;"""
    js = ovp(q)
    els = [] if not js else [{k: v for k, v in e.get("tags", {}).items() if k in ("name", "natural", "water", "waterway", "landuse", "boundary", "leisure", "admin_level", "protect_class")} for e in js["elements"]]
    els = [e for e in els if e and e.get("admin_level") not in ("2", "4", "6", "8")]
    res[rank] = els
    p(f"#{rank} {eco} {lat},{lon}: {els}")
    time.sleep(2)
json.dump(res, open("tools/probe_out_icewave.json", "w"), indent=1)
p("=== Coyote Canyon / Clodfelter")
js = ovp("""[out:json][timeout:60];
(way["name"~"Clodfelter"](45.9,-119.5,46.3,-118.9);node["name"~"Coyote Canyon|McBones|Mammoth",i](45.9,-119.5,46.3,-118.9);way["name"~"Coyote Canyon|McBones|Mammoth",i](45.9,-119.5,46.3,-118.9););out center tags;""")
for e in (js or {}).get("elements", []):
    c = e.get("center") or {"lat": e.get("lat"), "lon": e.get("lon")}
    p(" ", e["type"], e["id"], c, e.get("tags", {}).get("name"), {k: v for k, v in e.get("tags", {}).items() if k in ("highway", "natural", "landuse", "tourism", "historic")})
p("=== PBDB Pleistocene near Tri-Cities")
js = j("https://paleobiodb.org/data1.2/occs/list.json?" + urllib.parse.urlencode({"lngmin": -119.6, "lngmax": -118.8, "latmin": 45.9, "latmax": 46.5, "interval": "Pleistocene", "base_name": "Vertebrata", "show": "coords,loc"}))
for r in (js or {}).get("records", []):
    p(" ", r.get("oid"), r.get("tna"), r.get("lat"), r.get("lng"), r.get("cnm"), r.get("cid"))
