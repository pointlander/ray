# A small sphere scene, ray traced and served as a live page.
#
#   ~/.bend/bin/bend main.bend [side]
#
# side is the width and height in pixels, a power of two from 1 to 4096.
# The default is 128. Then open http://127.0.0.1:8080/
# Moving the mouse orbits the camera. A click toggles a closer view.
# Each frame is traced in this process and sent to the page.

import Base

# depth is log2(side). The picture is a square of that side.
type Size is Data:
  Size{depth: Nat, side: U32, f: F32}

type Choice is Data:
  Use{size: Size}
  Reject{}

type Pow is Data:
  PowGo{n: U32, acc: Nat}
  PowStop{out: Maybe<&2, Nat>}

def pow_odd(+n: U32, acc: Nat, odd: Bool) -> Pow:
  match odd:
    case True{}:
      PowStop{None{}}
    case False{}:
      PowGo{U32.shrn(n, 1n), 1n+acc}

def pow_go(+n: U32, acc: Nat, one: Bool) -> Pow:
  match one:
    case True{}:
      PowStop{Some{acc}}
    case False{}:
      pow_odd(n, acc, U32.is_eq(U32.and(n, 1), 1))

def pow_depth(fuel: Nat, step: Pow) -> Maybe<&2, Nat>:
  match fuel step:
    case 0n PowStop{out}:
      out
    case 0n PowGo{n, acc}:
      None{}
    case 1n+left PowStop{out}:
      out
    case 1n+left PowGo{+n, acc}:
      pow_depth(left, pow_go(n, acc, U32.is_eq(n, 1)))

def default_size() -> Size:
  Size{7n, 128, {128.0 : F32}}

def choice_of(+n: U32, got: Maybe<&2, Nat>) -> Choice:
  match got:
    case None{}:
      Reject{}
    case Some{depth}:
      Use{Size{depth, n, U32.to_f32(n)}}

# 4096 is 2^12. Anything larger is rejected before the log walk.
def choice_cap(n: U32, got: Maybe<&2, Nat>, big: Bool) -> Choice:
  match big:
    case True{}:
      Reject{}
    case False{}:
      choice_of(n, got)

def choice_read(got: Maybe<&2, U32>) -> Choice:
  match got:
    case None{}:
      Reject{}
    case Some{+n}:
      choice_cap(n, pow_depth(32n, PowGo{n, 0n}), U32.is_lt(4096, n))

def size_tail(tail: List<String>) -> Choice:
  match tail:
    case Nil{}:
      Use{default_size()}
    case a <> _:
      choice_read(U32.read(a))

# argv is the program, then an optional side.
def size_args(args: List<String>) -> Choice:
  match args:
    case Nil{}:
      Use{default_size()}
    case _ <> tail:
      size_tail(tail)

type Vec3 is Data:
  V3{x: F32, y: F32, z: F32}

