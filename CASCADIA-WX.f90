!=====================================================================
! CASCADIA-WX.f90                                       VERSION 2.0
! PACIFIC NORTHWEST MOUNTAIN WEATHER ANALYSIS
! RAINIER - OLYMPICS - CASCADES
!
! WHAT IT COMPUTES
!   SNOWPACK  12 NRCS SNOTEL STATIONS. SNOW WATER EQUIVALENT AND
!             WATER-YEAR PRECIPITATION AGAINST NRCS 1991-2020 DAILY
!             MEDIANS. MASSIF INDEX = SUM OF SWE / SUM OF MEDIANS,
!             THE WAY NRCS COMPUTES A BASIN INDEX.
!   UPPER AIR THE QUILLAYUTE (KUIL) WEATHER BALLOON, TWICE A DAY.
!             FREEZING LEVEL, WET-BULB ZERO, SNOW LEVEL, PRECIPITABLE
!             WATER AND INTEGRATED VAPOUR TRANSPORT (IVT), THE
!             QUANTITY THAT DEFINES AN ATMOSPHERIC RIVER.
!   LAPSE     FREE-AIR LAPSE RATE 850-700 HPA FROM THE BALLOON, AND
!             THE MOUNTAIN-SURFACE LAPSE RATE FROM A LEAST-SQUARES
!             FIT OF SNOTEL TEMPERATURE AGAINST ELEVATION.
!   REVIEW    LAST WATER YEAR: PEAK SWE AND MELT-OUT AGAINST MEDIAN.
!
! INPUT    stations.csv        THE 12 STATIONS (CHECKED AGAINST NRCS)
!          snotel_daily.csv    FROM fetch_wx.py
!          soundings_raw.csv   FROM fetch_wx.py
!          fetch_status.csv    FROM fetch_wx.py
!          sounding_series.csv EARLIER SOUNDINGS (UPDATED IN PLACE)
! OUTPUT   cascadia-wx-report.txt   132-COLUMN PRINTED REPORT
!          analysis.csv  massif.csv  review.csv  upper_air.csv
!          sounding_series.csv  summary.csv
!
! RETURN CODES   0  NORMAL
!                4  WARNING: A STATION OR THE SOUNDING IS MISSING
!                   OR STALE. THE REPORT SAYS WHICH.
!                8  NO SNOTEL DATA AT ALL. NOTHING WRITTEN.
!               12  AN INPUT FILE CANNOT BE OPENED.
!
! COMPILE  gfortran -O2 -o cascadia-wx CASCADIA-WX.f90
!=====================================================================

module cwx_util
  implicit none
  integer, parameter :: dp = kind(1.0d0)
  real(dp), parameter :: miss = -9999.0_dp
  integer, parameter :: maxf = 24
  character(len=3), parameter :: mon(12) = [character(len=3) :: &
    'JAN','FEB','MAR','APR','MAY','JUN', &
    'JUL','AUG','SEP','OCT','NOV','DEC']
contains

  logical function ok(x)
    real(dp), intent(in) :: x
    ok = x > miss + 1.0_dp
  end function ok

  ! split a comma-separated line; empty fields stay empty
  subroutine split(line, f, n)
    character(len=*), intent(in) :: line
    character(len=64), intent(out) :: f(maxf)
    integer, intent(out) :: n
    integer :: i, s, l
    f = ' '
    n = 1
    s = 1
    l = len_trim(line)
    do i = 1, l
      if (line(i:i) == ',') then
        if (i > s) f(n) = adjustl(line(s:i-1))
        if (n < maxf) n = n + 1
        s = i + 1
      end if
    end do
    if (l >= s) f(n) = adjustl(line(s:l))
  end subroutine split

  real(dp) function rval(s)
    character(len=*), intent(in) :: s
    integer :: ios
    rval = miss
    if (len_trim(s) == 0) return
    read(s, *, iostat=ios) rval
    if (ios /= 0) rval = miss
  end function rval

  ! julian day number of a calendar date
  integer function jdn(y, m, d)
    integer, intent(in) :: y, m, d
    integer :: a, yy, mm
    a = (14 - m) / 12
    yy = y + 4800 - a
    mm = m + 12*a - 3
    jdn = d + (153*mm + 2)/5 + 365*yy + yy/4 - yy/100 &
        + yy/400 - 32045
  end function jdn

  subroutine ymd(j, y, m, d)
    integer, intent(in) :: j
    integer, intent(out) :: y, m, d
    integer :: a, b, c, e, f
    a = j + 32044
    b = (4*a + 3) / 146097
    c = a - 146097*b/4
    e = (4*c + 3) / 1461
    f = c - 1461*e/4
    m = (5*f + 2) / 153
    d = f - (153*m + 2)/5 + 1
    y = 100*b + e - 4800 + m/10
    m = m + 3 - 12*(m/10)
  end subroutine ymd

  integer function jdn_s(s)          ! 'YYYY-MM-DD'
    character(len=*), intent(in) :: s
    integer :: y, m, d, ios
    jdn_s = 0
    if (len_trim(s) < 10) return
    read(s(1:4), *, iostat=ios) y
    if (ios /= 0) return
    read(s(6:7), *, iostat=ios) m
    if (ios /= 0) return
    read(s(9:10), *, iostat=ios) d
    if (ios /= 0) return
    jdn_s = jdn(y, m, d)
  end function jdn_s

  character(len=10) function dstr(j)
    integer, intent(in) :: j
    integer :: y, m, d
    call ymd(j, y, m, d)
    write(dstr, '(I4.4,A,I2.2,A,I2.2)') y, '-', m, '-', d
  end function dstr

  character(len=6) function mstr(j)  ! 'APR 02'
    integer, intent(in) :: j
    integer :: y, m, d
    call ymd(j, y, m, d)
    write(mstr, '(A3,1X,I2.2)') mon(m), d
  end function mstr

  ! fixed-width number for the report; '--' when missing
  function rf(x, w, d) result(s)
    real(dp), intent(in) :: x
    integer, intent(in) :: w, d
    character(len=w) :: s
    character(len=16) :: fm
    if (.not. ok(x)) then
      s = repeat(' ', w-2) // '--'
      return
    end if
    if (d == 0) then
      write(fm, '(A,I0,A)') '(I', w, ')'
      write(s, fm) nint(x)
    else
      write(fm, '(A,I0,A,I0,A)') '(F', w, '.', d, ')'
      write(s, fm) x
    end if
  end function rf

  ! trimmed number for csv; empty when missing
  function cs(x, d) result(s)
    real(dp), intent(in) :: x
    integer, intent(in) :: d
    character(len=:), allocatable :: s
    character(len=24) :: b
    character(len=16) :: fm
    if (.not. ok(x)) then
      s = ''
      return
    end if
    if (d == 0) then
      write(b, '(I24)') nint(x)
    else
      write(fm, '(A,I0,A)') '(F24.', d, ')'
      write(b, fm) x
    end if
    s = trim(adjustl(b))
    if (s(1:1) == '.') s = '0' // s
    if (len(s) > 1) then
      if (s(1:2) == '-.') s = '-0' // s(2:)
    end if
  end function cs

  character(len=20) function itoa(i)
    integer, intent(in) :: i
    write(itoa, '(I0)') i
  end function itoa

end module cwx_util

!=====================================================================
module cwx_phys
  use cwx_util
  implicit none
  real(dp), parameter :: grav = 9.80665_dp
  real(dp), parameter :: kt2ms = 0.514444_dp
  real(dp), parameter :: m2ft = 3.28084_dp
  real(dp), parameter :: pi = 3.14159265358979_dp
  integer, parameter :: maxl = 600

  type sounding
    integer :: key = 0              ! YYYYMMDDHH, UTC
    real(dp) :: psfc = miss, ptop = miss, zsfc = miss
    real(dp) :: fl = miss           ! freezing level, m
    real(dp) :: wbz = miss          ! wet-bulb zero, m
    real(dp) :: pw = miss           ! precipitable water, mm
    real(dp) :: ivt = miss          ! kg m-1 s-1
    real(dp) :: ivtdir = miss       ! direction it comes from
    real(dp) :: t850 = miss
    real(dp) :: lapse = miss        ! 850-700 hPa, C per km
    real(dp) :: w7dir = miss, w7kt = miss
  end type sounding

