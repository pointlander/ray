# A sphere scene and a tree, ray traced from a sparse voxel octree and served as a live page.
# The trunk and branches are conical frustums. The leaves are flat triangles.
# The octree is built once. Every pixel, shadow, and reflection marches it.
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

# A conical frustum from a to b, closed by discs. ra is the radius at a, rb at b.
type Cyl is Data:
  Cyl{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, ra: F32, rb: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# A two-sided triangle. The normal faces the incoming ray.
type Tri is Data:
  Tri{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, cx: F32, cy: F32, cz: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# Perpendicular parts of a ray against a cylinder axis. dv and ov are the axis dots.
# Sparse voxel octree. Children are indexed by x in bit 0, y in bit 1, z in bit 2.
# A leaf stores the surface that painted it: colour, reflectance, and outward normal.
type Vox is Data:
  Air{}
  Leaf{cr: F32, cg: F32, cb: F32, refl: F32, nx: F32, ny: F32, nz: F32}
  Fork{c0: Vox, c1: Vox, c2: Vox, c3: Vox, c4: Vox, c5: Vox, c6: Vox, c7: Vox}

# One primitive being painted into the octree. Later paints overwrite earlier leaves.
type Job is Data:
  Floor{}
  Ball{cx: F32, cy: F32, cz: F32, rad: F32, cr: F32, cg: F32, cb: F32, refl: F32}
  Beam{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, ra: F32, rb: F32, cr: F32, cg: F32, cb: F32, refl: F32}
  Blade{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, cx: F32, cy: F32, cz: F32, cr: F32, cg: F32, cb: F32, refl: F32}

# One node the ray still has siblings inside. Planes tx, ty, tz are the next
# crossing of that axis, or a far sentinel once that axis has been stepped.
type Frame is Data:
  Frame{
    c0: Vox, c1: Vox, c2: Vox, c3: Vox, c4: Vox, c5: Vox, c6: Vox, c7: Vox,
    bx: F32, by: F32, bz: F32, sz: F32,
    tx: F32, ty: F32, tz: F32, t1: F32,
    cx: Bool, cy: Bool, cz: Bool
  }

type March is Data:
  Down{node: Vox, bx: F32, by: F32, bz: F32, sz: F32, t0: F32, t1: F32, stack: List<&2, Frame>}
  Side{frame: Frame, stack: List<&2, Frame>}
  Found{hit: Hit}

type Span is Data:
  Span{lo: F32, hi: F32}

# Closest point on a segment. t is 0 at a and 1 at b.
type Near is Data:
  Near{t: F32, dist: F32, qx: F32, qy: F32, qz: F32}

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

# --- sparse voxel octree --------------------------------------------------
# The world cube is [-4, 4] x [-0.5, 7.5] x [-4, 4], split seven times.
# A leaf is 1/16 of a unit. Empty space stays Air, so the tree is sparse.

def vol_x() -> F32:
  F32.neg(4.0)

def vol_y() -> F32:
  F32.neg(0.5)

def vol_z() -> F32:
  F32.neg(4.0)

def vol_s() -> F32:
  8.0

def vol_n() -> Nat:
  7n

def far_t() -> F32:
  1000000.0

def len3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

def dot3(+ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32) -> F32:
  (ax * bx + ay * by + az * bz : F32)

def tiny(+d: F32) -> Bool:
  (d < 0.0001 : F32) && (d > F32.neg(0.0001) : F32)

def div_or(+numer: F32, +denom: F32, skip: Bool) -> F32:
  match skip:
    case True{}:
      F32.neg(1.0)
    case False{}:
      (numer / denom : F32)

def div_big(+numer: F32, +denom: F32, skip: Bool) -> F32:
  match skip:
    case True{}:
      far_t()
    case False{}:
      (numer / denom : F32)

# Outward normal of a cone. k is dr/ds along the unit axis.
def cone_normal(
  +rx: F32, +ry: F32, +rz: F32, +k: F32, +vx: F32, +vy: F32, +vz: F32
) -> Vec3:
  +rlen = len3(rx, ry, rz)
  +scale = pick_f((rlen < 0.00001 : F32), 1.0, rlen)
  norm3(
    ((rx / scale) - (k * vx) : F32),
    ((ry / scale) - (k * vy) : F32),
    ((rz / scale) - (k * vz) : F32))

def face_pick(back: Bool, +nx: F32, +ny: F32, +nz: F32) -> Vec3:
  match back:
    case True{}:
      V3{F32.neg(nx), F32.neg(ny), F32.neg(nz)}
    case False{}:
      V3{nx, ny, nz}

def face_vec(+nx: F32, +ny: F32, +nz: F32, +dx: F32, +dy: F32, +dz: F32) -> Vec3:
  face_pick((dot3(nx, ny, nz, dx, dy, dz) > 0.0 : F32), nx, ny, nz)

def cell_c(+a: F32, +size: F32) -> F32:
  (a + (size * 0.5) : F32)

def cell_pad(+size: F32) -> F32:
  (size * 0.9 : F32)

# --- segment and triangle distance ----------------------------------------

def seg_near(
  +px: F32, +py: F32, +pz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +bx: F32, +by: F32, +bz: F32
) -> Near:
  +abx = (bx - ax : F32)
  +aby = (by - ay : F32)
  +abz = (bz - az : F32)
  +ab2 = (abx * abx + aby * aby + abz * abz : F32)
  +t = F32.clamp(
    div_or(
      dot3((px - ax : F32), (py - ay : F32), (pz - az : F32), abx, aby, abz),
      ab2, tiny(ab2)),
    0.0, 1.0)
  +qx = (ax + (abx * t) : F32)
  +qy = (ay + (aby * t) : F32)
  +qz = (az + (abz * t) : F32)
  Near{t, len3((px - qx : F32), (py - qy : F32), (pz - qz : F32)), qx, qy, qz}

def near_dist(n: Near) -> F32:
  match n:
    case Near{t, dist, qx, qy, qz}:
      dist

def seg_dist(
  +px: F32, +py: F32, +pz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +bx: F32, +by: F32, +bz: F32
) -> F32:
  near_dist(seg_near(px, py, pz, ax, ay, az, bx, by, bz))

def plane_abs(+nd: F32, +nlen: F32, flat: Bool) -> F32:
  match flat:
    case True{}:
      far_t()
    case False{}:
      F32.abs((nd / nlen : F32))

# Distance from a point to a triangle. Inside the prism it is the plane
# distance. Outside it is the nearest edge, so a leaf stays diamond shaped.
def tri_dist(
  +px: F32, +py: F32, +pz: F32,
  +ax: F32, +ay: F32, +az: F32,
  +bx: F32, +by: F32, +bz: F32,
  +cx: F32, +cy: F32, +cz: F32
) -> F32:
  +abx = (bx - ax : F32)
  +aby = (by - ay : F32)
  +abz = (bz - az : F32)
  +acx = (cx - ax : F32)
  +acy = (cy - ay : F32)
  +acz = (cz - az : F32)
  +apx = (px - ax : F32)
  +apy = (py - ay : F32)
  +apz = (pz - az : F32)
  +d00 = dot3(abx, aby, abz, abx, aby, abz)
  +d01 = dot3(abx, aby, abz, acx, acy, acz)
  +d11 = dot3(acx, acy, acz, acx, acy, acz)
  +d20 = dot3(abx, aby, abz, apx, apy, apz)
  +d21 = dot3(acx, acy, acz, apx, apy, apz)
  +den = (d00 * d11 - d01 * d01 : F32)
  +inv = div_big(1.0, den, tiny(den))
  +u = (((d11 * d20) - (d01 * d21) : F32) * inv : F32)
  +v = (((d00 * d21) - (d01 * d20) : F32) * inv : F32)
  +nx = (aby * acz - abz * acy : F32)
  +ny = (abz * acx - abx * acz : F32)
  +nz = (abx * acy - aby * acx : F32)
  +nlen = len3(nx, ny, nz)
  +inside = (u >= 0.0 : F32) && (v >= 0.0 : F32) && ((u + v) <= 1.0 : F32) && Bool.not(tiny(den))
  pick_f(
    inside,
    plane_abs(dot3(nx, ny, nz, apx, apy, apz), nlen, tiny(nlen)),
    F32.min(
      seg_dist(px, py, pz, ax, ay, az, bx, by, bz),
      F32.min(
        seg_dist(px, py, pz, ax, ay, az, cx, cy, cz),
        seg_dist(px, py, pz, bx, by, bz, cx, cy, cz))))

# --- coverage and ink -----------------------------------------------------

def ball_hit(
  +x: F32, +y: F32, +z: F32, +size: F32,
  +cx: F32, +cy: F32, +cz: F32, +rad: F32
) -> Bool:
  +h = cell_pad(size)
  +dist = len3(
    (cell_c(x, size) - cx : F32),
    (cell_c(y, size) - cy : F32),
    (cell_c(z, size) - cz : F32))
  ((dist - h) <= rad : F32) && ((dist + h) >= rad : F32)

def beam_cover(n: Near, +ra: F32, +rb: F32, +size: F32) -> Bool:
  match n:
    case Near{t, dist, qx, qy, qz}:
      +rad = (ra + ((rb - ra) * t : F32) : F32)
      (dist <= (rad + cell_pad(size) : F32) : F32)

def beam_hit(
  +x: F32, +y: F32, +z: F32, +size: F32,
  +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +ra: F32, +rb: F32
) -> Bool:
  beam_cover(
    seg_near(cell_c(x, size), cell_c(y, size), cell_c(z, size), ax, ay, az, bx, by, bz),
    ra, rb, size)

def covers(+x: F32, +y: F32, +z: F32, +size: F32, job: Job) -> Bool:
  match job:
    case Floor{}:
      (y < 0.0 : F32) && ((y + size) >= 0.0 : F32)
    case Ball{+cx, +cy, +cz, +rad, cr, cg, cb, refl}:
      ball_hit(x, y, z, size, cx, cy, cz, rad)
    case Beam{+ax, +ay, +az, +bx, +by, +bz, +ra, +rb, cr, cg, cb, refl}:
      beam_hit(x, y, z, size, ax, ay, az, bx, by, bz, ra, rb)
    case Blade{+ax, +ay, +az, +bx, +by, +bz, +cx, +cy, +cz, cr, cg, cb, refl}:
      (tri_dist(
        cell_c(x, size), cell_c(y, size), cell_c(z, size),
        ax, ay, az, bx, by, bz, cx, cy, cz) <= cell_pad(size) : F32)

def floor_leaf(c: Vec3) -> Vox:
  match c:
    case V3{r, g, b}:
      Leaf{r, g, b, 0.18, 0.0, 1.0, 0.0}

def leaf_n(n: Vec3, cr: F32, cg: F32, cb: F32, refl: F32) -> Vox:
  match n:
    case V3{nx, ny, nz}:
      Leaf{cr, cg, cb, refl, nx, ny, nz}

def beam_k(+rb: F32, +ra: F32, +h: F32, flat: Bool) -> F32:
  match flat:
    case True{}:
      0.0
    case False{}:
      ((rb - ra) / h : F32)

def axis_part(+ab: F32, +h: F32, +fallback: F32, flat: Bool) -> F32:
  match flat:
    case True{}:
      fallback
    case False{}:
      (ab / h : F32)

def beam_from(
  n: Near, +x: F32, +y: F32, +z: F32, +size: F32,
  +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32,
  +ra: F32, +rb: F32, cr: F32, cg: F32, cb: F32, refl: F32
) -> Vox:
  match n:
    case Near{t, dist, +qx, +qy, +qz}:
      +abx = (bx - ax : F32)
      +aby = (by - ay : F32)
      +abz = (bz - az : F32)
      +h = len3(abx, aby, abz)
      +flat = tiny(h)
      leaf_n(
        cone_normal(
          (cell_c(x, size) - qx : F32),
          (cell_c(y, size) - qy : F32),
          (cell_c(z, size) - qz : F32),
          beam_k(rb, ra, h, flat),
          axis_part(abx, h, 0.0, flat),
          axis_part(aby, h, 1.0, flat),
          axis_part(abz, h, 0.0, flat)),
        cr, cg, cb, refl)

def ink(+x: F32, +y: F32, +z: F32, +size: F32, job: Job) -> Vox:
  match job:
    case Floor{}:
      floor_leaf(checker(cell_c(x, size), cell_c(z, size)))
    case Ball{+cx, +cy, +cz, rad, cr, cg, cb, refl}:
      leaf_n(norm3(
        (cell_c(x, size) - cx : F32),
        (cell_c(y, size) - cy : F32),
        (cell_c(z, size) - cz : F32)), cr, cg, cb, refl)
    case Beam{+ax, +ay, +az, +bx, +by, +bz, +ra, +rb, cr, cg, cb, refl}:
      beam_from(
        seg_near(cell_c(x, size), cell_c(y, size), cell_c(z, size), ax, ay, az, bx, by, bz),
        x, y, z, size, ax, ay, az, bx, by, bz, ra, rb, cr, cg, cb, refl)
    case Blade{+ax, +ay, +az, +bx, +by, +bz, +cx, +cy, +cz, cr, cg, cb, refl}:
      leaf_n(norm3(
        ((by - ay : F32) * (cz - az : F32) - (bz - az : F32) * (cy - ay : F32) : F32),
        ((bz - az : F32) * (cx - ax : F32) - (bx - ax : F32) * (cz - az : F32) : F32),
        ((bx - ax : F32) * (cy - ay : F32) - (by - ay : F32) * (cx - ax : F32) : F32)),
        cr, cg, cb, refl)

# Paint one primitive. `hit` is covers() of this cell, passed in so the match
# stays on parameters. A miss keeps the node. A hit at the last level overwrites
# one leaf. Above that, the eight children are painted together.
def paint(
  +level: Nat, node: Vox, +x: F32, +y: F32, +z: F32, +size: F32, +job: Job, hit: Bool
) -> Vox:
  match level node hit:
    case 0n kept False{}:
      kept
    case 0n _ True{}:
      ink(x, y, z, size, job)
    case 1n+p kept False{}:
      kept
    case 1n+p Air{} True{}:
      +h = (size * 0.5 : F32)
      +x1 = (x + h : F32)
      +y1 = (y + h : F32)
      +z1 = (z + h : F32)
      k0 k1 k2 k3 k4 k5 k6 k7 = paint(p, Air{}, x, y, z, h, job, covers(x, y, z, h, job)) paint(p, Air{}, x1, y, z, h, job, covers(x1, y, z, h, job)) paint(p, Air{}, x, y1, z, h, job, covers(x, y1, z, h, job)) paint(p, Air{}, x1, y1, z, h, job, covers(x1, y1, z, h, job)) paint(p, Air{}, x, y, z1, h, job, covers(x, y, z1, h, job)) paint(p, Air{}, x1, y, z1, h, job, covers(x1, y, z1, h, job)) paint(p, Air{}, x, y1, z1, h, job, covers(x, y1, z1, h, job)) paint(p, Air{}, x1, y1, z1, h, job, covers(x1, y1, z1, h, job))
      Fork{k0, k1, k2, k3, k4, k5, k6, k7}
    case 1n+p Fork{c0, c1, c2, c3, c4, c5, c6, c7} True{}:
      +h = (size * 0.5 : F32)
      +x1 = (x + h : F32)
      +y1 = (y + h : F32)
      +z1 = (z + h : F32)
      k0 k1 k2 k3 k4 k5 k6 k7 = paint(p, c0, x, y, z, h, job, covers(x, y, z, h, job)) paint(p, c1, x1, y, z, h, job, covers(x1, y, z, h, job)) paint(p, c2, x, y1, z, h, job, covers(x, y1, z, h, job)) paint(p, c3, x1, y1, z, h, job, covers(x1, y1, z, h, job)) paint(p, c4, x, y, z1, h, job, covers(x, y, z1, h, job)) paint(p, c5, x1, y, z1, h, job, covers(x1, y, z1, h, job)) paint(p, c6, x, y1, z1, h, job, covers(x, y1, z1, h, job)) paint(p, c7, x1, y1, z1, h, job, covers(x1, y1, z1, h, job))
      Fork{k0, k1, k2, k3, k4, k5, k6, k7}
    case 1n+p Leaf{cr, cg, cb, refl, nx, ny, nz} True{}:
      Leaf{cr, cg, cb, refl, nx, ny, nz}

def paint_at(node: Vox, +job: Job) -> Vox:
  paint(vol_n(), node, vol_x(), vol_y(), vol_z(), vol_s(), job, covers(vol_x(), vol_y(), vol_z(), vol_s(), job))

def paint_floor(node: Vox) -> Vox:
  paint_at(node, Floor{})

def paint_ball(
  node: Vox, +cx: F32, +cy: F32, +cz: F32, +rad: F32,
  +cr: F32, +cg: F32, +cb: F32, +refl: F32
) -> Vox:
  paint_at(node, Ball{cx, cy, cz, rad, cr, cg, cb, refl})

def paint_one_cyl(cyl: Cyl, node: Vox) -> Vox:
  match cyl:
    case Cyl{+ax, +ay, +az, +bx, +by, +bz, +ra, +rb, +cr, +cg, +cb, +refl}:
      paint_at(node, Beam{ax, ay, az, bx, by, bz, ra, rb, cr, cg, cb, refl})

def paint_cyls(cs: List<&2, Cyl>, node: Vox) -> Vox:
  match cs:
    case Nil{}:
      node
    case c <> rest:
      paint_cyls(rest, paint_one_cyl(c, node))

def paint_one_tri(tri: Tri, node: Vox) -> Vox:
  match tri:
    case Tri{+ax, +ay, +az, +bx, +by, +bz, +cx, +cy, +cz, +cr, +cg, +cb, +refl}:
      paint_at(node, Blade{ax, ay, az, bx, by, bz, cx, cy, cz, cr, cg, cb, refl})

def paint_tris(ts: List<&2, Tri>, node: Vox) -> Vox:
  match ts:
    case Nil{}:
      node
    case tri <> rest:
      paint_tris(rest, paint_one_tri(tri, node))

# --- ray march ------------------------------------------------------------
# The ray crosses a node through at most four children. Each step either
# descends into the next child or pops back to the parent. A leaf counts only
# when the ray enters it from outside, so a shadow ray skips the voxel it
# starts in.

def span_of(neg: Bool, +a: F32, +b: F32) -> Span:
  match neg:
    case True{}:
      Span{b, a}
    case False{}:
      Span{a, b}

def out_span(outside: Bool) -> Span:
  match outside:
    case True{}:
      Span{1.0, F32.neg(1.0)}
    case False{}:
      Span{F32.neg(far_t()), far_t()}

def flat_span(flat: Bool, neg: Bool, +o: F32, +d: F32, +mn: F32, +mx: F32) -> Span:
  match flat:
    case True{}:
      out_span((o < mn : F32) || (o > mx : F32))
    case False{}:
      span_of(neg, ((mn - o) / d : F32), ((mx - o) / d : F32))

def axis_span(+o: F32, +d: F32, +mn: F32, +mx: F32) -> Span:
  flat_span(tiny(d), (d < 0.0 : F32), o, d, mn, mx)

def cast_span(sx: Span, sy: Span, sz: Span) -> Span:
  match sx sy sz:
    case Span{x0, x1} Span{y0, y1} Span{z0, z1}:
      Span{F32.max(x0, F32.max(y0, z0)), F32.min(x1, F32.min(y1, z1))}

def plane_t(+o: F32, +d: F32, +plane: F32) -> F32:
  div_big((plane - o : F32), d, tiny(d))

def past_mid(pos: Bool, +t: F32, +tm: F32) -> Bool:
  match pos:
    case True{}:
      (t >= tm : F32)
    case False{}:
      (t <= tm : F32)

def axis_high(flat: Bool, +pos: Bool, +t: F32, +tm: F32, +at: F32, +mid: F32) -> Bool:
  match flat:
    case True{}:
      (at >= mid : F32)
    case False{}:
      past_mid(pos, t, tm)

# The next plane inside this node. A far sentinel means the ray leaves the
# node on this axis instead of crossing the middle.
def axis_next(high: Bool, pos: Bool, +tm: F32) -> F32:
  match high pos:
    case False{} True{}:
      tm
    case True{} False{}:
      tm
    case False{} False{}:
      far_t()
    case True{} True{}:
      far_t()

def pick8(
  cx: Bool, cy: Bool, cz: Bool,
  +c0: Vox, +c1: Vox, +c2: Vox, +c3: Vox, +c4: Vox, +c5: Vox, +c6: Vox, +c7: Vox
) -> Vox:
  match cx cy cz:
    case False{} False{} False{}:
      c0
    case True{} False{} False{}:
      c1
    case False{} True{} False{}:
      c2
    case True{} True{} False{}:
      c3
    case False{} False{} True{}:
      c4
    case True{} False{} True{}:
      c5
    case False{} True{} True{}:
      c6
    case True{} True{} True{}:
      c7

def pop_stack(stack: List<&2, Frame>) -> March:
  match stack:
    case Nil{}:
      Found{Miss{}}
    case frame <> rest:
      Side{frame, rest}

def bury(stack: List<&2, Frame>, hit: Hit) -> Hit:
  match stack:
    case Nil{}:
      hit
    case _ <> rest:
      bury(rest, hit)

def shade_hit(
  n: Vec3, +t: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  cr: F32, cg: F32, cb: F32, refl: F32
) -> Hit:
  match n:
    case V3{nx, ny, nz}:
      Hit{
        t,
        (ox + (dx * t) : F32), (oy + (dy * t) : F32), (oz + (dz * t) : F32),
        nx, ny, nz, cr, cg, cb, refl
      }

def leaf_march(
  near: Bool, +cr: F32, +cg: F32, +cb: F32, +refl: F32,
  +nx: F32, +ny: F32, +nz: F32, +t: F32, stack: List<&2, Frame>,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> March:
  match near:
    case False{}:
      pop_stack(stack)
    case True{}:
      Found{bury(stack, shade_hit(face_vec(nx, ny, nz, dx, dy, dz), t, ox, oy, oz, dx, dy, dz, cr, cg, cb, refl))}

def step_bit(step: Bool, bit: Bool) -> Bool:
  match step:
    case True{}:
      Bool.not(bit)
    case False{}:
      bit

def step_plane(step: Bool, +tp: F32) -> F32:
  match step:
    case True{}:
      far_t()
    case False{}:
      tp

def on_plane(+tp: F32, +tn: F32, +t1: F32) -> Bool:
  (tp <= (tn + 0.00001 : F32) : F32) && (tp < t1 : F32)

def child_t(+tx: F32, +ty: F32, +tz: F32, +t1: F32) -> F32:
  F32.min(tx, F32.min(ty, F32.min(tz, t1)))

def stepped(
  out: Bool,
  +c0: Vox, +c1: Vox, +c2: Vox, +c3: Vox, +c4: Vox, +c5: Vox, +c6: Vox, +c7: Vox,
  +bx: F32, +by: F32, +bz: F32, +sz: F32,
  +tx: F32, +ty: F32, +tz: F32, +tn: F32, +t1: F32,
  +cx: Bool, +cy: Bool, +cz: Bool,
  stack: List<&2, Frame>
) -> March:
  match out:
    case True{}:
      pop_stack(stack)
    case False{}:
      +sx = on_plane(tx, tn, t1)
      +sy = on_plane(ty, tn, t1)
      +szb = on_plane(tz, tn, t1)
      +nx = step_bit(sx, cx)
      +ny = step_bit(sy, cy)
      +nz = step_bit(szb, cz)
      +ntx = step_plane(sx, tx)
      +nty = step_plane(sy, ty)
      +ntz = step_plane(szb, tz)
      +h = (sz * 0.5 : F32)
      Down{
        pick8(nx, ny, nz, c0, c1, c2, c3, c4, c5, c6, c7),
        pick_f(nx, (bx + h : F32), bx),
        pick_f(ny, (by + h : F32), by),
        pick_f(nz, (bz + h : F32), bz),
        h, tn, child_t(ntx, nty, ntz, t1),
        (Frame{c0, c1, c2, c3, c4, c5, c6, c7, bx, by, bz, sz, ntx, nty, ntz, t1, nx, ny, nz} <> stack)
      }

def advance(
  +c0: Vox, +c1: Vox, +c2: Vox, +c3: Vox, +c4: Vox, +c5: Vox, +c6: Vox, +c7: Vox,
  +bx: F32, +by: F32, +bz: F32, +sz: F32,
  +tx: F32, +ty: F32, +tz: F32, +t1: F32,
  +cx: Bool, +cy: Bool, +cz: Bool,
  stack: List<&2, Frame>
) -> March:
  +tn = child_t(tx, ty, tz, t1)
  stepped((tn >= t1 : F32), c0, c1, c2, c3, c4, c5, c6, c7, bx, by, bz, sz, tx, ty, tz, tn, t1, cx, cy, cz, stack)

def open_fork(
  +c0: Vox, +c1: Vox, +c2: Vox, +c3: Vox, +c4: Vox, +c5: Vox, +c6: Vox, +c7: Vox,
  +bx: F32, +by: F32, +bz: F32, +sz: F32, +t0: F32, +t1: F32,
  stack: List<&2, Frame>,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> March:
  +h = (sz * 0.5 : F32)
  +mx = (bx + h : F32)
  +my = (by + h : F32)
  +mz = (bz + h : F32)
  +tmx = plane_t(ox, dx, mx)
  +tmy = plane_t(oy, dy, my)
  +tmz = plane_t(oz, dz, mz)
  +px = (ox + (dx * t0) : F32)
  +py = (oy + (dy * t0) : F32)
  +pz = (oz + (dz * t0) : F32)
  +xpos = (dx >= 0.0 : F32)
  +ypos = (dy >= 0.0 : F32)
  +zpos = (dz >= 0.0 : F32)
  +cx = axis_high(tiny(dx), xpos, t0, tmx, px, mx)
  +cy = axis_high(tiny(dy), ypos, t0, tmy, py, my)
  +cz = axis_high(tiny(dz), zpos, t0, tmz, pz, mz)
  +tx = axis_next(cx, xpos, tmx)
  +ty = axis_next(cy, ypos, tmy)
  +tz = axis_next(cz, zpos, tmz)
  Down{
    pick8(cx, cy, cz, c0, c1, c2, c3, c4, c5, c6, c7),
    pick_f(cx, mx, bx),
    pick_f(cy, my, by),
    pick_f(cz, mz, bz),
    h, t0, child_t(tx, ty, tz, t1),
    (Frame{c0, c1, c2, c3, c4, c5, c6, c7, bx, by, bz, sz, tx, ty, tz, t1, cx, cy, cz} <> stack)
  }

def open_node(
  node: Vox, +bx: F32, +by: F32, +bz: F32, +sz: F32, +t0: F32, +t1: F32,
  stack: List<&2, Frame>,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> March:
  match node:
    case Air{}:
      pop_stack(stack)
    case Leaf{+cr, +cg, +cb, +refl, +nx, +ny, +nz}:
      leaf_march((t0 > 0.001 : F32), cr, cg, cb, refl, nx, ny, nz, t0, stack, ox, oy, oz, dx, dy, dz)
    case Fork{+c0, +c1, +c2, +c3, +c4, +c5, +c6, +c7}:
      open_fork(c0, c1, c2, c3, c4, c5, c6, c7, bx, by, bz, sz, t0, t1, stack, ox, oy, oz, dx, dy, dz)

def enter_down(
  past: Bool, +node: Vox,
  +bx: F32, +by: F32, +bz: F32, +sz: F32, +t0: F32, +t1: F32,
  stack: List<&2, Frame>,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> March:
  match past:
    case True{}:
      pop_stack(stack)
    case False{}:
      open_node(node, bx, by, bz, sz, t0, t1, stack, ox, oy, oz, dx, dy, dz)

def march(
  fuel: Nat, st: March,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> Hit:
  match fuel st:
    case 0n Down{node, bx, by, bz, sz, t0, t1, stack}:
      Miss{}
    case 0n Side{frame, stack}:
      Miss{}
    case 0n Found{hit}:
      hit
    case 1n+p Found{hit}:
      hit
    case 1n+p Down{node, +bx, +by, +bz, +sz, +t0, +t1, stack}:
      march(p, enter_down((t0 > t1 : F32), node, bx, by, bz, sz, t0, t1, stack, ox, oy, oz, dx, dy, dz), ox, oy, oz, dx, dy, dz)
    case 1n+p Side{Frame{+c0, +c1, +c2, +c3, +c4, +c5, +c6, +c7, +bx, +by, +bz, +sz, +tx, +ty, +tz, +t1, +cx, +cy, +cz}, stack}:
      march(p, advance(c0, c1, c2, c3, c4, c5, c6, c7, bx, by, bz, sz, tx, ty, tz, t1, cx, cy, cz, stack), ox, oy, oz, dx, dy, dz)

def shoot_span(
  ok: Bool, +lo: F32, +hi: F32, +tree: Vox, +hop: Nat,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> Hit:
  match ok:
    case False{}:
      Miss{}
    case True{}:
      march(hop, Down{tree, vol_x(), vol_y(), vol_z(), vol_s(), F32.max(lo, 0.0), hi, Nil{}}, ox, oy, oz, dx, dy, dz)

def from_span(
  sp: Span, tree: Vox, hop: Nat,
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32
) -> Hit:
  match sp:
    case Span{+lo, +hi}:
      shoot_span((hi >= lo : F32) && (hi > 0.001 : F32), lo, hi, tree, hop, ox, oy, oz, dx, dy, dz)

def cast_tree(tree: Vox, hop: Nat, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Hit:
  +x0 = vol_x()
  +y0 = vol_y()
  +z0 = vol_z()
  +s = vol_s()
  from_span(
    cast_span(
      axis_span(ox, dx, x0, (x0 + s : F32)),
      axis_span(oy, dy, y0, (y0 + s : F32)),
      axis_span(oz, dz, z0, (z0 + s : F32))),
    tree, hop, ox, oy, oz, dx, dy, dz)

def block_saw(h: Hit) -> Bool:
  match h:
    case Miss{}:
      False{}
    case Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl}:
      True{}

def closest(tree: Vox, hop: Nat, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Hit:
  cast_tree(tree, hop, ox, oy, oz, dx, dy, dz)

def blocked(tree: Vox, hop: Nat, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  block_saw(closest(tree, hop, ox, oy, oz, dx, dy, dz))

def branches() -> List<&2, Cyl>:
  Cyl{F32.neg(1.90), F32.neg(0.02), F32.neg(1.25), F32.neg(1.90), 0.46, F32.neg(1.25), 0.155, 0.112, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.90), 0.46, F32.neg(1.25), F32.neg(1.90), 0.92, F32.neg(1.25), 0.112, 0.070, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.90), 0.92, F32.neg(1.25), F32.neg(1.90), 1.36, F32.neg(1.25), 0.070, 0.038, 0.40, 0.24, 0.11, 0.04} <> (Cyl{F32.neg(1.87), 0.36, F32.neg(1.13), F32.neg(1.80), 0.68, F32.neg(0.76), 0.056, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.80), 0.68, F32.neg(0.76), F32.neg(1.92), 0.84, F32.neg(0.53), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.80), 0.68, F32.neg(0.76), F32.neg(1.55), 0.92, F32.neg(0.57), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.80), 0.48, F32.neg(1.20), F32.neg(1.41), 0.86, F32.neg(0.99), 0.051, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.41), 0.86, F32.neg(0.99), F32.neg(1.28), 1.02, F32.neg(0.76), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.41), 0.86, F32.neg(0.99), F32.neg(1.08), 1.10, F32.neg(1.03), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.81), 0.56, F32.neg(1.30), F32.neg(1.39), 0.90, F32.neg(1.52), 0.047, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.39), 0.90, F32.neg(1.52), F32.neg(1.09), 1.06, F32.neg(1.49), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.39), 0.90, F32.neg(1.52), F32.neg(1.24), 1.14, F32.neg(1.78), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.88), 0.64, F32.neg(1.34), F32.neg(1.78), 1.06, F32.neg(1.80), 0.044, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.78), 1.06, F32.neg(1.80), F32.neg(1.56), 1.22, F32.neg(1.97), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.78), 1.06, F32.neg(1.80), F32.neg(1.92), 1.30, F32.neg(2.06), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.95), 0.74, F32.neg(1.32), F32.neg(2.19), 1.10, F32.neg(1.68), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.19), 1.10, F32.neg(1.68), F32.neg(2.18), 1.26, F32.neg(1.94), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.19), 1.10, F32.neg(1.68), F32.neg(2.51), 1.34, F32.neg(1.78), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.98), 0.82, F32.neg(1.26), F32.neg(2.40), 1.22, F32.neg(1.32), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.40), 1.22, F32.neg(1.32), F32.neg(2.61), 1.38, F32.neg(1.50), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.40), 1.22, F32.neg(1.32), F32.neg(2.70), 1.46, F32.neg(1.19), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.95), 0.92, F32.neg(1.20), F32.neg(2.24), 1.36, F32.neg(0.94), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(2.24), 1.36, F32.neg(0.94), F32.neg(2.54), 1.52, F32.neg(0.91), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(2.24), 1.36, F32.neg(0.94), F32.neg(2.32), 1.60, F32.neg(0.66), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.87), 1.04, F32.neg(1.20), F32.neg(1.73), 1.50, F32.neg(0.93), 0.040, 0.030, 0.36, 0.22, 0.11, 0.03} <> (Cyl{F32.neg(1.73), 1.50, F32.neg(0.93), F32.neg(1.77), 1.66, F32.neg(0.68), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Cyl{F32.neg(1.73), 1.50, F32.neg(0.93), F32.neg(1.43), 1.74, F32.neg(0.80), 0.030, 0.028, 0.32, 0.19, 0.10, 0.03} <> (Nil{})))))))))))))))))))))))))))

