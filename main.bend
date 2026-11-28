# A sphere scene and a tree, ray traced through a binary tree of spheres and served as a live page.
# The trunk and branches are conical frustums with bark. The leaves are flat,
# textured, and translucent. The sphere tree is built once. Every pixel, shadow,
# and reflection walks it.
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

# t is the ray distance. The normal faces the incoming ray. refl is 0..1.
# thru is 0 on an opaque surface. A leaf lets that fraction of the ray through.
type Hit is Data:
  Miss{}
  Hit{t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32, cr: F32, cg: F32, cb: F32, refl: F32, thru: F32}

# Bark or a leaf writes its shaded normal and colour through one of these.
type Tint is Data:
  Tint{nx: F32, ny: F32, nz: F32, cr: F32, cg: F32, cb: F32}

# A conical frustum from a to b, closed by discs. ra is the radius at a, rb at b.
type Cyl is Data:
  Cyl{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, ra: F32, rb: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# A two-sided triangle. The normal faces the incoming ray.
type Tri is Data:
  Tri{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, cx: F32, cy: F32, cz: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# Perpendicular parts of a ray against a cylinder axis. dv and ov are the axis dots.
# A binary tree of spheres. A tip holds one shape inside its bounding sphere.
# A fork's sphere covers both children. kind 1 on an orb is the checker floor.
type Shape is Data:
  Orb{cx: F32, cy: F32, cz: F32, rad: F32, cr: F32, cg: F32, cb: F32, refl: F32, kind: U32}
  Beam{cyl: Cyl}
  Blade{tri: Tri}

type Knot is Data:
  Tip{sx: F32, sy: F32, sz: F32, sr: F32, shape: Shape}
  Bin{sx: F32, sy: F32, sz: F32, sr: F32, a: Knot, b: Knot}

type Sphere is Data:
  Sphere{x: F32, y: F32, z: F32, r: F32}

type Perp is Data:
  Perp{dpx: F32, dpy: F32, dpz: F32, opx: F32, opy: F32, opz: F32, dv: F32, ov: F32}

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
  cr: F32, cg: F32, cb: F32, refl: F32, thru: F32, best: Hit
) -> Hit:
  match best:
    case Miss{}:
      Bool.pick(Hit, (t > 0.001 : F32), Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, thru}, Miss{})
    case Hit{+bt, bpx, bpy, bpz, bnx, bny, bnz, bcr, bcg, bcb, brefl, bthru}:
      Bool.pick(Hit,
        (t > 0.001 : F32) && (t < bt : F32),
        Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, thru},
        Hit{bt, bpx, bpy, bpz, bnx, bny, bnz, bcr, bcg, bcb, brefl, bthru})

def use_color(
  col: Vec3, t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32, refl: F32, best: Hit
) -> Hit:
  match col:
    case V3{cr, cg, cb}:
      keep_near(t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, 0.0, best)

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

# --- frustums and triangles -----------------------------------------------

def nearer(+a: F32, +b: F32) -> F32:
  pick_f((a < 0.0 : F32), b, pick_f((b < 0.0 : F32), a, pick_f((a < b : F32), a, b)))

def accept_axial(+t: F32, +along: F32, +h: F32) -> F32:
  pick_f(
    (t > 0.001 : F32) && (along > F32.neg(0.001) : F32) && (along < (h + 0.001) : F32),
    t, F32.neg(1.0))

def side_pair(+a: F32, +hb: F32, +sq: F32, +dv: F32, +ov: F32, +h: F32) -> F32:
  +inv = (1.0 / a : F32)
  +t0 = ((F32.neg(hb) - sq) * inv : F32)
  +t1 = ((F32.neg(hb) + sq) * inv : F32)
  nearer(
    accept_axial(t0, (ov + (t0 * dv) : F32), h),
    accept_axial(t1, (ov + (t1 * dv) : F32), h))

# bad skips the square root. The quadratic is A t^2 + 2 B t + C = 0.
def side_roots(+a: F32, +hb: F32, +disc: F32, +dv: F32, +ov: F32, +h: F32, bad: Bool) -> F32:
  match bad:
    case True{}:
      F32.neg(1.0)
    case False{}:
      side_pair(a, hb, F32.sqrt(disc), dv, ov, h)

def tiny(+d: F32) -> Bool:
  (d < 0.0001 : F32) && (d > F32.neg(0.0001) : F32)

# One root when the ray runs along the cone, so the t^2 term drops out.
def side_linear(+b: F32, +c: F32, +dv: F32, +ov: F32, +h: F32, flat: Bool) -> F32:
  match flat:
    case True{}:
      F32.neg(1.0)
    case False{}:
      +t = (F32.neg(c) / (b + b) : F32)
      accept_axial(t, (ov + (t * dv) : F32), h)

def side_choose(
  flat: Bool, +a: F32, +b: F32, +c: F32, +disc: F32, +dv: F32, +ov: F32, +h: F32
) -> F32:
  match flat:
    case True{}:
      side_linear(b, c, dv, ov, h, tiny(b))
    case False{}:
      side_roots(a, b, disc, dv, ov, h, (disc < 0.0 : F32))

def cyl_perp(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32, +vx: F32, +vy: F32, +vz: F32
) -> Perp:
  +ocx = (ox - ax : F32)
  +ocy = (oy - ay : F32)
  +ocz = (oz - az : F32)
  +dv = (dx * vx + dy * vy + dz * vz : F32)
  +ov = (ocx * vx + ocy * vy + ocz * vz : F32)
  Perp{
    (dx - (vx * dv) : F32), (dy - (vy * dv) : F32), (dz - (vz * dv) : F32),
    (ocx - (vx * ov) : F32), (ocy - (vy * ov) : F32), (ocz - (vz * ov) : F32),
    dv, ov
  }

def len3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

# Outward normal. k is dr/ds along the axis, so the normal leans with the taper.
def cone_normal(
  +rx: F32, +ry: F32, +rz: F32, +k: F32, +vx: F32, +vy: F32, +vz: F32
) -> Vec3:
  +rlen = len3(rx, ry, rz)
  +scale = pick_f((rlen < 0.00001 : F32), 1.0, rlen)
  norm3(
    ((rx / scale) - (k * vx) : F32),
    ((ry / scale) - (k * vy) : F32),
    ((rz / scale) - (k * vz) : F32))

# A vertical trunk would zero a cross with world up, so that case uses world X.
def bark_up(steep: Bool) -> Vec3:
  match steep:
    case True{}:
      V3{1.0, 0.0, 0.0}
    case False{}:
      V3{0.0, 1.0, 0.0}

def frame_tan(+vx: F32, +vy: F32, +vz: F32, up: Vec3) -> Vec3:
  match up:
    case V3{+ux, +uy, +uz}:
      norm3(
        (vy * uz - vz * uy : F32),
        (vz * ux - vx * uz : F32),
        (vx * uy - vy * ux : F32))

def frame_bit(+vx: F32, +vy: F32, +vz: F32, tan: Vec3) -> Vec3:
  match tan:
    case V3{+tx, +ty, +tz}:
      V3{
        (vy * tz - vz * ty : F32),
        (vz * tx - vx * tz : F32),
        (vx * ty - vy * tx : F32)
      }

def bark_ang(+rx: F32, +ry: F32, +rz: F32, tan: Vec3, bit: Vec3) -> F32:
  match tan bit:
    case V3{tx, ty, tz} V3{bx, by, bz}:
      F32.atan2(
        (rx * bx + ry * by + rz * bz : F32),
        (rx * tx + ry * ty + rz * tz : F32))