contains

  ! saturation vapour pressure over water, hPa (Bolton 1980)
  real(dp) function esat(t)
    real(dp), intent(in) :: t
    esat = 6.112_dp * exp(17.67_dp * t / (t + 243.5_dp))
  end function esat

  ! specific humidity, kg/kg, from pressure and dew point
  real(dp) function qspec(p, td)
    real(dp), intent(in) :: p, td
    real(dp) :: e
    e = esat(td)
    qspec = 0.622_dp * e / (p - 0.378_dp * e)
  end function qspec

  ! wet-bulb temperature: solve the psychrometric equation
  !   esat(tw) - gamma * p * (t - tw) = e   by bisection
  real(dp) function wetbulb(p, t, td)
    real(dp), intent(in) :: p, t, td
    real(dp) :: lo, hi, mid, e, f
    integer :: k
    e = esat(td)
    lo = td
    hi = t
    do k = 1, 40
      mid = 0.5_dp * (lo + hi)
      f = esat(mid) - 6.60e-4_dp * (1.0_dp + 0.00115_dp * mid) &
          * p * (t - mid) - e
      if (f > 0.0_dp) then
        hi = mid
      else
        lo = mid
      end if
    end do
    wetbulb = 0.5_dp * (lo + hi)
  end function wetbulb

  ! value of y at pressure pt, linear in ln p, from valid levels
  real(dp) function at_p(n, p, y, pt)
    integer, intent(in) :: n
    real(dp), intent(in) :: p(n), y(n), pt
    integer :: i, lo, hi
    at_p = miss
    lo = 0
    hi = 0
    do i = 1, n                     ! p decreases with i
      if (.not. ok(y(i))) cycle
      if (p(i) >= pt) lo = i
      if (p(i) <= pt .and. hi == 0) hi = i
    end do
    if (lo == 0 .or. hi == 0) return
    if (lo == hi) then
      at_p = y(lo)
      return
    end if
    at_p = y(lo) + (y(hi) - y(lo)) * log(pt / p(lo)) &
           / log(p(hi) / p(lo))
  end function at_p

  ! lowest height where y falls through zero going up
  real(dp) function zero_height(n, z, y)
    integer, intent(in) :: n
    real(dp), intent(in) :: z(n), y(n)
    integer :: i, prev
    zero_height = miss
    prev = 0
    do i = 1, n
      if (.not. ok(y(i)) .or. .not. ok(z(i))) cycle
      if (prev == 0) then
        if (y(i) <= 0.0_dp) then   ! freezing at the ground
          zero_height = z(i)
          return
        end if
      else if (y(prev) > 0.0_dp .and. y(i) <= 0.0_dp) then
        zero_height = z(prev) + (0.0_dp - y(prev)) &
          * (z(i) - z(prev)) / (y(i) - y(prev))
        return
      end if
      prev = i
    end do
  end function zero_height

  ! analyse one sounding. levels must be ordered by falling p.
  ! on return tw and q (g/kg) are filled for the profile output.
  subroutine analyse(s, n, p, z, t, td, dir, kt, tw, qg)
    type(sounding), intent(inout) :: s
    integer, intent(in) :: n
    real(dp), intent(in) :: p(n), t(n), td(n), dir(n), kt(n)
    real(dp), intent(inout) :: z(n)
    real(dp), intent(out) :: tw(n), qg(n)
    real(dp) :: q(n), u(n), v(n), uu(n), vv(n), qq(n)
    real(dp) :: pp(maxl+1), fq(maxl+1), fu(maxl+1), fv(maxl+1)
    real(dp) :: a, iu, iv, z8, z7, t7, u7, v7
    integer :: i, m, top

    s%psfc = p(1)
    s%ptop = p(n)
    ! heights missing on a few significant levels: fill in ln p
    do i = 1, n
      if (.not. ok(z(i))) z(i) = at_p(n, p, z, p(i))
    end do
    s%zsfc = z(1)
    tw = miss
    q = miss
    u = miss
    v = miss
    do i = 1, n
      if (ok(td(i))) then
        tw(i) = wetbulb(p(i), t(i), td(i))
        q(i) = qspec(p(i), td(i))
      end if
      if (ok(dir(i)) .and. ok(kt(i))) then
        a = dir(i) * pi / 180.0_dp
        u(i) = -kt(i) * kt2ms * sin(a)
        v(i) = -kt(i) * kt2ms * cos(a)
      end if
    end do
    s%fl = zero_height(n, z, t)
    s%wbz = zero_height(n, z, tw)

    ! fill gaps: q and wind in ln p; q is zero above the
    ! highest humidity report (dew point is not reported in
    ! the cold, dry upper air); wind keeps its nearest value
    top = 0
    do i = 1, n
      if (ok(q(i))) top = i
    end do
    do i = 1, n
      qq(i) = q(i)
      if (.not. ok(qq(i))) then
        if (i > top) then
          qq(i) = 0.0_dp
        else
          qq(i) = at_p(n, p, q, p(i))
        end if
      end if
      uu(i) = at_p(n, p, u, p(i))
      vv(i) = at_p(n, p, v, p(i))
      if (.not. ok(uu(i))) uu(i) = near_ok(i, u)
      if (.not. ok(vv(i))) vv(i) = near_ok(i, v)
    end do
    qg = miss
    do i = 1, n
      if (ok(q(i))) qg(i) = q(i) * 1000.0_dp
    end do

    ! integrate surface to 300 hPa:  (1/g) * integral q V dp
    if (s%ptop <= 300.0_dp .and. top > 0) then
      m = 0
      do i = 1, n
        if (p(i) < 300.0_dp) exit
        if (.not. ok(qq(i)) .or. .not. ok(uu(i))) cycle
        m = m + 1
        pp(m) = p(i)
        fq(m) = qq(i)
        fu(m) = qq(i) * uu(i)
        fv(m) = qq(i) * vv(i)
      end do
      if (m > 0) then
        if (pp(m) > 300.0_dp) then
          m = m + 1
          pp(m) = 300.0_dp
          fq(m) = at_p(n, p, qq, 300.0_dp)
          fu(m) = fq(m) * at_p(n, p, uu, 300.0_dp)
          fv(m) = fq(m) * at_p(n, p, vv, 300.0_dp)
        end if
        s%pw = 0.0_dp
        iu = 0.0_dp
        iv = 0.0_dp
        do i = 1, m - 1
          a = (pp(i) - pp(i+1)) * 100.0_dp / grav
          s%pw = s%pw + 0.5_dp * (fq(i) + fq(i+1)) * a
          iu = iu + 0.5_dp * (fu(i) + fu(i+1)) * a
          iv = iv + 0.5_dp * (fv(i) + fv(i+1)) * a
        end do
        s%ivt = sqrt(iu*iu + iv*iv)
        s%ivtdir = modulo(atan2(-iu, -iv) * 180.0_dp / pi, &
                          360.0_dp)
      end if
    end if

    s%t850 = at_p(n, p, t, 850.0_dp)
    t7 = at_p(n, p, t, 700.0_dp)
    z8 = at_p(n, p, z, 850.0_dp)
    z7 = at_p(n, p, z, 700.0_dp)
    if (ok(s%t850) .and. ok(t7) .and. ok(z8) .and. ok(z7)) &
      s%lapse = -(t7 - s%t850) / (z7 - z8) * 1000.0_dp
    u7 = at_p(n, p, u, 700.0_dp)
    v7 = at_p(n, p, v, 700.0_dp)
    if (ok(u7) .and. ok(v7)) then
      s%w7kt = sqrt(u7*u7 + v7*v7) / kt2ms
      s%w7dir = modulo(atan2(-u7, -v7) * 180.0_dp / pi, &
                       360.0_dp)
    end if
  contains
    real(dp) function near_ok(k, y)
      integer, intent(in) :: k
      real(dp), intent(in) :: y(n)
      integer :: j, best
      best = 0
      do j = 1, n
        if (.not. ok(y(j))) cycle
        if (best == 0) best = j
        if (abs(j - k) < abs(best - k)) best = j
      end do
      near_ok = miss
      if (best > 0) near_ok = y(best)
    end function near_ok
  end subroutine analyse

  ! atmospheric river strength from IVT (Ralph et al. 2019)
  character(len=12) function ar_cat(ivt)
    real(dp), intent(in) :: ivt
    if (.not. ok(ivt)) then
      ar_cat = 'NO DATA'
    else if (ivt < 250.0_dp) then
      ar_cat = 'NONE'
    else if (ivt < 500.0_dp) then
      ar_cat = 'WEAK'
    else if (ivt < 750.0_dp) then
      ar_cat = 'MODERATE'
    else if (ivt < 1000.0_dp) then
      ar_cat = 'STRONG'
    else if (ivt < 1250.0_dp) then
      ar_cat = 'EXTREME'
    else
      ar_cat = 'EXCEPTIONAL'
    end if
  end function ar_cat

  character(len=3) function compass(d)
    real(dp), intent(in) :: d
    character(len=3), parameter :: c(16) = [character(len=3) :: &
      'N','NNE','NE','ENE','E','ESE','SE','SSE', &
      'S','SSW','SW','WSW','W','WNW','NW','NNW']
    compass = '--'
    if (ok(d)) compass = c(modulo(nint(d / 22.5_dp), 16) + 1)
  end function compass