def leaves() -> List<&2, Tri>:
  Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.94), 0.91, F32.neg(0.63), F32.neg(1.96), 1.04, F32.neg(0.43), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.90), 0.81, F32.neg(0.40), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(2.04), 0.86, F32.neg(0.57), F32.neg(1.96), 1.04, F32.neg(0.43), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.80), 0.87, F32.neg(0.46), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(2.02), 0.81, F32.neg(0.45), F32.neg(1.96), 1.04, F32.neg(0.43), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.88), 0.69, F32.neg(0.60), F32.neg(1.96), 1.04, F32.neg(0.43), F32.neg(1.82), 0.92, F32.neg(0.58), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.50), 0.89, F32.neg(0.44), F32.neg(1.46), 1.12, F32.neg(0.50), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.57), 1.00, F32.neg(0.67), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.42), 0.89, F32.neg(0.54), F32.neg(1.46), 1.12, F32.neg(0.50), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.65), 1.00, F32.neg(0.57), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.45), 0.94, F32.neg(0.66), F32.neg(1.46), 1.12, F32.neg(0.50), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.61), 0.77, F32.neg(0.62), F32.neg(1.46), 1.12, F32.neg(0.50), F32.neg(1.62), 0.95, F32.neg(0.46), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.80), 0.62, F32.neg(0.96), F32.neg(1.81), 0.72, F32.neg(0.81), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.81), 0.72, F32.neg(0.81), F32.neg(1.84), 0.54, F32.neg(0.78), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.92), 0.60, F32.neg(0.89), F32.neg(1.81), 0.72, F32.neg(0.81), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.83), 0.45, F32.neg(0.93), F32.neg(1.81), 0.72, F32.neg(0.81), F32.neg(1.72), 0.57, F32.neg(0.86), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.40), 1.06, F32.neg(0.71), F32.neg(1.23), 1.22, F32.neg(0.67), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.15), 1.03, F32.neg(0.80), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.30), 1.00, F32.neg(0.63), F32.neg(1.23), 1.22, F32.neg(0.67), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.24), 1.09, F32.neg(0.87), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.18), 0.99, F32.neg(0.68), F32.neg(1.23), 1.22, F32.neg(0.67), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.32), 0.87, F32.neg(0.83), F32.neg(1.23), 1.22, F32.neg(0.67), F32.neg(1.36), 1.10, F32.neg(0.82), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.06, F32.neg(1.07), F32.neg(0.96), 1.30, F32.neg(1.04), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(1.17), 1.19, F32.neg(0.99), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(1.04), 1.11, F32.neg(1.16), F32.neg(0.96), 1.30, F32.neg(1.04), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(1.08), 1.15, F32.neg(0.90), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(1.15), 1.17, F32.neg(1.12), F32.neg(0.96), 1.30, F32.neg(1.04), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.16), 0.95, F32.neg(1.02), F32.neg(0.96), 1.30, F32.neg(1.04), F32.neg(0.98), 1.08, F32.neg(0.95), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.70, F32.neg(0.98), F32.neg(1.47), 0.88, F32.neg(1.02), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.88, F32.neg(1.02), F32.neg(1.59), 0.79, F32.neg(1.12), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.46), 0.73, F32.neg(1.12), F32.neg(1.47), 0.88, F32.neg(1.02), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.59), 0.61, F32.neg(1.09), F32.neg(1.47), 0.88, F32.neg(1.02), F32.neg(1.60), 0.76, F32.neg(0.99), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(1.02), 1.05, F32.neg(1.37), F32.neg(0.97), 1.26, F32.neg(1.48), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.13), 1.12, F32.neg(1.60), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.96), 1.02, F32.neg(1.48), F32.neg(0.97), 1.26, F32.neg(1.48), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.19), 1.15, F32.neg(1.49), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(1.01), 1.06, F32.neg(1.60), F32.neg(0.97), 1.26, F32.neg(1.48), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.18), 0.91, F32.neg(1.50), F32.neg(0.97), 1.26, F32.neg(1.48), F32.neg(1.14), 1.11, F32.neg(1.38), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.30), 1.14, F32.neg(1.90), F32.neg(1.18), 1.35, F32.neg(1.87), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.16), 1.20, F32.neg(1.68), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.36), 1.20, F32.neg(1.80), F32.neg(1.18), 1.35, F32.neg(1.87), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.10), 1.14, F32.neg(1.78), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.29), 1.23, F32.neg(1.69), F32.neg(1.18), 1.35, F32.neg(1.87), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.28), 0.99, F32.neg(1.71), F32.neg(1.18), 1.35, F32.neg(1.87), F32.neg(1.17), 1.11, F32.neg(1.89), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.50), 0.76, F32.neg(1.55), F32.neg(1.45), 0.93, F32.neg(1.49), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.45), 0.93, F32.neg(1.49), F32.neg(1.53), 0.83, F32.neg(1.36), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.60), 0.83, F32.neg(1.48), F32.neg(1.45), 0.93, F32.neg(1.49), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.58), 0.67, F32.neg(1.42), F32.neg(1.45), 0.93, F32.neg(1.49), F32.neg(1.43), 0.76, F32.neg(1.43), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.45), 1.18, F32.neg(2.03), F32.neg(1.47), 1.42, F32.neg(2.04), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.65), 1.31, F32.neg(1.93), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.55), 1.20, F32.neg(2.10), F32.neg(1.47), 1.42, F32.neg(2.04), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.55), 1.28, F32.neg(1.86), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.66), 1.27, F32.neg(2.05), F32.neg(1.47), 1.42, F32.neg(2.04), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.63), 1.07, F32.neg(1.92), F32.neg(1.47), 1.42, F32.neg(2.04), F32.neg(1.44), 1.22, F32.neg(1.91), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(2.02), 1.34, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(1.83), 1.31, F32.neg(2.16), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.90), 1.38, F32.neg(1.96), F32.neg(1.97), 1.51, F32.neg(2.15), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(1.95), 1.27, F32.neg(2.19), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.81), 1.37, F32.neg(2.04), F32.neg(1.97), 1.51, F32.neg(2.15), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.88), 1.15, F32.neg(1.99), F32.neg(1.97), 1.51, F32.neg(2.15), F32.neg(2.04), 1.29, F32.neg(2.11), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.91), 0.95, F32.neg(1.64), F32.neg(1.80), 1.07, F32.neg(1.73), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.80), 1.07, F32.neg(1.73), F32.neg(1.72), 0.91, F32.neg(1.68), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.79), 0.97, F32.neg(1.57), F32.neg(1.80), 1.07, F32.neg(1.73), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.83), 0.80, F32.neg(1.60), F32.neg(1.80), 1.07, F32.neg(1.73), F32.neg(1.84), 0.89, F32.neg(1.75), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.26), 1.24, F32.neg(2.05), F32.neg(2.18), 1.46, F32.neg(2.04), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.11), 1.33, F32.neg(1.85), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.31), 1.29, F32.neg(1.94), F32.neg(2.18), 1.46, F32.neg(2.04), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.05), 1.28, F32.neg(1.96), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.24), 1.34, F32.neg(1.84), F32.neg(2.18), 1.46, F32.neg(2.04), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.19), 1.11, F32.neg(1.86), F32.neg(2.18), 1.46, F32.neg(2.04), F32.neg(2.13), 1.23, F32.neg(2.05), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.45), 1.42, F32.neg(1.70), F32.neg(2.62), 1.54, F32.neg(1.82), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.60), 1.31, F32.neg(1.88), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.41), 1.42, F32.neg(1.82), F32.neg(2.62), 1.54, F32.neg(1.82), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.64), 1.31, F32.neg(1.75), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.49), 1.37, F32.neg(1.91), F32.neg(2.62), 1.54, F32.neg(1.82), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.43), 1.19, F32.neg(1.76), F32.neg(2.62), 1.54, F32.neg(1.82), F32.neg(2.56), 1.37, F32.neg(1.66), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.06), 1.04, F32.neg(1.50), F32.neg(2.16), 1.13, F32.neg(1.63), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.16), 1.13, F32.neg(1.63), F32.neg(2.18), 0.95, F32.neg(1.64), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.04), 0.99, F32.neg(1.64), F32.neg(2.16), 1.13, F32.neg(1.63), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.08), 0.86, F32.neg(1.52), F32.neg(2.16), 1.13, F32.neg(1.63), F32.neg(2.20), 1.00, F32.neg(1.51), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.72), 1.40, F32.neg(1.41), F32.neg(2.70), 1.58, F32.neg(1.56), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.53), 1.41, F32.neg(1.59), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.60), 1.45, F32.neg(1.39), F32.neg(2.70), 1.58, F32.neg(1.56), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.64), 1.35, F32.neg(1.62), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.51), 1.46, F32.neg(1.48), F32.neg(2.70), 1.58, F32.neg(1.56), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.55), 1.23, F32.neg(1.44), F32.neg(2.70), 1.58, F32.neg(1.56), F32.neg(2.74), 1.35, F32.neg(1.53), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.63), 1.55, F32.neg(1.26), F32.neg(2.80), 1.66, F32.neg(1.14), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.79), 1.43, F32.neg(1.10), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.74), 1.50, F32.neg(1.31), F32.neg(2.80), 1.66, F32.neg(1.14), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.68), 1.47, F32.neg(1.05), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.82), 1.44, F32.neg(1.23), F32.neg(2.80), 1.66, F32.neg(1.14), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.62), 1.31, F32.neg(1.22), F32.neg(2.80), 1.66, F32.neg(1.14), F32.neg(2.60), 1.53, F32.neg(1.13), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.23), 1.11, F32.neg(1.39), F32.neg(2.33), 1.24, F32.neg(1.31), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.33), 1.24, F32.neg(1.31), F32.neg(2.31), 1.09, F32.neg(1.21), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.35), 1.06, F32.neg(1.35), F32.neg(2.33), 1.24, F32.neg(1.31), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.21), 0.96, F32.neg(1.29), F32.neg(2.33), 1.24, F32.neg(1.31), F32.neg(2.19), 1.14, F32.neg(1.26), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.48), 1.58, F32.neg(0.82), F32.neg(2.66), 1.72, F32.neg(0.90), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.63), 1.50, F32.neg(1.01), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.45), 1.61, F32.neg(0.94), F32.neg(2.66), 1.72, F32.neg(0.90), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.66), 1.48, F32.neg(0.88), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.52), 1.57, F32.neg(1.04), F32.neg(2.66), 1.72, F32.neg(0.90), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.45), 1.37, F32.neg(0.92), F32.neg(2.66), 1.72, F32.neg(0.90), F32.neg(2.59), 1.52, F32.neg(0.79), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.42), 1.65, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.22), 1.60, F32.neg(0.57), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.44), 1.60, F32.neg(0.61), F32.neg(2.34), 1.81, F32.neg(0.56), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.20), 1.66, F32.neg(0.68), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.57, F32.neg(0.53), F32.neg(2.34), 1.81, F32.neg(0.56), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.30), 1.45, F32.neg(0.73), F32.neg(2.34), 1.81, F32.neg(0.56), F32.neg(2.29), 1.68, F32.neg(0.76), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.22), 1.23, F32.neg(1.10), F32.neg(2.20), 1.37, F32.neg(0.98), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.20), 1.37, F32.neg(0.98), F32.neg(2.09), 1.23, F32.neg(0.94), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.23), 1.19, F32.neg(0.96), F32.neg(2.20), 1.37, F32.neg(0.98), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(2.11), 1.09, F32.neg(1.06), F32.neg(2.20), 1.37, F32.neg(0.98), F32.neg(2.08), 1.27, F32.neg(1.08), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.74), 1.74, F32.neg(0.78), F32.neg(1.79), 1.86, F32.neg(0.58), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.80), 1.63, F32.neg(0.55), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.87), 1.72, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.68), 1.65, F32.neg(0.58), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.90), 1.66, F32.neg(0.64), F32.neg(1.79), 1.86, F32.neg(0.58), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.76), 1.51, F32.neg(0.75), F32.neg(1.79), 1.86, F32.neg(0.58), F32.neg(1.65), 1.71, F32.neg(0.69), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.43), 1.75, F32.neg(0.67), F32.neg(1.32), 1.94, F32.neg(0.76), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.40), 1.79, F32.neg(0.93), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.70, F32.neg(0.73), F32.neg(1.32), 1.94, F32.neg(0.76), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.50), 1.83, F32.neg(0.87), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.31), 1.72, F32.neg(0.86), F32.neg(1.32), 1.94, F32.neg(0.76), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.50), 1.59, F32.neg(0.84), F32.neg(1.32), 1.94, F32.neg(0.76), F32.neg(1.52), 1.81, F32.neg(0.74), 0.20, 0.52, 0.17, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.87), 1.37, F32.neg(0.97), F32.neg(1.75), 1.51, F32.neg(0.97), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.75), 1.51, F32.neg(0.97), F32.neg(1.68), 1.36, F32.neg(1.05), 0.08, 0.32, 0.11, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.74), 1.33, F32.neg(0.92), F32.neg(1.75), 1.51, F32.neg(0.97), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.79), 1.22, F32.neg(1.05), F32.neg(1.75), 1.51, F32.neg(0.97), F32.neg(1.81), 1.39, F32.neg(1.10), 0.24, 0.56, 0.19, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.93), 1.46, F32.neg(1.39), F32.neg(1.89), 1.65, F32.neg(1.25), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.87), 1.46, F32.neg(1.11), 0.15, 0.46, 0.14, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(2.03), 1.47, F32.neg(1.29), F32.neg(1.89), 1.65, F32.neg(1.25), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.77), 1.45, F32.neg(1.21), 0.10, 0.36, 0.12, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(2.00), 1.46, F32.neg(1.16), F32.neg(1.89), 1.65, F32.neg(1.25), 0.12, 0.40, 0.13, 0.05} <> (Tri{F32.neg(1.91), 1.27, F32.neg(1.25), F32.neg(1.89), 1.65, F32.neg(1.25), F32.neg(1.80), 1.46, F32.neg(1.34), 0.12, 0.40, 0.13, 0.05} <> (Nil{}))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))