def sign_f(+s: F32) -> F32:
  pick_f((s > 0.0 : F32), 1.0, F32.neg(1.0))

def bark_tone(+plate: F32, +grain: F32) -> F32:
  (0.42 + plate * 0.78 + grain : F32)

# Cracks stay dark and a little redder. Plates are the light ridges. lent are the pores.
def bark_color(+cr: F32, +cg: F32, +cb: F32, +tone: F32, +plate: F32, +lent: F32) -> Vec3:
  V3{
    (cr * tone + (1.0 - plate) * 0.08 + lent * 0.50 : F32),
    (cg * tone + lent * 0.40 : F32),
    (cb * tone * (0.70 + plate * 0.30) + lent * 0.22 : F32)
  }

def bark_n(n: Vec3, bit: Vec3, axis: Vec3, +slope: F32, +rip: F32) -> Vec3:
  match n bit axis:
    case V3{nx, ny, nz} V3{bx, by, bz} V3{vx, vy, vz}:
      norm3(
        (nx + bx * slope + vx * rip : F32),
        (ny + by * slope + vy * rip : F32),
        (nz + bz * slope + vz * rip : F32))

def tint_of(n: Vec3, c: Vec3) -> Tint:
  match n c:
    case V3{nx, ny, nz} V3{cr, cg, cb}:
      Tint{nx, ny, nz, cr, cg, cb}

# Six furrows around the limb, wandering along it. The groove is the dark half of the wave.
def bark_finish(
  +ang: F32, +along: F32,
  +cr: F32, +cg: F32, +cb: F32,
  n: Vec3, bit: Vec3, axis: Vec3
) -> Tint:
  +phase = (ang * 6.0 + F32.sin((along * 3.4 : F32)) * 1.3 : F32)
  +s = F32.sin(phase)
  +plate = F32.abs(s)
  +slope = (F32.cos(phase) * sign_f(s) * 0.42 : F32)
  +rip = (F32.cos((along * 52.0 + ang * 2.0 : F32)) * 0.08 : F32)
  +grain = (F32.cos((along * 40.0 : F32)) * 0.15 : F32)
  +lent = max0((F32.sin((ang * 14.0 : F32)) * F32.sin((along * 19.0 : F32)) - 0.62 : F32))
  tint_of(
    bark_n(n, bit, axis, slope, rip),
    bark_color(cr, cg, cb, bark_tone(plate, grain), plate, lent))

def bark_shade(
  +rx: F32, +ry: F32, +rz: F32, +along: F32,
  +vx: F32, +vy: F32, +vz: F32,
  +cr: F32, +cg: F32, +cb: F32,
  n: Vec3, +tan: Vec3
) -> Tint:
  +bit = frame_bit(vx, vy, vz, tan)
  bark_finish(
    bark_ang(rx, ry, rz, tan, bit), along, cr, cg, cb, n, bit, V3{vx, vy, vz})

def bark_tint(
  +rx: F32, +ry: F32, +rz: F32, +along: F32,
  +k: F32, +vx: F32, +vy: F32, +vz: F32,
  +cr: F32, +cg: F32, +cb: F32
) -> Tint:
  bark_shade(
    rx, ry, rz, along, vx, vy, vz, cr, cg, cb,
    cone_normal(rx, ry, rz, k, vx, vy, vz),
    frame_tan(vx, vy, vz, bark_up((F32.abs(vy) > 0.85 : F32))))

def bark_commit(
  +t: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  tint: Tint, refl: F32, best: Hit
) -> Hit:
  match tint:
    case Tint{nx, ny, nz, cr, cg, cb}:
      keep_near(
        t, (ox + (dx * t) : F32), (oy + (dy * t) : F32), (oz + (dz * t) : F32),
        nx, ny, nz, cr, cg, cb, refl, 0.0, best)

def cone_commit(
  +t: F32, +dpx: F32, +dpy: F32, +dpz: F32, +opx: F32, +opy: F32, +opz: F32,
  +k: F32, +vx: F32, +vy: F32, +vz: F32, +dv: F32, +ov: F32,
  cr: F32, cg: F32, cb: F32, refl: F32,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit
) -> Hit:
  bark_commit(
    t, ox, oy, oz, dx, dy, dz,
    bark_tint(
      (opx + (t * dpx) : F32),
      (opy + (t * dpy) : F32),
      (opz + (t * dpz) : F32),
      (ov + (t * dv) : F32),
      k, vx, vy, vz, cr, cg, cb),
    refl, best)

# Radius along the axis is ra + k * s. k is (rb - ra) / length.
def hit_side_from(
  p: Perp, +h: F32, +ra: F32, +k: F32, +vx: F32, +vy: F32, +vz: F32,
  cr: F32, cg: F32, cb: F32, refl: F32,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit
) -> Hit:
  match p:
    case Perp{+dpx, +dpy, +dpz, +opx, +opy, +opz, +dv, +ov}:
      +ap = (dpx * dpx + dpy * dpy + dpz * dpz : F32)
      +hb = (dpx * opx + dpy * opy + dpz * opz : F32)
      +cp = (opx * opx + opy * opy + opz * opz : F32)
      +m = (ra + (k * ov) : F32)
      +n = (k * dv : F32)
      +a = (ap - (n * n) : F32)
      +b = (hb - (m * n) : F32)
      +c = (cp - (m * m) : F32)
      +disc = (b * b - (a * c) : F32)
      cone_commit(
        side_choose(tiny(a), a, b, c, disc, dv, ov, h),
        dpx, dpy, dpz, opx, opy, opz, k, vx, vy, vz, dv, ov,
        cr, cg, cb, refl, ox, oy, oz, dx, dy, dz, best)

