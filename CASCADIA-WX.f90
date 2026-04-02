!=======================================================================!
! CASCADIA-WX.f90                                                       !
! PACIFIC NORTHWEST MOUNTAIN WEATHER ANALYSIS SYSTEM                    !
! Rainier / Olympics / Cascades                                          !
!                                                                       !
! COMPUTATIONS:                                                          !
!   - Environmental lapse rate (temp gradient by elevation)             !
!   - Snow level estimation (precipitation phase boundary)              !
!   - Precipitation phase partitioning (snow vs rain fraction)          !
!   - Degree day accumulation (snowmelt energy budget)                  !
!   - Atmospheric river index (integrated vapor transport proxy)        !
!   - Storm classification (Gulf of AK / Pineapple Express / Cutoff)   !
!   - SWE anomaly (percent of normal vs 30-year median)                !
!   - Station-to-station lapse rate by mountain massif                  !
!                                                                       !
! INPUT:  snotel_data.csv    (NRCS SNOTEL stations)                     !
!         valley_data.csv    (NOAA surface stations)                    !
!         baselines.csv      (30-year SNOTEL medians)                   !
!                                                                       !
! OUTPUT: cascadia-wx-report.txt  (formatted analysis report)           !
!         analysis.csv            (machine-readable results)            !
!                                                                       !
! COMPILE: gfortran -o cascadia-wx CASCADIA-WX.f90 -lm                 !
!=======================================================================!