# Floor, then the tree, then the five spheres so a later surface overwrites.
def scene() -> Vox:
  paint_ball(
    paint_ball(
      paint_ball(
        paint_ball(
          paint_ball(
            paint_tris(leaves(), paint_cyls(branches(), paint_floor(Air{}))),
            F32.neg(1.05), 0.50, 0.15, 0.50, 0.86, 0.16, 0.12, 0.05),
          0.15, 0.50, F32.neg(0.35), 0.50, 0.93, 0.93, 0.95, 0.90),
        1.25, 0.50, 0.25, 0.50, 0.16, 0.32, 0.86, 0.22),
      F32.neg(0.35), 0.22, 1.05, 0.22, 0.96, 0.66, 0.16, 0.38),
    0.85, 0.18, 1.20, 0.18, 0.22, 0.72, 0.32, 0.12)

def vis_of(in_shadow: Bool) -> F32:
  match in_shadow:
    case True{}:
      0.0
    case False{}:
      1.0

# Sun from the upper right, fill from the upper left. spec rides on the sun only.
def surface(
  +px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  +cr: F32, +cg: F32, +cb: F32, +dx: F32, +dy: F32, +dz: F32,
  tree: Vox, hop: Nat
) -> Vec3:
  +eps = {0.2 : F32}
  +ox = (px + nx * eps : F32)
  +oy = (py + ny * eps : F32)
  +oz = (pz + nz * eps : F32)
  +lx = {F32.neg(0.31701148) : F32}
  +ly = {0.81014045 : F32}
  +lz = {F32.neg(0.49312897) : F32}
  +ndotl = max0((nx * lx + ny * ly + nz * lz : F32))
  +ndotf = max0((nx * 0.57543534 + ny * 0.51789180 + nz * 0.63297887 : F32))
  +vis = vis_of(blocked(tree, hop, ox, oy, oz, lx, ly, lz))
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