def hit_side(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32, +vx: F32, +vy: F32, +vz: F32,
  +h: F32, +ra: F32, +k: F32, cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  hit_side_from(
    cyl_perp(ox, oy, oz, dx, dy, dz, ax, ay, az, vx, vy, vz),
    h, ra, k, vx, vy, vz, cr, cg, cb, refl, ox, oy, oz, dx, dy, dz, best)

def div_or(+numer: F32, +denom: F32, skip: Bool) -> F32:
  match skip:
    case True{}:
      F32.neg(1.0)
    case False{}:
      (numer / denom : F32)

def cap_keep(+t: F32, +dd: F32, +r2: F32) -> F32:
  pick_f((t > 0.001 : F32) && (dd <= r2 : F32), t, F32.neg(1.0))

def cap_t(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +cx: F32, +cy: F32, +cz: F32, +nx: F32, +ny: F32, +nz: F32, +rad: F32
) -> F32:
  +denom = (dx * nx + dy * ny + dz * nz : F32)
  +numer = ((cx - ox) * nx + (cy - oy) * ny + (cz - oz) * nz : F32)
  +t = div_or(numer, denom, tiny(denom))
  +px = (ox + (dx * t) : F32)
  +py = (oy + (dy * t) : F32)
  +pz = (oz + (dz * t) : F32)
  cap_keep(
    t,
    ((px - cx) * (px - cx) + (py - cy) * (py - cy) + (pz - cz) * (pz - cz) : F32),
    (rad * rad : F32))

def cap_commit(
  +t: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  nx: F32, ny: F32, nz: F32, cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  keep_near(
    t, (ox + (dx * t) : F32), (oy + (dy * t) : F32), (oz + (dz * t) : F32),
    nx, ny, nz, cr, cg, cb, refl, 0.0, best)

def hit_cap(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +cx: F32, +cy: F32, +cz: F32, +nx: F32, +ny: F32, +nz: F32, +rad: F32,
  cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  cap_commit(
    cap_t(ox, oy, oz, dx, dy, dz, cx, cy, cz, nx, ny, nz, rad),
    ox, oy, oz, dx, dy, dz, nx, ny, nz, cr, cg, cb, refl, best)

def hit_cyl_axis(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32,
  +ra: F32, +rb: F32, +k: F32, +h: F32, axis: Vec3,
  +cr: F32, +cg: F32, +cb: F32, +refl: F32, best: Hit
) -> Hit:
  match axis:
    case V3{+vx, +vy, +vz}:
      hit_cap(
        ox, oy, oz, dx, dy, dz, ax, ay, az, F32.neg(vx), F32.neg(vy), F32.neg(vz), ra,
        cr, cg, cb, refl,
        hit_cap(
          ox, oy, oz, dx, dy, dz, bx, by, bz, vx, vy, vz, rb, cr, cg, cb, refl,
          hit_side(
            ox, oy, oz, dx, dy, dz, ax, ay, az, vx, vy, vz, h, ra, k,
            cr, cg, cb, refl, best)))

def hit_cyl_len(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32,
  +ra: F32, +rb: F32, cr: F32, cg: F32, cb: F32, refl: F32, +h: F32, best: Hit
) -> Hit:
  hit_cyl_axis(
    ox, oy, oz, dx, dy, dz, ax, ay, az, bx, by, bz, ra, rb,
    ((rb - ra) / h : F32), h,
    norm3((bx - ax : F32), (by - ay : F32), (bz - az : F32)),
    cr, cg, cb, refl, best)

def hit_cyl(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, cyl: Cyl, best: Hit
) -> Hit:
  match cyl:
    case Cyl{+ax, +ay, +az, +bx, +by, +bz, +ra, +rb, cr, cg, cb, refl}:
      hit_cyl_len(
        ox, oy, oz, dx, dy, dz, ax, ay, az, bx, by, bz, ra, rb, cr, cg, cb, refl,
        len3((bx - ax : F32), (by - ay : F32), (bz - az : F32)), best)

def cross3(+ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32) -> Vec3:
  V3{
    (ay * bz - az * by : F32),
    (az * bx - ax * bz : F32),
    (ax * by - ay * bx : F32)
  }

def dot3(+ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32) -> F32:
  (ax * bx + ay * by + az * bz : F32)

def tri_parallel(+det: F32) -> Bool:
  (det < 0.00001 : F32) && (det > F32.neg(0.00001) : F32)

def tri_ok(+t: F32, +u: F32, +v: F32) -> F32:
  pick_f(
    (t > 0.001 : F32) && (u >= 0.0 : F32) && (v >= 0.0 : F32) && ((u + v) <= 1.0 : F32),
    t, F32.neg(1.0))

def face_pick(back: Bool, +nx: F32, +ny: F32, +nz: F32) -> Vec3:
  match back:
    case True{}:
      V3{F32.neg(nx), F32.neg(ny), F32.neg(nz)}
    case False{}:
      V3{nx, ny, nz}

def face_vec(+nx: F32, +ny: F32, +nz: F32, +dx: F32, +dy: F32, +dz: F32) -> Vec3:
  face_pick((dot3(nx, ny, nz, dx, dy, dz) > 0.0 : F32), nx, ny, nz)

def unit_face(v: Vec3) -> Vec3:
  match v:
    case V3{x, y, z}:
      norm3(x, y, z)

# Half the light goes through a leaf. The blade still reads, and the sky behind it greens.
def leaf_thru() -> F32:
  0.5

# across is 0 on the midrib (u = v) and about 1 at either edge. A tiny span is the stem.
def span_across(+u: F32, +v: F32, skip: Bool) -> F32:
  match skip:
    case True{}:
      0.0
    case False{}:
      ((u - v) / (u + v) : F32)

def leaf_color(
  +u: F32, +v: F32, +px: F32, +py: F32, +pz: F32, +cr: F32, +cg: F32, +cb: F32
) -> Vec3:
  +span = (u + v : F32)
  +w = (1.0 - span : F32)
  +across = span_across(u, v, (span < 0.04 : F32))
  +rib = max0((0.22 - F32.abs(across) : F32))
  +mix = F32.clamp((rib * 5.0 : F32), 0.0, 1.0)
  +edge = F32.min(u, F32.min(v, max0(w)))
  +rim = max0((0.12 - edge : F32))
  +shade = (1.0 - F32.min((rim * 5.0 : F32), 0.72) : F32)
  +mottle = (F32.sin((px * 17.0 + py * 9.0 + pz * 13.0 : F32)) * 0.12 + w * 0.08 : F32)
  +gain = (shade * (1.0 + mottle) : F32)
  +kr = ((1.0 - mix) * cr + mix * 0.72 : F32)
  +kg = ((1.0 - mix) * cg + mix * 0.78 : F32)
  +kb = ((1.0 - mix) * cb + mix * 0.28 : F32)
  V3{(kr * gain : F32), (kg * gain : F32), (kb * gain : F32)}

def leaf_hit(
  col: Vec3, t: F32, px: F32, py: F32, pz: F32, nx: F32, ny: F32, nz: F32, refl: F32, best: Hit
) -> Hit:
  match col:
    case V3{cr, cg, cb}:
      keep_near(t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, leaf_thru(), best)

def tri_shade_f(
  +t: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +u: F32, +v: F32, n: Vec3, +cr: F32, +cg: F32, +cb: F32, refl: F32, best: Hit
) -> Hit:
  match n:
    case V3{nx, ny, nz}:
      +px = (ox + (dx * t) : F32)
      +py = (oy + (dy * t) : F32)
      +pz = (oz + (dz * t) : F32)
      leaf_hit(leaf_color(u, v, px, py, pz, cr, cg, cb), t, px, py, pz, nx, ny, nz, refl, best)

def tri_shade(
  +t: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +u: F32, +v: F32, raw: Vec3, cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match raw:
    case V3{+nx, +ny, +nz}:
      tri_shade_f(
        t, ox, oy, oz, dx, dy, dz, u, v,
        unit_face(face_vec(nx, ny, nz, dx, dy, dz)), cr, cg, cb, refl, best)

def tri_q(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +e1x: F32, +e1y: F32, +e1z: F32, +e2x: F32, +e2y: F32, +e2z: F32,
  +u: F32, +inv: F32, qvec: Vec3, cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match qvec:
    case V3{+qx, +qy, +qz}:
      +v = (dot3(dx, dy, dz, qx, qy, qz) * inv : F32)
      +t = (dot3(e2x, e2y, e2z, qx, qy, qz) * inv : F32)
      tri_shade(
        tri_ok(t, u, v), ox, oy, oz, dx, dy, dz, u, v,
        cross3(e1x, e1y, e1z, e2x, e2y, e2z), cr, cg, cb, refl, best)

def tri_solve(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +e1x: F32, +e1y: F32, +e1z: F32, +e2x: F32, +e2y: F32, +e2z: F32,
  +px: F32, +py: F32, +pz: F32, +inv: F32,
  cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  +tvx = (ox - ax : F32)
  +tvy = (oy - ay : F32)
  +tvz = (oz - az : F32)
  +u = (dot3(tvx, tvy, tvz, px, py, pz) * inv : F32)
  tri_q(
    ox, oy, oz, dx, dy, dz, e1x, e1y, e1z, e2x, e2y, e2z, u, inv,
    cross3(tvx, tvy, tvz, e1x, e1y, e1z), cr, cg, cb, refl, best)

def hit_tri_det(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +e1x: F32, +e1y: F32, +e1z: F32, +e2x: F32, +e2y: F32, +e2z: F32,
  +px: F32, +py: F32, +pz: F32, +det: F32, parallel: Bool,
  cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match parallel:
    case True{}:
      best
    case False{}:
      tri_solve(
        ox, oy, oz, dx, dy, dz, ax, ay, az, e1x, e1y, e1z, e2x, e2y, e2z,
        px, py, pz, (1.0 / det : F32), cr, cg, cb, refl, best)

def hit_tri_p(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +e1x: F32, +e1y: F32, +e1z: F32, +e2x: F32, +e2y: F32, +e2z: F32,
  pvec: Vec3, cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match pvec:
    case V3{+px, +py, +pz}:
      +det = dot3(e1x, e1y, e1z, px, py, pz)
      hit_tri_det(
        ox, oy, oz, dx, dy, dz, ax, ay, az, e1x, e1y, e1z, e2x, e2y, e2z,
        px, py, pz, det, tri_parallel(det), cr, cg, cb, refl, best)

def hit_tri_e(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +ax: F32, +ay: F32, +az: F32, e1: Vec3, e2: Vec3,
  cr: F32, cg: F32, cb: F32, refl: F32, best: Hit
) -> Hit:
  match e1 e2:
    case V3{+e1x, +e1y, +e1z} V3{+e2x, +e2y, +e2z}:
      hit_tri_p(
        ox, oy, oz, dx, dy, dz, ax, ay, az, e1x, e1y, e1z, e2x, e2y, e2z,
        cross3(dx, dy, dz, e2x, e2y, e2z), cr, cg, cb, refl, best)

def hit_tri(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, tri: Tri, best: Hit
) -> Hit:
  match tri:
    case Tri{+ax, +ay, +az, +bx, +by, +bz, +cx, +cy, +cz, cr, cg, cb, refl}:
      hit_tri_e(
        ox, oy, oz, dx, dy, dz, ax, ay, az,
        V3{(bx - ax : F32), (by - ay : F32), (bz - az : F32)},
        V3{(cx - ax : F32), (cy - ay : F32), (cz - az : F32)},
        cr, cg, cb, refl, best)

# --- binary tree of spheres ----------------------------------------------
# Each node is a sphere. A tip stores one shape, and that sphere is the shape's
# bound. A fork's sphere covers both children. Missing a sphere skips that side.

def wider(+a: F32, +b: F32) -> F32:
  pick_f((a > b : F32), a, b)

def contained(+dist: F32, +outer: F32, +inner: F32) -> Bool:
  ((dist + inner) <= outer : F32)

# Pad the merged radius a little so a rounding error cannot hide a child.
def merge_grow(
  flat: Bool,
  +ax: F32, +ay: F32, +az: F32, +ar: F32,
  +bx: F32, +by: F32, +bz: F32, +br: F32,
  +dist: F32
) -> Sphere:
  match flat:
    case True{}:
      Sphere{ax, ay, az, (wider(ar, br) + 0.01 : F32)}
    case False{}:
      +rad = (((dist + ar + br) / 2.0) + 0.01 : F32)
      +t = ((rad - ar) / dist : F32)
      Sphere{
        (ax + (bx - ax) * t : F32),
        (ay + (by - ay) * t : F32),
        (az + (bz - az) * t : F32),
        rad
      }

def merge_which(
  a_holds: Bool, b_holds: Bool,
  +ax: F32, +ay: F32, +az: F32, +ar: F32,
  +bx: F32, +by: F32, +bz: F32, +br: F32,
  +dist: F32
) -> Sphere:
  match a_holds b_holds:
    case True{} _:
      Sphere{ax, ay, az, (ar + 0.01 : F32)}
    case False{} True{}:
      Sphere{bx, by, bz, (br + 0.01 : F32)}
    case False{} False{}:
      merge_grow(tiny(dist), ax, ay, az, ar, bx, by, bz, br, dist)

def merge_sph(
  +ax: F32, +ay: F32, +az: F32, +ar: F32,
  +bx: F32, +by: F32, +bz: F32, +br: F32
) -> Sphere:
  +dist = len3((bx - ax : F32), (by - ay : F32), (bz - az : F32))
  merge_which(
    contained(dist, ar, br), contained(dist, br, ar),
    ax, ay, az, ar, bx, by, bz, br, dist)

def opened(node: Knot) -> Sphere & Knot:
  match node:
    case Tip{+sx, +sy, +sz, +sr, shape}:
      (Sphere{sx, sy, sz, sr}, Tip{sx, sy, sz, sr, shape})
    case Bin{+sx, +sy, +sz, +sr, a, b}:
      (Sphere{sx, sy, sz, sr}, Bin{sx, sy, sz, sr, a, b})

def place(s: Sphere, a: Knot, b: Knot) -> Knot:
  match s:
    case Sphere{x, y, z, r}:
      Bin{x, y, z, r, a, b}

def join_sph(sa: Sphere, sb: Sphere, a: Knot, b: Knot) -> Knot:
  match sa sb:
    case Sphere{ax, ay, az, ar} Sphere{bx, by, bz, br}:
      place(merge_sph(ax, ay, az, ar, bx, by, bz, br), a, b)

def join_b(sa: Sphere, a: Knot, gb: Sphere & Knot) -> Knot:
  match gb:
    case (sb, b):
      join_sph(sa, sb, a, b)

def join_ab(ga: Sphere & Knot, gb: Sphere & Knot) -> Knot:
  match ga:
    case (sa, a):
      join_b(sa, a, gb)

def join(a: Knot, b: Knot) -> Knot:
  join_ab(opened(a), opened(b))

def pair_acc(xs: List<&2, Knot>, acc: List<&2, Knot>) -> List<&2, Knot>:
  match xs:
    case Nil{}:
      List.reverse(&2, Knot, acc)
    case a <> Nil{}:
      List.reverse(&2, Knot, a <> acc)
    case a <> (b <> rest):
      pair_acc(rest, join(a, b) <> acc)

def spare_tip() -> Knot:
  Tip{0.0, F32.neg(100.0), 0.0, 0.0, Orb{0.0, F32.neg(100.0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0}}

def first_knot(keep: Knot, xs: List<&2, Knot>) -> Knot:
  match xs:
    case Nil{}:
      keep
    case _ <> t:
      first_knot(keep, t)

def first_or_spare(xs: List<&2, Knot>) -> Knot:
  match xs:
    case Nil{}:
      spare_tip()
    case h <> t:
      first_knot(h, t)

# Fuel counts pairing rounds. A singleton list stays a singleton until fuel ends.
def fold_tree(fuel: Nat, xs: List<&2, Knot>) -> Knot:
  match fuel:
    case 0n:
      first_or_spare(xs)
    case 1n+p:
      fold_tree(p, pair_acc(xs, Nil{}))

def orb_tip(
  +cx: F32, +cy: F32, +cz: F32, +rad: F32,
  cr: F32, cg: F32, cb: F32, refl: F32, kind: U32
) -> Knot:
  Tip{cx, cy, cz, rad, Orb{cx, cy, cz, rad, cr, cg, cb, refl, kind}}

def beam_tip(cyl: Cyl) -> Knot:
  match cyl:
    case Cyl{+ax, +ay, +az, +bx, +by, +bz, +ra, +rb, cr, cg, cb, refl}:
      +mx = (((ax + bx : F32) * 0.5) : F32)
      +my = (((ay + by : F32) * 0.5) : F32)
      +mz = (((az + bz : F32) * 0.5) : F32)
      +half = (len3((bx - ax : F32), (by - ay : F32), (bz - az : F32)) * 0.5 : F32)
      +rad = ((half + wider(ra, rb) : F32) + 0.01 : F32)
      Tip{mx, my, mz, rad, Beam{Cyl{ax, ay, az, bx, by, bz, ra, rb, cr, cg, cb, refl}}}

def far3(+a: F32, +b: F32, +c: F32) -> F32:
  wider(a, wider(b, c))

def blade_tip(tri: Tri) -> Knot:
  match tri:
    case Tri{+ax, +ay, +az, +bx, +by, +bz, +cx, +cy, +cz, cr, cg, cb, refl}:
      +mx = ((((ax + bx : F32) + cx : F32) / 3.0) : F32)
      +my = ((((ay + by : F32) + cy : F32) / 3.0) : F32)
      +mz = ((((az + bz : F32) + cz : F32) / 3.0) : F32)
      +rad = (far3(
        len3((ax - mx : F32), (ay - my : F32), (az - mz : F32)),
        len3((bx - mx : F32), (by - my : F32), (bz - mz : F32)),
        len3((cx - mx : F32), (cy - my : F32), (cz - mz : F32))) + 0.01 : F32)
      Tip{mx, my, mz, rad, Blade{Tri{ax, ay, az, bx, by, bz, cx, cy, cz, cr, cg, cb, refl}}}

def beams_of(cs: List<&2, Cyl>) -> List<&2, Knot>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> rest:
      beam_tip(c) <> beams_of(rest)

def blades_of(ts: List<&2, Tri>) -> List<&2, Knot>:
  match ts:
    case Nil{}:
      Nil{}
    case tri <> rest:
      blade_tip(tri) <> blades_of(rest)

def sphere_row() -> List<&2, Knot>:
  orb_tip(F32.neg(1.05), 0.50, 0.15, 0.50, 0.86, 0.16, 0.12, 0.05, 0)
    <> (orb_tip(0.15, 0.50, F32.neg(0.35), 0.50, 0.93, 0.93, 0.95, 0.90, 0)
    <> (orb_tip(1.25, 0.50, 0.25, 0.50, 0.16, 0.32, 0.86, 0.22, 0)
    <> (orb_tip(F32.neg(0.35), 0.22, 1.05, 0.22, 0.96, 0.66, 0.16, 0.38, 0)
    <> (orb_tip(0.85, 0.18, 1.20, 0.18, 0.22, 0.72, 0.32, 0.12, 0)
    <> Nil{}))))

# The floor is a sphere of radius 100 whose top is the plane y = 0.
def ground_tip() -> Knot:
  orb_tip(0.0, F32.neg(100.0), 0.0, 100.0, 0.0, 0.0, 0.0, 0.18, 1)

def hit_shape(
  shape: Shape, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit
) -> Hit:
  match shape:
    case Orb{cx, cy, cz, rad, cr, cg, cb, refl, kind}:
      hit_sph(ox, oy, oz, dx, dy, dz, cx, cy, cz, rad, cr, cg, cb, refl, kind, best)
    case Beam{cyl}:
      hit_cyl(ox, oy, oz, dx, dy, dz, cyl, best)
    case Blade{tri}:
      hit_tri(ox, oy, oz, dx, dy, dz, tri, best)

def touches(+node: Knot, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  match node:
    case Tip{+sx, +sy, +sz, +sr, +shape}:
      sph_blocks(ox, oy, oz, dx, dy, dz, sx, sy, sz, sr)
    case Bin{+sx, +sy, +sz, +sr, +a, +b}:
      sph_blocks(ox, oy, oz, dx, dy, dz, sx, sy, sz, sr)

# go is the sphere test for this node. The node itself is the shrinking argument.
def walk(
  node: Knot, go: Bool, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, best: Hit
) -> Hit:
  match node go:
    case _ False{}:
      best
    case Tip{+sx, +sy, +sz, +sr, shape} True{}:
      hit_shape(shape, ox, oy, oz, dx, dy, dz, best)
    case Bin{+sx, +sy, +sz, +sr, +a, +b} True{}:
      walk(
        a, touches(a, ox, oy, oz, dx, dy, dz), ox, oy, oz, dx, dy, dz,
        walk(b, touches(b, ox, oy, oz, dx, dy, dz), ox, oy, oz, dx, dy, dz, best))

def closest(+tree: Knot, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Hit:
  walk(tree, touches(tree, ox, oy, oz, dx, dy, dz), ox, oy, oz, dx, dy, dz, Miss{})

def branches() -> List<&2, Cyl>:
  Cyl{F32.neg(1.90), F32.neg(0.02), F32.neg(1.25), F32.neg(1.90), 0.46, F32.neg(1.25), 0.155, 0.112, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.90), 0.46, F32.neg(1.25), F32.neg(1.90), 0.92, F32.neg(1.25), 0.112, 0.070, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.90), 0.92, F32.neg(1.25), F32.neg(1.90), 1.36, F32.neg(1.25), 0.070, 0.038, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.87), 0.36, F32.neg(1.13), F32.neg(1.80), 0.68, F32.neg(0.76), 0.056, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.80), 0.68, F32.neg(0.76), F32.neg(1.92), 0.84, F32.neg(0.53), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.80), 0.68, F32.neg(0.76), F32.neg(1.55), 0.92, F32.neg(0.57), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.80), 0.48, F32.neg(1.20), F32.neg(1.41), 0.86, F32.neg(0.99), 0.051, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.41), 0.86, F32.neg(0.99), F32.neg(1.28), 1.02, F32.neg(0.76), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.41), 0.86, F32.neg(0.99), F32.neg(1.08), 1.10, F32.neg(1.03), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.81), 0.56, F32.neg(1.30), F32.neg(1.39), 0.90, F32.neg(1.52), 0.047, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.39), 0.90, F32.neg(1.52), F32.neg(1.09), 1.06, F32.neg(1.49), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.39), 0.90, F32.neg(1.52), F32.neg(1.24), 1.14, F32.neg(1.78), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.88), 0.64, F32.neg(1.34), F32.neg(1.78), 1.06, F32.neg(1.80), 0.044, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.78), 1.06, F32.neg(1.80), F32.neg(1.56), 1.22, F32.neg(1.97), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.78), 1.06, F32.neg(1.80), F32.neg(1.92), 1.30, F32.neg(2.06), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.95), 0.74, F32.neg(1.32), F32.neg(2.19), 1.10, F32.neg(1.68), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.19), 1.10, F32.neg(1.68), F32.neg(2.18), 1.26, F32.neg(1.94), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.19), 1.10, F32.neg(1.68), F32.neg(2.51), 1.34, F32.neg(1.78), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.98), 0.82, F32.neg(1.26), F32.neg(2.40), 1.22, F32.neg(1.32), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.40), 1.22, F32.neg(1.32), F32.neg(2.61), 1.38, F32.neg(1.50), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.40), 1.22, F32.neg(1.32), F32.neg(2.70), 1.46, F32.neg(1.19), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.95), 0.92, F32.neg(1.20), F32.neg(2.24), 1.36, F32.neg(0.94), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.24), 1.36, F32.neg(0.94), F32.neg(2.54), 1.52, F32.neg(0.91), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.24), 1.36, F32.neg(0.94), F32.neg(2.32), 1.60, F32.neg(0.66), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.87), 1.04, F32.neg(1.20), F32.neg(1.73), 1.50, F32.neg(0.93), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.73), 1.50, F32.neg(0.93), F32.neg(1.77), 1.66, F32.neg(0.68), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.73), 1.50, F32.neg(0.93), F32.neg(1.43), 1.74, F32.neg(0.80), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Nil{})))))))))))))))))))))))))))

