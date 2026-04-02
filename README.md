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

> *"Numerical weather prediction is the use of mathematical models of the atmosphere to predict the weather. The first successful NWP run was performed in 1950 on the ENIAC — programmed in FORTRAN."*

**[→ Launch the Live Dashboard](https://bdgroves.github.io/cascadia-wx)**

---

## What It Is

CASCADIA-WX is a FORTRAN scientific analysis engine for Pacific Northwest mountain weather. It reads live NRCS SNOTEL snowpack data from 11 stations across three mountain massifs, combines it with NOAA surface temperatures at valley airports, and computes atmospheric science metrics every morning at 8AM Pacific.

The sister project to **[SIERRA-FLOW](https://github.com/bdgroves/sierra-flow-cobol)** — which does Sierra Nevada streamflow analysis in COBOL. Together: vintage languages, live government data, zero cloud costs.

---

## What FORTRAN Computes

| Computation | Description |
|-------------|-------------|
| **Environmental lapse rate** | Temperature gradient C/km from valley floor to mountain stations |
| **Snow level** | Elevation where precipitation phase changes (rain → snow boundary) |
| **Precipitation phase partitioning** | Snow % vs rain % at each station elevation |
| **Degree day accumulation** | Heating/cooling/positive degree days — snowmelt energy budget |
| **Atmospheric river index** | Proxy IVT score from snow level anomaly + SWE accumulation rate |
| **Storm classification** | Gulf of Alaska / Pineapple Express / Cutoff Low |
| **SWE percent of normal** | Current snowpack vs 30-year NRCS median |
| **Massif roll-up** | Average SWE and snow level by Rainier / Olympics / Cascades |
| **Atmospheric stability** | Unstable / Conditionally Unstable / Neutral / Stable |

---

## The Eleven Stations

| Station | Massif | Elevation |
|---------|--------|-----------|
| Paradise | Rainier | 5,427 ft |
| Sunrise | Rainier | 6,400 ft |
| Cayuse Pass | Rainier | 3,960 ft |
| Hurricane Ridge | Olympics | 5,757 ft |
| Waterhole | Olympics | 4,200 ft |
| Snoqualmie Pass | Cascades | 3,000 ft |
| Stevens Pass | Cascades | 4,061 ft |
| Stampede Pass | Cascades | 3,960 ft |
| White Pass | Cascades | 4,500 ft |
| Crystal Mountain | Cascades | 4,400 ft |
| Chinook Pass | Cascades | 5,432 ft |

---

## The Pipeline

```
NRCS AWDB API (SNOTEL)  +  NOAA Observations API
              │
              ▼
        fetch_wx.py          Python 3.12 · stdlib only · zero pip
        snotel_data.csv
        valley_data.csv
              │
              ▼
        CASCADIA-WX.f90      GFortran 13 · 700+ lines
        reads both CSVs
              │
              ├── Lapse rate computation
              ├── Snow level estimation
              ├── Precipitation phase partitioning
              ├── Degree day accumulation
              ├── Atmospheric River index
              ├── Storm classification
              └── 4-section formatted report
              │
              ▼
        cascadia-wx-report.txt   committed daily
        analysis.csv             committed daily
              │
              ▼
        index.html               reads analysis.csv live · no rebuild
```

---

## Why FORTRAN

FORTRAN (Formula Translation) was designed in 1957 by John Backus at IBM. The first successful numerical weather prediction run was performed in 1950 on ENIAC — and when NWP code was ported to faster machines, it was written in FORTRAN.

Today the National Weather Service runs FORTRAN. NCAR runs FORTRAN. ECMWF runs FORTRAN. The WRF (Weather Research & Forecasting) model — the backbone of modern regional weather forecasting — is FORTRAN. The atmosphere has been computed in FORTRAN for 75 years and will continue to be for decades more.

Running FORTRAN in a GitHub Actions pipeline in 2026 isn't ironic. It's appropriate.

---

## Requirements

| Item | Details |
|------|---------|
| FORTRAN compiler | [GFortran](https://gcc.gnu.org/fortran/) 9+ |
| Python | 3.9+ · stdlib only |
| OS | Linux, macOS, Windows (WSL) |
| Data | NRCS AWDB + NOAA APIs — free, no key required |

```bash
# Ubuntu / Debian / WSL
sudo apt install gfortran

# macOS
brew install gcc   # includes gfortran
```

---

## Build & Run

```bash
# 1. Fetch live SNOTEL + valley data
python3 fetch_wx.py

# 2. Compile
gfortran -O2 -o cascadia-wx CASCADIA-WX.f90 -lm

# 3. Run
./cascadia-wx

# 4. View report
cat cascadia-wx-report.txt

# Or: make
```

---

## GitHub Actions

Runs daily at **8:00 AM Pacific** (15:00 UTC) — after SNOTEL stations report their overnight data:

```yaml
schedule:
  - cron: '0 15 * * *'
```

---

## File Structure

```
cascadia-wx/
├── CASCADIA-WX.f90                 ← Main FORTRAN source
├── fetch_wx.py                     ← NRCS + NOAA fetcher (stdlib only)
├── baselines.csv                   ← 30-year SNOTEL medians
├── snotel_data.csv                 ← Live snowpack data (updated daily)
├── valley_data.csv                 ← Surface temps for lapse rate (updated daily)
├── cascadia-wx-report.txt          ← Formatted analysis report (updated daily)
├── analysis.csv                    ← Machine-readable results (updated daily)
├── index.html                      ← Live dashboard (reads analysis.csv)
├── Makefile
├── pixi.toml
└── .github/workflows/cascadia-wx.yml
```

---

## Related Projects

- **[SIERRA-FLOW](https://bdgroves.github.io/sierra-flow-cobol)** — COBOL sister project. Live USGS streamflow, 8 Sierra Nevada gages, daily CI/CD.
- **[Sierra Streamflow Monitor](https://bdgroves.github.io/sierra-streamflow)** — 20-year spaghetti charts, Leaflet map, Tuolumne/Merced/Stanislaus.
- **[EDGAR](https://bdgroves.github.io/EDGAR)** — Mariners/Rainiers analytics. Nightly updates.
- **[brooksgroves.com](https://brooksgroves.com)** — Project hub.

---

```
  CASCADIA-WX.f90
  NORMAL TERMINATION.  RETURN CODE: 0.
  *** END OF JOB ***
```