# t is the ray distance. The normal faces outward. refl is 0..1.
type Hit is Data:
  Miss{}
  Hit{t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# Pinhole camera. sc is tan(half the vertical field of view).
type Cam is Data:
  Cam{ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32, rx: F32, ry: F32, rz: F32, ux: F32, uy: F32, uz: F32, sc: F32}

# One row-major strip of the picture. Each row is R,G,B bytes, top to bottom.
type Rows is Data:
  RNil{}
  RCons{row: List<&2, U32>, rest: Rows}

def pick_f(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}:
      a
    case False{}:
      b

def max0(+a: F32) -> F32:
  pick_f((a > 0.0 : F32), a, 0.0)

def norm3(+x: F32, +y: F32, +z: F32) -> Vec3:
  +len = F32.sqrt((x * x + y * y + z * z : F32))
  V3{(x / len : F32), (y / len : F32), (z / len : F32)}

def mix3(a: Vec3, b: Vec3, +t: F32) -> Vec3:
  match a b:
    case V3{ar, ag, ab} V3{br, bg, bb}:
      +k = (1.0 - t : F32)
      V3{(ar * k + br * t : F32), (ag * k + bg * t : F32), (ab * k + bb * t : F32)}

# --- colour ---------------------------------------------------------------

def channel(+c: F32) -> U32:
  +g = F32.sqrt(F32.clamp(c, 0.0, 1.0))
  F32.to_u32(F32.min((g * 255.0 : F32), 255.0))

def pack(c: Vec3) -> U32:
  match c:
    case V3{r, g, b}:
      +ri = channel(r)
      +gi = channel(g)
      +bi = channel(b)
      U32.or(U32.or(U32.shln(ri, 16n), U32.shln(gi, 8n)), bi)

def bytes3(+c: U32) -> List<&2, U32>:
  +r = U32.shrn(U32.and(c, 16711680), 16n)
  +g = U32.shrn(U32.and(c, 65280), 8n)
  +b = U32.and(c, 255)
  r <> (g <> (b <> Nil{}))

# Horizon is warm, zenith is blue, and a tight disc sits on the sun.
def sky(+dx: F32, +dy: F32, +dz: F32) -> Vec3:
  +t = F32.clamp((dy * 0.55 + 0.50 : F32), 0.0, 1.0)
  +hr = (0.97 + (0.32 - 0.97) * t : F32)
  +hg = (0.80 + (0.52 - 0.80) * t : F32)
  +hb = (0.58 + (0.96 - 0.58) * t : F32)
  +sun = F32.pow(max0((dx * F32.neg(0.31701148) + dy * 0.81014045 + dz * F32.neg(0.49312897) : F32)), 220.0)
  V3{(hr + sun * 1.4 : F32), (hg + sun * 1.15 : F32), (hb + sun * 0.70 : F32)}

def checker_tone(dark: Bool) -> Vec3:
  match dark:
    case True{}:
      V3{0.15, 0.16, 0.18}
    case False{}:
      V3{0.84, 0.81, 0.74}

# Cell size 1/2. sin changes sign every half unit.
def checker(+px: F32, +pz: F32) -> Vec3:
  +a = F32.sin((px * 6.2831855 : F32))
  +b = F32.sin((pz * 6.2831855 : F32))
  checker_tone((a * b < 0.0 : F32))

def color_of(chk: Bool, px: F32, pz: F32, cr: F32, cg: F32, cb: F32) -> Vec3:
  match chk:
    case False{}:
      V3{cr, cg, cb}
    case True{}:
      checker(px, pz)

def surface_color(kind: U32, +px: F32, +pz: F32, cr: F32, cg: F32, cb: F32) -> Vec3:
  color_of(U32.is_eq(kind, 1), px, pz, cr, cg, cb)

# --- rays and spheres -----------------------------------------------------

def near_t(+half_b: F32, +sq: F32) -> F32:
  +t0 = (F32.neg(half_b) - sq : F32)
  +t1 = (F32.neg(half_b) + sq : F32)
  pick_f((t0 > 0.001 : F32), t0, pick_f((t1 > 0.001 : F32), t1, F32.neg(1.0)))

# Nearest positive root of t^2 + 2*half_b*t + c = 0, or -1 on a miss.
def choose_t(+disc: F32, +half_b: F32, neg: Bool) -> F32:
  match neg:
    case True{}:
      F32.neg(1.0)
    case False{}:
      near_t(half_b, F32.sqrt(disc))

def keep_near(
  +t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32,
  cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match best:
    case Miss{}:
      Bool.pick(Hit, (t > 0.001 : F32), Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl}, Miss{})
    case Hit{+bt, bpx, bpy, bpz, bnx, bny, bnz, bcr, bcg, bcb, brefl}:
      Bool.pick(Hit,
        (t > 0.001 : F32) && (t < bt : F32),
        Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl},
        Hit{bt, bpx, bpy, bpz, bnx, bny, bnz, bcr, bcg, bcb, brefl})

def use_color(
  col: Vec3, t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32, refl: F32, best: Hit
) -> Hit:
  match col:
    case V3{cr, cg, cb}:
      keep_near(t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, best)

# kind 0 is a flat colour. kind 1 is the checker, and cr/cg/cb are ignored.
def hit_sph(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +cx: F32, +cy: F32, +cz: F32, +rad: F32,
  cr: F32, cg: F32, cb: F32, refl: F32, kind: U32, best: Hit
) -> Hit:
  +ocx = (ox - cx : F32)
  +ocy = (oy - cy : F32)
  +ocz = (oz - cz : F32)
  +half_b = (ocx * dx + ocy * dy + ocz * dz : F32)
  +c = (ocx * ocx + ocy * ocy + ocz * ocz - rad * rad : F32)
  +disc = (half_b * half_b - c : F32)
  +t = choose_t(disc, half_b, (disc < 0.0 : F32))
  +px = (ox + dx * t : F32)
  +py = (oy + dy * t : F32)
  +pz = (oz + dz * t : F32)
  +inv = (1.0 / rad : F32)
  +nx = ((px - cx) * inv : F32)
  +ny = ((py - cy) * inv : F32)
  +nz = ((pz - cz) * inv : F32)
  use_color(surface_color(kind, px, pz, cr, cg, cb), t, px, py, pz, nx, ny, nz, refl, best)