def leaves() -> List<&2, Tri>:
  Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.94), 0.91, F32.neg(0.63), F32.neg(1.96), 1.04, F32.neg(0.43), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.90), 0.81, F32.neg(0.40), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(2.04), 0.86, F32.neg(0.57), F32.neg(1.96), 1.04, F32.neg(0.43), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.80), 0.87, F32.neg(0.46), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(2.02), 0.81, F32.neg(0.45), F32.neg(1.96), 1.04, F32.neg(0.43), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.82), 0.92, F32.neg(0.58), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.50), 0.89, F32.neg(0.44), F32.neg(1.46), 1.12, F32.neg(0.50), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.57), 1.00, F32.neg(0.67), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.42), 0.89, F32.neg(0.54), F32.neg(1.46), 1.12, F32.neg(0.50), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.65), 1.00, F32.neg(0.57), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.45), 0.94, F32.neg(0.66), F32.neg(1.46), 1.12, F32.neg(0.50), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.62), 0.95, F32.neg(0.46), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.80), 0.62, F32.neg(0.96), F32.neg(1.81), 0.72, F32.neg(0.81), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.81), 0.72, F32.neg(0.81), F32.neg(1.84), 0.54, F32.neg(0.78), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.92), 0.60, F32.neg(0.89), F32.neg(1.81), 0.72, F32.neg(0.81), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.81), 0.72, F32.neg(0.81), F32.neg(1.72), 0.57, F32.neg(0.86), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.40), 1.06, F32.neg(0.71), F32.neg(1.23), 1.22, F32.neg(0.67), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.15), 1.03, F32.neg(0.80), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.30), 1.00, F32.neg(0.63), F32.neg(1.23), 1.22, F32.neg(0.67), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.24), 1.09, F32.neg(0.87), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.18), 0.99, F32.neg(0.68), F32.neg(1.23), 1.22, F32.neg(0.67), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.36), 1.10, F32.neg(0.82), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.06, F32.neg(1.07), F32.neg(0.96), 1.30, F32.neg(1.04), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(1.17), 1.19, F32.neg(0.99), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(1.04), 1.11, F32.neg(1.16), F32.neg(0.96), 1.30, F32.neg(1.04), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(1.08), 1.15, F32.neg(0.90), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(1.15), 1.17, F32.neg(1.12), F32.neg(0.96), 1.30, F32.neg(1.04), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(0.98), 1.08, F32.neg(0.95), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.70, F32.neg(0.98), F32.neg(1.47), 0.88, F32.neg(1.02), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.88, F32.neg(1.02), F32.neg(1.59), 0.79, F32.neg(1.12), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.46), 0.73, F32.neg(1.12), F32.neg(1.47), 0.88, F32.neg(1.02), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.88, F32.neg(1.02), F32.neg(1.60), 0.76, F32.neg(0.99), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(1.02), 1.05, F32.neg(1.37), F32.neg(0.97), 1.26, F32.neg(1.48), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.13), 1.12, F32.neg(1.60), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.96), 1.02, F32.neg(1.48), F32.neg(0.97), 1.26, F32.neg(1.48), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.19), 1.15, F32.neg(1.49), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(1.01), 1.06, F32.neg(1.60), F32.neg(0.97), 1.26, F32.neg(1.48), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.14), 1.11, F32.neg(1.38), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.30), 1.14, F32.neg(1.90), F32.neg(1.18), 1.35, F32.neg(1.87), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.16), 1.20, F32.neg(1.68), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.36), 1.20, F32.neg(1.80), F32.neg(1.18), 1.35, F32.neg(1.87), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.10), 1.14, F32.neg(1.78), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.29), 1.23, F32.neg(1.69), F32.neg(1.18), 1.35, F32.neg(1.87), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.17), 1.11, F32.neg(1.89), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.50), 0.76, F32.neg(1.55), F32.neg(1.45), 0.93, F32.neg(1.49), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.45), 0.93, F32.neg(1.49), F32.neg(1.53), 0.83, F32.neg(1.36), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.60), 0.83, F32.neg(1.48), F32.neg(1.45), 0.93, F32.neg(1.49), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.45), 0.93, F32.neg(1.49), F32.neg(1.43), 0.76, F32.neg(1.43), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.45), 1.18, F32.neg(2.03), F32.neg(1.47), 1.42, F32.neg(2.04), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.65), 1.31, F32.neg(1.93), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.55), 1.20, F32.neg(2.10), F32.neg(1.47), 1.42, F32.neg(2.04), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.55), 1.28, F32.neg(1.86), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.66), 1.27, F32.neg(2.05), F32.neg(1.47), 1.42, F32.neg(2.04), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.44), 1.22, F32.neg(1.91), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(2.02), 1.34, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(1.83), 1.31, F32.neg(2.16), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.90), 1.38, F32.neg(1.96), F32.neg(1.97), 1.51, F32.neg(2.15), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(1.95), 1.27, F32.neg(2.19), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.81), 1.37, F32.neg(2.04), F32.neg(1.97), 1.51, F32.neg(2.15), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(2.04), 1.29, F32.neg(2.11), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.91), 0.95, F32.neg(1.64), F32.neg(1.80), 1.07, F32.neg(1.73), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.80), 1.07, F32.neg(1.73), F32.neg(1.72), 0.91, F32.neg(1.68), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.79), 0.97, F32.neg(1.57), F32.neg(1.80), 1.07, F32.neg(1.73), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.80), 1.07, F32.neg(1.73), F32.neg(1.84), 0.89, F32.neg(1.75), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.26), 1.24, F32.neg(2.05), F32.neg(2.18), 1.46, F32.neg(2.04), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.11), 1.33, F32.neg(1.85), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.31), 1.29, F32.neg(1.94), F32.neg(2.18), 1.46, F32.neg(2.04), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.05), 1.28, F32.neg(1.96), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.24), 1.34, F32.neg(1.84), F32.neg(2.18), 1.46, F32.neg(2.04), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.13), 1.23, F32.neg(2.05), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.45), 1.42, F32.neg(1.70), F32.neg(2.62), 1.54, F32.neg(1.82), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.60), 1.31, F32.neg(1.88), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.41), 1.42, F32.neg(1.82), F32.neg(2.62), 1.54, F32.neg(1.82), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.64), 1.31, F32.neg(1.75), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.49), 1.37, F32.neg(1.91), F32.neg(2.62), 1.54, F32.neg(1.82), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.56), 1.37, F32.neg(1.66), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.06), 1.04, F32.neg(1.50), F32.neg(2.16), 1.13, F32.neg(1.63), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.16), 1.13, F32.neg(1.63), F32.neg(2.18), 0.95, F32.neg(1.64), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.04), 0.99, F32.neg(1.64), F32.neg(2.16), 1.13, F32.neg(1.63), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.16), 1.13, F32.neg(1.63), F32.neg(2.20), 1.00, F32.neg(1.51), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.72), 1.40, F32.neg(1.41), F32.neg(2.70), 1.58, F32.neg(1.56), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.53), 1.41, F32.neg(1.59), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.60), 1.45, F32.neg(1.39), F32.neg(2.70), 1.58, F32.neg(1.56), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.64), 1.35, F32.neg(1.62), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.51), 1.46, F32.neg(1.48), F32.neg(2.70), 1.58, F32.neg(1.56), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.74), 1.35, F32.neg(1.53), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.63), 1.55, F32.neg(1.26), F32.neg(2.80), 1.66, F32.neg(1.14), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.79), 1.43, F32.neg(1.10), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.74), 1.50, F32.neg(1.31), F32.neg(2.80), 1.66, F32.neg(1.14), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.68), 1.47, F32.neg(1.05), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.82), 1.44, F32.neg(1.23), F32.neg(2.80), 1.66, F32.neg(1.14), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.60), 1.53, F32.neg(1.13), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.23), 1.11, F32.neg(1.39), F32.neg(2.33), 1.24, F32.neg(1.31), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.33), 1.24, F32.neg(1.31), F32.neg(2.31), 1.09, F32.neg(1.21), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.35), 1.06, F32.neg(1.35), F32.neg(2.33), 1.24, F32.neg(1.31), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.33), 1.24, F32.neg(1.31), F32.neg(2.19), 1.14, F32.neg(1.26), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.48), 1.58, F32.neg(0.82), F32.neg(2.66), 1.72, F32.neg(0.90), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.63), 1.50, F32.neg(1.01), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.45), 1.61, F32.neg(0.94), F32.neg(2.66), 1.72, F32.neg(0.90), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.66), 1.48, F32.neg(0.88), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.52), 1.57, F32.neg(1.04), F32.neg(2.66), 1.72, F32.neg(0.90), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.59), 1.52, F32.neg(0.79), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.42), 1.65, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.22), 1.60, F32.neg(0.57), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.44), 1.60, F32.neg(0.61), F32.neg(2.34), 1.81, F32.neg(0.56), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.20), 1.66, F32.neg(0.68), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.57, F32.neg(0.53), F32.neg(2.34), 1.81, F32.neg(0.56), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.29), 1.68, F32.neg(0.76), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.22), 1.23, F32.neg(1.10), F32.neg(2.20), 1.37, F32.neg(0.98), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.20), 1.37, F32.neg(0.98), F32.neg(2.09), 1.23, F32.neg(0.94), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.23), 1.19, F32.neg(0.96), F32.neg(2.20), 1.37, F32.neg(0.98), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.20), 1.37, F32.neg(0.98), F32.neg(2.08), 1.27, F32.neg(1.08), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.74), 1.74, F32.neg(0.78), F32.neg(1.79), 1.86, F32.neg(0.58), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.80), 1.63, F32.neg(0.55), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.87), 1.72, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.68), 1.65, F32.neg(0.58), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.90), 1.66, F32.neg(0.64), F32.neg(1.79), 1.86, F32.neg(0.58), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.65), 1.71, F32.neg(0.69), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.43), 1.75, F32.neg(0.67), F32.neg(1.32), 1.94, F32.neg(0.76), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.40), 1.79, F32.neg(0.93), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.70, F32.neg(0.73), F32.neg(1.32), 1.94, F32.neg(0.76), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.50), 1.83, F32.neg(0.87), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.31), 1.72, F32.neg(0.86), F32.neg(1.32), 1.94, F32.neg(0.76), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.52), 1.81, F32.neg(0.74), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.87), 1.37, F32.neg(0.97), F32.neg(1.75), 1.51, F32.neg(0.97), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.75), 1.51, F32.neg(0.97), F32.neg(1.68), 1.36, F32.neg(1.05), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.74), 1.33, F32.neg(0.92), F32.neg(1.75), 1.51, F32.neg(0.97), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.75), 1.51, F32.neg(0.97), F32.neg(1.81), 1.39, F32.neg(1.10), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.93), 1.46, F32.neg(1.39), F32.neg(1.89), 1.65, F32.neg(1.25), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.87), 1.46, F32.neg(1.11), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(2.03), 1.47, F32.neg(1.29), F32.neg(1.89), 1.65, F32.neg(1.25), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.77), 1.45, F32.neg(1.21), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(2.00), 1.46, F32.neg(1.16), F32.neg(1.89), 1.65, F32.neg(1.25), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.80), 1.46, F32.neg(1.34), 0.12, 0.40, 0.13, 0.05} <> (Nil{}))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))

