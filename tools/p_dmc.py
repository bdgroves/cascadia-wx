"""Probe 2 for 30DMC 2026: layer fields."""
import json, os, urllib.parse, urllib.request
OUT = "tools/probe_out.txt"
log = open(OUT, "w")
def p(*a):
    print(*a); print(*a, file=log); log.flush()
UA = {"User-Agent": "30DayMapChallenge-2026 probe (github.com/bdgroves)"}
def j(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
            return json.loads(r.read())
    except Exception as e:
        p("  ERR", url, e); return None
SV = {
 "ahab": "https://services7.arcgis.com/vUVXhXafpruJFs3l/arcgis/rest/services/AHAB_Points/FeatureServer",
 "pc_volc": "https://services2.arcgis.com/1UvBaQ5y1ubjUPmd/arcgis/rest/services/Volcanic_Hazards/FeatureServer",
 "pc_travel": "https://services2.arcgis.com/1UvBaQ5y1ubjUPmd/arcgis/rest/services/Volcanic_Time_of_Travel/FeatureServer",
 "wsda_yak24": "https://services.arcgis.com/tsh3MgS57Cs86wmq/arcgis/rest/services/WSDA_Crop_2024_joinCropDetail_Yakima/FeatureServer",
}
for k, u in SV.items():
    p(f"=== {k}")
    js = j(u + "?f=json")
    if not js: continue
    p("  layers", [(l["id"], l["name"]) for l in js.get("layers", [])], "copyright", (js.get("copyrightText") or "")[:200], "desc", (js.get("serviceDescription") or "")[:300])
    for l in js.get("layers", [])[:4]:
        lj = j(f"{u}/{l['id']}?f=json")
        if not lj: continue
        p(f"  layer {l['id']} {l['name']} geom {lj.get('geometryType')} maxRec {lj.get('maxRecordCount')} fields {[f['name'] for f in lj.get('fields', [])]}")
        c = j(f"{u}/{l['id']}/query?where=1%3D1&returnCountOnly=true&f=json")
        p("    count", c)
        s = j(f"{u}/{l['id']}/query?where=1%3D1&outFields=*&returnGeometry=false&resultRecordCount=4&f=json")
        for f in (s or {}).get("features", [])[:4]:
            p("    ", json.dumps(f["attributes"])[:400])
# AHAB in Pierce: distinct purposes
u = SV["ahab"] + "/0/query?" + urllib.parse.urlencode({"where": "1=1", "geometry": "-122.75,46.6,-121.3,47.45", "geometryType": "esriGeometryEnvelope",
    "inSR": 4326, "outFields": "*", "returnGeometry": "true", "outSR": 4326, "f": "json"})
js = j(u)
fs = (js or {}).get("features", [])
p(f"=== AHAB in the Pierce box: {len(fs)}")
for f in fs[:80]:
    p("  ", f.get("geometry"), json.dumps(f["attributes"])[:260])
# WSDA hops
for fld in ["CropType", "CropGroup", "Crop_Type", "CROPTYPE"]:
    u = SV["wsda_yak24"] + "/0/query?" + urllib.parse.urlencode({"where": f"{fld} LIKE '%Hop%'", "returnCountOnly": "true", "f": "json"})
    p("  hops by", fld, j(u))
log.close()