def sph_blocks(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +cx: F32, +cy: F32, +cz: F32, +rad: F32
) -> Bool:
  +ocx = (ox - cx : F32)
  +ocy = (oy - cy : F32)
  +ocz = (oz - cz : F32)
  +half_b = (ocx * dx + ocy * dy + ocz * dz : F32)
  +c = (ocx * ocx + ocy * ocy + ocz * ocz - rad * rad : F32)
  +disc = (half_b * half_b - c : F32)
  +t = choose_t(disc, half_b, (disc < 0.0 : F32))
  (t > 0.001 : F32)

# Centres sit on the floor (y = radius), except the floor itself, which is
# a sphere of radius 100 whose top is the plane y = 0.
def hit_ground(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, 0.0, F32.neg(100.0), 0.0, 100.0, 0.0, 0.0, 0.0, 0.18, 1, best)

def hit_red(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, F32.neg(1.05), 0.50, 0.15, 0.50, 0.86, 0.16, 0.12, 0.05, 0, best)

def hit_chrome(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, 0.15, 0.50, F32.neg(0.35), 0.50, 0.93, 0.93, 0.95, 0.90, 0, best)

def hit_blue(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, 1.25, 0.50, 0.25, 0.50, 0.16, 0.32, 0.86, 0.22, 0, best)

def hit_gold(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, F32.neg(0.35), 0.22, 1.05, 0.22, 0.96, 0.66, 0.16, 0.38, 0, best)

def hit_green(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit) -> Hit:
  hit_sph(ox, oy, oz, dx, dy, dz, 0.85, 0.18, 1.20, 0.18, 0.22, 0.72, 0.32, 0.12, 0, best)