def trace(+n: Nat, step: Step, +tree: Vox, +hop: Nat) -> Vec3:
  match n step:
    case 0n Go{ox, oy, oz, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 0n Saw{Hit{t, px, py, pz, nx, ny, nz, cr, cg, cb, refl}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Go{ox, oy, oz, +dx, +dy, +dz}:
      trace(p, Saw{closest(tree, hop, ox, oy, oz, dx, dy, dz), dx, dy, dz}, tree, hop)
    case 1n+p Saw{Miss{}, dx, dy, dz}:
      sky(dx, dy, dz)
    case 1n+p Saw{Hit{t, +px, +py, +pz, +nx, +ny, +nz, cr, cg, cb, refl}, +dx, +dy, +dz}:
      +eps = {0.2 : F32}
      +ox = (px + nx * eps : F32)
      +oy = (py + ny * eps : F32)
      +oz = (pz + nz * eps : F32)
      +nd = (dx * nx + dy * ny + dz * nz : F32)
      +k = (nd * 2.0 : F32)
      mix3(
        surface(px, py, pz, nx, ny, nz, cr, cg, cb, dx, dy, dz, tree, hop),
        trace(p, Go{ox, oy, oz, (dx - k * nx : F32), (dy - k * ny : F32), (dz - k * nz : F32)}, tree, hop),
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

def shoot(ex: F32, ey: F32, ez: F32, dir: Vec3, tree: Vox, hop: Nat) -> U32:
  match dir:
    case V3{dx, dy, dz}:
      pack(trace(6n, Go{ex, ey, ez, dx, dy, dz}, tree, hop))

def aim(
  +x: U32, +y: U32, +side: F32,
  ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32,
  rx: F32, ry: F32, rz: F32, ux: F32, uy: F32, uz: F32, +sc: F32,
  tree: Vox, hop: Nat
) -> U32:
  +u = ((U32.to_f32(x) + 0.5) / side - 0.5 : F32)
  +v = (0.5 - (U32.to_f32(y) + 0.5) / side : F32)
  +su = (u * (sc * 2.0) : F32)
  +sv = (v * (sc * 2.0) : F32)
  shoot(ex, ey, ez, norm3(
    (fx + rx * su + ux * sv : F32),
    (fy + ry * su + uy * sv : F32),
    (fz + rz * su + uz * sv : F32)), tree, hop)

def pixel(+x: U32, +y: U32, +side: F32, cam: Cam, tree: Vox, hop: Nat) -> U32:
  match cam:
    case Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc}:
      aim(x, y, side, ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, sc, tree, hop)

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
def block(+k: Nat, +x: U32, +y: U32, +s: U32, +side: F32, +cam: Cam, +tree: Vox, +hop: Nat) -> Rows:
  match k:
    case 0n:
      RCons{bytes3(pixel(x, y, side, cam, tree, hop)), RNil{}}
    case 1n+p:
      +h = U32.shrn(s, 1n)
      +x2 = (x + h : U32)
      +y2 = (y + h : U32)
      a b c d = block(p, x, y, h, side, cam, tree, hop) block(p, x2, y, h, side, cam, tree, hop) block(p, x, y2, h, side, cam, tree, hop) block(p, x2, y2, h, side, cam, tree, hop)
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

def render(depth: Nat, side: U32, f: F32, cam: Cam, tree: Vox, hop: Nat) -> List<&2, U32>:
  List.reverse(&2, U32, flatten(block(depth, 0, 0, side, f, cam, tree, hop), Nil{}))

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
  "<!doctype html><html><head><meta charset='utf-8'><title>Voxel trace</title><style>"
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
  tree: Vox, hop: Nat
) -> IO(Unit):
  do IO<Unit>:
    body : List<&2, U32> = render(depth, side, f, cam_of(view), tree, hop)
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, with_header(frame_header(side), body))
    sent_then(sent, listener, next)

