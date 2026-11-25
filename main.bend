# A small sphere scene, ray traced.
#
#   ~/.bend/bin/bend main.bend
#
# Writes scene.ppm (P6, side x side) in the current directory.
# The picture is a checker floor, three large spheres (clay, chrome,
# plastic) and two small ones, lit by a sun and a fill light.
# Reflections run for three hits; the next ray is the sky.

import Base

# 2^depth on a side. 7 is 128, 8 is 256.
def depth() -> Nat:
  9n

def side_u() -> U32:
  512

def side_f() -> F32:
  512.0

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

def cam_right(+fx: F32, +fy: F32, +fz: F32, right: Vec3) -> Cam:
  match right:
    case V3{+rx, +ry, +rz}:
      Cam{
        0.05, 1.35, 4.10,
        fx, fy, fz,
        rx, ry, rz,
        (ry * fz - rz * fy : F32),
        (rz * fx - rx * fz : F32),
        (rx * fy - ry * fx : F32),
        0.38
      }

def cam_fwd(fwd: Vec3) -> Cam:
  match fwd:
    case V3{+fx, +fy, +fz}:
      cam_right(fx, fy, fz, norm3(F32.neg(fz), 0.0, fx))

# eye (0.05, 1.35, 4.10), looking at (0, 0.35, 0). World up is +Y.
def camera() -> Cam:
  cam_fwd(norm3(F32.neg(0.05), F32.neg(1.0), F32.neg(4.10)))

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

def render() -> List<&2, U32>:
  List.reverse(&2, U32, flatten(block(depth(), 0, 0, side_u(), side_f(), camera()), Nil{}))

def ppm_header() -> String:
  "P6\n" ++ U32.show(side_u()) ++ " " ++ U32.show(side_u()) ++ "\n255\n"

def die_write(file: File, code: U32, msg: String) -> IO(File):
  do IO<File>:
    Unit <- File.close(file)
    IO.die(File, code, msg)

def unwrap_write(step: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  match step:
    case (file, Done{v}):
      IO.pure(File, file)
    case (file, Fail{(code, msg)}):
      die_write(file, code, msg)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    IO.print("tracing " ++ U32.show(side_u()) ++ "x" ++ U32.show(side_u()))
    body : List<&2, U32> = render()
    t1 : Nat <- IO.now()
    IO.print("traced in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    file : File <- IO.try(File, File.open("scene.ppm", "w"))
    w1 : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, ppm_header())
    file2 : File <- unwrap_write(w1)
    w2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file2, body)
    file3 : File <- unwrap_write(w2)
    File.close(file3)
    IO.print("wrote scene.ppm")