PROGRAM CASCADIA_WX
  IMPLICIT NONE

  !=== CONSTANTS =========================================================
  REAL, PARAMETER :: DALR        = -9.8      ! Dry Adiabatic Lapse Rate C/km
  REAL, PARAMETER :: MALR        = -6.5      ! Moist Adiabatic Lapse Rate C/km
  REAL, PARAMETER :: ENVLR_STD   = -6.5      ! Standard atmosphere lapse rate
  REAL, PARAMETER :: SNOW_TEMP   =  2.0      ! Rain/snow threshold C
  REAL, PARAMETER :: FREEZE_TEMP =  0.0      ! Freezing point C
  REAL, PARAMETER :: BASE_ELEV   =  0.0      ! Sea level reference m
  REAL, PARAMETER :: M_TO_KM     =  0.001    ! Meters to kilometers
  REAL, PARAMETER :: FT_TO_M     =  0.3048   ! Feet to meters
  REAL, PARAMETER :: IN_TO_MM    =  25.4     ! Inches to mm
  INTEGER, PARAMETER :: MAX_STATIONS = 20
  INTEGER, PARAMETER :: MAX_DAYS     = 30
  INTEGER, PARAMETER :: RPT_WIDTH    = 100

  !=== SNOTEL STATION DATA ===============================================
  INTEGER :: n_snotel
  CHARACTER(LEN=40) :: snotel_name(MAX_STATIONS)
  CHARACTER(LEN=20) :: snotel_id(MAX_STATIONS)
  CHARACTER(LEN=20) :: snotel_massif(MAX_STATIONS)
  REAL :: snotel_elev_ft(MAX_STATIONS)
  REAL :: snotel_elev_m(MAX_STATIONS)
  REAL :: snotel_swe(MAX_STATIONS)        ! inches
  REAL :: snotel_swe_pct(MAX_STATIONS)    ! percent of median
  REAL :: snotel_precip(MAX_STATIONS)     ! inches accumulated
  REAL :: snotel_tmax(MAX_STATIONS)       ! degrees F
  REAL :: snotel_tmin(MAX_STATIONS)       ! degrees F
  REAL :: snotel_tavg_c(MAX_STATIONS)     ! converted to C
  REAL :: snotel_tmax_c(MAX_STATIONS)
  REAL :: snotel_tmin_c(MAX_STATIONS)
  CHARACTER(LEN=10) :: snotel_date(MAX_STATIONS)

  !=== VALLEY STATION DATA (for lapse rate baseline) ====================
  INTEGER :: n_valley
  CHARACTER(LEN=40) :: valley_name(MAX_STATIONS)
  REAL :: valley_elev_m(MAX_STATIONS)
  REAL :: valley_temp_c(MAX_STATIONS)

  !=== BASELINE DATA =====================================================
  CHARACTER(LEN=20) :: bl_id(MAX_STATIONS)
  REAL :: bl_median_swe(MAX_STATIONS)
  INTEGER :: n_baselines

  !=== COMPUTED RESULTS ==================================================
  ! Per-station
  REAL :: lapse_rate(MAX_STATIONS)         ! C/km
  REAL :: snow_level_m(MAX_STATIONS)       ! meters elevation
  REAL :: snow_level_ft(MAX_STATIONS)      ! feet elevation
  REAL :: rain_fraction(MAX_STATIONS)      ! 0.0 to 1.0
  REAL :: snow_fraction(MAX_STATIONS)
  REAL :: hdd(MAX_STATIONS)                ! heating degree days
  REAL :: cdd(MAX_STATIONS)                ! cooling degree days
  REAL :: melt_index(MAX_STATIONS)         ! positive degree days
  REAL :: swe_anomaly(MAX_STATIONS)        ! % of normal

  ! Massif-level
  REAL :: massif_lapse_rate(3)             ! RAINIER / OLYMPICS / CASCADES
  REAL :: massif_avg_swe(3)
  REAL :: massif_avg_pct(3)
  INTEGER :: massif_count(3)
  CHARACTER(LEN=12) :: massif_names(3)
  DATA massif_names / 'RAINIER     ', 'OLYMPICS    ', 'CASCADES    ' /

  ! Basin-wide
  REAL :: ar_index                         ! Atmospheric River proxy index
  INTEGER :: storm_class                   ! 1=Gulf AK, 2=Pineapple, 3=Cutoff
  CHARACTER(LEN=20) :: storm_type
  REAL :: region_snow_level               ! Regional mean snow level ft
  REAL :: region_swe_pct                  ! Regional mean SWE % normal
  REAL :: env_lapse_rate                  ! Environmental lapse rate C/km

  !=== WORK VARIABLES ====================================================
  INTEGER :: i, j, ios, massif_idx
  REAL :: temp_c, elev_diff_km
  REAL :: sum_lapse, count_lapse
  REAL :: valley_ref_temp, valley_ref_elev
  CHARACTER(LEN=200) :: line
  CHARACTER(LEN=10)  :: run_date
  CHARACTER(LEN=8)   :: run_time

  !=== FILE UNITS ========================================================
  INTEGER, PARAMETER :: U_SNOTEL   = 10
  INTEGER, PARAMETER :: U_VALLEY   = 11
  INTEGER, PARAMETER :: U_BASELINE = 12
  INTEGER, PARAMETER :: U_REPORT   = 20
  INTEGER, PARAMETER :: U_CSV      = 21

  !=== INITIALIZE ========================================================
  WRITE(*,'(A)') 'CASCADIA-WX: INITIALIZING...'
  n_snotel   = 0
  n_valley   = 0
  n_baselines = 0
  massif_count   = 0
  massif_avg_swe = 0.0
  massif_avg_pct = 0.0
  massif_lapse_rate = 0.0

  CALL DATE_AND_TIME(DATE=run_date, TIME=run_time)

  !=== LOAD SNOTEL DATA ==================================================
  WRITE(*,'(A)') 'CASCADIA-WX: LOADING SNOTEL DATA...'
  OPEN(UNIT=U_SNOTEL, FILE='snotel_data.csv', STATUS='OLD', &
       ACTION='READ', IOSTAT=ios)
  IF (ios /= 0) THEN
    WRITE(*,'(A)') 'ERROR: snotel_data.csv not found'
    STOP 1
  END IF

  READ(U_SNOTEL, '(A)', IOSTAT=ios) line  ! skip header
  DO
    READ(U_SNOTEL, '(A)', IOSTAT=ios) line
    IF (ios /= 0) EXIT
    IF (LEN_TRIM(line) == 0) CYCLE
    n_snotel = n_snotel + 1
    CALL PARSE_SNOTEL_ROW(line, n_snotel,              &
         snotel_id, snotel_name, snotel_massif,        &
         snotel_elev_ft, snotel_swe, snotel_swe_pct,   &
         snotel_precip, snotel_tmax, snotel_tmin,      &
         snotel_date)
    ! Convert units
    snotel_elev_m(n_snotel) = snotel_elev_ft(n_snotel) * FT_TO_M
    snotel_tmax_c(n_snotel) = (snotel_tmax(n_snotel) - 32.0) * 5.0/9.0
    snotel_tmin_c(n_snotel) = (snotel_tmin(n_snotel) - 32.0) * 5.0/9.0
    snotel_tavg_c(n_snotel) = (snotel_tmax_c(n_snotel) + &
                                snotel_tmin_c(n_snotel)) / 2.0
    WRITE(*,'(A,I2,A,A)') '  STATION ', n_snotel, ': ', &
         TRIM(snotel_name(n_snotel))
  END DO
  CLOSE(U_SNOTEL)
  WRITE(*,'(A,I2,A)') 'CASCADIA-WX: ', n_snotel, ' SNOTEL STATIONS LOADED'

  !=== LOAD VALLEY DATA ==================================================
  WRITE(*,'(A)') 'CASCADIA-WX: LOADING VALLEY STATION DATA...'
  OPEN(UNIT=U_VALLEY, FILE='valley_data.csv', STATUS='OLD', &
       ACTION='READ', IOSTAT=ios)
  IF (ios /= 0) THEN
    WRITE(*,'(A)') 'WARNING: valley_data.csv not found - using standard lapse rate'
    env_lapse_rate = ENVLR_STD
  ELSE
    READ(U_VALLEY, '(A)', IOSTAT=ios) line
    DO
      READ(U_VALLEY, '(A)', IOSTAT=ios) line
      IF (ios /= 0) EXIT
      IF (LEN_TRIM(line) == 0) CYCLE
      n_valley = n_valley + 1
      CALL PARSE_VALLEY_ROW(line, n_valley, valley_name, &
                             valley_elev_m, valley_temp_c)
    END DO
    CLOSE(U_VALLEY)
    WRITE(*,'(A,I2,A)') 'CASCADIA-WX: ', n_valley, ' VALLEY STATIONS LOADED'
  END IF

  !=== LOAD BASELINES ====================================================
  OPEN(UNIT=U_BASELINE, FILE='baselines.csv', STATUS='OLD', &
       ACTION='READ', IOSTAT=ios)
  IF (ios == 0) THEN
    READ(U_BASELINE, '(A)', IOSTAT=ios) line
    DO
      READ(U_BASELINE, '(A)', IOSTAT=ios) line
      IF (ios /= 0) EXIT
      IF (LEN_TRIM(line) == 0) CYCLE
      n_baselines = n_baselines + 1
      CALL PARSE_BASELINE_ROW(line, n_baselines, bl_id, bl_median_swe)
    END DO
    CLOSE(U_BASELINE)
    ! Apply baselines to SNOTEL stations
    DO i = 1, n_snotel
      DO j = 1, n_baselines
        IF (TRIM(snotel_id(i)) == TRIM(bl_id(j))) THEN
          IF (bl_median_swe(j) > 0.0) THEN
            snotel_swe_pct(i) = (snotel_swe(i) / bl_median_swe(j)) * 100.0
          END IF
        END IF
      END DO
    END DO
  END IF

  !=== COMPUTE ENVIRONMENTAL LAPSE RATE =================================
  WRITE(*,'(A)') 'CASCADIA-WX: COMPUTING LAPSE RATES...'
  IF (n_valley > 0) THEN
    ! Use lowest valley station as reference
    valley_ref_temp = valley_temp_c(1)
    valley_ref_elev = valley_elev_m(1)
    sum_lapse   = 0.0
    count_lapse = 0.0
    DO i = 1, n_snotel
      elev_diff_km = (snotel_elev_m(i) - valley_ref_elev) * M_TO_KM
      IF (elev_diff_km > 0.1) THEN
        lapse_rate(i) = (snotel_tavg_c(i) - valley_ref_temp) / elev_diff_km
        sum_lapse   = sum_lapse + lapse_rate(i)
        count_lapse = count_lapse + 1.0
      END IF
    END DO
    IF (count_lapse > 0.0) THEN
      env_lapse_rate = sum_lapse / count_lapse
    ELSE
      env_lapse_rate = ENVLR_STD
    END IF
  ELSE
    env_lapse_rate = ENVLR_STD
    DO i = 1, n_snotel
      lapse_rate(i) = ENVLR_STD
    END DO
  END IF

  !=== COMPUTE SNOW LEVEL AND PHASE PARTITIONING ========================
  WRITE(*,'(A)') 'CASCADIA-WX: COMPUTING SNOW LEVELS...'
  DO i = 1, n_snotel
    ! Snow level = elevation where temp = SNOW_TEMP
    ! T(z) = T_stn + LR * (z - z_stn) --> solve for z where T = SNOW_TEMP
    IF (ABS(env_lapse_rate) > 0.1) THEN
      snow_level_m(i) = snotel_elev_m(i) + &
                        (SNOW_TEMP - snotel_tavg_c(i)) / env_lapse_rate * 1000.0
    ELSE
      snow_level_m(i) = snotel_elev_m(i)
    END IF
    snow_level_ft(i) = snow_level_m(i) / FT_TO_M

    ! Phase partitioning: logistic curve centered on SNOW_TEMP
    ! Below snow_level -> snow; above -> rain
    IF (snotel_elev_m(i) >= snow_level_m(i)) THEN
      snow_fraction(i) = 0.95
      rain_fraction(i) = 0.05
    ELSE IF (snotel_elev_m(i) < snow_level_m(i) - 500.0) THEN
      snow_fraction(i) = 0.05
      rain_fraction(i) = 0.95
    ELSE
      ! Transition zone - linear interpolation
      snow_fraction(i) = 0.05 + 0.90 * &
        (snotel_elev_m(i) - (snow_level_m(i) - 500.0)) / 500.0
      rain_fraction(i) = 1.0 - snow_fraction(i)
    END IF
  END DO

  !=== COMPUTE DEGREE DAYS AND MELT INDEX ================================
  WRITE(*,'(A)') 'CASCADIA-WX: COMPUTING DEGREE DAYS...'
  DO i = 1, n_snotel
    ! Heating degree days (base 65F = 18.3C)
    IF (snotel_tavg_c(i) < 18.3) THEN
      hdd(i) = 18.3 - snotel_tavg_c(i)
    ELSE
      hdd(i) = 0.0
    END IF
    ! Cooling degree days
    IF (snotel_tavg_c(i) > 18.3) THEN
      cdd(i) = snotel_tavg_c(i) - 18.3
    ELSE
      cdd(i) = 0.0
    END IF
    ! Positive degree days (snowmelt index - base 0C)
    melt_index(i) = MAX(0.0, snotel_tavg_c(i))
    ! SWE anomaly
    IF (snotel_swe_pct(i) > 0.0) THEN
      swe_anomaly(i) = snotel_swe_pct(i) - 100.0
    ELSE
      swe_anomaly(i) = 0.0
    END IF
  END DO

  !=== COMPUTE MASSIF AVERAGES ===========================================
  WRITE(*,'(A)') 'CASCADIA-WX: COMPUTING MASSIF SUMMARIES...'
  DO i = 1, n_snotel
    massif_idx = MASSIF_INDEX(snotel_massif(i))
    IF (massif_idx > 0) THEN
      massif_count(massif_idx) = massif_count(massif_idx) + 1
      massif_avg_swe(massif_idx) = massif_avg_swe(massif_idx) + snotel_swe(i)
      massif_avg_pct(massif_idx) = massif_avg_pct(massif_idx) + snotel_swe_pct(i)
    END IF
  END DO
  DO i = 1, 3
    IF (massif_count(i) > 0) THEN
      massif_avg_swe(i) = massif_avg_swe(i) / massif_count(i)
      massif_avg_pct(i) = massif_avg_pct(i) / massif_count(i)
    END IF
  END DO

  !=== ATMOSPHERIC RIVER INDEX ===========================================
  ! Proxy: high SWE accumulation rate + warm temps + high snow level
  ! A real implementation would use IVT from reanalysis data
  WRITE(*,'(A)') 'CASCADIA-WX: COMPUTING AR INDEX...'
  region_snow_level = 0.0
  region_swe_pct    = 0.0
  DO i = 1, n_snotel
    region_snow_level = region_snow_level + snow_level_ft(i)
    region_swe_pct    = region_swe_pct + snotel_swe_pct(i)
  END DO
  IF (n_snotel > 0) THEN
    region_snow_level = region_snow_level / n_snotel
    region_swe_pct    = region_swe_pct / n_snotel
  END IF

  ! AR index: normalized combination of snow level anomaly and precip rate
  ! High snow level + active precip = likely AR conditions
  ar_index = (region_snow_level - 3000.0) / 1000.0 + &
             (region_swe_pct - 100.0) / 100.0

  ! Storm classification based on AR index and lapse rate
  IF (ar_index > 1.5) THEN
    storm_class = 2  ! Pineapple Express - warm, high snow level
    storm_type  = 'PINEAPPLE EXPRESS  '
  ELSE IF (env_lapse_rate < -7.5) THEN
    storm_class = 1  ! Gulf of Alaska - steep lapse rate, unstable
    storm_type  = 'GULF OF ALASKA     '
  ELSE
    storm_class = 3  ! Cutoff Low / Other
    storm_type  = 'CUTOFF LOW / OTHER '
  END IF

  !=== WRITE REPORT ======================================================
  WRITE(*,'(A)') 'CASCADIA-WX: WRITING REPORT...'
  OPEN(UNIT=U_REPORT, FILE='cascadia-wx-report.txt', STATUS='REPLACE', &
       ACTION='WRITE')

  CALL WRITE_REPORT_HEADER(U_REPORT, run_date, n_snotel)
  CALL WRITE_SECTION_I(U_REPORT, n_snotel, snotel_name, snotel_id, &
       snotel_massif, snotel_elev_ft, snotel_swe, snotel_swe_pct, &
       snotel_tmax_c, snotel_tmin_c, snotel_tavg_c, &
       snow_level_ft, snow_fraction, melt_index, snotel_date)
  CALL WRITE_SECTION_II(U_REPORT, n_snotel, snotel_name, snotel_id, &
       snotel_elev_ft, lapse_rate, snow_level_ft, rain_fraction, &
       snow_fraction, env_lapse_rate, region_snow_level)
  CALL WRITE_SECTION_III(U_REPORT, massif_names, massif_count, &
       massif_avg_swe, massif_avg_pct, 3)
  CALL WRITE_SECTION_IV(U_REPORT, ar_index, storm_type, &
       env_lapse_rate, region_snow_level, region_swe_pct)
  CALL WRITE_REPORT_FOOTER(U_REPORT, n_snotel)

  CLOSE(U_REPORT)

  !=== WRITE ANALYSIS CSV ================================================
  OPEN(UNIT=U_CSV, FILE='analysis.csv', STATUS='REPLACE', ACTION='WRITE')
  WRITE(U_CSV,'(A)') 'station_id,station_name,massif,elev_ft,'// &
    'swe_in,swe_pct,tmax_c,tmin_c,tavg_c,'// &
    'snow_level_ft,snow_frac,melt_index,date'
  DO i = 1, n_snotel
    WRITE(U_CSV,'(A,A,A,A,A,F6.0,A,F6.2,A,F6.1,A,F6.1,A,F6.1,A,'// &
                'F6.1,A,F6.1,A,F6.1,A,F6.1,A,F6.3,A,F6.2,A,A,A)') &
      TRIM(snotel_id(i)), ',', &
      '"', TRIM(snotel_name(i)), '",', &
      TRIM(snotel_massif(i)), ',', &
      snotel_elev_ft(i), ',', &
      snotel_swe(i), ',', &
      snotel_swe_pct(i), ',', &
      snotel_tmax_c(i), ',', &
      snotel_tmin_c(i), ',', &
      snotel_tavg_c(i), ',', &
      snow_level_ft(i), ',', &
      snow_fraction(i), ',', &
      melt_index(i), ',', &
      TRIM(snotel_date(i))
  END DO
  CLOSE(U_CSV)

  WRITE(*,'(A)') 'CASCADIA-WX: REPORT WRITTEN TO cascadia-wx-report.txt'
  WRITE(*,'(A)') 'CASCADIA-WX: ANALYSIS WRITTEN TO analysis.csv'
  WRITE(*,'(A)') 'CASCADIA-WX: NORMAL TERMINATION.'