def send_frame(size: Size, listener: Listener, sock: Socket, view: View, next: Listener -> IO(Unit), tree: Vox, hop: Nat) -> IO(Unit):
  match size:
    case Size{depth, +side, f}:
      send_rendered(depth, side, f, listener, sock, view, next, tree, hop)

def route(size: Size, path: String, listener: Listener, sock: Socket, next: Listener -> IO(Unit), +tree: Vox, +hop: Nat) -> IO(Unit):
  match path:
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{48}, rest}}}:
      send_frame(size, listener, sock, view_of(48, rest), next, tree, hop)
    case SCon{Chr{47}, SCon{Chr{102}, SCon{Chr{49}, rest}}}:
      send_frame(size, listener, sock, view_of(49, rest), next, tree, hop)
    case SCon{Chr{47}, SCon{Chr{32}, _}}:
      send_text(listener, sock, page(size), next)
    case _:
      send_text(listener, sock, not_found(), next)

def got_req(
  size: Size, listener: Listener, got: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
  next: Listener -> IO(Unit), +tree: Vox, +hop: Nat
) -> IO(Unit):
  match got:
    case (sock, Done{Some{text}}):
      route(size, String.drop(text, 4n), listener, sock, next, tree, hop)
    case (sock, Done{None{}}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)
    case (sock, Fail{err}):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        next(listener)