def closest(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Hit:
  hit_green(ox, oy, oz, dx, dy, dz,
    hit_gold(ox, oy, oz, dx, dy, dz,
      hit_blue(ox, oy, oz, dx, dy, dz,
        hit_chrome(ox, oy, oz, dx, dy, dz,
          hit_red(ox, oy, oz, dx, dy, dz,
            hit_ground(ox, oy, oz, dx, dy, dz, Miss{}))))))

def cast_ground(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, 0.0, F32.neg(100.0), 0.0, 100.0)

def cast_red(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, F32.neg(1.05), 0.50, 0.15, 0.50)

def cast_chrome(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, 0.15, 0.50, F32.neg(0.35), 0.50)

def cast_blue(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, 1.25, 0.50, 0.25, 0.50)

def cast_gold(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, F32.neg(0.35), 0.22, 1.05, 0.22)

def cast_green(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  sph_blocks(ox, oy, oz, dx, dy, dz, 0.85, 0.18, 1.20, 0.18)

def blocked(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  Bool.or(cast_ground(ox, oy, oz, dx, dy, dz),
    Bool.or(cast_red(ox, oy, oz, dx, dy, dz),
      Bool.or(cast_chrome(ox, oy, oz, dx, dy, dz),
        Bool.or(cast_blue(ox, oy, oz, dx, dy, dz),
          Bool.or(cast_gold(ox, oy, oz, dx, dy, dz),
            cast_green(ox, oy, oz, dx, dy, dz))))))

def vis_of(in_shadow: Bool) -> F32:
  match in_shadow:
    case True{}:
      0.0
    case False{}:
      1.0

# Sun from the upper right, fill from the upper left. spec rides on the sun only.
def surface(
  +px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  +cr: F32, +cg: F32, +cb: F32, +dx: F32, +dy: F32, +dz: F32
) -> Vec3:
  +eps = {0.02 : F32}
  +ox = (px + nx * eps : F32)
  +oy = (py + ny * eps : F32)
  +oz = (pz + nz * eps : F32)
  +lx = {F32.neg(0.31701148) : F32}
  +ly = {0.81014045 : F32}
  +lz = {F32.neg(0.49312897) : F32}
  +ndotl = max0((nx * lx + ny * ly + nz * lz : F32))
  +ndotf = max0((nx * 0.57543534 + ny * 0.51789180 + nz * 0.63297887 : F32))
  +vis = vis_of(blocked(ox, oy, oz, lx, ly, lz))
  +rx = ((ndotl * (nx * 2.0)) - lx : F32)
  +ry = ((ndotl * (ny * 2.0)) - ly : F32)
  +rz = ((ndotl * (nz * 2.0)) - lz : F32)
  +vd = max0((rx * F32.neg(dx) + ry * F32.neg(dy) + rz * F32.neg(dz) : F32))
  +spec = (F32.pow(vd, 56.0) * ndotl * vis : F32)
  +lit = (0.11 + ndotl * vis * 1.10 + ndotf * 0.24 : F32)
  V3{
    (cr * lit + spec * 0.90 : F32),
    (cg * lit + spec * 0.86 : F32),
    (cb * lit + spec * 0.76 : F32)
  }

# Go fires a ray. Saw has already intersected it. Folding both into one def
# keeps the bounce recursive without a second function calling back.
# Two steps of n make one bounce, so trace starts at 6n: three hits, then sky.
type Step is Data:
  Go{ox: F32, oy: F32, oz: F32, dx: F32, dy: F32, dz: F32}
  Saw{hit: Hit, dx: F32, dy: F32, dz: F32}

def trace(+n: Nat, step: Step) -> Vec3:
  match n step:
    case 0n Go{ox, oy, oz, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Go{ox, oy, oz, +dx, +dy, +dz}:
      trace(p, Saw{closest(ox, oy, oz, dx, dy, dz), dx, dy, dz})
    case 1n+p Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Saw{Hit{t, +px, +py, +pz, +nx, +ny, +nz, cr, cg, cb, refl}, +dx, +dy, +dz}:
      +eps = {0.02 : F32}
      +ox = (px + nx * eps : F32)
      +oy = (py + ny * eps : F32)
      +oz = (pz + nz * eps : F32)
      +nd = (dx * nx + dy * ny + dz * nz : F32)
      +k = (nd * 2.0 : F32)
      mix3(
        surface(px, py, pz, nx, ny, nz, cr, cg, cb, dx, dy, dz),
        trace(p, Go{ox, oy, oz, (dx - k * nx : F32), (dy - k * ny : F32), (dz - k * nz : F32)}),
        refl)

# --- camera and pixels ----------------------------------------------------

# Right is cross(forward, world up). Up of the camera is cross(right, forward).
def cam_axes(
  +ex: F32, +ey: F32, +ez: F32, +fx: F32, +fy: F32, +fz: F32, +sc: F32, right: Vec3
) -> Cam:
  match right:
    case V3{+rx, +ry, +rz}:
      Cam{
        ex, ey, ez,
        fx, fy, fz,
        rx, ry, rz,
        (ry * fz - rz * fy : F32),
        (rz * fx - rx * fz : F32),
        (rx * fy - ry * fx : F32),
        sc
      }

def cam_from_fwd(+ex: F32, +ey: F32, +ez: F32, +sc: F32, fwd: Vec3) -> Cam:
  match fwd:
    case V3{+fx, +fy, +fz}:
      cam_axes(ex, ey, ez, fx, fy, fz, sc, norm3(F32.neg(fz), 0.0, fx))

# Look from the eye toward the target. World up is +Y.
def look_at(
  +ex: F32, +ey: F32, +ez: F32, +tx: F32, +ty: F32, +tz: F32, +sc: F32
) -> Cam:
  cam_from_fwd(ex, ey, ez, sc, norm3((tx - ex : F32), (ty - ey : F32), (tz - ez : F32)))

# Orbit the point the original picture looks at. yaw 0 is the front.
def orbit(+yaw: F32, +pitch: F32, +dist: F32, +sc: F32) -> Cam:
  +cp = F32.cos(pitch)
  +sp = F32.sin(pitch)
  +cy = F32.cos(yaw)
  +sy = F32.sin(yaw)
  +tx = {0.05 : F32}
  +ty = {0.38 : F32}
  +tz = {0.0 : F32}
  look_at(
    (tx + (dist * cp) * sy : F32),
    (ty + dist * sp : F32),
    (tz + (dist * cp) * cy : F32),
    tx, ty, tz, sc)

def shoot(ex: F32, ey: F32, ez: F32, dir: Vec3) -> U32:
  match dir:
    case V3{dx, dy, dz}:
      pack(trace(6n, Go{ex, ey, ez, dx, dy, dz}))

def aim(
  +x: U32, +y: U32, +side: F32,
  ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32,
  rx: F32, ry: F32, rz: F32, ux: F32, uy: F32, uz: F32, +sc: F32
) -> U32:
  +u = ((U32.to_f32(x) + 0.5) / side - 0.5 : F32)
  +v = (0.5 - (U32.to_f32(y) + 0.5) / side : F32)
  +su = (u * (sc * 2.0) : F32)
  +sv = (v * (sc * 2.0) : F32)
  shoot(ex, ey, ez, norm3(
    (fx + rx * su + ux * sv : F32),
    (fy + ry * su + uy * sv : F32),
    (fz + rz * su + uz * sv : F32)))

def pixel(+x: U32, +y: U32, +side: F32, cam: Cam) -> U32:
  match cam:
    case Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc}:
      aim(x, y, side, ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc)

# --- picture --------------------------------------------------------------

def zip_rows(a: Rows, b: Rows) -> Rows:
  match a b:
    case RNil{} RNil{}:
      RNil{}
    case RCons{lr, lt} RCons{rr, rt}:
      RCons{List.append(&2, U32, lr, rr), zip_rows(lt, rt)}
    case RNil{} RCons{row, rest}:
      RNil{}
    case RCons{row, rest} RNil{}:
      RNil{}

def cat_rows(a: Rows, b: Rows) -> Rows:
  match a:
    case RNil{}:
      b
    case RCons{row, rest}:
      RCons{row, cat_rows(rest, b)}

# The square at (x, y) with side s = 2^k. Forks four ways down to a pixel.
def block(+k: Nat, +x: U32, +y: U32, +s: U32, +side: F32, +cam: Cam) -> Rows:
  match k:
    case 0n:
      RCons{bytes3(pixel(x, y, side, cam)), RNil{}}
    case 1n+p:
      +h = U32.shrn(s, 1n)
      +x2 = (x + h : U32)
      +y2 = (y + h : U32)
      a b c d = block(p, x, y, h, side, cam) block(p, x2, y, h, side, cam) block(p, x, y2, h, side, cam) block(p, x2, y2, h, side, cam)
      cat_rows(zip_rows(a, b), zip_rows(c, d))

def onto(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      onto(t, h <> acc)

def flatten(rows: Rows, acc: List<&2, U32>) -> List<&2, U32>:
  match rows:
    case RNil{}:
      acc
    case RCons{row, rest}:
      flatten(rest, onto(row, acc))

def render(depth: Nat, side: U32, f: F32, cam: Cam) -> List<&2, U32>:
  List.reverse(&2, U32, flatten(block(depth, 0, 0, side, f, cam), Nil{}))

# --- view -----------------------------------------------------------------
# The page asks for /f SYYYY PPPP Z
# S is 0 or 1 (yaw sign), YYYY and PPPP are thousandths, Z is 0 or 1.

type View is Data:
  View{yaw: F32, pitch: F32, zoom: U32}

def num_step(n: Nat, s: String, acc: U32) -> U32 & String:
  match n s:
    case 0n rest:
      (acc, rest)
    case 1n+p SCon{Chr{c}, t}:
      num_step(p, t, ((acc * 10 + (c - 48)) : U32))
    case _ rest:
      (acc, rest)

def yaw_of(sign: U32, mag: U32) -> F32:
  +v = (U32.to_f32(mag) / 1000.0 : F32)
  pick_f(U32.is_eq(sign, 49), F32.neg(v), v)

def view_zoom(sign: U32, yaw_mag: U32, pitch_mag: U32, rest: String) -> View:
  match rest:
    case SCon{Chr{z}, _}:
      View{yaw_of(sign, yaw_mag), (U32.to_f32(pitch_mag) / 1000.0 : F32), z}
    case _:
      View{{0.15 : F32}, {0.38 : F32}, 48}

def view_pitch(sign: U32, yaw_mag: U32, got: U32 & String) -> View:
  match got:
    case (pitch_mag, rest):
      view_zoom(sign, yaw_mag, pitch_mag, rest)

def view_mag(sign: U32, got: U32 & String) -> View:
  match got:
    case (mag, rest):
      view_pitch(sign, mag, num_step(4n, rest, 0))

def view_of(sign: U32, s: String) -> View:
  view_mag(sign, num_step(4n, s, 0))

def dist_of(zoom: U32) -> F32:
  pick_f(U32.is_eq(zoom, 49), {2.25 : F32}, {4.6 : F32})

def fov_of(zoom: U32) -> F32:
  pick_f(U32.is_eq(zoom, 49), {0.26 : F32}, {0.44 : F32})

def cam_of(v: View) -> Cam:
  match v:
    case View{yaw, pitch, +zoom}:
      orbit(yaw, F32.clamp(pitch, {0.12 : F32}, {1.12 : F32}), dist_of(zoom), fov_of(zoom))

# --- http -----------------------------------------------------------------

def body_len(+side: U32) -> U32:
  (side * side * 3 : U32)

def prepend_str(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, t}:
      prepend_str(t, c <> acc)

def str_bytes(s: String) -> List<&2, U32>:
  List.reverse(&2, U32, prepend_str(s, Nil{}))

def with_header(header: String, body: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, str_bytes(header), body)

def frame_header(side: U32) -> String:
  "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store\r\nContent-Length: "
    ++ U32.show(body_len(side))
    ++ "\r\nConnection: close\r\n\r\n"

def text_header(kind: String, n: Nat) -> String:
  "HTTP/1.1 200 OK\r\nContent-Type: " ++ kind ++ "\r\nCache-Control: no-store\r\nContent-Length: "
    ++ Nat.show(n)
    ++ "\r\nConnection: close\r\n\r\n"

def not_found() -> String:
  "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

def html_body(+side: U32) -> String:
  "<!doctype html><html><head><meta charset='utf-8'><title>Sphere trace</title><style>"
    ++ "html,body{margin:0;height:100%;background:#12141a;color:#e8e6e1;font:15px sans-serif;}"
    ++ "body{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;user-select:none;}"
    ++ "canvas{background:#000;cursor:crosshair;touch-action:none;}"
    ++ "p{margin:0;letter-spacing:.02em;opacity:.85;}"
    ++ "</style></head><body><canvas id='view' width='"
    ++ U32.show(side)
    ++ "' height='"
    ++ U32.show(side)
    ++ "'></canvas><p id='hud'>move to orbit, click to zoom</p><script>"
    ++ "const side = "
    ++ U32.show(side)
    ++ "; const canvas = document.getElementById('view');"
    ++ "const ctx = canvas.getContext('2d', {alpha:false});"
    ++ "const hud = document.getElementById('hud');"
    ++ "let yaw = 0.15; let pitch = 0.38; let zoom = 0;"
    ++ "function pad(n){const s = String(Math.max(0, Math.min(9999, n|0))); return '0000'.slice(s.length) + s;}"
    ++ "function path(){const ys = yaw < 0 ? '1' : '0'; return '/f' + ys + pad(Math.round(Math.abs(yaw)*1000)) + pad(Math.round(pitch*1000)) + (zoom ? '1' : '0');}"
    ++ "function look(e){const r = canvas.getBoundingClientRect();"
    ++ "let nx = ((e.clientX - r.left) / r.width) * 2 - 1;"
    ++ "let ny = 1 - ((e.clientY - r.top) / r.height) * 2;"
    ++ "if (nx < -1) nx = -1; if (nx > 1) nx = 1; if (ny < -1) ny = -1; if (ny > 1) ny = 1;"
    ++ "yaw = nx * 2.6; pitch = 0.46 + ny * 0.48;}"
    ++ "window.addEventListener('pointermove', look);"
    ++ "window.addEventListener('pointerdown', function(e){ zoom = zoom ? 0 : 1; look(e); });"
    ++ "const img = ctx.createImageData(side, side);"
    ++ "let frames = 0; let t0 = performance.now();"
    ++ "async function loop(){for(;;){"
    ++ "let buf; try { const res = await fetch(path(), {cache:'no-store'}); buf = new Uint8Array(await res.arrayBuffer()); }"
    ++ "catch(e){ await new Promise(function(r){ setTimeout(r, 200); }); continue; }"
    ++ "if (buf.length !== side*side*3) continue;"
    ++ "const d = img.data; let j = 0;"
    ++ "for (let i = 0; i < buf.length; i += 3){ d[j++] = buf[i]; d[j++] = buf[i+1]; d[j++] = buf[i+2]; d[j++] = 255; }"
    ++ "ctx.putImageData(img, 0, 0); frames++;"
    ++ "const now = performance.now();"
    ++ "if (now - t0 >= 500){ const fps = (frames * 1000 / (now - t0)).toFixed(1);"
    ++ "hud.textContent = fps + ' fps  -  move the mouse to orbit, click to zoom ' + (zoom ? '(close)' : '(wide)');"
    ++ "frames = 0; t0 = now; } } }"
    ++ "loop();</script></body></html>"

def page_of(+side: U32) -> String:
  +body = html_body(side)
  text_header("text/html; charset=utf-8", String.length(body)) ++ body

def page(size: Size) -> String:
  match size:
    case Size{depth, side, f}:
      page_of(side)

# A sent socket is closed, then the accept loop continues.
def sent_then(
  sent: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>,
  listener: Listener, next: Listener -> IO(Unit)
) -> IO(Unit):
  match sent:
    case (sock, Done{v}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)
    case (sock, Fail{err}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)

def send_text(listener: Listener, sock: Socket, text: String, next: Listener -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, text)
    sent_then(sent, listener, next)

def send_rendered(
  depth: Nat, +side: U32, f: F32,
  listener: Listener, sock: Socket, view: View, next: Listener -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    body : List<&2, U32> = render(depth, side, f, cam_of(view))
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, with_header(frame_header(side), body))
    sent_then(sent, listener, next)

def send_frame(size: Size, listener: Listener, sock: Socket, view: View, next: Listener -> IO(Unit)) -> IO(Unit):
  match size:
    case Size{depth, +side, f}:
      send_rendered(depth, side, f, listener, sock, view, next)

def route(size: Size, path: String, listener: Listener, sock: Socket, next: Listener -> IO(Unit)) -> IO(Unit):
  match path:
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{48}, rest}}}:
      send_frame(size, listener, sock, view_of(48, rest), next)
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{49}, rest}}}:
      send_frame(size, listener, sock, view_of(49, rest), next)
    case SCon{Chr{47}, SCon{Chr{32}, _}}:
      send_text(listener, sock, page(size), next)
    case _:
      send_text(listener, sock, not_found(), next)