end module cwx_phys

!=====================================================================
program cascadia_wx
  use cwx_util
  use cwx_phys
  implicit none

  integer, parameter :: maxs = 20, maxd = 800, maxser = 4000
  integer, parameter :: ust = 10, urp = 20, uout = 21
  character(len=*), parameter :: ver = 'CASCADIA-WX V2.0'

  ! stations
  integer :: ns
  character(len=12) :: trip(maxs)
  character(len=20) :: sname(maxs)
  character(len=8) :: smass(maxs)
  real(dp) :: elev(maxs), slat(maxs), slon(maxs)

  ! daily snotel, day index 1 = Oct 1 of last water year
  real(dp) :: swe(maxs,maxd), swem(maxs,maxd), dep(maxs,maxd)
  real(dp) :: prc(maxs,maxd), prcm(maxs,maxd), tav(maxs,maxd)

  ! per-station results on the data date
  real(dp) :: r_swe(maxs), r_med(maxs), r_pct(maxs), r_chg(maxs)
  real(dp) :: r_dep(maxs), r_prc(maxs), r_prm(maxs), r_ppc(maxs)
  real(dp) :: r_tav(maxs)
  integer :: r_last(maxs)
  logical :: r_stale(maxs)

  ! last water year
  real(dp) :: v_peak(maxs), v_mpeak(maxs), v_pct(maxs)
  integer :: v_pday(maxs), v_mpday(maxs), v_out(maxs)
  integer :: v_mout(maxs)

  ! massifs
  character(len=8), parameter :: mname(3) = [character(len=8) :: &
    'RAINIER', 'OLYMPICS', 'CASCADES']
  real(dp) :: m_swe(4), m_med(4), m_pct(4), m_prc(4), m_prm(4)
  real(dp) :: m_ppc(4), m_pk(4), m_mpk(4)
  integer :: m_n(4)
  character(len=18) :: m_cls(4)

  ! soundings
  type(sounding) :: ser(maxser), snew
  integer :: nser
  real(dp) :: lp(maxl), lz(maxl), lt(maxl), ltd(maxl)
  real(dp) :: ldir(maxl), lkt(maxl), ltw(maxl), lq(maxl)
  real(dp) :: kp(maxl), kz(maxl), kt_(maxl), ktd(maxl)
  real(dp) :: kdir(maxl), kkt(maxl), ktw(maxl), kq(maxl)
  integer :: nl, nk, cur, nnew, latest

  ! mountain lapse rate
  real(dp) :: mslope, mr2
  integer :: mn, tday

  ! run
  character(len=10) :: pdate
  character(len=16) :: runutc
  character(len=64) :: f(maxf)
  character(len=512) :: line
  character(len=80) :: msg(60)
  integer :: nmsg, rc, ios, nf, i, j, k, d, base, nday, dd
  integer :: wy, wy0, wy1, py0, py1, today, nrows, nskip
  integer :: soundings_in
  real(dp) :: x, y, sx, sy, sxx, sxy, syy
  character(len=8) :: cdate
  character(len=10) :: ctime

  rc = 0
  nmsg = 0
  call date_and_time(date=cdate, time=ctime)
  write(*,'(A)') 'CWX000I ' // ver // ' STARTED ' // cdate(1:4) &
    // '-' // cdate(5:6) // '-' // cdate(7:8) // ' ' // &
    ctime(1:2) // ':' // ctime(3:4) // ':' // ctime(5:6)

  !-- fetch status: today's Pacific date --------------------------
  pdate = ' '
  runutc = ' '
  open(ust, file='fetch_status.csv', status='old', iostat=ios)
  if (ios == 0) then
    do
      read(ust, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      if (f(1) == 'pacific_date') pdate = f(2)(1:10)
      if (f(1) == 'run_utc') runutc = f(2)(1:16)
    end do
    close(ust)
  end if
  if (pdate == ' ') then
    pdate = cdate(1:4) // '-' // cdate(5:6) // '-' // cdate(7:8)
    call note('CWX010W NO fetch_status.csv: USING THE CLOCK', 0)
  end if
  if (runutc == ' ') runutc = pdate
  today = jdn_s(pdate)
  call ymd(today, wy, i, j)
  if (i >= 10) wy = wy + 1
  base = jdn(wy - 2, 10, 1)       ! day 1
  nday = today - base + 1

  !-- stations ----------------------------------------------------
  ns = 0
  open(ust, file='stations.csv', status='old', iostat=ios)
  if (ios /= 0) call fail('stations.csv')
  read(ust, '(A)', iostat=ios) line
  do
    read(ust, '(A)', iostat=ios) line
    if (ios /= 0) exit
    if (len_trim(line) == 0) cycle
    call split(line, f, nf)
    if (nf < 6 .or. ns == maxs) cycle
    ns = ns + 1
    trip(ns) = f(1)
    sname(ns) = f(2)
    smass(ns) = f(3)
    elev(ns) = rval(f(4))
    slat(ns) = rval(f(5))
    slon(ns) = rval(f(6))
  end do
  close(ust)
  write(*,'(A,I6)') 'CWX001I STATIONS LOADED ............', ns

  !-- snotel daily ------------------------------------------------
  swe = miss
  swem = miss
  dep = miss
  prc = miss
  prcm = miss
  tav = miss
  nrows = 0
  nskip = 0
  open(ust, file='snotel_daily.csv', status='old', iostat=ios)
  if (ios /= 0) call fail('snotel_daily.csv')
  read(ust, '(A)', iostat=ios) line
  do
    read(ust, '(A)', iostat=ios) line
    if (ios /= 0) exit
    if (len_trim(line) == 0) cycle
    call split(line, f, nf)
    d = jdn_s(f(1)) - base + 1
    k = 0
    do i = 1, ns
      if (f(2) == trip(i)) k = i
    end do
    if (k == 0 .or. d < 1 .or. d > maxd .or. d > nday) then
      nskip = nskip + 1
      cycle
    end if
    nrows = nrows + 1
    swe(k,d) = rval(f(3))
    swem(k,d) = rval(f(4))
    dep(k,d) = rval(f(5))
    prc(k,d) = rval(f(6))
    prcm(k,d) = rval(f(7))
    tav(k,d) = rval(f(8))
    if (ok(tav(k,d))) tav(k,d) = (tav(k,d) - 32.0_dp) / 1.8_dp
  end do
  close(ust)
  write(*,'(A,I6)') 'CWX002I STATION-DAYS LOADED ........', nrows
  write(*,'(A,I6)') 'CWX003I RECORDS SKIPPED ............', nskip
  if (nrows == 0) then
    write(*,'(A)') 'CWX008E NO SNOTEL DATA. NOTHING WRITTEN.'
    write(*,'(A)') 'CWX999I ' // ver // ' ENDED  RC= 8'
    call exit(8)
  end if

  !-- the data date: the latest day any station reported SWE -----
  dd = 0
  do d = 1, nday
    do i = 1, ns
      if (ok(swe(i,d))) dd = d
    end do
  end do
  if (dd == 0) dd = nday
  if (today - (base + dd - 1) > 1) call note( &
    'CWX011W NRCS DATA ARE ' // trim(itoa(today - base - dd + 1)) &
    // ' DAYS OLD (LATEST ' // dstr(base + dd - 1) // ')', 4)
  call ymd(base + dd - 1, wy1, i, j)
  if (i >= 10) wy1 = wy1 + 1
  wy0 = jdn(wy1 - 1, 10, 1) - base + 1     ! current WY, day 1
  py0 = jdn(wy1 - 2, 10, 1) - base + 1     ! last WY
  py1 = wy0 - 1

  !-- per station --------------------------------------------------
  do i = 1, ns
    r_last(i) = 0
    do d = 1, dd
      if (ok(swe(i,d))) r_last(i) = d
    end do
    r_stale(i) = r_last(i) < dd
    if (r_last(i) == 0) then
      call note('CWX012W ' // trim(sname(i)) // ': NO DATA', 4)
    else if (r_stale(i)) then
      call note('CWX013W ' // trim(sname(i)) // ': LAST DATA ' &
        // dstr(base + r_last(i) - 1), 4)
    end if
    r_swe(i) = swe(i,dd)
    r_med(i) = swem(i,dd)
    r_pct(i) = miss
    if (ok(r_swe(i)) .and. ok(r_med(i))) then
      if (r_med(i) >= 1.0_dp) r_pct(i) = 100.0_dp * r_swe(i) &
                                         / r_med(i)
    end if
    r_chg(i) = miss
    if (dd > 7) then
      if (ok(swe(i,dd)) .and. ok(swe(i,dd-7))) &
        r_chg(i) = swe(i,dd) - swe(i,dd-7)
    end if
    r_dep(i) = dep(i,dd)
    r_prc(i) = prc(i,dd)
    r_prm(i) = prcm(i,dd)
    r_ppc(i) = miss
    if (ok(r_prc(i)) .and. ok(r_prm(i))) then
      if (r_prm(i) >= 1.0_dp) r_ppc(i) = 100.0_dp * r_prc(i) &
                                         / r_prm(i)
    end if
  end do

  !-- massif index: sum of SWE over sum of medians -----------------
  m_swe = 0.0_dp
  m_med = 0.0_dp
  m_prc = 0.0_dp
  m_prm = 0.0_dp
  m_n = 0
  do i = 1, ns
    k = massif(smass(i))
    if (k == 0) cycle
    if (ok(r_swe(i)) .and. ok(r_med(i))) then
      m_n(k) = m_n(k) + 1
      m_swe(k) = m_swe(k) + r_swe(i)
      m_med(k) = m_med(k) + r_med(i)
    end if
    if (ok(r_prc(i)) .and. ok(r_prm(i))) then
      m_prc(k) = m_prc(k) + r_prc(i)
      m_prm(k) = m_prm(k) + r_prm(i)
    end if
  end do
  m_n(4) = sum(m_n(1:3))
  m_swe(4) = sum(m_swe(1:3))
  m_med(4) = sum(m_med(1:3))
  m_prc(4) = sum(m_prc(1:3))
  m_prm(4) = sum(m_prm(1:3))
  do k = 1, 4
    m_pct(k) = miss
    m_ppc(k) = miss
    ! a percent of a median smaller than an inch per station
    ! means nothing; NRCS shows none either
    if (m_n(k) > 0 .and. m_med(k) >= 1.0_dp * m_n(k)) &
      m_pct(k) = 100.0_dp * m_swe(k) / m_med(k)
    if (m_prm(k) >= 1.0_dp * max(m_n(k), 1)) &
      m_ppc(k) = 100.0_dp * m_prc(k) / m_prm(k)
    m_cls(k) = classify(m_pct(k))
    if (m_n(k) == 0) then
      m_swe(k) = miss
      m_med(k) = miss
    end if
  end do

  !-- last water year: peak and melt-out ---------------------------
  m_pk = 0.0_dp
  m_mpk = 0.0_dp
  do i = 1, ns
    v_peak(i) = miss
    v_mpeak(i) = miss
    v_pday(i) = 0
    v_mpday(i) = 0
    v_out(i) = 0
    v_mout(i) = 0
    v_pct(i) = miss
    if (py0 < 1) cycle
    do d = py0, py1
      if (ok(swe(i,d))) then
        if (.not. ok(v_peak(i)) .or. swe(i,d) > v_peak(i)) then
          v_peak(i) = swe(i,d)
          v_pday(i) = d
        end if
      end if
      if (ok(swem(i,d))) then
        if (.not. ok(v_mpeak(i)) .or. swem(i,d) > v_mpeak(i)) then
          v_mpeak(i) = swem(i,d)
          v_mpday(i) = d
        end if
      end if
    end do
    if (v_pday(i) > 0) then
      do d = v_pday(i), py1
        if (ok(swe(i,d))) then
          if (swe(i,d) <= 0.0_dp) then
            v_out(i) = d
            exit
          end if
        end if
      end do
    end if
    if (v_mpday(i) > 0) then
      do d = v_mpday(i), py1
        if (ok(swem(i,d))) then
          if (swem(i,d) <= 0.0_dp) then
            v_mout(i) = d
            exit
          end if
        end if
      end do
    end if
    if (ok(v_peak(i)) .and. ok(v_mpeak(i))) then
      if (v_mpeak(i) >= 1.0_dp) &
        v_pct(i) = 100.0_dp * v_peak(i) / v_mpeak(i)
      k = massif(smass(i))
      if (k > 0) then
        m_pk(k) = m_pk(k) + v_peak(i)
        m_mpk(k) = m_mpk(k) + v_mpeak(i)
      end if
    end if
  end do
  m_pk(4) = sum(m_pk(1:3))
  m_mpk(4) = sum(m_mpk(1:3))

  !-- mountain lapse rate: least squares, T against elevation ------
  ! the newest day with temperature at 5 or more stations
  tday = 0
  r_tav = miss
  do d = dd, max(1, dd - 5), -1
    mn = count([(ok(tav(i,d)), i = 1, ns)])
    if (mn >= 5) then
      tday = d
      exit
    end if
  end do
  mslope = miss
  mr2 = miss
  mn = 0
  if (tday > 0) then
    sx = 0
    sy = 0
    sxx = 0
    sxy = 0
    syy = 0
    do i = 1, ns
      r_tav(i) = tav(i,tday)
      if (.not. ok(r_tav(i))) cycle
      x = elev(i) / m2ft / 1000.0_dp            ! km
      y = r_tav(i)
      mn = mn + 1
      sx = sx + x
      sy = sy + y
      sxx = sxx + x*x
      sxy = sxy + x*y
      syy = syy + y*y
    end do
    x = mn*sxx - sx*sx
    if (mn >= 5 .and. x > 0.0_dp) then
      mslope = (mn*sxy - sx*sy) / x            ! C per km
      y = mn*syy - sy*sy
      if (y > 0.0_dp) mr2 = (mn*sxy - sx*sy)**2 / (x*y)
      mslope = -mslope                         ! cooling rate
    end if
  else
    r_tav = miss
    call note('CWX014W TOO FEW STATIONS REPORT TEMPERATURE', 4)
  end if

  !-- soundings ---------------------------------------------------
  call read_series()
  nnew = 0
  soundings_in = 0
  latest = 0
  nk = 0
  open(ust, file='soundings_raw.csv', status='old', iostat=ios)
  if (ios == 0) then
    read(ust, '(A)', iostat=ios) line
    cur = 0
    nl = 0
    do
      read(ust, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      read(f(1), *, iostat=k) j
      if (k /= 0) cycle
      if (j /= cur .and. nl > 0) call take()
      cur = j
      if (nl < maxl .and. ok(rval(f(2))) .and. ok(rval(f(4)))) then
        nl = nl + 1
        lp(nl) = rval(f(2))
        lz(nl) = rval(f(3))
        lt(nl) = rval(f(4))
        ltd(nl) = rval(f(5))
        ldir(nl) = rval(f(6))
        lkt(nl) = rval(f(7))
      end if
    end do
    if (nl > 0) call take()
    close(ust)
  end if
  call sort_series()
  ! keep two water years
  j = 0
  do i = 1, nser
    if (ser(i)%key >= key_of(base)) then
      j = j + 1
      ser(j) = ser(i)
    end if
  end do
  nser = j
  write(*,'(A,I6)') 'CWX004I SOUNDINGS READ .............', &
    soundings_in
  write(*,'(A,I6)') 'CWX005I SOUNDINGS ON FILE ..........', nser
  if (nser == 0) then
    call note('CWX015W NO QUILLAYUTE SOUNDINGS', 4)
  else if (hours_since(ser(nser)%key) > 36) then
    call note('CWX016W LATEST SOUNDING IS ' // &
      trim(itoa(hours_since(ser(nser)%key))) // ' HOURS OLD', 4)
  end if
  if (nser > 0) then
    if (.not. ok(ser(nser)%ivt)) call note( &
      'CWX017W LATEST SOUNDING ENDS BELOW 300 HPA: NO IVT', 4)
  end if

  !-- write everything ---------------------------------------------
  call write_series()
  if (nk > 0) call write_profile()
  call write_analysis()
  call write_massif()
  call write_review()
  call write_report()
  call write_summary()

  write(*,'(A)') 'CWX006I REPORT WRITTEN: cascadia-wx-report.txt'
  write(*,'(A)') 'CWX007I RESULTS WRITTEN: analysis.csv massif.csv' &
    // ' review.csv summary.csv'
  do i = 1, nmsg
    write(*,'(A)') trim(msg(i))
  end do
  write(*,'(A,I2)') 'CWX999I ' // ver // ' ENDED  RC=', rc
  call exit(rc)

contains

  subroutine note(text, level)
    character(len=*), intent(in) :: text
    integer, intent(in) :: level
    if (nmsg < size(msg)) then
      nmsg = nmsg + 1
      msg(nmsg) = text
    end if
    rc = max(rc, level)
  end subroutine note

  subroutine fail(name)
    character(len=*), intent(in) :: name
    write(*,'(A)') 'CWX012E CANNOT OPEN ' // name
    write(*,'(A)') 'CWX999I ' // ver // ' ENDED  RC=12'
    call exit(12)
  end subroutine fail

  integer function massif(name)
    character(len=*), intent(in) :: name
    integer :: m
    massif = 0
    do m = 1, 3
      if (trim(name) == trim(mname(m))) massif = m
    end do
  end function massif

  ! NRCS snowpack map classes
  character(len=18) function classify(p)
    real(dp), intent(in) :: p
    if (.not. ok(p)) then
      classify = 'SEASON NOT STARTED'
    else if (p < 50.0_dp) then
      classify = 'UNDER 50%'
    else if (p < 70.0_dp) then
      classify = '50-69%'
    else if (p < 90.0_dp) then
      classify = '70-89%'
    else if (p < 110.0_dp) then
      classify = 'NEAR NORMAL'
    else if (p < 130.0_dp) then
      classify = '110-129%'
    else if (p < 150.0_dp) then
      classify = '130-149%'
    else
      classify = '150% OR MORE'
    end if
  end function classify

  integer function key_of(j)
    integer, intent(in) :: j
    integer :: y, m, dy
    call ymd(j, y, m, dy)
    key_of = ((y*100 + m)*100 + dy)*100
  end function key_of

  integer function hours_since(key)
    integer, intent(in) :: key
    integer :: y, m, dy, h, v(8)
    ! v(4) is the clock's offset from UTC in minutes
    call date_and_time(values=v)
    y = key / 1000000
    m = mod(key / 10000, 100)
    dy = mod(key / 100, 100)
    h = mod(key, 100)
    hours_since = (jdn(v(1), v(2), v(3)) - jdn(y, m, dy)) * 24 &
      + v(5) - h - nint(v(4) / 60.0)
  end function hours_since

  character(len=17) function key_iso(key)
    integer, intent(in) :: key
    write(key_iso, '(I4.4,A,I2.2,A,I2.2,A,I2.2,A)') &
      key/1000000, '-', mod(key/10000,100), '-', &
      mod(key/100,100), 'T', mod(key,100), ':00Z'
  end function key_iso

  ! one sounding has been read into lp..lkt: analyse and file it
  subroutine take()
    integer :: a, b, kk
    real(dp) :: tmp(7)
    ! order by falling pressure, drop repeated pressures
    do a = 2, nl
      tmp = [lp(a), lz(a), lt(a), ltd(a), ldir(a), lkt(a), 0d0]
      b = a - 1
      do while (b >= 1)
        if (lp(b) >= tmp(1)) exit
        lp(b+1) = lp(b)
        lz(b+1) = lz(b)
        lt(b+1) = lt(b)
        ltd(b+1) = ltd(b)
        ldir(b+1) = ldir(b)
        lkt(b+1) = lkt(b)
        b = b - 1
      end do
      lp(b+1) = tmp(1)
      lz(b+1) = tmp(2)
      lt(b+1) = tmp(3)
      ltd(b+1) = tmp(4)
      ldir(b+1) = tmp(5)
      lkt(b+1) = tmp(6)
    end do
    b = 1
    do a = 2, nl
      if (lp(a) < lp(b)) then
        b = b + 1
        lp(b) = lp(a)
        lz(b) = lz(a)
        lt(b) = lt(a)
        ltd(b) = ltd(a)
        ldir(b) = ldir(a)
        lkt(b) = lkt(a)
      end if
    end do
    nl = b
    soundings_in = soundings_in + 1
    if (nl >= 10 .and. lp(1) > 900.0_dp) then
      snew = sounding()
      snew%key = cur
      call analyse(snew, nl, lp(1:nl), lz(1:nl), lt(1:nl), &
        ltd(1:nl), ldir(1:nl), lkt(1:nl), ltw(1:nl), lq(1:nl))
      kk = 0
      do a = 1, nser
        if (ser(a)%key == cur) kk = a
      end do
      if (kk == 0 .and. nser < maxser) then
        nser = nser + 1
        kk = nser
      end if
      if (kk > 0) ser(kk) = snew
      nnew = nnew + 1
      if (cur >= latest) then        ! keep the newest profile
        latest = cur
        nk = nl
        kp(1:nl) = lp(1:nl)
        kz(1:nl) = lz(1:nl)
        kt_(1:nl) = lt(1:nl)
        ktd(1:nl) = ltd(1:nl)
        kdir(1:nl) = ldir(1:nl)
        kkt(1:nl) = lkt(1:nl)
        ktw(1:nl) = ltw(1:nl)
        kq(1:nl) = lq(1:nl)
      end if
    end if
    nl = 0
  end subroutine take

  subroutine sort_series()
    integer :: a, b
    type(sounding) :: t
    do a = 2, nser
      t = ser(a)
      b = a - 1
      do while (b >= 1)
        if (ser(b)%key <= t%key) exit
        ser(b+1) = ser(b)
        b = b - 1
      end do
      ser(b+1) = t
    end do
  end subroutine sort_series

  subroutine read_series()
    integer :: u
    nser = 0
    open(newunit=u, file='sounding_series.csv', status='old', &
         iostat=ios)
    if (ios /= 0) return
    read(u, '(A)', iostat=ios) line
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      if (nf < 15 .or. nser == maxser) cycle
      nser = nser + 1
      read(f(1), *, iostat=k) ser(nser)%key
      if (k /= 0) then
        nser = nser - 1
        cycle
      end if
      ser(nser)%psfc = rval(f(3))
      ser(nser)%ptop = rval(f(4))
      ser(nser)%fl = rval(f(5))
      if (ok(ser(nser)%fl)) ser(nser)%fl = ser(nser)%fl / m2ft
      ser(nser)%wbz = rval(f(6))
      if (ok(ser(nser)%wbz)) ser(nser)%wbz = ser(nser)%wbz / m2ft
      ser(nser)%pw = rval(f(8))
      ser(nser)%ivt = rval(f(9))
      ser(nser)%ivtdir = rval(f(10))
      ser(nser)%t850 = rval(f(12))
      ser(nser)%lapse = rval(f(13))
      ser(nser)%w7dir = rval(f(14))
      ser(nser)%w7kt = rval(f(15))
    end do
    close(u)
  end subroutine read_series

  ! snow level: the NWS rule of thumb, 1000 ft below freezing
  real(dp) function snow_ft(s)
    type(sounding), intent(in) :: s
    snow_ft = miss
    if (ok(s%fl)) snow_ft = max(s%fl * m2ft - 1000.0_dp, &
                                s%zsfc * m2ft)
  end function snow_ft

  real(dp) function ft(z)
    real(dp), intent(in) :: z
    ft = miss
    if (ok(z)) ft = z * m2ft
  end function ft

  subroutine write_series()
    integer :: u, a
    open(newunit=u, file='sounding_series.tmp', status='replace')
    write(u, '(A)') 'key,valid_utc,psfc_hpa,ptop_hpa,' // &
      'freezing_ft,wetbulb0_ft,snow_level_ft,pw_mm,' // &
      'ivt,ivt_from_deg,ar_category,t850_c,' // &
      'lapse_850_700_c_km,w700_from_deg,w700_kt'
    do a = 1, nser
      write(u, '(A)') trim(itoa(ser(a)%key)) // ',' // &
        trim(key_iso(ser(a)%key)) // ',' // &
        cs(ser(a)%psfc, 0) // ',' // cs(ser(a)%ptop, 0) // &
        ',' // cs(ft(ser(a)%fl), 0) // ',' // &
        cs(ft(ser(a)%wbz), 0) // ',' // &
        cs(snow_ft(ser(a)), 0) // ',' // cs(ser(a)%pw, 1) // &
        ',' // cs(ser(a)%ivt, 0) // ',' // &
        cs(ser(a)%ivtdir, 0) // ',' // &
        trim(ar_cat(ser(a)%ivt)) // ',' // &
        cs(ser(a)%t850, 1) // ',' // cs(ser(a)%lapse, 2) // &
        ',' // cs(ser(a)%w7dir, 0) // ',' // cs(ser(a)%w7kt, 0)
    end do
    close(u)
    call rename('sounding_series.tmp', 'sounding_series.csv')
  end subroutine write_series

  subroutine write_profile()
    integer :: u, a
    open(newunit=u, file='upper_air.csv', status='replace')
    write(u, '(A)') 'valid_utc,p_hpa,z_m,t_c,td_c,tw_c,q_gkg,' // &
      'wind_from_deg,wind_kt'
    do a = 1, nk
      write(u, '(A)') trim(key_iso(latest)) // ',' // &
        cs(kp(a), 1) // ',' // cs(kz(a), 0) // ',' // &
        cs(kt_(a), 1) // ',' // cs(ktd(a), 1) // ',' // &
        cs(ktw(a), 1) // ',' // cs(kq(a), 2) // ',' // &
        cs(kdir(a), 0) // ',' // cs(kkt(a), 0)
    end do
    close(u)
  end subroutine write_profile

  subroutine write_analysis()
    integer :: u, a
    character(len=10) :: last
    open(newunit=u, file='analysis.csv', status='replace')
    write(u, '(A)') 'triplet,name,massif,elev_ft,lat,lon,' // &
      'data_date,last_date,swe_in,swe_median_in,swe_pct,' // &
      'swe_7day_in,depth_in,wy_precip_in,wy_precip_median_in,' // &
      'wy_precip_pct,tavg_c,status'
    do a = 1, ns
      last = ' '
      if (r_last(a) > 0) last = dstr(base + r_last(a) - 1)
      write(u, '(A)') trim(trip(a)) // ',' // trim(sname(a)) // &
        ',' // trim(smass(a)) // ',' // cs(elev(a), 0) // ',' // &
        cs(slat(a), 5) // ',' // cs(slon(a), 5) // ',' // &
        dstr(base + dd - 1) // ',' // trim(last) // ',' // &
        cs(r_swe(a), 1) // ',' // cs(r_med(a), 1) // ',' // &
        cs(r_pct(a), 0) // ',' // cs(r_chg(a), 1) // ',' // &
        cs(r_dep(a), 0) // ',' // cs(r_prc(a), 1) // ',' // &
        cs(r_prm(a), 1) // ',' // cs(r_ppc(a), 0) // ',' // &
        cs(r_tav(a), 1) // ',' // trim(status_of(a))
    end do
    close(u)
  end subroutine write_analysis

  character(len=12) function status_of(a)
    integer, intent(in) :: a
    status_of = 'OK'
    if (r_last(a) == 0) then
      status_of = 'NO DATA'
    else if (r_stale(a)) then
      status_of = 'STALE'
    end if
  end function status_of

  subroutine write_massif()
    integer :: u, a
    character(len=8) :: nm
    open(newunit=u, file='massif.csv', status='replace')
    write(u, '(A)') 'massif,stations,swe_in,swe_median_in,' // &
      'swe_pct,class,wy_precip_in,wy_precip_median_in,' // &
      'wy_precip_pct,last_wy_peak_sum_in,last_wy_median_peak' // &
      '_sum_in,last_wy_peak_pct'
    do a = 1, 4
      nm = 'ALL'
      if (a <= 3) nm = mname(a)
      write(u, '(A)') trim(nm) // ',' // trim(itoa(m_n(a))) // &
        ',' // cs(m_swe(a), 1) // ',' // cs(m_med(a), 1) // &
        ',' // cs(m_pct(a), 0) // ',' // trim(m_cls(a)) // &
        ',' // cs(m_prc(a), 1) // ',' // cs(m_prm(a), 1) // &
        ',' // cs(m_ppc(a), 0) // ',' // cs(m_pk(a), 1) // &
        ',' // cs(m_mpk(a), 1) // ',' // cs(pk_pct(a), 0)
    end do
    close(u)
  end subroutine write_massif

  real(dp) function pk_pct(a)
    integer, intent(in) :: a
    pk_pct = miss
    if (m_mpk(a) >= 1.0_dp) pk_pct = 100.0_dp * m_pk(a) / m_mpk(a)
  end function pk_pct

  character(len=10) function dday(d)
    integer, intent(in) :: d
    dday = ' '
    if (d > 0) dday = dstr(base + d - 1)
  end function dday

  subroutine write_review()
    integer :: u, a
    open(newunit=u, file='review.csv', status='replace')
    write(u, '(A)') 'triplet,name,massif,water_year,peak_in,' // &
      'peak_date,median_peak_in,median_peak_date,peak_pct,' // &
      'melt_out,median_melt_out,melt_out_days_early'
    do a = 1, ns
      write(u, '(A)') trim(trip(a)) // ',' // trim(sname(a)) // &
        ',' // trim(smass(a)) // ',' // trim(itoa(wy1 - 1)) // &
        ',' // cs(v_peak(a), 1) // ',' // trim(dday(v_pday(a))) &
        // ',' // cs(v_mpeak(a), 1) // ',' // &
        trim(dday(v_mpday(a))) // ',' // cs(v_pct(a), 0) // &
        ',' // trim(dday(v_out(a))) // ',' // &
        trim(dday(v_mout(a))) // ',' // trim(early(a))
    end do
    close(u)
  end subroutine write_review

  character(len=8) function early(a)
    integer, intent(in) :: a
    early = ' '
    if (v_out(a) > 0 .and. v_mout(a) > 0) &
      early = trim(itoa(v_mout(a) - v_out(a)))
  end function early

  subroutine write_summary()
    integer :: u
    type(sounding) :: s
    open(newunit=u, file='summary.csv', status='replace')
    write(u, '(A)') 'key,value'
    write(u, '(A)') 'version,' // ver
    write(u, '(A)') 'run_utc,' // trim(runutc)
    write(u, '(A)') 'pacific_date,' // pdate
    write(u, '(A)') 'data_date,' // dstr(base + dd - 1)
    write(u, '(A)') 'water_year,' // trim(itoa(wy1))
    write(u, '(A)') 'return_code,' // trim(itoa(rc))
    write(u, '(A)') 'stations,' // trim(itoa(ns))
    write(u, '(A)') 'stations_reporting,' // &
      trim(itoa(count(r_last(1:ns) == dd)))
    write(u, '(A)') 'region_swe_pct,' // cs(m_pct(4), 0)
    write(u, '(A)') 'region_class,' // trim(m_cls(4))
    write(u, '(A)') 'region_precip_pct,' // cs(m_ppc(4), 0)
    write(u, '(A)') 'last_wy_peak_pct,' // cs(pk_pct(4), 0)
    write(u, '(A)') 'mountain_lapse_c_km,' // cs(mslope, 2)
    write(u, '(A)') 'mountain_lapse_r2,' // cs(mr2, 2)
    write(u, '(A)') 'mountain_lapse_n,' // trim(itoa(mn))
    if (tday > 0) then
      write(u, '(A)') 'mountain_lapse_date,' // dstr(base+tday-1)
    else
      write(u, '(A)') 'mountain_lapse_date,'
    end if
    if (nser > 0) then
      s = ser(nser)
      write(u, '(A)') 'sounding_valid_utc,' // trim(key_iso(s%key))
      write(u, '(A)') 'freezing_level_ft,' // cs(ft(s%fl), 0)
      write(u, '(A)') 'wetbulb_zero_ft,' // cs(ft(s%wbz), 0)
      write(u, '(A)') 'snow_level_ft,' // cs(snow_ft(s), 0)
      write(u, '(A)') 'pw_mm,' // cs(s%pw, 1)
      write(u, '(A)') 'ivt,' // cs(s%ivt, 0)
      write(u, '(A)') 'ivt_from,' // trim(compass(s%ivtdir))
      write(u, '(A)') 'ar_category,' // trim(ar_cat(s%ivt))
      write(u, '(A)') 't850_c,' // cs(s%t850, 1)
      write(u, '(A)') 'free_air_lapse_c_km,' // cs(s%lapse, 2)
      write(u, '(A)') 'w700,' // trim(compass(s%w7dir)) // ' ' &
        // cs(s%w7kt, 0) // ' kt'
    end if
    write(u, '(A)') 'messages,' // trim(itoa(nmsg))
    close(u)
  end subroutine write_summary

  !-- the printed report, 132 columns ------------------------------
  subroutine write_report()
    integer :: u, a, b, m
    character(len=132) :: rule, dash
    type(sounding) :: s
    real(dp) :: pz(7), v(7)
    character(len=6) :: lab(7)
    rule = repeat('=', 132)
    dash = repeat('-', 132)
    open(newunit=u, file='cascadia-wx-report.txt', status='replace')
    write(u, '(A)') rule
    write(u, '(A)') ver // ' ' // repeat(' ', 22) // &
      'PACIFIC NORTHWEST MOUNTAIN WEATHER ANALYSIS' // &
      repeat(' ', 24) // 'RUN ' // runutc // ' UTC'
    write(u, '(A)') repeat(' ', 47) // &
      'RAINIER  -  OLYMPICS  -  CASCADES'
    write(u, '(A)') 'SNOTEL DATA FOR ' // dstr(base + dd - 1) // &
      '   WATER YEAR ' // trim(itoa(wy1)) // ', DAY ' // &
      trim(itoa(dd - wy0 + 1)) // repeat(' ', 30) // &
      'MEDIANS: NRCS 1991-2020'
    write(u, '(A)') rule
    write(u, '(A)')

    write(u, '(A)') 'SECTION I    SNOWPACK BY STATION'
    write(u, '(A)')
    write(u, '(A)') 'STATION          MASSIF     ELEV  ' // &
      '  SWE  MEDIAN   %MED  7-DAY   DEPTH   ' // &
      'WY PRECIP  MEDIAN   %MED   TAVG  STATUS'
    write(u, '(A)') '                             FT   ' // &
      '   IN      IN           IN      IN   ' // &
      '       IN      IN            C'
    write(u, '(A)') dash
    do m = 1, 3
      do a = 1, ns
        if (massif(smass(a)) /= m) cycle
        write(u, '(A16,1X,A8,A7,2X,A6,A8,A7,A7,A8,3X,A8,' // &
          'A8,A7,A7,2X,A)') sname(a)(1:16), smass(a), &
          rf(elev(a),7,0), &
          rf(r_swe(a),6,1), rf(r_med(a),8,1), rf(r_pct(a),7,0), &
          rf(r_chg(a),7,1), rf(r_dep(a),8,0), rf(r_prc(a),8,1), &
          rf(r_prm(a),8,1), rf(r_ppc(a),7,0), rf(r_tav(a),7,1), &
          trim(status_of(a)) // trim(lastnote(a))
      end do
    end do
    write(u, '(A)') dash
    write(u, '(A)') '  % OF MEDIAN IS LEFT BLANK UNTIL THE MEDIAN ' // &
      'ITSELF REACHES 1 INCH.  TAVG IS ' // &
      trim(dlabel(tday)) // ', SNOTEL SENSORS.'
    write(u, '(A)')

    write(u, '(A)') 'SECTION II   MASSIF INDEX     (SUM OF ' // &
      'STATION VALUES OVER SUM OF THEIR MEDIANS)'
    write(u, '(A)')
    write(u, '(A)') 'MASSIF     STATIONS     SWE  MEDIAN   ' // &
      '%MED  CLASS                 WY PRECIP  MEDIAN   %MED'
    write(u, '(A)') dash(1:100)
    do a = 1, 4
      if (a <= 3) then
        write(u, '(A8,I10,A9,A8,A7,2X,A18,A14,A8,A7)') mname(a), &
          m_n(a), rf(m_swe(a),9,1), rf(m_med(a),8,1), &
          rf(m_pct(a),7,0), m_cls(a), rf(m_prc(a),14,1), &
          rf(m_prm(a),8,1), rf(m_ppc(a),7,0)
      else
        write(u, '(A)') dash(1:100)
        write(u, '(A8,I10,A9,A8,A7,2X,A18,A14,A8,A7)') 'ALL', &
          m_n(a), rf(m_swe(a),9,1), rf(m_med(a),8,1), &
          rf(m_pct(a),7,0), m_cls(a), rf(m_prc(a),14,1), &
          rf(m_prm(a),8,1), rf(m_ppc(a),7,0)
      end if
    end do
    write(u, '(A)')

    write(u, '(A)') 'SECTION III  UPPER AIR     QUILLAYUTE, WA ' // &
      '(KUIL, WMO 72797)   NWS RADIOSONDE'
    write(u, '(A)')
    if (nser == 0) then
      write(u, '(A)') '  NO SOUNDINGS ON FILE.'
    else
      s = ser(nser)
      write(u, '(A)') '  LATEST BALLOON ........... ' // &
        key_iso(s%key) // '   (' // &
        trim(itoa(hours_since(s%key))) // ' HOURS BEFORE THIS RUN)'
      write(u, '(A)') '  FREEZING LEVEL ........... ' // &
        rf(ft(s%fl),7,0) // ' FT'
      write(u, '(A)') '  WET-BULB ZERO ............ ' // &
        rf(ft(s%wbz),7,0) // ' FT'
      write(u, '(A)') '  SNOW LEVEL (ESTIMATE) .... ' // &
        rf(snow_ft(s),7,0) // ' FT   1000 FT BELOW FREEZING,' // &
        ' THE NWS RULE OF THUMB'
      write(u, '(A)') '  PRECIPITABLE WATER ....... ' // &
        rf(s%pw,7,1) // ' MM'
      write(u, '(A)') '  VAPOUR TRANSPORT (IVT) ... ' // &
        rf(s%ivt,7,0) // ' KG/M/S FROM THE ' // &
        trim(compass(s%ivtdir)) // '   ATMOSPHERIC RIVER: ' // &
        trim(ar_cat(s%ivt))
      write(u, '(A)') '  850 HPA TEMPERATURE ...... ' // &
        rf(s%t850,7,1) // ' C'
      write(u, '(A)') '  LAPSE RATE 850-700 HPA ... ' // &
        rf(s%lapse,7,2) // ' C/KM   (DRY ADIABATIC 9.8)'
      write(u, '(A)') '  700 HPA WIND ............. ' // &
        rf(s%w7kt,7,0) // ' KT FROM THE ' // trim(compass(s%w7dir))
      write(u, '(A)')
      if (nk > 0) then
        write(u, '(A)') '    LEVEL     HEIGHT    TEMP   DEWPT  ' // &
          'WETBULB    Q G/KG    WIND'
        write(u, '(A)') '      HPA         FT       C       C  ' // &
          '      C'
        pz = [kp(1), 1000d0, 925d0, 850d0, 700d0, 500d0, 300d0]
        lab = ['   SFC', '  1000', '   925', '   850', '   700', &
               '   500', '   300']
        do b = 1, 7
          if (b > 1 .and. pz(b) > kp(1)) cycle
          v(1) = at_p(nk, kp, kz, pz(b))
          v(2) = at_p(nk, kp, kt_, pz(b))
          v(3) = at_p(nk, kp, ktd, pz(b))
          v(4) = at_p(nk, kp, ktw, pz(b))
          v(5) = at_p(nk, kp, kq, pz(b))
          write(u, '(3X,A6,A11,A8,A8,A9,A10,4X,A)') lab(b), &
            rf(ft(v(1)),11,0), rf(v(2),8,1), rf(v(3),8,1), &
            rf(v(4),9,1), rf(v(5),10,2), trim(wind_at(pz(b)))
        end do
        write(u, '(A)')
      end if
      write(u, '(A)') '  RECENT SOUNDINGS        FREEZING  ' // &
        'SNOW LEVEL      PW      IVT  FROM  ATMOSPHERIC RIVER'
      write(u, '(A)') '                                FT  ' // &
        '        FT      MM   KG/M/S'
      do a = max(1, nser - 9), nser
        write(u, '(2X,A17,A15,A12,A8,A9,3X,A3,2X,A)') &
          key_iso(ser(a)%key), rf(ft(ser(a)%fl),15,0), &
          rf(snow_ft(ser(a)),12,0), rf(ser(a)%pw,8,1), &
          rf(ser(a)%ivt,9,0), compass(ser(a)%ivtdir), &
          trim(ar_cat(ser(a)%ivt))
      end do
      write(u, '(A)') '  IVT IS ONE BALLOON AT ONE MOMENT; THE ' // &
        'OFFICIAL AR SCALE ALSO WEIGHS HOW LONG IT LASTS.'
    end if
    write(u, '(A)')

    write(u, '(A)') 'SECTION IV   TEMPERATURE WITH HEIGHT'
    write(u, '(A)')
    if (nser > 0) write(u, '(A)') '  FREE AIR, 850-700 HPA ' // &
      '(BALLOON) ......... ' // rf(ser(nser)%lapse,6,2) // &
      ' C PER KM'
    write(u, '(A)') '  MOUNTAIN SURFACE (SNOTEL FIT) ' // &
      '......... ' // rf(mslope,6,2) // ' C PER KM   R-SQUARED' // &
      rf(mr2,5,2) // '   STATIONS ' // trim(itoa(mn)) // &
      '   ' // trim(dlabel(tday))
    if (ok(mslope)) then
      if (mslope < 0.0_dp) write(u, '(A)') '  NEGATIVE MEANS ' // &
        'IT WAS WARMER HIGHER UP: AN INVERSION.'
    end if
    write(u, '(A)') '  THE SURFACE RATE IS USUALLY SHALLOWER ' // &
      'THAN THE FREE AIR: COLD AIR POOLS IN VALLEYS'
    write(u, '(A)') '  AND THE SENSORS SIT ON THREE DIFFERENT ' // &
      'MOUNTAIN RANGES, WEST AND EAST OF THE CREST.'
    write(u, '(A)')

    write(u, '(A)') 'SECTION V    WATER YEAR ' // &
      trim(itoa(wy1 - 1)) // ' IN REVIEW   (OCT 1 ' // &
      trim(itoa(wy1 - 2)) // ' - SEP 30 ' // trim(itoa(wy1 - 1)) &
      // ')'
    write(u, '(A)')
    write(u, '(A)') 'STATION          MASSIF       PEAK  ' // &
      'DATE    MEDIAN PEAK  DATE      %MED   MELT-OUT  MEDIAN  ' // &
      ' DAYS EARLY'
    write(u, '(A)') '                                IN  ' // &
      '                IN'
    write(u, '(A)') dash
    do m = 1, 3
      do a = 1, ns
        if (massif(smass(a)) /= m) cycle
        write(u, '(A16,1X,A8,A9,2X,A6,A13,2X,A6,A8,3X,A6,' // &
          '3X,A6,A10)') sname(a)(1:16), smass(a), &
          rf(v_peak(a),9,1), mday(v_pday(a)), &
          rf(v_mpeak(a),13,1), mday(v_mpday(a)), &
          rf(v_pct(a),8,0), mday(v_out(a)), mday(v_mout(a)), &
          adjustr(early(a))
      end do
    end do
    write(u, '(A)') dash
    write(u, '(A)') '  ALL STATIONS: SUM OF PEAKS ' // &
      trim(cs(m_pk(4),1)) // ' IN, SUM OF MEDIAN PEAKS ' // &
      trim(cs(m_mpk(4),1)) // ' IN = ' // trim(cs(pk_pct(4),0)) &
      // '% OF MEDIAN'
    write(u, '(A)')

    write(u, '(A)') rule
    if (nmsg == 0) then
      write(u, '(A)') 'MESSAGES     NONE'
    else
      write(u, '(A)') 'MESSAGES'
      do a = 1, nmsg
        write(u, '(2X,A)') trim(msg(a))
      end do
    end if
    write(u, '(A)') 'SOURCES      NRCS AWDB (SNOTEL)  -  NWS ' // &
      'RADIOSONDE VIA THE IOWA ENVIRONMENTAL MESONET'
    write(u, '(A)') 'END OF REPORT   ' // trim(itoa(ns)) // &
      ' STATIONS   ' // trim(itoa(nser)) // ' SOUNDINGS ON FILE' &
      // '   RETURN CODE ' // trim(itoa(rc))
    write(u, '(A)') rule
    close(u)
  end subroutine write_report

  character(len=24) function lastnote(a)
    integer, intent(in) :: a
    lastnote = ' '
    if (r_stale(a) .and. r_last(a) > 0) &
      lastnote = ' (' // mstr(base + r_last(a) - 1) // ')'
  end function lastnote

  character(len=6) function mday(d)
    integer, intent(in) :: d
    mday = '    --'
    if (d > 0) mday = mstr(base + d - 1)
  end function mday

  character(len=24) function dlabel(d)
    integer, intent(in) :: d
    dlabel = 'NOT AVAILABLE'
    if (d > 0) dlabel = 'FOR ' // dstr(base + d - 1)
  end function dlabel

  character(len=16) function wind_at(pt)
    real(dp), intent(in) :: pt
    integer :: a
    wind_at = '--'
    do a = 1, nk
      if (abs(kp(a) - pt) < 0.5_dp .and. ok(kdir(a)) .and. &
          ok(kkt(a))) then
        wind_at = trim(compass(kdir(a))) // ' ' // &
          trim(cs(kkt(a), 0)) // ' KT'
        return
      end if
    end do
  end function wind_at

end program cascadia_wx
