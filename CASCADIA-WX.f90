!=====================================================================
! CASCADIA-WX.f90                                       VERSION 3.0
! PACIFIC NORTHWEST UPPER-AIR AND SNOWPACK ANALYSIS
!
! THE AIR   FOUR NWS WEATHER-BALLOON SITES, TWICE A DAY: QUILLAYUTE
!           ON THE COAST, SALEM, MEDFORD, AND SPOKANE EAST OF THE
!           CASCADES. FOR EACH BALLOON: FREEZING LEVEL, WET-BULB
!           ZERO, SNOW LEVEL, PRECIPITABLE WATER AND INTEGRATED
!           VAPOUR TRANSPORT (IVT), THE MEASURE OF AN ATMOSPHERIC
!           RIVER, EACH RANKED AGAINST 1991-2020 FOR THE DATE
!           (normals.csv, BUILT BY NORMALS.f90 FROM 30 YEARS OF
!           BALLOONS).
! THE SNOW  12 NRCS SNOTEL STATIONS AGAINST NRCS 1991-2020 MEDIANS,
!           WHEN NRCS IS ANSWERING. MASSIF INDEX = SUM OF SWE OVER
!           SUM OF MEDIANS, AS NRCS COMPUTES A BASIN INDEX.
!
! INPUT    balloons.csv  stations.csv  normals.csv  fetch_status.csv
!          soundings_raw.csv  sounding_series.csv  snotel_daily.csv
! OUTPUT   cascadia-wx-report.txt   132-COLUMN PRINTED REPORT
!          air.csv  upper_air.csv  sounding_series.csv  summary.csv
!          analysis.csv  massif.csv  review.csv   (THE SNOW)
!
! RETURN CODES   0  NORMAL
!                4  WARNING: A BALLOON OR A STATION IS MISSING OR
!                   STALE. THE REPORT SAYS WHICH.
!                8  NO SOUNDINGS AT ALL. NOTHING WRITTEN.
!               12  AN INPUT FILE CANNOT BE OPENED.
!
! COMPILE  gfortran -O2 -o cascadia-wx CWX_PHYS.f90 CASCADIA-WX.f90
!=====================================================================
program cascadia_wx
  use cwx_util
  use cwx_phys
  implicit none

  integer, parameter :: maxb = 8, maxs = 20, maxd = 800
  integer, parameter :: maxser = 12000
  integer, parameter :: ust = 10
  character(len=*), parameter :: ver = 'CASCADIA-WX V3.0'

  ! balloon sites and their normals
  integer :: nb
  character(len=8) :: bid(maxb)
  character(len=12) :: bname(maxb)
  real(dp) :: belev(maxb)
  real(dp) :: nrm(15, 366, maxb), narp(366, maxb)
  logical :: have_nrm(maxb)

  ! soundings: the series and the newest profile at each site
  type(sounding) :: ser(maxser), snew
  integer :: sst(maxser), nser, lat(maxb), nk(maxb)
  real(dp) :: lp(maxl), lz(maxl), lt(maxl), ltd(maxl)
  real(dp) :: ldir(maxl), lkt(maxl), ltw(maxl), lq(maxl)
  real(dp) :: kp(maxl,maxb), kz(maxl,maxb), kt_(maxl,maxb)
  real(dp) :: ktd(maxl,maxb), kdir(maxl,maxb), kkt(maxl,maxb)
  real(dp) :: ktw(maxl,maxb), kq(maxl,maxb)
  integer :: nl, cur, curb, newkey(maxb), soundings_in

  ! snow stations
  integer :: ns
  character(len=12) :: trip(maxs)
  character(len=20) :: sname(maxs)
  character(len=8) :: smass(maxs)
  real(dp) :: elev(maxs), slat(maxs), slon(maxs)
  real(dp) :: swe(maxs,maxd), swem(maxs,maxd), dep(maxs,maxd)
  real(dp) :: prc(maxs,maxd), prcm(maxs,maxd), tav(maxs,maxd)
  real(dp) :: r_swe(maxs), r_med(maxs), r_pct(maxs), r_chg(maxs)
  real(dp) :: r_dep(maxs), r_prc(maxs), r_prm(maxs), r_ppc(maxs)
  real(dp) :: r_tav(maxs)
  integer :: r_last(maxs)
  logical :: r_stale(maxs), snow
  real(dp) :: v_peak(maxs), v_mpeak(maxs), v_pct(maxs)
  integer :: v_pday(maxs), v_mpday(maxs), v_out(maxs), v_mout(maxs)
  character(len=8), parameter :: mname(3) = [character(len=8) :: &
    'RAINIER', 'OLYMPICS', 'CASCADES']
  real(dp) :: m_swe(4), m_med(4), m_pct(4), m_prc(4), m_prm(4)
  real(dp) :: m_ppc(4), m_pk(4), m_mpk(4)
  integer :: m_n(4)
  character(len=18) :: m_cls(4)
  real(dp) :: mslope, mr2
  integer :: mn, tday

  ! run
  character(len=10) :: pdate
  character(len=16) :: runutc
  character(len=64) :: f(maxf)
  character(len=512) :: line
  character(len=80) :: msg(80)
  integer :: nmsg, rc, ios, nf, i, j, k, d, base, nday, dd
  integer :: wy, wy0, wy1, py0, py1, today, nrows, nskip
  real(dp) :: x, y, sx, sy, sxx, sxy, syy
  character(len=8) :: cdate
  character(len=10) :: ctime

  rc = 0
  nmsg = 0
  call date_and_time(date=cdate, time=ctime)
  write(*,'(A)') 'CWX000I ' // ver // ' STARTED ' // cdate(1:4) &
    // '-' // cdate(5:6) // '-' // cdate(7:8) // ' ' // &
    ctime(1:2) // ':' // ctime(3:4) // ':' // ctime(5:6)

  !-- today's Pacific date, from the fetcher --------------------
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
  base = jdn(wy - 2, 10, 1)            ! day 1 of the snow arrays
  nday = today - base + 1
  wy1 = wy

  call read_balloons()
  call read_normals()
  call read_series()
  call read_raw()
  call sort_series()
  ! keep two water years of balloons
  j = 0
  do i = 1, nser
    if (ser(i)%key >= key_of(base)) then
      j = j + 1
      ser(j) = ser(i)
      sst(j) = sst(i)
    end if
  end do
  nser = j
  write(*,'(A,I6)') 'CWX004I SOUNDINGS READ .............', &
    soundings_in
  write(*,'(A,I6)') 'CWX005I SOUNDINGS ON FILE ..........', nser
  if (nser == 0) then
    write(*,'(A)') 'CWX008E NO SOUNDINGS. NOTHING WRITTEN.'
    write(*,'(A)') 'CWX999I ' // ver // ' ENDED  RC= 8'
    call exit(8)
  end if
  lat = 0
  do i = 1, nser
    lat(sst(i)) = i
  end do
  do i = 1, nb
    if (lat(i) == 0) then
      call note('CWX015W ' // trim(bname(i)) // ': NO SOUNDINGS', 4)
    else if (hours_since(ser(lat(i))%key) > 36) then
      call note('CWX016W ' // trim(bname(i)) // ': LATEST BALLOON '&
        // trim(itoa(hours_since(ser(lat(i))%key))) // ' HOURS OLD',&
        4)
    else if (.not. ok(ser(lat(i))%ivt)) then
      call note('CWX017W ' // trim(bname(i)) // ': LATEST BALLOON ' &
        // 'ENDS BELOW 300 HPA, NO IVT', 4)
    end if
    if (.not. have_nrm(i)) call note('CWX018W ' // trim(bname(i)) &
      // ': NO NORMALS', 4)
  end do

  call snowpack()

  call write_series()
  call write_profiles()
  call write_air()
  if (snow) then
    call write_analysis()
    call write_massif()
    call write_review()
  end if
  call write_report()
  call write_summary()

  write(*,'(A)') 'CWX006I REPORT WRITTEN: cascadia-wx-report.txt'
  write(*,'(A)') 'CWX007I RESULTS WRITTEN: air.csv upper_air.csv ' // &
    'sounding_series.csv summary.csv'
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

  !-- inputs ------------------------------------------------------
  subroutine read_balloons()
    integer :: u
    nb = 0
    open(newunit=u, file='balloons.csv', status='old', iostat=ios)
    if (ios /= 0) call fail('balloons.csv')
    read(u, '(A)') line
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      if (nf < 6 .or. nb == maxb) cycle
      nb = nb + 1
      bid(nb) = f(1)
      bname(nb) = f(3)
      belev(nb) = rval(f(6))
    end do
    close(u)
    write(*,'(A,I6)') 'CWX001I BALLOON SITES ..............', nb
  end subroutine read_balloons

  integer function site(code)
    character(len=*), intent(in) :: code
    integer :: a
    site = 0
    do a = 1, nb
      if (trim(code) == trim(bid(a))) site = a
    end do
  end function site

  subroutine read_normals()
    integer :: u, b, dy, a, n
    nrm = miss
    narp = miss
    have_nrm = .false.
    n = 0
    open(newunit=u, file='normals.csv', status='old', iostat=ios)
    if (ios /= 0) return
    read(u, '(A)') line
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      b = site(f(1))
      dy = int(rval(f(2)))
      if (b == 0 .or. dy < 1 .or. dy > 366 .or. nf < 22) cycle
      ! fl p10..p90 in 5-9, pw in 11-15, ivt in 17-21
      do a = 1, 5
        nrm(a, dy, b) = rval(f(4 + a))
        nrm(5 + a, dy, b) = rval(f(10 + a))
        nrm(10 + a, dy, b) = rval(f(16 + a))
      end do
      narp(dy, b) = rval(f(22))
      have_nrm(b) = .true.
      n = n + 1
    end do
    close(u)
    write(*,'(A,I6)') 'CWX002I NORMALS LOADED (SITE-DAYS) .', n
  end subroutine read_normals

  subroutine read_series()
    integer :: u, b
    nser = 0
    open(newunit=u, file='sounding_series.csv', status='old', &
         iostat=ios)
    if (ios /= 0) return
    read(u, '(A)', iostat=ios) line
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      b = site(f(2))
      if (nf < 16 .or. nser == maxser .or. b == 0) cycle
      nser = nser + 1
      read(f(1), *, iostat=k) ser(nser)%key
      if (k /= 0) then
        nser = nser - 1
        cycle
      end if
      sst(nser) = b
      ser(nser)%psfc = rval(f(4))
      ser(nser)%ptop = rval(f(5))
      ser(nser)%fl = rval(f(6))
      if (ok(ser(nser)%fl)) ser(nser)%fl = ser(nser)%fl / m2ft
      ser(nser)%wbz = rval(f(7))
      if (ok(ser(nser)%wbz)) ser(nser)%wbz = ser(nser)%wbz / m2ft
      ser(nser)%zsfc = belev(b)
      ser(nser)%pw = rval(f(9))
      ser(nser)%ivt = rval(f(10))
      ser(nser)%ivtdir = rval(f(11))
      ser(nser)%t850 = rval(f(13))
      ser(nser)%lapse = rval(f(14))
      ser(nser)%w7dir = rval(f(15))
      ser(nser)%w7kt = rval(f(16))
    end do
    close(u)
  end subroutine read_series

  subroutine read_raw()
    integer :: u, b
    character(len=8) :: sta
    soundings_in = 0
    nk = 0
    newkey = 0
    open(newunit=u, file='soundings_raw.csv', status='old', iostat=ios)
    if (ios /= 0) return
    read(u, '(A)', iostat=ios) line
    cur = 0
    curb = 0
    nl = 0
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      read(f(1), *, iostat=k) j
      if (k /= 0) cycle
      sta = f(2)(1:8)
      b = site(sta)
      if ((j /= cur .or. b /= curb) .and. nl > 0) call take()
      cur = j
      curb = b
      if (nl < maxl .and. ok(rval(f(3))) .and. ok(rval(f(5)))) then
        nl = nl + 1
        lp(nl) = rval(f(3))
        lz(nl) = rval(f(4))
        lt(nl) = rval(f(5))
        ltd(nl) = rval(f(6))
        ldir(nl) = rval(f(7))
        lkt(nl) = rval(f(8))
      end if
    end do
    if (nl > 0) call take()
    close(u)
  end subroutine read_raw

  ! one sounding has been read into lp..lkt: analyse and file it
  subroutine take()
    integer :: a, kk
    soundings_in = soundings_in + 1
    call prep_levels(nl, lp, lz, lt, ltd, ldir, lkt)
    if (curb > 0 .and. nl >= 10) then
      if (lp(1) > 850.0_dp) then
        snew = sounding()
        snew%key = cur
        call analyse(snew, nl, lp(1:nl), lz(1:nl), lt(1:nl), &
          ltd(1:nl), ldir(1:nl), lkt(1:nl), ltw(1:nl), lq(1:nl))
        kk = 0
        do a = 1, nser
          if (ser(a)%key == cur .and. sst(a) == curb) kk = a
        end do
        if (kk == 0 .and. nser < maxser) then
          nser = nser + 1
          kk = nser
        end if
        if (kk > 0) then
          ser(kk) = snew
          sst(kk) = curb
        end if
        if (cur >= newkey(curb)) then   ! keep the newest profile
          newkey(curb) = cur
          nk(curb) = nl
          kp(1:nl,curb) = lp(1:nl)
          kz(1:nl,curb) = lz(1:nl)
          kt_(1:nl,curb) = lt(1:nl)
          ktd(1:nl,curb) = ltd(1:nl)
          kdir(1:nl,curb) = ldir(1:nl)
          kkt(1:nl,curb) = lkt(1:nl)
          ktw(1:nl,curb) = ltw(1:nl)
          kq(1:nl,curb) = lq(1:nl)
        end if
      end if
    end if
    nl = 0
  end subroutine take

  subroutine sort_series()
    integer :: a, b, tb
    type(sounding) :: t
    do a = 2, nser
      t = ser(a)
      tb = sst(a)
      b = a - 1
      do while (b >= 1)
        if (sst(b) < tb) exit
        if (sst(b) == tb .and. ser(b)%key <= t%key) exit
        ser(b+1) = ser(b)
        sst(b+1) = sst(b)
        b = b - 1
      end do
      ser(b+1) = t
      sst(b+1) = tb
    end do
  end subroutine sort_series

  !-- helpers -----------------------------------------------------
  integer function key_of(jd)
    integer, intent(in) :: jd
    integer :: yy, mm, dy
    call ymd(jd, yy, mm, dy)
    key_of = ((yy*100 + mm)*100 + dy)*100
  end function key_of

  integer function key_doy(key)
    integer, intent(in) :: key
    key_doy = doy366(mod(key / 10000, 100), mod(key / 100, 100))
  end function key_doy

  integer function hours_since(key)
    integer, intent(in) :: key
    integer :: yy, mm, dy, h, v(8)
    ! v(4) is the clock's offset from UTC in minutes
    call date_and_time(values=v)
    yy = key / 1000000
    mm = mod(key / 10000, 100)
    dy = mod(key / 100, 100)
    h = mod(key, 100)
    hours_since = (jdn(v(1), v(2), v(3)) - jdn(yy, mm, dy)) * 24 &
      + v(5) - h - nint(v(4) / 60.0)
  end function hours_since

  character(len=17) function key_iso(key)
    integer, intent(in) :: key
    write(key_iso, '(I4.4,A,I2.2,A,I2.2,A,I2.2,A)') &
      key/1000000, '-', mod(key/10000,100), '-', &
      mod(key/100,100), 'T', mod(key,100), ':00Z'
  end function key_iso

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

  ! a normal for site b on the sounding's date: what 1=fl 2=pw
  ! 3=ivt, q 1..5 = p10 p25 p50 p75 p90
  real(dp) function nv(b, key, what, q)
    integer, intent(in) :: b, key, what, q
    nv = nrm((what - 1) * 5 + q, key_doy(key), b)
  end function nv

  character(len=12) function vs(b, key, what, x)
    integer, intent(in) :: b, key, what
    real(dp), intent(in) :: x
    real(dp) :: xr
    ! compare at the precision the files store, so a rerun from
    ! sounding_series.csv gives the same answer
    xr = x
    if (ok(x)) then
      if (what == 2) then
        xr = anint(x * 10.0_dp) / 10.0_dp
      else
        xr = anint(x)
      end if
    end if
    vs = versus(xr, nv(b, key, what, 1), nv(b, key, what, 2), &
                nv(b, key, what, 4), nv(b, key, what, 5))
  end function vs

  character(len=16) function wind_at(b, pt)
    integer, intent(in) :: b
    real(dp), intent(in) :: pt
    integer :: a
    wind_at = '--'
    do a = 1, nk(b)
      if (abs(kp(a,b) - pt) < 0.5_dp .and. ok(kdir(a,b)) .and. &
          ok(kkt(a,b))) then
        wind_at = trim(compass(kdir(a,b))) // ' ' // &
          trim(cs(kkt(a,b), 0)) // ' KT'
        return
      end if
    end do
  end function wind_at

  !-- the snow, when NRCS is answering ------------------------------
  subroutine snowpack()
    integer :: u
    snow = .false.
    ns = 0
    open(newunit=u, file='stations.csv', status='old', iostat=ios)
    if (ios /= 0) return
    read(u, '(A)', iostat=ios) line
    do
      read(u, '(A)', iostat=ios) line
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
    close(u)
    swe = miss
    swem = miss
    dep = miss
    prc = miss
    prcm = miss
    tav = miss
    nrows = 0
    nskip = 0
    open(newunit=u, file='snotel_daily.csv', status='old', iostat=ios)
    if (ios == 0) then
      read(u, '(A)', iostat=ios) line
      do
        read(u, '(A)', iostat=ios) line
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
      close(u)
    end if
    write(*,'(A,I6)') 'CWX003I SNOTEL STATION-DAYS .........', nrows
    if (nrows == 0) then
      call note('CWX030I SNOWPACK SECTION SKIPPED: NO NRCS DATA ' // &
        'ON FILE YET', 0)
      return
    end if
    snow = .true.
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
    wy0 = jdn(wy1 - 1, 10, 1) - base + 1
    py0 = jdn(wy1 - 2, 10, 1) - base + 1
    py1 = wy0 - 1
    call snow_stations()
    call snow_massifs()
    call snow_review()
    call snow_lapse()
  end subroutine snowpack

  subroutine snow_stations()
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
  end subroutine snow_stations

  subroutine snow_massifs()
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
      ! a percent of a median under an inch per station means
      ! nothing; NRCS shows none either
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
  end subroutine snow_massifs

  subroutine snow_review()
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
  end subroutine snow_review

  ! least squares, SNOTEL mean temperature against elevation, on
  ! the newest day with temperature at 5 or more stations
  subroutine snow_lapse()
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
    if (tday == 0) return
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
      mslope = -(mn*sxy - sx*sy) / x            ! cooling, C/km
      y = mn*syy - sy*sy
      if (y > 0.0_dp) mr2 = (mn*sxy - sx*sy)**2 / (x*y)
    end if
  end subroutine snow_lapse

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

  character(len=12) function status_of(a)
    integer, intent(in) :: a
    status_of = 'OK'
    if (r_last(a) == 0) then
      status_of = 'NO DATA'
    else if (r_stale(a)) then
      status_of = 'STALE'
    end if
  end function status_of

  real(dp) function pk_pct(a)
    integer, intent(in) :: a
    pk_pct = miss
    if (m_mpk(a) >= 1.0_dp) pk_pct = 100.0_dp * m_pk(a) / m_mpk(a)
  end function pk_pct

  character(len=10) function dday(dy)
    integer, intent(in) :: dy
    dday = ' '
    if (dy > 0) dday = dstr(base + dy - 1)
  end function dday

  character(len=6) function mday(dy)
    integer, intent(in) :: dy
    mday = '    --'
    if (dy > 0) mday = mstr(base + dy - 1)
  end function mday

  character(len=8) function early(a)
    integer, intent(in) :: a
    early = ' '
    if (v_out(a) > 0 .and. v_mout(a) > 0) &
      early = trim(itoa(v_mout(a) - v_out(a)))
  end function early

  character(len=24) function lastnote(a)
    integer, intent(in) :: a
    lastnote = ' '
    if (r_stale(a) .and. r_last(a) > 0) &
      lastnote = ' (' // mstr(base + r_last(a) - 1) // ')'
  end function lastnote

  character(len=24) function dlabel(dy)
    integer, intent(in) :: dy
    dlabel = 'NOT AVAILABLE'
    if (dy > 0) dlabel = 'FOR ' // dstr(base + dy - 1)
  end function dlabel

  ! atmospheric-river soundings this water year at site b
  subroutine ar_season(b, n, nar, imax, kmax)
    integer, intent(in) :: b
    integer, intent(out) :: n, nar, kmax
    real(dp), intent(out) :: imax
    integer :: a
    n = 0
    nar = 0
    imax = miss
    kmax = 0
    do a = 1, nser
      if (sst(a) /= b .or. ser(a)%key < key_of(jdn(wy - 1, 10, 1))) &
        cycle
      if (.not. ok(ser(a)%ivt)) cycle
      n = n + 1
      if (ser(a)%ivt >= 250.0_dp) nar = nar + 1
      if (.not. ok(imax) .or. ser(a)%ivt > imax) then
        imax = ser(a)%ivt
        kmax = ser(a)%key
      end if
    end do
  end subroutine ar_season

  !-- outputs -----------------------------------------------------
  subroutine write_series()
    integer :: u, a, b
    open(newunit=u, file='sounding_series.tmp', status='replace')
    write(u, '(A)') 'key,station,valid_utc,psfc_hpa,ptop_hpa,' // &
      'freezing_ft,wetbulb0_ft,snow_level_ft,pw_mm,ivt,' // &
      'ivt_from_deg,ar_category,t850_c,lapse_850_700_c_km,' // &
      'w700_from_deg,w700_kt,fl_vs_normal,pw_vs_normal'
    do a = 1, nser
      b = sst(a)
      write(u, '(A)') trim(itoa(ser(a)%key)) // ',' // trim(bid(b)) &
        // ',' // trim(key_iso(ser(a)%key)) // ',' // &
        cs(ser(a)%psfc, 0) // ',' // cs(ser(a)%ptop, 0) // ',' // &
        cs(ft(ser(a)%fl), 0) // ',' // cs(ft(ser(a)%wbz), 0) // &
        ',' // cs(snow_ft(ser(a)), 0) // ',' // cs(ser(a)%pw, 1) // &
        ',' // cs(ser(a)%ivt, 0) // ',' // cs(ser(a)%ivtdir, 0) // &
        ',' // trim(ar_cat(ser(a)%ivt)) // ',' // &
        cs(ser(a)%t850, 1) // ',' // cs(ser(a)%lapse, 2) // ',' // &
        cs(ser(a)%w7dir, 0) // ',' // cs(ser(a)%w7kt, 0) // ',' // &
        trim(vs(b, ser(a)%key, 1, ft(ser(a)%fl))) // ',' // &
        trim(vs(b, ser(a)%key, 2, ser(a)%pw))
    end do
    close(u)
    call rename('sounding_series.tmp', 'sounding_series.csv')
  end subroutine write_series

  subroutine write_profiles()
    integer :: u, a, b
    if (sum(nk) == 0) return             ! nothing new: keep the file
    open(newunit=u, file='upper_air.csv', status='replace')
    write(u, '(A)') 'station,valid_utc,p_hpa,z_m,t_c,td_c,tw_c,' // &
      'q_gkg,wind_from_deg,wind_kt'
    do b = 1, nb
      do a = 1, nk(b)
        write(u, '(A)') trim(bid(b)) // ',' // &
          trim(key_iso(newkey(b))) // ',' // cs(kp(a,b), 1) // ',' // &
          cs(kz(a,b), 0) // ',' // cs(kt_(a,b), 1) // ',' // &
          cs(ktd(a,b), 1) // ',' // cs(ktw(a,b), 1) // ',' // &
          cs(kq(a,b), 2) // ',' // cs(kdir(a,b), 0) // ',' // &
          cs(kkt(a,b), 0)
      end do
    end do
    close(u)
  end subroutine write_profiles

  subroutine write_air()
    integer :: u, b, n, nar, kmax, key
    real(dp) :: imax
    type(sounding) :: s
    open(newunit=u, file='air.csv', status='replace')
    write(u, '(A)') 'station,name,valid_utc,hours_old,freezing_ft,' // &
      'fl_p10,fl_p25,fl_p50,fl_p75,fl_p90,fl_vs_normal,' // &
      'wetbulb0_ft,snow_level_ft,pw_mm,pw_p50,pw_vs_normal,ivt,' // &
      'ivt_from,ar_category,ivt_p90,ar_pct_normal,t850_c,' // &
      'lapse_850_700_c_km,w700,wy_soundings,wy_ar_soundings,' // &
      'wy_max_ivt,wy_max_ivt_utc'
    do b = 1, nb
      if (lat(b) == 0) cycle
      s = ser(lat(b))
      key = s%key
      call ar_season(b, n, nar, imax, kmax)
      write(u, '(A)') trim(bid(b)) // ',' // trim(bname(b)) // ',' &
        // trim(key_iso(key)) // ',' // trim(itoa(hours_since(key))) &
        // ',' // cs(ft(s%fl), 0) // ',' // cs(nv(b,key,1,1), 0) // &
        ',' // cs(nv(b,key,1,2), 0) // ',' // cs(nv(b,key,1,3), 0) &
        // ',' // cs(nv(b,key,1,4), 0) // ',' // &
        cs(nv(b,key,1,5), 0) // ',' // trim(vs(b,key,1,ft(s%fl))) &
        // ',' // cs(ft(s%wbz), 0) // ',' // cs(snow_ft(s), 0) // &
        ',' // cs(s%pw, 1) // ',' // cs(nv(b,key,2,3), 1) // ',' // &
        trim(vs(b,key,2,s%pw)) // ',' // cs(s%ivt, 0) // ',' // &
        trim(compass(s%ivtdir)) // ',' // trim(ar_cat(s%ivt)) // &
        ',' // cs(nv(b,key,3,5), 0) // ',' // &
        cs(narp(key_doy(key), b), 1) // ',' // cs(s%t850, 1) // ',' &
        // cs(s%lapse, 2) // ',' // trim(compass(s%w7dir)) // ' ' // &
        trim(cs(s%w7kt, 0)) // ' kt,' // trim(itoa(n)) // ',' // &
        trim(itoa(nar)) // ',' // cs(imax, 0) // ',' // &
        trim(merge(key_iso(kmax), repeat(' ', 17), kmax > 0))
    end do
    close(u)
  end subroutine write_air

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

  subroutine write_summary()
    integer :: u, b
    type(sounding) :: s
    open(newunit=u, file='summary.csv', status='replace')
    write(u, '(A)') 'key,value'
    write(u, '(A)') 'version,' // ver
    write(u, '(A)') 'run_utc,' // trim(runutc)
    write(u, '(A)') 'pacific_date,' // pdate
    write(u, '(A)') 'water_year,' // trim(itoa(wy))
    write(u, '(A)') 'return_code,' // trim(itoa(rc))
    write(u, '(A)') 'balloon_sites,' // trim(itoa(nb))
    write(u, '(A)') 'balloon_sites_current,' // &
      trim(itoa(count([(lat(b) > 0, b = 1, nb)])))
    b = site('KUIL')
    if (b > 0) then
      if (lat(b) > 0) then
        s = ser(lat(b))
        write(u, '(A)') 'sounding_valid_utc,' // trim(key_iso(s%key))
        write(u, '(A)') 'freezing_level_ft,' // cs(ft(s%fl), 0)
        write(u, '(A)') 'freezing_vs_normal,' // &
          trim(vs(b, s%key, 1, ft(s%fl)))
        write(u, '(A)') 'freezing_normal_p50,' // &
          cs(nv(b, s%key, 1, 3), 0)
        write(u, '(A)') 'wetbulb_zero_ft,' // cs(ft(s%wbz), 0)
        write(u, '(A)') 'snow_level_ft,' // cs(snow_ft(s), 0)
        write(u, '(A)') 'pw_mm,' // cs(s%pw, 1)
        write(u, '(A)') 'pw_vs_normal,' // trim(vs(b,s%key,2,s%pw))
        write(u, '(A)') 'ivt,' // cs(s%ivt, 0)
        write(u, '(A)') 'ivt_from,' // trim(compass(s%ivtdir))
        write(u, '(A)') 'ar_category,' // trim(ar_cat(s%ivt))
        write(u, '(A)') 't850_c,' // cs(s%t850, 1)
        write(u, '(A)') 'free_air_lapse_c_km,' // cs(s%lapse, 2)
        write(u, '(A)') 'w700,' // trim(compass(s%w7dir)) // ' ' &
          // trim(cs(s%w7kt, 0)) // ' kt'
      end if
    end if
    write(u, '(A)') 'snow,' // trim(merge('yes', 'no ', snow))
    if (snow) then
      write(u, '(A)') 'data_date,' // dstr(base + dd - 1)
      write(u, '(A)') 'stations,' // trim(itoa(ns))
      write(u, '(A)') 'stations_reporting,' // &
        trim(itoa(count(r_last(1:ns) == dd)))
      write(u, '(A)') 'region_swe_pct,' // cs(m_pct(4), 0)
      write(u, '(A)') 'region_class,' // trim(m_cls(4))
      write(u, '(A)') 'region_precip_pct,' // cs(m_ppc(4), 0)
      write(u, '(A)') 'last_wy_peak_pct,' // cs(pk_pct(4), 0)
      write(u, '(A)') 'mountain_lapse_c_km,' // cs(mslope, 2)
      write(u, '(A)') 'mountain_lapse_r2,' // cs(mr2, 2)
    end if
    write(u, '(A)') 'messages,' // trim(itoa(nmsg))
    close(u)
  end subroutine write_summary

  !-- the printed report, 132 columns ------------------------------
  subroutine write_report()
    integer :: u, a, b, m, n, nar, kmax, key, c, prev
    character(len=132) :: rule, dash
    type(sounding) :: s
    real(dp) :: pz(7), v(7), imax
    character(len=6) :: lab(7)
    character(len=17) :: kiso
    rule = repeat('=', 132)
    dash = repeat('-', 132)
    open(newunit=u, file='cascadia-wx-report.txt', status='replace')
    write(u, '(A)') rule
    write(u, '(A)') ver // ' ' // repeat(' ', 20) // &
      'PACIFIC NORTHWEST UPPER AIR AND SNOWPACK' // &
      repeat(' ', 29) // 'RUN ' // runutc // ' UTC'
    write(u, '(A)') repeat(' ', 37) // &
      'QUILLAYUTE - SALEM - MEDFORD - SPOKANE   RAINIER - ' // &
      'OLYMPICS - CASCADES'
    write(u, '(A)') 'WATER YEAR ' // trim(itoa(wy)) // &
      repeat(' ', 52) // 'NORMALS: 1991-2020 (BALLOONS AND NRCS)'
    write(u, '(A)') rule
    write(u, '(A)')

    write(u, '(A)') 'SECTION I    THE AIR NOW    LATEST WEATHER ' // &
      'BALLOON AT EACH SITE, AGAINST 1991-2020 FOR THE DATE'
    write(u, '(A)')
    write(u, '(A)') 'SITE         BALLOON         FREEZING   ' // &
      'NORMAL RANGE  VS NORMAL     SNOW LVL     PW  VS NORMAL' // &
      '       IVT  RIVER         700 HPA WIND'
    write(u, '(A)') '                                   FT   ' // &
      ' 25TH-75TH FT                    FT     MM               ' // &
      'KG/M/S'
    write(u, '(A)') dash
    do b = 1, nb
      if (lat(b) == 0) then
        write(u, '(A12,1X,A)') bname(b), 'NO SOUNDINGS'
        cycle
      end if
      s = ser(lat(b))
      key = s%key
      kiso = key_iso(key)
      write(u, '(A12,1X,A14,A10,A8,A1,A6,2X,A12,A10,A7,2X,A12,' // &
        'A8,2X,A12,2X,A)') bname(b), kiso(1:13) // 'Z', &
        rf(ft(s%fl),10,0), rf(nv(b,key,1,2),8,0), '-', &
        adjustl(rf(nv(b,key,1,4),6,0)), vs(b,key,1,ft(s%fl)), &
        rf(snow_ft(s),10,0), rf(s%pw,7,1), vs(b,key,2,s%pw), &
        rf(s%ivt,8,0), ar_cat(s%ivt), trim(wind_at(b, 700.0_dp))
    end do
    write(u, '(A)') dash
    write(u, '(A)') '  VS NORMAL: BELOW THE 10TH PERCENTILE IS ' // &
      'MUCH BELOW, 25TH-75TH IS NORMAL, ABOVE THE 90TH IS MUCH ' // &
      'ABOVE,' // &
      ' FOR BALLOONS'
    write(u, '(A)') '  WITHIN 7 DAYS OF THE DATE, 1991-2020. SNOW ' // &
      'LEVEL: 1000 FT BELOW FREEZING, THE NWS RULE OF THUMB.'
    write(u, '(A)') '  IVT: VAPOUR CARRIED THROUGH THE COLUMN, ' // &
      'SURFACE TO 300 HPA. 250 AND UP IS ATMOSPHERIC-RIVER ' // &
      'STRENGTH (RALPH 2019).'
    write(u, '(A)')

    write(u, '(A)') 'SECTION II   THE COAST, LEVEL BY LEVEL    ' // &
      'QUILLAYUTE, WA (KUIL, WMO 72797)'
    write(u, '(A)')
    b = site('KUIL')
    if (b == 0) then
      write(u, '(A)') '  NO QUILLAYUTE SITE.'
    else if (nk(b) == 0) then
      write(u, '(A)') '  NO NEW BALLOON THIS RUN.'
    else
      write(u, '(A)') '  BALLOON ' // key_iso(newkey(b))
      write(u, '(A)') '    LEVEL     HEIGHT    TEMP   DEWPT  ' // &
        'WETBULB    Q G/KG    WIND'
      write(u, '(A)') '      HPA         FT       C       C  ' // &
        '      C'
      pz = [kp(1,b), 1000d0, 925d0, 850d0, 700d0, 500d0, 300d0]
      lab = ['   SFC', '  1000', '   925', '   850', '   700', &
             '   500', '   300']
      do c = 1, 7
        if (c > 1 .and. pz(c) > kp(1,b)) cycle
        v(1) = at_p(nk(b), kp(:,b), kz(:,b), pz(c))
        v(2) = at_p(nk(b), kp(:,b), kt_(:,b), pz(c))
        v(3) = at_p(nk(b), kp(:,b), ktd(:,b), pz(c))
        v(4) = at_p(nk(b), kp(:,b), ktw(:,b), pz(c))
        v(5) = at_p(nk(b), kp(:,b), kq(:,b), pz(c))
        write(u, '(3X,A6,A11,A8,A8,A9,A10,4X,A)') lab(c), &
          rf(ft(v(1)),11,0), rf(v(2),8,1), rf(v(3),8,1), &
          rf(v(4),9,1), rf(v(5),10,2), trim(wind_at(b, pz(c)))
      end do
    end if
    write(u, '(A)')

    write(u, '(A)') 'SECTION III  ATMOSPHERIC RIVERS, WATER YEAR ' // &
      trim(itoa(wy)) // ' (SINCE OCT 1)'
    write(u, '(A)')
    write(u, '(A)') 'SITE         BALLOONS   AT AR STRENGTH   ' // &
      'STRONGEST IVT  WHEN               STRENGTH'
    write(u, '(A)') dash(1:100)
    do b = 1, nb
      call ar_season(b, n, nar, imax, kmax)
      write(u, '(A12,I10,I17,A15,2X,A17,2X,A)') bname(b), n, nar, &
        rf(imax,15,0), merge(key_iso(kmax), '               --', &
        kmax > 0), trim(merge(ar_cat(imax), '--          ', n > 0))
    end do
    write(u, '(A)') '  ONE BALLOON IS ONE MOMENT AT ONE PLACE; ' // &
      'THE OFFICIAL AR SCALE ALSO WEIGHS HOW LONG A RIVER LASTS.'
    write(u, '(A)')

    write(u, '(A)') 'SECTION IV   RECENT BALLOONS    FREEZING ' // &
      'LEVEL (FT) AND IVT (KG/M/S)'
    write(u, '(A)')
    write(u, '(A)', advance='no') '  BALLOON          '
    do b = 1, nb
      write(u, '(A20)', advance='no') adjustr(bname(b))
    end do
    write(u, '(A)')
    ! the eight latest launch times at any site, newest first
    prev = huge(prev)
    do a = 1, 8
      key = 0
      do b = 1, nb
        if (lat(b) == 0) cycle
        do c = max(1, lat(b) - 15), lat(b)
          if (sst(c) == b .and. ser(c)%key < prev) &
            key = max(key, ser(c)%key)
        end do
      end do
      if (key == 0) exit
      prev = key
      kiso = key_iso(key)
      write(u, '(2X,A16)', advance='no') kiso(1:16)
      do b = 1, nb
        m = 0
        do c = max(1, lat(b) - 15), lat(b)
          if (lat(b) == 0) exit
          if (sst(c) == b .and. ser(c)%key == key) m = c
        end do
        if (m > 0) then
          write(u, '(A12,A8)', advance='no') &
            rf(ft(ser(m)%fl),12,0), rf(ser(m)%ivt,8,0)
        else
          write(u, '(A20)', advance='no') '--'
        end if
      end do
      write(u, '(A)')
    end do
    write(u, '(A)')

    write(u, '(A)') 'SECTION V    TEMPERATURE WITH HEIGHT'
    write(u, '(A)')
    do b = 1, nb
      if (lat(b) == 0) cycle
      write(u, '(A)') '  FREE AIR 850-700 HPA, ' // bname(b) // &
        ' ....' // rf(ser(lat(b))%lapse,6,2) // ' C PER KM'
    end do
    if (snow) then
      write(u, '(A)') '  MOUNTAIN SURFACE (SNOTEL FIT) ' // &
        '..........' // rf(mslope,6,2) // ' C PER KM   R-SQUARED' &
        // rf(mr2,5,2) // '   STATIONS ' // trim(itoa(mn)) // &
        '   ' // trim(dlabel(tday))
      if (ok(mslope)) then
        if (mslope < 0.0_dp) write(u, '(A)') '  NEGATIVE MEANS ' &
          // 'IT WAS WARMER HIGHER UP: AN INVERSION.'
      end if
    end if
    write(u, '(A)') '  DRY ADIABATIC IS 9.8 C PER KM; THE STANDARD ' &
      // 'ATMOSPHERE 6.5.'
    write(u, '(A)')

    write(u, '(A)') 'SECTION VI   SNOWPACK    NRCS SNOTEL, 12 ' // &
      'STATIONS, AGAINST NRCS 1991-2020 MEDIANS'
    write(u, '(A)')
    if (.not. snow) then
      write(u, '(A)') '  NO NRCS DATA ON FILE YET. THIS SECTION ' // &
        'FILLS IN WHEN THE NRCS SERVICE ANSWERS.'
    else
      write(u, '(A)') '  DATA FOR ' // dstr(base + dd - 1)
      write(u, '(A)') 'STATION          MASSIF     ELEV  ' // &
        '  SWE  MEDIAN   %MED  7-DAY   DEPTH   ' // &
        'WY PRECIP  MEDIAN   %MED   TAVG  STATUS'
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
      write(u, '(A)') 'MASSIF     STATIONS     SWE  MEDIAN   ' // &
        '%MED  CLASS                 WY PRECIP  MEDIAN   %MED'
      do a = 1, 4
        write(u, '(A8,I10,A9,A8,A7,2X,A18,A14,A8,A7)') &
          merge(mname(min(a,3)), 'ALL     ', a <= 3), m_n(a), &
          rf(m_swe(a),9,1), rf(m_med(a),8,1), rf(m_pct(a),7,0), &
          m_cls(a), rf(m_prc(a),14,1), rf(m_prm(a),8,1), &
          rf(m_ppc(a),7,0)
      end do
      write(u, '(A)')
      write(u, '(A)') '  WATER YEAR ' // trim(itoa(wy1 - 1)) // &
        ' IN REVIEW'
      write(u, '(A)') 'STATION          MASSIF       PEAK  ' // &
        'DATE    MEDIAN PEAK  DATE      %MED   MELT-OUT  MEDIAN  ' // &
        ' DAYS EARLY'
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
      write(u, '(A)') '  ALL STATIONS: SUM OF PEAKS ' // &
        trim(cs(m_pk(4),1)) // ' IN, SUM OF MEDIAN PEAKS ' // &
        trim(cs(m_mpk(4),1)) // ' IN = ' // &
        trim(cs(pk_pct(4),0)) // '% OF MEDIAN'
    end if
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
    write(u, '(A)') 'SOURCES      NWS RADIOSONDES VIA THE IOWA ' // &
      'ENVIRONMENTAL MESONET  -  NRCS AWDB (SNOTEL)'
    write(u, '(A)') 'END OF REPORT   ' // trim(itoa(nb)) // &
      ' BALLOON SITES   ' // trim(itoa(nser)) // ' BALLOONS ON FILE' &
      // '   RETURN CODE ' // trim(itoa(rc))
    write(u, '(A)') rule
    close(u)
  end subroutine write_report

end program cascadia_wx
