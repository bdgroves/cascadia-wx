```
╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║    ██████╗ █████╗ ███████╗ ██████╗ █████╗ ██████╗ ██╗ █████╗            ║
║   ██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗██║██╔══██╗           ║
║   ██║     ███████║███████╗██║     ███████║██║  ██║██║███████║           ║
║   ██║     ██╔══██║╚════██║██║     ██╔══██║██║  ██║██║██╔══██║           ║
║   ╚██████╗██║  ██║███████║╚██████╗██║  ██║██████╔╝██║██║  ██║           ║
║    ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝           ║
║                          W  X                                            ║
║                                                                          ║
║   PACIFIC NORTHWEST MOUNTAIN WEATHER ANALYSIS  ·  FORTRAN               ║
║   RAINIER  ·  OLYMPICS  ·  CASCADES  ·  NRCS SNOTEL  ·  NOAA           ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**[→ Launch the Live Dashboard](https://bdgroves.github.io/cascadia-wx)**

---

> *"We're going to go out there and put this machine right in the path of the storm."*
> — Dr. Jo Harding, Twister (1996)

---

## The Setup

It's early April. The Cascades are running dry — 15% of normal snowpack. Snoqualmie Pass is bare. Stevens is bare. Stampede is bare. Someone in a cabin somewhere in the foothills can feel it. The snowpack that should be sitting up there, waiting to melt slow into August, isn't there. The reservoirs will notice in July.

Every morning at 8AM, a terminal somewhere wakes up. A Python script reaches out to 11 weather stations buried in the mountains — sensors at Paradise on Rainier, high ridges in the Olympics, fog-soaked Cascade passes. It pulls the numbers. It writes a CSV. Then FORTRAN takes over.

Not a wrapper. Not a library. **FORTRAN.** The language that computed the first numerical weather forecast in 1950 on a machine that filled a room. The same mathematical DNA that still runs inside the National Weather Service, NCAR, ECMWF — every serious atmospheric model on the planet. It reads the data, cranks through the physics — lapse rates, snow levels, precipitation phase, atmospheric river index, storm classification — and prints a report.

Then it terminates. Normally. Return code zero.

Nobody asked for this. It just needed to happen.

---

## The Numbers

```
4, 8, 15, 16, 23, 42
```

Enter them every 108 minutes or the snowpack anomaly gets worse. We don't make the rules.

```
CASCADIA-WX: LOADING SNOTEL DATA...
  STATION  1: Paradise
  STATION  2: Cayuse Pass
  STATION  3: Burnt Mountain
  ...
  STATION 11: Corral Pass
CASCADIA-WX: 11 SNOTEL STATIONS LOADED
CASCADIA-WX: COMPUTING LAPSE RATES...
CASCADIA-WX: COMPUTING SNOW LEVELS...
CASCADIA-WX: COMPUTING DEGREE DAYS...
CASCADIA-WX: COMPUTING AR INDEX...
CASCADIA-WX: WRITING REPORT...
CASCADIA-WX: NORMAL TERMINATION.
```

Every day. Automated. Whether anyone's watching or not. The hatch has to be maintained.

---

## What It Computes

FORTRAN does the atmospheric science. Not because it's convenient — because it's what the atmosphere deserves.

| Computation | Physics |
|-------------|---------|
| **Environmental lapse rate** | Temperature gradient C/km, valley floor → mountain stations |
| **Snow level** | Elevation where T = 2°C — the rain/snow phase boundary |
| **Precipitation phase** | Snow % vs rain % at each station using transition zone logic |
| **Degree days** | Heating / cooling / positive — the snowmelt energy budget |
| **Atmospheric river index** | Proxy IVT score from snow level anomaly + SWE rate |
| **Storm classification** | Gulf of Alaska / Pineapple Express / Cutoff Low |
| **SWE percent of normal** | Current snowpack vs 30-year NRCS median |
| **Massif roll-up** | Rainier / Olympics / Cascades averaged and classified |
| **Atmospheric stability** | Unstable / Cond. Unstable / Neutral / Stable |

---

## April 2, 2026 — What the Numbers Said

```
SECTION III: MOUNTAIN MASSIF SNOWPACK SUMMARY

  MASSIF        STATIONS  AVG SWE (IN)  AVG % NORMAL  STATUS
  ------------------------------------------------------------
  RAINIER            4         24.65          52.5  WELL BELOW NORMAL
  OLYMPICS           2         13.90          33.2  WELL BELOW NORMAL
  CASCADES           5          4.68          15.1  WELL BELOW NORMAL

SECTION IV: ATMOSPHERIC ANALYSIS

  ATMOSPHERIC RIVER INDEX:      -0.71
  AR STATUS:                  NO AR CONDITIONS
  STORM CLASSIFICATION:       GULF OF ALASKA
  ENVIRONMENTAL LAPSE RATE:    -5.43 C/km
  REGIONAL SNOW LEVEL:         2972. ft
  REGIONAL SWE % NORMAL:        32.0%