# Ground sphere beside the cluster of spheres, frustums, and leaves.
def scene() -> Knot:
  join(
    fold_tree(
      32n,
      List.append(&2, Knot,
        sphere_row(),
        List.append(&2, Knot, beams_of(branches()), blades_of(leaves())))),
    ground_tip())

# A leaf in front of the light lets its thru fraction through. Anything solid blocks.
def saw_vis(h: Hit) -> F32:
  match h:
    case Miss{}:
      1.0
    case Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, +thru}:
      pick_f((thru > 0.02 : F32), thru, 0.0)

def light_vis(
  +tree: Knot, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> F32:
  saw_vis(closest(tree, ox, oy, oz, dx, dy, dz))

# Sun from the upper right, fill from the upper left. spec rides on the sun only.
# A leaf also glows when the sun is behind it and nothing solid blocks that side.
def surface(
  +px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  +cr: F32, +cg: F32, +cb: F32, +dx: F32, +dy: F32, +dz: F32,
  +thru: F32, +tree: Knot
) -> Vec3:
  +eps = {0.02 : F32}
  +ox = (px + (nx * eps) : F32)
  +oy = (py + (ny * eps) : F32)
  +oz = (pz + (nz * eps) : F32)
  +bx = (px - (nx * eps) : F32)
  +by = (py - (ny * eps) : F32)
  +bz = (pz - (nz * eps) : F32)
  +lx = {F32.neg(0.31701148) : F32}
  +ly = {0.81014045 : F32}
  +lz = {F32.neg(0.49312897) : F32}
  +nl = (nx * lx + ny * ly + nz * lz : F32)
  +ndotl = max0(nl)
  +ndotf = max0((nx * 0.57543534 + ny * 0.51789180 + nz * 0.63297887 : F32))
  +vis = light_vis(tree, ox, oy, oz, lx, ly, lz)
  +bvis = light_vis(tree, bx, by, bz, lx, ly, lz)
  +glow = (max0(F32.neg(nl)) * bvis * pick_f((thru > 0.02 : F32), 1.35, 0.0) : F32)
  +rx = ((ndotl * (nx * 2.0)) - lx : F32)
  +ry = ((ndotl * (ny * 2.0)) - ly : F32)
  +rz = ((ndotl * (nz * 2.0)) - lz : F32)
  +vd = max0((rx * F32.neg(dx) + ry * F32.neg(dy) + rz * F32.neg(dz) : F32))
  +spec = (F32.pow(vd, 56.0) * ndotl * vis : F32)
  +lit = (0.11 + ndotl * vis * 1.10 + ndotf * 0.24 : F32)
  V3{
    (cr * lit + spec * 0.90 + glow * 0.85 : F32),
    (cg * lit + spec * 0.86 + glow * 1.05 : F32),
    (cb * lit + spec * 0.76 + glow * 0.25 : F32)
  }

# Green the light that has passed through a leaf. An opaque bounce stays as it is.
def beer_tint(+cr: F32, +cg: F32, +cb: F32, far: Vec3) -> Vec3:
  match far:
    case V3{rr, rg, rb}:
      V3{
        (rr * (0.45 + (cr * 0.8) : F32) : F32),
        (rg * (0.35 + (cg * 0.9) : F32) : F32),
        (rb * (0.25 + (cb * 0.55) : F32) : F32)
      }

def beer(leaf: Bool, +cr: F32, +cg: F32, +cb: F32, far: Vec3) -> Vec3:
  match leaf:
    case True{}:
      beer_tint(cr, cg, cb, far)
    case False{}:
      far

def shade_bounce(
  leaf: Bool, +cr: F32, +cg: F32, +cb: F32, lit: Vec3, far: Vec3, +w: F32
) -> Vec3:
  mix3(lit, beer(leaf, cr, cg, cb, far), w)

# Go fires a ray. Saw has already intersected it. Folding both into one def
# keeps the bounce recursive without a second function calling back.
# Two steps of n make one bounce, so trace starts at 6n: three hits, then sky.
# A leaf continues the ray through the blade. Anything else reflects.
type Step is Data:
  Go{ox: F32, oy: F32, oz: F32, dx: F32, dy: F32, dz: F32}
  Saw{hit: Hit, dx: F32, dy: F32, dz: F32}

def trace(+n: Nat, step: Step, +tree: Knot) -> Vec3:
  match n step:
    case 0n Go{ox, oy, oz, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl, thru}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Go{ox, oy, oz, +dx, +dy, +dz}:
      trace(p, Saw{closest(tree, ox, oy, oz, dx, dy, dz), dx, dy, dz}, tree)
    case 1n+p Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Saw{Hit{t, +px, +py, +pz, +nx, +ny, +nz, +cr, +cg, +cb, refl, +thru}, +dx, +dy, +dz}:
      +leaf = (thru > 0.02 : F32)
      +eps = {0.02 : F32}
      +ox = pick_f(leaf, (px + (dx * 0.05) - (nx * 0.02) : F32), (px + (nx * eps) : F32))
      +oy = pick_f(leaf, (py + (dy * 0.05) - (ny * 0.02) : F32), (py + (ny * eps) : F32))
      +oz = pick_f(leaf, (pz + (dz * 0.05) - (nz * 0.02) : F32), (pz + (nz * eps) : F32))
      +nd = (dx * nx + dy * ny + dz * nz : F32)
      +k = (nd * 2.0 : F32)
      +rdx = pick_f(leaf, dx, (dx - (k * nx) : F32))
      +rdy = pick_f(leaf, dy, (dy - (k * ny) : F32))
      +rdz = pick_f(leaf, dz, (dz - (k * nz) : F32))
      shade_bounce(
        leaf, cr, cg, cb,
        surface(px, py, pz, nx, ny, nz, cr, cg, cb, dx, dy, dz, thru, tree),
        trace(p, Go{ox, oy, oz, rdx, rdy, rdz}, tree),
        pick_f(leaf, thru, refl))

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

def shoot(ex: F32, ey: F32, ez: F32, dir: Vec3, tree: Knot) -> U32:
  match dir:
    case V3{dx, dy, dz}:
      pack(trace(6n, Go{ex, ey, ez, dx, dy, dz}, tree))

def aim(
  +x: U32, +y: U32, +side: F32,
  ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32,
  rx: F32, ry: F32, rz: F32, ux: F32, uy: F32, uz: F32, +sc: F32,
  tree: Knot
) -> U32:
  +u = ((U32.to_f32(x) + 0.5) / side - 0.5 : F32)
  +v = (0.5 - (U32.to_f32(y) + 0.5) / side : F32)
  +su = (u * (sc * 2.0) : F32)
  +sv = (v * (sc * 2.0) : F32)
  shoot(ex, ey, ez, norm3(
    (fx + rx * su + ux * sv : F32),
    (fy + ry * su + uy * sv : F32),
    (fz + rz * su + uz * sv : F32)), tree)

def pixel(+x: U32, +y: U32, +side: F32, cam: Cam, tree: Knot) -> U32:
  match cam:
    case Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc}:
      aim(x, y, side, ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc, tree)

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
def block(+k: Nat, +x: U32, +y: U32, +s: U32, +side: F32, +cam: Cam, +tree: Knot) -> Rows:
  match k:
    case 0n:
      RCons{bytes3(pixel(x, y, side, cam, tree)), RNil{}}
    case 1n+p:
      +h = U32.shrn(s, 1n)
      +x2 = (x + h : U32)
      +y2 = (y + h : U32)
      a b c d = block(p, x, y, h, side, cam, tree) block(p, x2, y, h, side, cam, tree) block(p, x, y2, h, side, cam, tree) block(p, x2, y2, h, side, cam, tree)
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