CONTAINS

  !=======================================================================
  INTEGER FUNCTION MASSIF_INDEX(massif_name)
    CHARACTER(LEN=*), INTENT(IN) :: massif_name
    CHARACTER(LEN=20) :: m
    m = ADJUSTL(massif_name)
    IF (INDEX(m,'RAINIER') > 0)  MASSIF_INDEX = 1
    IF (INDEX(m,'OLYMPIC') > 0)  MASSIF_INDEX = 2
    IF (INDEX(m,'CASCADE') > 0)  MASSIF_INDEX = 3
    IF (MASSIF_INDEX < 1 .OR. MASSIF_INDEX > 3) MASSIF_INDEX = 0
  END FUNCTION MASSIF_INDEX

  !=======================================================================
  SUBROUTINE PARSE_SNOTEL_ROW(line, idx, id, name, massif, &
       elev_ft, swe, swe_pct, precip, tmax, tmin, date)
    CHARACTER(LEN=*), INTENT(IN)    :: line
    INTEGER,          INTENT(IN)    :: idx
    CHARACTER(LEN=20), INTENT(INOUT) :: id(*)
    CHARACTER(LEN=40), INTENT(INOUT) :: name(*)
    CHARACTER(LEN=20), INTENT(INOUT) :: massif(*)
    REAL,             INTENT(INOUT) :: elev_ft(*), swe(*), swe_pct(*)
    REAL,             INTENT(INOUT) :: precip(*), tmax(*), tmin(*)
    CHARACTER(LEN=10), INTENT(INOUT) :: date(*)
    CHARACTER(LEN=20) :: fields(10)
    INTEGER :: nf
    CALL SPLIT_CSV(line, fields, nf, 10)
    IF (nf >= 9) THEN
      id(idx)      = TRIM(fields(1))
      name(idx)    = TRIM(fields(2))
      massif(idx)  = TRIM(fields(3))
      READ(fields(4), *, ERR=99) elev_ft(idx)
      READ(fields(5), *, ERR=99) swe(idx)
      READ(fields(6), *, ERR=99) swe_pct(idx)
      READ(fields(7), *, ERR=99) tmax(idx)
      READ(fields(8), *, ERR=99) tmin(idx)
      READ(fields(9), *, ERR=99) precip(idx)
      IF (nf >= 10) date(idx) = TRIM(fields(10))
    END IF
    99 RETURN
  END SUBROUTINE PARSE_SNOTEL_ROW

  !=======================================================================
  SUBROUTINE PARSE_VALLEY_ROW(line, idx, name, elev_m, temp_c)
    CHARACTER(LEN=*), INTENT(IN)     :: line
    INTEGER,          INTENT(IN)     :: idx
    CHARACTER(LEN=40), INTENT(INOUT) :: name(*)
    REAL,             INTENT(INOUT)  :: elev_m(*), temp_c(*)
    CHARACTER(LEN=20) :: fields(5)
    INTEGER :: nf
    CALL SPLIT_CSV(line, fields, nf, 5)
    IF (nf >= 3) THEN
      name(idx) = TRIM(fields(1))
      READ(fields(2), *, ERR=99) elev_m(idx)
      READ(fields(3), *, ERR=99) temp_c(idx)
    END IF
    99 RETURN
  END SUBROUTINE PARSE_VALLEY_ROW

  !=======================================================================
  SUBROUTINE PARSE_BASELINE_ROW(line, idx, id, median_swe)
    CHARACTER(LEN=*), INTENT(IN)     :: line
    INTEGER,          INTENT(IN)     :: idx
    CHARACTER(LEN=20), INTENT(INOUT) :: id(*)
    REAL,             INTENT(INOUT)  :: median_swe(*)
    CHARACTER(LEN=20) :: fields(5)
    INTEGER :: nf
    CALL SPLIT_CSV(line, fields, nf, 5)
    IF (nf >= 2) THEN
      id(idx) = TRIM(fields(1))
      READ(fields(2), *, ERR=99) median_swe(idx)
    END IF
    99 RETURN
  END SUBROUTINE PARSE_BASELINE_ROW

  !=======================================================================
  SUBROUTINE SPLIT_CSV(line, fields, nf, max_fields)
    CHARACTER(LEN=*), INTENT(IN)  :: line
    CHARACTER(LEN=20), INTENT(OUT) :: fields(*)
    INTEGER, INTENT(OUT) :: nf
    INTEGER, INTENT(IN)  :: max_fields
    INTEGER :: i, start, flen
    nf    = 1
    start = 1
    fields(1) = ''
    flen  = LEN_TRIM(line)
    DO i = 1, flen
      IF (line(i:i) == ',') THEN
        IF (nf < max_fields) THEN
          fields(nf) = TRIM(ADJUSTL(line(start:i-1)))
          nf    = nf + 1
          start = i + 1
          fields(nf) = ''
        END IF
      END IF
    END DO
    fields(nf) = TRIM(ADJUSTL(line(start:flen)))
  END SUBROUTINE SPLIT_CSV

  !=======================================================================
  SUBROUTINE WRITE_REPORT_HEADER(unit, run_date, n)
    INTEGER, INTENT(IN)           :: unit, n
    CHARACTER(LEN=*), INTENT(IN)  :: run_date
    WRITE(unit,'(A)') REPEAT('=', 100)
    WRITE(unit,'(A)')
    WRITE(unit,'(A)') '              CASCADIA-WX  //  PACIFIC NORTHWEST MOUNTAIN WEATHER ANALYSIS'
    WRITE(unit,'(A)') '                     RAINIER  ·  OLYMPICS  ·  CASCADES'
    WRITE(unit,'(A)')
    WRITE(unit,'(A,A4,A,A2,A,A2)') '                          PROCESSING DATE: ', &
      run_date(1:4), '-', run_date(5:6), '-', run_date(7:8)
    WRITE(unit,'(A)')
    WRITE(unit,'(A)') REPEAT('=', 100)
    WRITE(unit,'(A)')
  END SUBROUTINE WRITE_REPORT_HEADER

  !=======================================================================
  SUBROUTINE WRITE_SECTION_I(unit, n, name, id, massif, elev_ft, &
       swe, swe_pct, tmax_c, tmin_c, tavg_c, &
       snow_level_ft, snow_frac, melt_idx, date)
    INTEGER, INTENT(IN) :: unit, n
    CHARACTER(LEN=40), INTENT(IN) :: name(*)
    CHARACTER(LEN=20), INTENT(IN) :: id(*), massif(*)
    CHARACTER(LEN=10), INTENT(IN) :: date(*)
    REAL, INTENT(IN) :: elev_ft(*), swe(*), swe_pct(*)
    REAL, INTENT(IN) :: tmax_c(*), tmin_c(*), tavg_c(*)
    REAL, INTENT(IN) :: snow_level_ft(*), snow_frac(*), melt_idx(*)
    INTEGER :: i
    CHARACTER(LEN=6) :: phase_str

    WRITE(unit,'(A)') 'SECTION I: SNOTEL STATION ANALYSIS'
    WRITE(unit,'(A)')
    WRITE(unit,'(A)') '  STATION                            MASSIF     ELEV(FT)' // &
      '  SWE(IN)  %NORM  TMAX-C  TMIN-C  TAVG-C  SNOLVL(FT)  PHASE    MELT-IDX'
    WRITE(unit,'(A)') REPEAT('-', 100)

    DO i = 1, n
      IF (snow_frac(i) >= 0.8) THEN
        phase_str = 'SNOW  '
      ELSE IF (snow_frac(i) <= 0.2) THEN
        phase_str = 'RAIN  '
      ELSE
        phase_str = 'MIXED '
      END IF

      WRITE(unit,'(2X,A30,2X,A10,F8.0,F8.2,F7.1,F8.1,F8.1,F8.1,F12.0,2X,A6,F9.2)') &
        name(i)(1:30), massif(i)(1:10), elev_ft(i), &
        swe(i), swe_pct(i), tmax_c(i), tmin_c(i), tavg_c(i), &
        snow_level_ft(i), phase_str, melt_idx(i)
    END DO
    WRITE(unit,'(A)')
  END SUBROUTINE WRITE_SECTION_I

  !=======================================================================
  SUBROUTINE WRITE_SECTION_II(unit, n, name, id, elev_ft, &
       lapse_rate, snow_level_ft, rain_frac, snow_frac, &
       env_lr, region_snolvl)
    INTEGER, INTENT(IN) :: unit, n
    CHARACTER(LEN=40), INTENT(IN) :: name(*)
    CHARACTER(LEN=20), INTENT(IN) :: id(*)
    REAL, INTENT(IN) :: elev_ft(*), lapse_rate(*)
    REAL, INTENT(IN) :: snow_level_ft(*), rain_frac(*), snow_frac(*)
    REAL, INTENT(IN) :: env_lr, region_snolvl
    INTEGER :: i

    WRITE(unit,'(A)') 'SECTION II: LAPSE RATE & PRECIPITATION PHASE ANALYSIS'
    WRITE(unit,'(A)')
    WRITE(unit,'(A,F6.2,A)') '  ENVIRONMENTAL LAPSE RATE:  ', env_lr, ' C/km'
    WRITE(unit,'(A,F6.2,A)') '  DRY ADIABATIC LAPSE RATE:  -9.80 C/km'
    WRITE(unit,'(A,F6.2,A)') '  MOIST ADIABATIC LAPSE RATE: -6.50 C/km'
    WRITE(unit,'(A,F7.0,A)') '  REGIONAL MEAN SNOW LEVEL:  ', region_snolvl, ' ft'
    WRITE(unit,'(A)')
    WRITE(unit,'(A)') '  STATION                            ELEV(FT)  LPS(C/km)' // &
      '  SNOLVL(FT)  SNOW%   RAIN%   STABILITY'
    WRITE(unit,'(A)') REPEAT('-', 100)

    DO i = 1, n
      WRITE(unit,'(2X,A30,F10.0,F10.2,F12.0,F8.1,F8.1,4X,A)') &
        name(i)(1:30), elev_ft(i), lapse_rate(i), &
        snow_level_ft(i), snow_frac(i)*100.0, rain_frac(i)*100.0, &
        STABILITY_CLASS(lapse_rate(i))
    END DO
    WRITE(unit,'(A)')
  END SUBROUTINE WRITE_SECTION_II

  !=======================================================================
  CHARACTER(LEN=12) FUNCTION STABILITY_CLASS(lr)
    REAL, INTENT(IN) :: lr
    IF (lr < -9.8) THEN
      STABILITY_CLASS = 'UNSTABLE    '
    ELSE IF (lr < -6.5) THEN
      STABILITY_CLASS = 'COND UNSTBL '
    ELSE IF (lr < -5.0) THEN
      STABILITY_CLASS = 'NEUTRAL     '
    ELSE
      STABILITY_CLASS = 'STABLE      '
    END IF
  END FUNCTION STABILITY_CLASS

  !=======================================================================
  SUBROUTINE WRITE_SECTION_III(unit, names, counts, avg_swe, avg_pct, n)
    INTEGER, INTENT(IN) :: unit, n
    CHARACTER(LEN=12), INTENT(IN) :: names(*)
    INTEGER, INTENT(IN) :: counts(*)
    REAL, INTENT(IN) :: avg_swe(*), avg_pct(*)
    INTEGER :: i
    CHARACTER(LEN=20) :: swe_status

    WRITE(unit,'(A)') 'SECTION III: MOUNTAIN MASSIF SNOWPACK SUMMARY'
    WRITE(unit,'(A)')
    WRITE(unit,'(A)') '  MASSIF        STATIONS  AVG SWE (IN)  AVG % NORMAL  STATUS'
    WRITE(unit,'(A)') REPEAT('-', 60)

    DO i = 1, n
      IF (avg_pct(i) > 130.0) THEN
        swe_status = 'WELL ABOVE NORMAL '
      ELSE IF (avg_pct(i) > 110.0) THEN
        swe_status = 'ABOVE NORMAL      '
      ELSE IF (avg_pct(i) >= 90.0) THEN
        swe_status = 'NEAR NORMAL       '
      ELSE IF (avg_pct(i) >= 70.0) THEN
        swe_status = 'BELOW NORMAL      '
      ELSE
        swe_status = 'WELL BELOW NORMAL '
      END IF
      WRITE(unit,'(2X,A12,I8,F14.2,F14.1,2X,A)') &
        names(i), counts(i), avg_swe(i), avg_pct(i), TRIM(swe_status)
    END DO
    WRITE(unit,'(A)')
  END SUBROUTINE WRITE_SECTION_III

  !=======================================================================
  SUBROUTINE WRITE_SECTION_IV(unit, ar_idx, storm_type, &
       env_lr, region_snolvl, region_swe_pct)
    INTEGER, INTENT(IN)          :: unit
    REAL, INTENT(IN)             :: ar_idx, env_lr
    REAL, INTENT(IN)             :: region_snolvl, region_swe_pct
    CHARACTER(LEN=*), INTENT(IN) :: storm_type
    CHARACTER(LEN=30) :: ar_status

    IF (ar_idx > 2.0) THEN
      ar_status = 'STRONG AR CONDITIONS        '
    ELSE IF (ar_idx > 1.0) THEN
      ar_status = 'MODERATE AR CONDITIONS      '
    ELSE IF (ar_idx > 0.0) THEN
      ar_status = 'WEAK AR SIGNATURE           '
    ELSE
      ar_status = 'NO AR CONDITIONS            '
    END IF

    WRITE(unit,'(A)') 'SECTION IV: ATMOSPHERIC ANALYSIS'
    WRITE(unit,'(A)')
    WRITE(unit,'(A,F7.2)')  '  ATMOSPHERIC RIVER INDEX:    ', ar_idx
    WRITE(unit,'(A,A)')     '  AR STATUS:                  ', TRIM(ar_status)
    WRITE(unit,'(A,A)')     '  STORM CLASSIFICATION:       ', TRIM(storm_type)
    WRITE(unit,'(A,F7.2,A)') '  ENVIRONMENTAL LAPSE RATE:  ', env_lr, ' C/km'
    WRITE(unit,'(A,F7.0,A)') '  REGIONAL SNOW LEVEL:       ', region_snolvl, ' ft'
    WRITE(unit,'(A,F7.1,A)') '  REGIONAL SWE % NORMAL:     ', region_swe_pct, '%'
    WRITE(unit,'(A)')
  END SUBROUTINE WRITE_SECTION_IV

  !=======================================================================
  SUBROUTINE WRITE_REPORT_FOOTER(unit, n)
    INTEGER, INTENT(IN) :: unit, n
    WRITE(unit,'(A)') REPEAT('=', 100)
    WRITE(unit,'(A,I3,A)') '  END OF REPORT  //  ', n, ' STATIONS PROCESSED'
    WRITE(unit,'(A)') '  CASCADIA-WX  //  NORMAL TERMINATION.'
    WRITE(unit,'(A)') REPEAT('=', 100)
  END SUBROUTINE WRITE_REPORT_FOOTER

END PROGRAM CASCADIA_WX