def read_one(size: Size, listener: Listener, sock: Socket, next: Listener -> IO(Unit), tree: Vox, hop: Nat) -> IO(Unit):
  do IO<Unit>:
    got : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(sock, 8192)
    got_req(size, listener, got, next, tree, hop)

def accepted(size: Size, got: Listener & Result<&1, &1, U32 & String, Socket>, next: Listener -> IO(Unit), +tree: Vox, +hop: Nat) -> IO(Unit):
  match got:
    case (listener, Done{sock}):
      read_one(size, listener, sock, next, tree, hop)
    case (listener, Fail{err}):
      do IO<Unit>:
        IO.print("accept ended")
        Listener.close(listener)

def accept_one(size: Size, listener: Listener, next: Listener -> IO(Unit), tree: Vox, hop: Nat) -> IO(Unit):
  do IO<Unit>:
    got : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    accepted(size, got, next, tree, hop)

def serve(fuel: Nat, +size: Size, listener: Listener, +tree: Vox, +hop: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("stopping")
        Listener.close(listener)
    case 1n+left:
      accept_one(size, listener, l => serve(left, size, l, tree, hop), tree, hop)

def side_of(size: Size) -> U32:
  match size:
    case Size{depth, side, f}:
      side

def listen(+size: Size) -> IO(Unit):
  do IO<Unit>:
    IO.print("building the octree")
    tree : Vox = scene()
    hop : Nat = 4096n
    IO.print("ray tracer at http://127.0.0.1:8080/  side " ++ U32.show(side_of(size)))
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", 8080))
    serve(4294967295n, size, listener, tree, hop)

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