def render(depth: Nat, side: U32, f: F32, cam: Cam, tree: Knot) -> List<&2, U32>:
  List.reverse(&2, U32, flatten(block(depth, 0, 0, side, f, cam, tree), Nil{}))

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
  "<!doctype html><html><head><meta charset='utf-8'><title>Sphere tree</title><style>"
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
  listener: Listener, sock: Socket, view: View, next: Listener -> IO(Unit),
  tree: Knot
) -> IO(Unit):
  do IO<Unit>:
    body : List<&2, U32> = render(depth, side, f, cam_of(view), tree)
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, with_header(frame_header(side), body))
    sent_then(sent, listener, next)

def send_frame(size: Size, listener: Listener, sock: Socket, view: View, next: Listener -> IO(Unit), tree: Knot) -> IO(Unit):
  match size:
    case Size{depth, +side, f}:
      send_rendered(depth, side, f, listener, sock, view, next, tree)

def route(size: Size, path: String, listener: Listener, sock: Socket, next: Listener -> IO(Unit), +tree: Knot) -> IO(Unit):
  match path:
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{48}, rest}}}:
      send_frame(size, listener, sock, view_of(48, rest), next, tree)
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{49}, rest}}}:
      send_frame(size, listener, sock, view_of(49, rest), next, tree)
    case SCon{Chr{47}, SCon{Chr{32}, _}}:
      send_text(listener, sock, page(size), next)
    case _:
      send_text(listener, sock, not_found(), next)

