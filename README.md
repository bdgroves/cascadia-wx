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

**[→ The live page: brooksgroves.com/cascadia-wx](https://brooksgroves.com/cascadia-wx/)**

Twelve NRCS SNOTEL snow stations on Rainier, the Olympics and the Cascades, and the National Weather Service weather balloon at Quillayute on the Washington coast, run twice a day through a FORTRAN batch job. **CASCADIA-WX.f90** works out how much snow is on the mountains against NRCS's own medians, how high it's freezing, how much water vapour is coming ashore and whether that's atmospheric-river strength, and what last winter amounted to. It prints a 132-column report. The page shows that report on green-bar paper, the job log, the latest balloon's temperature profile, every balloon's freezing level and vapour transport, each station's snowpack against median, and the vapour-transport loop on a FORTRAN coding form.

It is the sister project of [SIERRA-FLOW](https://github.com/bdgroves/sierra-flow-cobol), which does Sierra Nevada rivers in COBOL.

---

## The batch job

At 15:17 and 03:17 UTC (8:17 a.m. and p.m. PDT), after each 12Z and 00Z balloon has reached the archive, GitHub Actions runs `run_job.sh` on Ubuntu 24.04:

```
STEP FETCH     python3 fetch_wx.py       NRCS SNOTEL + KUIL soundings  → snotel_daily.csv, soundings_raw.csv
STEP COMPILE   gfortran -O2              GNU Fortran 13
STEP CASCADWX  ./cascadia-wx             → cascadia-wx-report.txt and the CSVs below
```

Each step's output, return code and time go into `job-log.txt`. The job carries on through warnings and stops on a return code of 8 or more, like a mainframe step with `COND=(8,LE)`.

| RC | Meaning |
|---|---|
| 0 | Normal: every station reported and the latest balloon is under 36 hours old |
| 4 | Warning: a station or the balloon is missing or stale. The report names it (`CWX011W`–`CWX017W`) |
| 8 | No SNOTEL data at all. Nothing is written |
| 12 | An input file can't be opened |

If NRCS doesn't answer for a station, the fetcher keeps that station's rows from the last run and the FORTRAN flags them as stale. If the first three stations all fail, it treats NRCS as down and doesn't wait on the rest. Nothing is ever filled in with made-up values.

## What it computes

**Snowpack.** For each station on the latest day: snow water equivalent (SWE), snow depth, 7-day change, water-year precipitation, and each against NRCS's 1991–2020 median for that calendar day, which AWDB returns alongside the value. Percent of median is left blank until the median itself reaches 1 inch, as NRCS does, because early-season percentages are meaningless. The **massif index** is the sum of the stations' SWE over the sum of their medians, the way NRCS computes a basin index (not an average of percentages). The classes are NRCS's map classes: under 50%, 50–69, 70–89, 90–109 (near normal), 110–129, 130–149, 150% or more.

**The balloon.** For every Quillayute sounding (KUIL, WMO 72797), from every level it reports:

| Quantity | How |
|---|---|
| Freezing level | Lowest height where the temperature falls through 0 °C, interpolated between levels |
| Wet-bulb temperature | The psychrometric equation, e<sub>s</sub>(T<sub>w</sub>) − γ·p·(T − T<sub>w</sub>) = e, solved by bisection |
| Wet-bulb zero | Lowest height where the wet-bulb falls through 0 °C |
| Snow level | 1,000 ft below the freezing level: the National Weather Service's rule of thumb, labelled as an estimate |
| Precipitable water | (1/g) ∫ q dp, surface to 300 hPa |
| Integrated vapour transport (IVT) | (1/g) ∫ q·**V** dp, surface to 300 hPa, as east and north components; direction it comes from |
| Atmospheric river | IVT ≥ 250 kg m⁻¹ s⁻¹; weak, moderate, strong, extreme and exceptional at 250/500/750/1000/1250 (Ralph et al. 2019) |
| Lapse rate | 850 to 700 hPa, °C per km |
| 700 hPa wind | Interpolated in ln p |

Specific humidity comes from the dew point (Bolton 1980). Humidity and wind are interpolated in ln p where a level lacks them; humidity above the highest dew-point report is taken as zero. A sounding that ends below 300 hPa gets no IVT and a `CWX017W` warning. The balloon is one place at one moment; the official atmospheric-river scale also weighs duration, and the report says so.

**Checked.** For the 2026-10-02 12Z sounding, FORTRAN's precipitable water is 27.6 mm; MetPy gives 27.8 mm and the University of Wyoming's sounding page 28.1 mm. Wet-bulb at 850 hPa: 7.1 °C (MetPy 7.0 °C). IVT for four soundings matches an independent Python integration on a 5 hPa grid to the unit (186, 250, 302, 242 kg m⁻¹ s⁻¹).

**Temperature with height.** The free-air rate from the balloon, and the mountain-surface rate from a least-squares fit of SNOTEL daily mean temperature against elevation, with r². The surface rate is usually shallower, and often negative in fall and winter when cold air pools in valleys.

**Last water year in review.** Each station's peak SWE and date against the median peak, and its melt-out date against the median melt-out.

## Files

| File | What |
|---|---|
| `CASCADIA-WX.f90` | The program. Kept to 72 columns |
| `fetch_wx.py` | The fetcher. Python standard library only |
| `stations.csv` | The 12 stations, checked against NRCS station metadata |
| `run_job.sh` | The batch job; writes `job-log.txt` |
| `snotel_daily.csv` | Daily station data and medians, last water year and this one |
| `sounding_series.csv` | One row per balloon, last water year and this one; updated in place |
| `upper_air.csv` | Every level of the latest balloon, with wet-bulb and humidity |
| `analysis.csv`, `massif.csv`, `review.csv`, `summary.csv` | Results |
| `cascadia-wx-report.txt` | The printed report |
| `index.html` | The page. It reads the files above and draws them; it calculates nothing |

## The twelve stations

| Station | NRCS ID | Massif | Elevation |
|---|---|---|---|
| Paradise | 679 | Rainier | 5,150 ft |
| Cayuse Pass | 1085 | Rainier | 5,260 ft |
| Burnt Mountain | 942 | Rainier | 4,160 ft |
| Corral Pass | 418 | Rainier | 5,810 ft |
| Dungeness | 943 | Olympics | 3,990 ft |
| Buckinghorse | 1107 | Olympics | 4,850 ft |
| Waterhole | 974 | Olympics | 5,010 ft |
| Olallie Meadows (Snoqualmie Pass) | 672 | Cascades | 4,010 ft |
| Stevens Pass | 791 | Cascades | 3,940 ft |
| Stampede Pass | 788 | Cascades | 3,850 ft |
| Elbow Lake | 910 | Cascades | 3,050 ft |
| Bumping Ridge | 375 | Cascades | 4,600 ft |

## Corrections (October 2026)

Version 1 (April 2026) got several things wrong, and the conclusions drawn from it with them:

- **Three stations didn't exist.** It asked NRCS for 774, 778 and 780 as Snoqualmie, Stevens and Stampede passes. NRCS answers "Stations do not exist" for all three. Stevens Pass is 791 and Stampede Pass 788; there is no Snoqualmie Pass SNOTEL, and Olallie Meadows (672) is the station for the pass.
- **Missing data became zero snow.** When a request failed, the fetcher filled in 32 °F, 28 °F and 0 inches and carried on. Those three stations read zero every day from April 1, and on 15 days NRCS was down and every station read zero. The report still ended "NORMAL TERMINATION".
- **The normals were made up.** `baselines.csv` held one April 1 figure per station that doesn't match NRCS (Paradise 50.3 in; NRCS's April 1 median is 72.6 in), and every day of the year was compared against it.
- **The atmospheric river index wasn't a measurement.** It was (snow level − 3000)/1000 + (SWE% − 100)/100. On a dry October 1 it reported "STRONG AR CONDITIONS, PINEAPPLE EXPRESS". The storm classification, stability classes and melt index were invented the same way, and the page recomputed the index with different rules from the program and hard-coded the lapse rate.

So the April write-up's headline, that the passes were bare and the Cascades were at 15% of normal, was an artifact. NRCS's numbers for April 2, 2026 show Olallie Meadows at 24.8 in (46% of median) and Paradise at 38.3 in (53%): a poor year, not a bare one.

## Run it yourself

```bash
sudo apt install gfortran        # Ubuntu / WSL;  macOS: brew install gcc
./run_job.sh                     # or: make
cat cascadia-wx-report.txt
python3 -m http.server           # then open http://localhost:8000
```

On Windows, run it in WSL.

## Sources

- NRCS Air and Water Database (AWDB) REST API: SNOTEL daily data and 1991–2020 medians. SNOTEL air temperatures carry a known sensor bias that NRCS is working on.
- NWS radiosonde observations, from the Iowa Environmental Mesonet RAOB archive.
- Ralph, F. M., et al. (2019). A scale to characterize the strength and impacts of atmospheric rivers. *Bulletin of the American Meteorological Society*, 100(2), 269–289.
- Bolton, D. (1980). The computation of equivalent potential temperature. *Monthly Weather Review*, 108, 1046–1053.

---

```
  CASCADIA-WX  V2.0
  NORMAL TERMINATION.  RETURN CODE 0.
```