```

Snoqualmie Pass: 0.0 inches. Stevens Pass: 0.0 inches. Stampede Pass: 0.0 inches.
Paradise, sitting at 5,150 feet on the flank of Rainier, still holding 36.7 inches — 73% of normal.
The mountain remembers what the passes have forgotten.

---

## The Eleven Stations

Three massifs. Eleven sensors. Each one a data point in a system that's been measuring snowpack since before most of the code running today was written.

| Station | Massif | Elevation | What It Watches |
|---------|--------|-----------|-----------------|
| Paradise | Rainier | 5,150 ft | Heart of the Nisqually watershed |
| Cayuse Pass | Rainier | 5,260 ft | White River headwaters |
| Burnt Mountain | Rainier | 4,160 ft | Wilkeson Creek drainage |
| Corral Pass | Rainier | 5,810 ft | Highest station — last to lose snow |
| Dungeness | Olympics | 3,990 ft | Olympic Peninsula water supply |
| Buckinghorse | Olympics | 4,850 ft | Elwha River headwaters |
| Snoqualmie Pass | Cascades | 3,000 ft | I-90 corridor — first to go bare |
| Stevens Pass | Cascades | 4,061 ft | US-2 corridor |
| Stampede Pass | Cascades | 3,960 ft | Yakima River basin |
| Elbow Lake | Cascades | 3,050 ft | South Fork Nooksack |
| Bumping Ridge | Cascades | 4,600 ft | Bumping River / Yakima |

---

## The Pipeline

```
         ┌─────────────────────────────────────────┐
         │         8:00 AM PACIFIC                  │
         │         GitHub Actions wakes up          │
         └───────────────────┬─────────────────────┘
                             │
                             ▼
              NRCS SNOTEL API  +  NOAA Observations
              (free · public · no key · been running
               since before the internet existed)
                             │
                             ▼
                      fetch_wx.py
                  Python · zero dependencies
                  stdlib only · no pip
                             │
                  snotel_data.csv  ←─── 11 stations
                  valley_data.csv  ←─── 4 airports
                             │
                             ▼
                    CASCADIA-WX.f90
                  ┌──────────────────────────────┐
                  │  FORTRAN · GFortran 13        │
                  │  Lapse rate computation       │
                  │  Snow level estimation        │
                  │  Phase partitioning           │
                  │  Degree day accumulation      │
                  │  Atmospheric river index      │
                  │  Storm classification         │
                  │  Massif roll-up               │
                  │  4-section formatted report   │
                  └──────────────────────────────┘
                             │
               cascadia-wx-report.txt  (the printout)
               analysis.csv            (the machine read)
                             │
                             ▼
                    git commit + push
                             │
                             ▼
              bdgroves.github.io/cascadia-wx
              reads analysis.csv live · no rebuild
              amber phosphor · updates on page load
```

---

## Why FORTRAN. Why Now. Why Anyone.

FORTRAN was designed in 1957 by John Backus at IBM. The first successful numerical weather prediction run was performed in 1950 on ENIAC — and when that code was ported to faster machines, it was rewritten in FORTRAN. Today the National Weather Service runs FORTRAN. NCAR runs FORTRAN. ECMWF runs FORTRAN. The WRF model — the backbone of regional weather forecasting — is FORTRAN. The atmosphere has been computed in FORTRAN for 75 years.

How many people are writing new FORTRAN in 2026? Compiling it fresh on WSL, feeding it live government sensor data, running it through GitHub Actions every morning, and serving the output as a web dashboard? Not many. Maybe a handful of grad students who had no choice. Maybe some legacy system maintainers who know too much. And now, apparently, a developer in Lakewood, Washington, who thought it would be fun.

It was fun. It still is. The numbers come in every morning. The atmosphere doesn't care what language you use to understand it — but FORTRAN has been understanding it longer than anything else, and it does it without apology, without overhead, and without anyone asking for permission.

The hatch needs to be maintained. We maintain the hatch.

---

## Requirements

| Item | Details |
|------|---------|
| FORTRAN | [GFortran](https://gcc.gnu.org/fortran/) 9+ |
| Python | 3.9+ · zero external dependencies |
| OS | Linux, macOS, Windows (WSL) |
| Data | NRCS AWDB + NOAA APIs — free, no key, publicly funded |

```bash
# Ubuntu / Debian / WSL
sudo apt install gfortran

# macOS
brew install gcc
```

---

## Build & Run

```bash
python3 fetch_wx.py
gfortran -O2 -o cascadia-wx CASCADIA-WX.f90 -lm
./cascadia-wx
cat cascadia-wx-report.txt

# or just: make
```

---

## File Structure

```
cascadia-wx/
├── CASCADIA-WX.f90              ← FORTRAN source
├── fetch_wx.py                  ← NRCS + NOAA fetcher
├── baselines.csv                ← 30-year SNOTEL medians
├── snotel_data.csv              ← Live snowpack (updated daily)
├── valley_data.csv              ← Surface temps (updated daily)
├── cascadia-wx-report.txt       ← The printout (updated daily)
├── analysis.csv                 ← Machine-readable (updated daily)
├── index.html                   ← Live dashboard
├── Makefile
├── pixi.toml
└── .github/workflows/cascadia-wx.yml
```

---

## Related Projects

- **[SIERRA-FLOW](https://bdgroves.github.io/sierra-flow-cobol)** — COBOL sister project. Live USGS streamflow, 8 Sierra Nevada gages, percent-of-normal, trend analysis, daily CI/CD. Same idea, different watershed, different decade of computing history.
- **[Sierra Streamflow Monitor](https://bdgroves.github.io/sierra-streamflow)** — 20-year spaghetti charts, Leaflet map, Tuolumne/Merced/Stanislaus.
- **[EDGAR](https://bdgroves.github.io/EDGAR)** — Mariners/Rainiers analytics. Nightly updates.
- **[brooksgroves.com](https://brooksgroves.com)** — All of it, in one place.

---

```
  The hatch is maintained.
  The numbers have been entered.
  The snowpack has been measured.

  CASCADIA-WX.f90
  NORMAL TERMINATION.  RETURN CODE: 0.
  *** END OF JOB ***
```