def got_req(
  size: Size, listener: Listener, got: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
  next: Listener -> IO(Unit), +tree: Knot
) -> IO(Unit):
  match got:
    case (sock, Done{Some{text}}):
      route(size, String.drop(text, 4n), listener, sock, next, tree)
    case (sock, Done{None{}}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)
    case (sock, Fail{err}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)

def read_one(size: Size, listener: Listener, sock: Socket, next: Listener -> IO(Unit), tree: Knot) -> IO(Unit):
  do IO<Unit>:
    got : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(sock, 8192)
    got_req(size, listener, got, next, tree)

def accepted(size: Size, got: Listener & Result<&1, &1, U32 & String, Socket>, next: Listener -> IO(Unit), +tree: Knot) -> IO(Unit):
  match got:
    case (listener, Done{sock}):
      read_one(size, listener, sock, next, tree)
    case (listener, Fail{err}):
      do IO<Unit>:
        IO.print("accept ended")
        Listener.close(listener)

def accept_one(size: Size, listener: Listener, next: Listener -> IO(Unit), tree: Knot) -> IO(Unit):
  do IO<Unit>:
    got : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    accepted(size, got, next, tree)

def serve(fuel: Nat, +size: Size, listener: Listener, +tree: Knot) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("stopping")
        Listener.close(listener)
    case 1n+left:
      accept_one(size, listener, l => serve(left, size, l, tree), tree)

def side_of(size: Size) -> U32:
  match size:
    case Size{depth, side, f}:
      side

def listen(+size: Size) -> IO(Unit):
  do IO<Unit>:
    IO.print("building the sphere tree")
    tree : Knot = scene()
    IO.print("ray tracer at http://127.0.0.1:8080/  side " ++ U32.show(side_of(size)))
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", 8080))
    serve(4294967295n, size, listener, tree)

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
