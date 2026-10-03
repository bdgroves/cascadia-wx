!=====================================================================
! NORMALS.f90                                           VERSION 1.0
! THIRTY YEARS OF WEATHER BALLOONS, 1991-2020
!
! READS EVERY 00Z AND 12Z SOUNDING FROM THE FOUR NWS UPPER-AIR SITES
! (history/*.csv, LISTED IN history/files.txt), WORKS OUT EACH ONE'S
! FREEZING LEVEL, PRECIPITABLE WATER AND VAPOUR TRANSPORT WITH THE
! SAME CODE AS THE DAILY RUN, AND WRITES normals.csv: FOR EVERY SITE
! AND EVERY DAY OF THE YEAR, THE 10TH, 25TH, 50TH, 75TH AND 90TH
! PERCENTILES OF EACH, FROM ALL SOUNDINGS WITHIN 7 DAYS OF THE DATE,
! AND HOW OFTEN IVT REACHED ATMOSPHERIC-RIVER STRENGTH (250).
!
! PERCENTILES: WEIBULL PLOTTING POSITION, P*(N+1), AS SIERRA-FLOW.
! RETURN CODES  0 NORMAL   4 A SITE HAS FEWER THAN 20 YEARS
!               12 AN INPUT FILE CANNOT BE OPENED
!=====================================================================
program normals
  use cwx_util
  use cwx_phys
  implicit none
  integer, parameter :: maxs = 8, maxh = 40000, win = 7
  integer, parameter :: y0 = 1991, y1 = 2020
  character(len=8) :: sid(maxs)
  integer :: ns, nh(maxs)
  integer(kind=2) :: hdoy(maxh, maxs), hyr(maxh, maxs)
  real :: hfl(maxh, maxs), hpw(maxh, maxs), hivt(maxh, maxs)
  real(dp) :: lp(maxl), lz(maxl), lt(maxl), ltd(maxl)
  real(dp) :: ldir(maxl), lkt(maxl), ltw(maxl), lq(maxl)
  real(dp) :: buf(maxh)
  type(sounding) :: s
  character(len=64) :: f(maxf)
  character(len=256) :: line, fname
  character(len=8) :: cursta
  integer :: nf, ios, u, uf, i, k, d, j, cur, nl, rc, nfiles
  integer :: nread, nused, nskip, years(maxs)
  real(dp) :: q(5, 3), arp
  integer :: nq(3)
  logical :: seen(y0:y1, maxs)

  rc = 0
  write(*,'(A)') 'NRML000I NORMALS V1.0 STARTED'
  ns = 0
  open(newunit=u, file='balloons.csv', status='old', iostat=ios)
  if (ios /= 0) call fail('balloons.csv')
  read(u, '(A)') line
  do
    read(u, '(A)', iostat=ios) line
    if (ios /= 0) exit
    call split(line, f, nf)
    if (len_trim(f(1)) == 0 .or. ns == maxs) cycle
    ns = ns + 1
    sid(ns) = f(1)
  end do
  close(u)
  nh = 0
  seen = .false.
  nread = 0
  nused = 0
  nskip = 0
  nfiles = 0

  open(newunit=uf, file='history/files.txt', status='old', iostat=ios)
  if (ios /= 0) call fail('history/files.txt')
  do
    read(uf, '(A)', iostat=ios) fname
    if (ios /= 0) exit
    if (len_trim(fname) == 0) cycle
    open(newunit=u, file='history/' // trim(fname), status='old', &
         iostat=ios)
    if (ios /= 0) call fail(trim(fname))
    nfiles = nfiles + 1
    read(u, '(A)', iostat=ios) line
    cur = 0
    nl = 0
    cursta = ' '
    do
      read(u, '(A)', iostat=ios) line
      if (ios /= 0) exit
      call split(line, f, nf)
      read(f(1), *, iostat=k) j
      if (k /= 0) cycle
      if ((j /= cur .or. f(2)(1:8) /= cursta) .and. nl > 0) &
        call take()
      cur = j
      cursta = f(2)(1:8)
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
  end do
  close(uf)
  write(*,'(A,I8)') 'NRML001I FILES READ ...............', nfiles
  write(*,'(A,I8)') 'NRML002I SOUNDINGS READ ...........', nread
  write(*,'(A,I8)') 'NRML003I SOUNDINGS USED (00Z,12Z) .', nused
  write(*,'(A,I8)') 'NRML004I SOUNDINGS SKIPPED ........', nskip
  do i = 1, ns
    years(i) = count(seen(:, i))
    write(*,'(A,A8,I7,A,I3,A)') 'NRML005I ', sid(i), nh(i), &
      ' SOUNDINGS IN ', years(i), ' YEARS'
    if (years(i) < 20) then
      write(*,'(A)') 'NRML010W ' // trim(sid(i)) // &
        ' HAS FEWER THAN 20 YEARS'
      rc = 4
    end if
  end do

  open(newunit=u, file='normals.csv', status='replace')
  write(u, '(A)') 'station,doy,years,n_fl,fl_p10,fl_p25,fl_p50,' // &
    'fl_p75,fl_p90,n_pw,pw_p10,pw_p25,pw_p50,pw_p75,pw_p90,' // &
    'n_ivt,ivt_p10,ivt_p25,ivt_p50,ivt_p75,ivt_p90,ar_pct'
  do i = 1, ns
    do d = 1, 366
      call window(i, d, 1, nq(1), q(:, 1))
      call window(i, d, 2, nq(2), q(:, 2))
      call window(i, d, 3, nq(3), q(:, 3))
      arp = miss
      if (nq(3) > 0) arp = 100.0_dp * count(near(i, d) .and. &
        hivt(1:nh(i), i) >= 250.0) / nq(3)
      write(u, '(A)') trim(sid(i)) // ',' // trim(itoa(d)) // ',' // &
        trim(itoa(years(i))) // ',' // trim(row(1)) // ',' // &
        trim(row(2)) // ',' // trim(row(3)) // ',' // cs(arp, 1)
    end do
  end do
  close(u)
  write(*,'(A)') 'NRML006I NORMALS WRITTEN: normals.csv'
  write(*,'(A,I2)') 'NRML999I NORMALS ENDED  RC=', rc
  call exit(rc)

contains

  subroutine fail(name)
    character(len=*), intent(in) :: name
    write(*,'(A)') 'NRML012E CANNOT OPEN ' // name
    write(*,'(A)') 'NRML999I NORMALS ENDED  RC=12'
    call exit(12)
  end subroutine fail

  ! one sounding is in lp..lkt: keep its numbers if it is a
  ! 00Z or 12Z launch from 1991-2020 at one of our sites
  subroutine take()
    integer :: k2, yy, mm, dd, hh, jj, ii
    nread = nread + 1
    k2 = 0
    do ii = 1, ns
      if (cursta == sid(ii)) k2 = ii
    end do
    yy = cur / 1000000
    mm = mod(cur / 10000, 100)
    dd = mod(cur / 100, 100)
    hh = mod(cur, 100)
    call prep_levels(nl, lp, lz, lt, ltd, ldir, lkt)
    if (k2 == 0 .or. (hh /= 0 .and. hh /= 12) .or. yy < y0 .or. &
        yy > y1 .or. nl < 10 .or. nh(max(k2,1)) >= maxh) then
      nskip = nskip + 1
      nl = 0
      return
    end if
    if (lp(1) < 850.0_dp) then          ! no surface level
      nskip = nskip + 1
      nl = 0
      return
    end if
    s = sounding()
    s%key = cur
    call analyse(s, nl, lp(1:nl), lz(1:nl), lt(1:nl), ltd(1:nl), &
                 ldir(1:nl), lkt(1:nl), ltw(1:nl), lq(1:nl))
    nh(k2) = nh(k2) + 1
    jj = nh(k2)
    hdoy(jj, k2) = int(doy366(mm, dd), 2)
    hyr(jj, k2) = int(yy, 2)
    hfl(jj, k2) = real(rmiss(s%fl * m2ft, s%fl))
    hpw(jj, k2) = real(s%pw)
    hivt(jj, k2) = real(s%ivt)
    seen(yy, k2) = .true.
    nused = nused + 1
    nl = 0
  end subroutine take

  real(dp) function rmiss(v, chk)
    real(dp), intent(in) :: v, chk
    rmiss = miss
    if (ok(chk)) rmiss = v
  end function rmiss

  ! soundings within win days of day d (the year wraps)
  function near(i2, d2) result(m)
    integer, intent(in) :: i2, d2
    logical :: m(nh(i2))
    integer :: a, dist
    do a = 1, nh(i2)
      dist = abs(hdoy(a, i2) - d2)
      dist = min(dist, 366 - dist)
      m(a) = dist <= win
    end do
  end function near

  subroutine window(i2, d2, what, n, qq)
    integer, intent(in) :: i2, d2, what
    integer, intent(out) :: n
    real(dp), intent(out) :: qq(5)
    logical :: m(nh(i2))
    real :: v
    integer :: a
    m = near(i2, d2)
    n = 0
    do a = 1, nh(i2)
      if (.not. m(a)) cycle
      select case (what)
      case (1)
        v = hfl(a, i2)
      case (2)
        v = hpw(a, i2)
      case default
        v = hivt(a, i2)
      end select
      if (v > real(miss) + 1.0) then
        n = n + 1
        buf(n) = v
      end if
    end do
    qq = miss
    if (n < 30) return
    call hsort(n, buf(1:n))
    qq = [pctl(n, buf(1:n), 0.10_dp), pctl(n, buf(1:n), 0.25_dp), &
          pctl(n, buf(1:n), 0.50_dp), pctl(n, buf(1:n), 0.75_dp), &
          pctl(n, buf(1:n), 0.90_dp)]
  end subroutine window

  character(len=80) function row(what)
    integer, intent(in) :: what
    integer :: dg
    dg = 0
    if (what == 2) dg = 1
    row = trim(itoa(nq(what))) // ',' // cs(q(1, what), dg) // ',' // &
      cs(q(2, what), dg) // ',' // cs(q(3, what), dg) // ',' // &
      cs(q(4, what), dg) // ',' // cs(q(5, what), dg)
  end function row

end program normals
