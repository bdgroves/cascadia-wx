!=====================================================================
! CWX_PHYS.f90   SHARED BY CASCADIA-WX AND NORMALS
!   cwx_util  CSV SPLITTING, DATES, NUMBER FORMATTING
!   cwx_phys  SOUNDING PHYSICS: WET BULB, HUMIDITY, FREEZING LEVEL,
!             PRECIPITABLE WATER, VAPOUR TRANSPORT, LAPSE RATE
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

  ! day of year 1-366 on a leap-year calendar, so Feb 29 has its
  ! own slot and Mar 1 is always day 61
  integer function doy366(m, d)
    integer, intent(in) :: m, d
    integer, parameter :: c(12) = [0, 31, 60, 91, 121, 152, &
                                   182, 213, 244, 274, 305, 335]
    doy366 = c(m) + d
  end function doy366

  ! heapsort, ascending, in place
  subroutine hsort(n, a)
    integer, intent(in) :: n
    real(dp), intent(inout) :: a(n)
    integer :: i, k
    real(dp) :: t
    do i = n / 2, 1, -1
      call sift(i, n)
    end do
    do k = n, 2, -1
      t = a(1)
      a(1) = a(k)
      a(k) = t
      call sift(1, k - 1)
    end do
  contains
    subroutine sift(lo, hi)
      integer, intent(in) :: lo, hi
      integer :: r, c
      real(dp) :: v
      r = lo
      v = a(r)
      do
        c = 2 * r
        if (c > hi) exit
        if (c < hi) then
          if (a(c+1) > a(c)) c = c + 1
        end if
        if (a(c) <= v) exit
        a(r) = a(c)
        r = c
      end do
      a(r) = v
    end subroutine sift
  end subroutine hsort

  ! Weibull plotting position: the value at P*(N+1) in a sorted
  ! sample, interpolated; clamped to the ends
  real(dp) function pctl(n, a, p)
    integer, intent(in) :: n
    real(dp), intent(in) :: a(n), p
    real(dp) :: r
    integer :: k
    pctl = miss
    if (n < 1) return
    r = p * (n + 1)
    k = int(r)
    if (k < 1) then
      pctl = a(1)
    else if (k >= n) then
      pctl = a(n)
    else
      pctl = a(k) + (r - k) * (a(k+1) - a(k))
    end if
  end function pctl

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

  ! order levels by falling pressure and drop repeated pressures;
  ! n comes back as the number of levels kept
  subroutine prep_levels(n, p, z, t, td, dir, kt)
    integer, intent(inout) :: n
    real(dp), intent(inout) :: p(:), z(:), t(:), td(:)
    real(dp), intent(inout) :: dir(:), kt(:)
    real(dp) :: v(6)
    integer :: a, b
    do a = 2, n
      v = [p(a), z(a), t(a), td(a), dir(a), kt(a)]
      b = a - 1
      do while (b >= 1)
        if (p(b) >= v(1)) exit
        p(b+1) = p(b)
        z(b+1) = z(b)
        t(b+1) = t(b)
        td(b+1) = td(b)
        dir(b+1) = dir(b)
        kt(b+1) = kt(b)
        b = b - 1
      end do
      p(b+1) = v(1)
      z(b+1) = v(2)
      t(b+1) = v(3)
      td(b+1) = v(4)
      dir(b+1) = v(5)
      kt(b+1) = v(6)
    end do
    if (n < 1) return
    b = 1
    do a = 2, n
      if (p(a) < p(b)) then
        b = b + 1
        p(b) = p(a)
        z(b) = z(a)
        t(b) = t(a)
        td(b) = td(a)
        dir(b) = dir(a)
        kt(b) = kt(a)
      end if
    end do
    n = b
  end subroutine prep_levels

  ! where x sits among the normals: WaterWatch-style classes
  character(len=12) function versus(x, p10, p25, p75, p90)
    real(dp), intent(in) :: x, p10, p25, p75, p90
    versus = '--'
    if (.not. ok(x) .or. .not. ok(p10)) return
    if (x < p10) then
      versus = 'MUCH BELOW'
    else if (x < p25) then
      versus = 'BELOW'
    else if (x <= p75) then
      versus = 'NORMAL'
    else if (x <= p90) then
      versus = 'ABOVE'
    else
      versus = 'MUCH ABOVE'
    end if
  end function versus

end module cwx_phys