def got_req(
  size: Size, listener: Listener, got: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
  next: Listener -> IO(Unit)
) -> IO(Unit):
  match got:
    case (sock, Done{Some{text}}):
      route(size, String.drop(text, 4n), listener, sock, next)
    case (sock, Done{None{}}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)
    case (sock, Fail{err}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)

def read_one(size: Size, listener: Listener, sock: Socket, next: Listener -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(sock, 8192)
    got_req(size, listener, got, next)

def accepted(size: Size, got: Listener & Result<&1, &1, U32 & String, Socket>, next: Listener -> IO(Unit)) -> IO(Unit):
  match got:
    case (listener, Done{sock}):
      read_one(size, listener, sock, next)
    case (listener, Fail{err}):
      do IO<Unit>:
        IO.print("accept ended")
        Listener.close(listener)

def accept_one(size: Size, listener: Listener, next: Listener -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    accepted(size, got, next)

def serve(fuel: Nat, +size: Size, listener: Listener) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("stopping")
        Listener.close(listener)
    case 1n+left:
      accept_one(size, listener, l => serve(left, size, l))

def side_of(size: Size) -> U32:
  match size:
    case Size{depth, side, f}:
      side

def listen(+size: Size) -> IO(Unit):
  do IO<Unit>:
    IO.print("ray tracer at http://127.0.0.1:8080/  side " ++ U32.show(side_of(size)))
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", 8080))
    serve(4294967295n, size, listener)

def run(picked: Choice) -> IO(Unit):
  match picked:
    case Reject{}:
      do IO<Unit>:
        IO.print_err("side must be a power of two from 1 to 4096, for example 128")
        IO.exit(1)
    case Use{size}:
      listen(size)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(size_args(args))
