# Eldergrove Faire -- a high-fantasy theme park, built in Bend.
#
#   bend main.bend -o park && ./park          play
#   ./park --shot out.ppm 900 [tool]          headless: 900 ticks, one frame
#
# A frame is a list of drawables in front-to-back order; the quadtree
# rasterizer filters it down cell by cell (in parallel) and each pixel takes
# the first opaque colour.
import Base
import ./core.bend as C
import ./art.bend as A
import ./font.bend as F
import ./sound.bend as Z
import ./save.bend as S

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def B() -> U32:
  4096

# Drawables
# ---------

type Dr is Data:
  DBlock{x: U32, y: U32, dl: U32, dr: U32, ter: U32, obj: U32, hov: U32,
    wx: U32, wy: U32, nb: U32}
  DTree{x: U32, y: U32, v: U32, n: U32}
  DRide{x: U32, y: U32, k: U32, ra: U32, rb: U32, st: U32}
  DGate{x: U32, y: U32}
  DTrack{x: U32, y: U32, code: U32, zr: U32}
  DGuest{x: U32, y: U32, look: U32, ph: U32}
  DCar{x: U32, y: U32, d: U32, lead: U32, rd: U32}
  DGlyph{x: U32, y: U32, bits: U32, col: U32}
  DRect{x: U32, y: U32, w: U32, h: U32, col: U32}
  DIcon{x: U32, y: U32, tool: U32, on: U32}

def ov(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +bx: U32, +by: U32, +s: U32)
  -> Bool:
  ((x1 > bx) && (x0 < bx + s) && (y1 > by) && (y0 < by + s) : U32)

def Dr.hits(d: Dr, +bx: U32, +by: U32, +s: U32) -> Bool:
  match d:
    case DBlock{+x, +y, +dl, +dr, ter, obj, hov, wx, wy, +nb}:
      +top = sel(U32.is_eq((nb >> 6n : U32), 0), 7, 30)
      ov((x - 16 : U32), (y - top : U32), (x + 17 : U32), (y + 17 + U32.max(dl, dr) : U32), bx, by, s)
    case DTree{+x, +y, v, n}:
      ov((x - 13 : U32), (y - 40 : U32), (x + 14 : U32), (y + 6 : U32), bx, by, s)
    case DRide{+x, +y, k, ra, rb, st}:
      ov((x - 30 : U32), (y - 92 : U32), (x + 31 : U32), (y + 16 : U32), bx, by, s)
    case DGate{+x, +y}:
      ov((x - 20 : U32), (y - 48 : U32), (x + 20 : U32), (y + 6 : U32), bx, by, s)
    case DTrack{+x, +y, code, +zr}:
      ov((x - 16 : U32), (y - zr * 8 - 12 : U32), (x + 17 : U32), (y + 17 : U32), bx, by, s)
    case DGuest{+x, +y, +look, ph}:
      +top = sel(U32.is_eq(((look >> 20n) .&. 15 : U32), 0), 15, 27)
      ov((x - 5 : U32), (y - top : U32), (x + 7 : U32), (y + 1 : U32), bx, by, s)
    case DCar{+x, +y, d, lead, rd}:
      ov((x - 10 : U32), (y - 19 : U32), (x + 11 : U32), (y + 6 : U32), bx, by, s)
    case DGlyph{+x, +y, bits, col}:
      ov(x, y, (x + 4 : U32), (y + 6 : U32), bx, by, s)
    case DRect{+x, +y, +w, +h, col}:
      ov(x, y, (x + w : U32), (y + h : U32), bx, by, s)
    case DIcon{+x, +y, tool, on}:
      ov(x, y, (x + 22 : U32), (y + 22 : U32), bx, by, s)

def Dr.shade(d: Dr, +px: U32, +py: U32, +t: U32) -> U32:
  match d:
    case DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}:
      A.Art.block(x, y, dl, dr, ter, obj, hov, wx, wy, t, px, py, nb)
    case DTree{x, y, v, n}:
      A.Art.tree(v, (px - x : U32), (py - y : U32), n, t)
    case DRide{x, y, k, ra, rb, st}:
      A.Art.ride(k, (px - x : U32), (py - y : U32), t, ra, rb, st)
    case DGate{x, y}:
      A.Art.gate((px - x : U32), (py - y : U32), t)
    case DTrack{x, y, code, zr}:
      A.Art.track(x, y, code, zr, t, px, py)
    case DGuest{x, y, look, ph}:
      A.Art.guest((px - x : U32), (py - y : U32), look, ph)
    case DCar{x, y, d, lead, rd}:
      A.Art.car((px - x : U32), (py - y : U32), d, lead, rd)
    case DGlyph{x, y, bits, col}:
      A.Art.glyph(bits, (px - x : U32), (py - y : U32), col)
    case DRect{x, y, w, h, col}:
      col
    case DIcon{x, y, tool, on}:
      A.Art.icon(tool, on, (px - x : U32), (py - y : U32), t)

# The rasterizer
# --------------

# The rasterizer
# --------------
# The frame is cut into 64-px cells and 16-px tiles, as Bend's shader guide
# prescribes. Each cell cuts the frame's list once for itself and each tile
# cuts its cell's list; the tile's pixels then walk that short list in
# straight-line code (no forks below the tile). A list handed down the tree
# is only ever matched, so every read is a borrow, not a reference count;
# a kept entry is copied from its fields, so no entry is shared between
# cores; and each list has one last consumer (R.fin) that frees it.

def SKY() -> U32:
  1714237

def Dr.shade_if(hit: Bool, d: Dr, +px: U32, +py: U32, +t: U32) -> U32:
  match hit:
    case True{}:
      Dr.shade(d, px, py, t)
    case False{}:
      A.TR()

# front-to-back: the first opaque sample wins; `done` stops the walk
def first(+xs: +List<Dr>, done: Bool, +c: U32, +px: U32, +py: U32, +t: U32)
  -> U32:
  match xs done:
    case _ True{}:
      c
    case Nil{} False{}:
      SKY()
    case Con{+d, rest} False{}:
      +c2 = Dr.shade_if(Dr.hits(d, px, py, 1), d, px, py, t)
      first(rest, A.opaque(c2), c2, px, py, t)

# a fresh copy from the fields, so no drawable is shared between lists
def Dr.cp(d: Dr) -> Dr:
  match d:
    case DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}:
      DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}
    case DTree{x, y, v, n}:
      DTree{x, y, v, n}
    case DRide{x, y, k, ra, rb, st}:
      DRide{x, y, k, ra, rb, st}
    case DGate{x, y}:
      DGate{x, y}
    case DTrack{x, y, code, zr}:
      DTrack{x, y, code, zr}
    case DGuest{x, y, look, ph}:
      DGuest{x, y, look, ph}
    case DCar{x, y, d, lead, rd}:
      DCar{x, y, d, lead, rd}
    case DGlyph{x, y, bits, col}:
      DGlyph{x, y, bits, col}
    case DRect{x, y, w, h, col}:
      DRect{x, y, w, h, col}
    case DIcon{x, y, tool, on}:
      DIcon{x, y, tool, on}

def cut.put(keep: Bool, d: Dr, xs: +List<Dr>) -> +List<Dr>:
  match keep:
    case True{}:
      Dr.cp(d) <> xs
    case False{}:
      xs

# the entries that reach the square (bx, by, s), in order
def cut(xs: +List<Dr>, +bx: U32, +by: U32, +s: U32) -> +List<Dr>:
  match xs:
    case []:
      []
    case +d <> rest:
      cut.put(Dr.hits(d, bx, by, s), d, cut(rest, bx, by, s))

def empty(+xs: +List<Dr>) -> Bool:
  match xs:
    case []:
      True{}
    case d <> rest:
      False{}

# a square wholly inside a solid rectangle at the front of its list
def Dr.solid(d: Dr, +x0: U32, +y0: U32, +s: U32) -> U32:
  match d:
    case DRect{+x, +y, +w, +h, col}:
      sel(((x <= x0) && (y <= y0) && (x0 + s <= x + w) && (y0 + s <= y + h) : U32), col, A.TR())
    case _:
      A.TR()

def solid(+xs: +List<Dr>, +x0: U32, +y0: U32, +s: U32) -> U32:
  match xs:
    case []:
      SKY()
    case d <> rest:
      Dr.solid(d, x0, y0, s)

# the list's last consumer: walks it after the readers, then answers img
def R.fin(img: Image, xs: +List<Dr>) -> Image:
  match xs:
    case []:
      img
    case d <> rest:
      R.fin(img, rest)

def R.px4(same: Bool, +c0: U32, +c1: U32, +c2: U32, +c3: U32) -> Image:
  match same:
    case True{}:
      Pix{c0}
    case False{}:
      Qua{Pix{c0}, Pix{c1}, Pix{c2}, Pix{c3}}

def R.b2(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  +c0 = first(xs, False{}, 0, x, y, t)
  +c1 = first(xs, False{}, 0, x1, y, t)
  +c2 = first(xs, False{}, 0, x, y1, t)
  +c3 = first(xs, False{}, 0, x1, y1, t)
  R.px4(U32.is_eq(c0, c1) && U32.is_eq(c0, c2) && U32.is_eq(c0, c3), c0, c1, c2, c3)

def R.b4(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b2(xs, x, y, t), R.b2(xs, (x + 2 : U32), y, t), R.b2(xs, x, (y + 2 : U32), t),
    R.b2(xs, (x + 2 : U32), (y + 2 : U32), t)}

def R.b8(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b4(xs, x, y, t), R.b4(xs, (x + 4 : U32), y, t), R.b4(xs, x, (y + 4 : U32), t),
    R.b4(xs, (x + 4 : U32), (y + 4 : U32), t)}

def R.b16(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b8(xs, x, y, t), R.b8(xs, (x + 8 : U32), y, t), R.b8(xs, x, (y + 8 : U32), t),
    R.b8(xs, (x + 8 : U32), (y + 8 : U32), t)}

# a 16-px tile: one colour when empty or under a solid panel, else pixels
def R.tile.go(skip: Bool, +fc: U32, +xs: +List<Dr>, +x: U32, +y: U32, +t: U32)
  -> Image:
  match skip:
    case True{}:
      R.fin(Pix{fc}, xs)
    case False{}:
      R.fin(R.b16(xs, x, y, t), xs)

def R.tile(+cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +xs = cut(cl, x, y, 16)
  +fc = solid(xs, x, y, 16)
  R.tile.go(A.opaque(fc), fc, xs, x, y, t)

def R.quad(+cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +x1 = (x + 16 : U32)
  +y1 = (y + 16 : U32)
  a b c e = R.tile(cl, x, y, t) R.tile(cl, x1, y, t) R.tile(cl, x, y1, t)
    R.tile(cl, x1, y1, t)
  Qua{a, b, c, e}

# a 64-px cell: four 32-px quads of four tiles, all cut from the cell's list
def R.cell(none: Bool, +cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  match none:
    case True{}:
      R.fin(Pix{SKY()}, cl)
    case False{}:
      +x1 = (x + 32 : U32)
      +y1 = (y + 32 : U32)
      a b c e = R.quad(cl, x, y, t) R.quad(cl, x1, y, t) R.quad(cl, x, y1, t)
        R.quad(cl, x1, y1, t)
      R.fin(Qua{a, b, c, e}, cl)

def R.off(+y: U32) -> Bool:
  (y >= B() + 320 : U32)

# the frame's tree down to the cells (64 << d px); squares below the view
# answer sky before any cut
def R.root(+d: Nat, off: Bool, +g: +List<Dr>, +x: U32, +y: U32, +t: U32)
  -> Image:
  match d off:
    case _ True{}:
      Pix{SKY()}
    case 0n False{}:
      +cl = cut(g, x, y, 64)
      R.cell(empty(cl), cl, x, y, t)
    case 1n+p False{}:
      +s = U32.shln(64, p)
      +x1 = (x + s : U32)
      +y1 = (y + s : U32)
      a b c e = R.root(p, R.off(y), g, x, y, t) R.root(p, R.off(y), g, x1, y, t)
        R.root(p, R.off(y1), g, x, y1, t) R.root(p, R.off(y1), g, x1, y1, t)
      Qua{a, b, c, e}

def R.frame(+g: +List<Dr>, +t: U32) -> Image:
  R.fin(R.root(3n, False{}, g, B(), B(), t), g)

def pick_at(+q: C.Q, +mx: U32, +my: U32, +camx: U32, +camy: U32, +h: U32)
  -> U32:
  +a = ((mx + camx) - 1280 : U32)
  +b = (((my + camy + 8 * h) - 512) * 2 : U32)
  +u = A.iso_u(a, b)
  +v = A.iso_v(a, b)
  +i = (u >> 4n : U32)
  +j = (v >> 4n : U32)
  +ok = C.inmap(i, j) && U32.is_eq(C.Land.h(q, i, j), h)
  sel(ok, (i * 64 + j : U32), 99999)

def pick.go(+n: Nat, +q: C.Q, +mx: U32, +my: U32, +camx: U32, +camy: U32,
  +h: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +c = pick_at(q, mx, my, camx, camy, h)
      pick.go(p, q, mx, my, camx, camy, (h - 1 : U32),
        sel(U32.is_eq(acc, 99999), c, acc))

type UI is Data:
  UI{camx: U32, camy: U32, keys: U32, mx: U32, my: U32, mdown: U32,
    tool: U32, var: U32, speed: U32, msg: U32, frame: U32, income: U32,
    last: U32, io: U32, fps: U32, tl: Nat}

def pick(+q: C.Q, +ui: UI) -> U32:
  UI{camx, camy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = ui
  sel((my < 290 : U32) && (my > 12 : U32), pick.go(8n, q, mx, my, camx, camy, 7, 99999), 99999)

type Dyn is Data:
  Dyn{k: U32, d: Dr}

def Dyn.le(a: Dyn, b: Dyn) -> Bool:
  Dyn{ka, da} = a
  Dyn{kb, db} = b
  (ka <= kb : U32)

def scr_x(+i: U32, +j: U32, +camx: U32) -> U32:
  ((B() + 1280 + 16 * i) - (16 * j + camx) : U32)

def scr_y(+i: U32, +j: U32, +h: U32, +camy: U32) -> U32:
  ((B() + 512 + 8 * i + 8 * j) - (8 * h + camy) : U32)

# Riders
# ------
# A rider is drawn from an 8-bit code: bit 7 occupied, bits 0-1 class, 2-4
# tunic, 5-6 skin -- the same person, in the same outfit, as on the paths.

def rider_code(+lk: U32) -> U32:
  (128 .|. (lk .&. 3) .|. (((lk >> 4n) .&. 7) << 2n) .|. (((lk >> 8n) .&. 3) << 5n) : U32)

def byte_at(+n: U32) -> U32:
  match n:
    case 0:
      1
    case 1:
      256
    case 2:
      65536
    case _:
      16777216

# one pass per frame files every rider's code under their ride (seats 0-3
# in ra, 4-7 in rb) or, on the coaster, under their train (lo, hi)
type RT is Data:
  RT{ra: List<&2, U32>, rb: List<&2, U32>, lo: List<&2, U32>, hi: List<&2, U32>}

def RT.or(on: Bool, +t: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match on:
    case True{}:
      C.Tab.or(t, i, v)
    case False{}:
      t

def RT.add4(+t: +List<U32>, +i: U32, +seat: U32, +code: U32, +hi: Bool) -> +List<U32>:
  +base = sel(hi, 4, 0)
  +inr = (seat >= base : U32) && (seat < base + 4 : U32)
  RT.or(inr, t, i, (code * byte_at((seat - base : U32)) : U32))

def RT.add.go(on: Bool, coaster: Bool, +dir: U32, +tgt: U32, +lk: U32, t: RT) -> RT:
  match on coaster:
    case True{} False{}:
      RT{+ra, +rb, +lo, +hi} = t
      RT{RT.add4(ra, tgt, (dir .&. 7 : U32), rider_code(lk), False{}),
        RT.add4(rb, tgt, (dir .&. 7 : U32), rider_code(lk), True{}), lo, hi}
    case True{} True{}:
      RT{+ra, +rb, +lo, +hi} = t
      RT{ra, rb, RT.add4(lo, (dir >> 3n : U32), (dir .&. 7 : U32), rider_code(lk), False{}),
        RT.add4(hi, (dir >> 3n : U32), (dir .&. 7 : U32), rider_code(lk), True{})}
    case False{} _:
      t

def RT.add(g: C.Guest, +rs: +List<C.Ride>, t: RT) -> RT:
  C.Guest{id, x, y, +dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, +lk, mind} = g
  RT.add.go(U32.is_eq(st, 1), U32.is_eq(C.Ride.kind(C.Rides.get(rs, tgt)), 5), dir, tgt, lk, t)

def RT.fill(+gs: +List<C.Guest>, +rs: +List<C.Ride>, t: RT) -> RT:
  match gs:
    case []:
      t
    case g <> rest:
      RT.fill(rest, rs, RT.add(g, rs, t))

def RT.of(+gs: +List<C.Guest>, +rs: +List<C.Ride>) -> RT:
  +n = C.len32(C.Ride, rs)
  RT.fill(gs, rs, RT{C.Tab.zero(n, []), C.Tab.zero(n, []), C.Tab.zero(32, []), C.Tab.zero(32, [])})

def RT.ra(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi} = t
  ra

def RT.rb(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi} = t
  rb

def RT.lo(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi} = t
  lo

def RT.hi(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi} = t
  hi

# what a ride shows: its phase and time into it, and bit 30 when it can't run
# for want of an entrance or an exit
def ride_st(r: C.Ride) -> U32:
  +r2 = r
  +k = C.Ride.kind(r2)
  +broken = Bool.not(C.Ride.shop(k)) && Bool.not(U32.is_eq(k, 0))
    && (U32.is_eq(C.Ride.ent(r2), C.NONE()) || U32.is_eq(C.Ride.ex(r2), C.NONE()))
  ((C.Ride.ph(r2) << 16n) .|. U32.min(C.Ride.tm(r2), 65535) .|. sel(broken, 1073741824, 0) : U32)

def obj_dr.go(+obj: U32, +a: U32, +b: U32, +h: U32, +i: U32, +j: U32,
  +sx: U32, +sy: U32, +k: U32, +st: U32, +rt: RT) -> +List<Dr>:
  match obj:
    case 2:
      [DTree{sx, (sy + 8 : U32), a, A.hash(i, j)}]
    case 5:
      [DGate{sx, (sy + 8 : U32)}]
    case 3:
      Bool.pick(+List<Dr>, U32.is_eq(b, 1),
        [DRide{sx, sel(U32.is_eq(C.Ride.size(k), 2), sy, (sy + 8 : U32)), k,
          C.Tab.at(RT.ra(rt), a), C.Tab.at(RT.rb(rt), a), st}], [])
    case 6:
      [DTrack{sx, sy, a, (b - h : U32)}]
    case _:
      []

def obj_dr(+t: C.Tile, +i: U32, +j: U32, +sx: U32, +sy: U32,
  +rs: +List<C.Ride>, +rt: RT) -> +List<Dr>:
  C.Tile{+h, ter, +obj, +a, +b} = t
  +rd = C.Rides.get(rs, a)
  obj_dr.go(obj, a, b, h, i, j, sx, sy, C.Ride.kind(rd), ride_st(rd), rt)

# which neighbours a path or queue joins (paths, queues, the gate, rides),
# or which neighbours of water are water: bit 1 i-1, 2 i+1, 4 j-1, 8 j+1
# mode 1: a path, joined by paths, rides, the gate, queues and track;
# 2: water's edge; 3: inside a queue line, open only along the line and to
# its ride; 4: a queue's free end, open to paths as well
def joins(+mode: U32, +q: C.Q, +i: U32, +j: U32) -> Bool:
  +t = C.Land.get(q, i, j)
  +o = C.Tile.obj(t)
  +water = U32.is_eq(C.Tile.ter(t), 2) || Bool.not(C.inmap(i, j))
  +line = U32.is_eq(o, 7) || U32.is_eq(o, 3)
  +path = line || U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 6)
  U32.is_eq(mode, 2) && water || U32.is_eq(mode, 3) && line
    || (U32.is_eq(mode, 1) || U32.is_eq(mode, 4)) && path

def nb.go(+mode: U32, +q: C.Q, +i: U32, +j: U32) -> U32:
  match mode:
    case 0:
      15
    case _:
      (sel(joins(mode, q, (i - 1 : U32), j), 1, 0) + sel(joins(mode, q, (i + 1 : U32), j), 2, 0)
        + sel(joins(mode, q, i, (j - 1 : U32)), 4, 0) + sel(joins(mode, q, i, (j + 1 : U32)), 8, 0) : U32)

def nbmask(+q: C.Q, +i: U32, +j: U32, +obj: U32, +ter: U32) -> U32:
  +qm = sel(U32.is_eq(obj, 7), sel(C.Land.qend(U32.is_eq(obj, 7), q, i, j), 4, 3), 0)
  nb.go(sel(U32.is_eq(obj, 1), 1, sel((qm > 0 : U32), qm, sel(U32.is_eq(ter, 2), 2, 0))), q, i, j)

# Entrance and exit arches: each ride's door tiles, packed tile << 4 | 1
# (entrance) or 2 (exit)
def Arches.put(+e: U32, +k: U32, +acc: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(e, C.NONE()), acc, ((e << 4n) .|. k : U32) <> acc)

def Arches.of(+rs: +List<C.Ride>) -> +List<U32>:
  match rs:
    case []:
      []
    case r <> rest:
      +r2 = r
      Arches.put(C.Ride.ent(r2), 1, Arches.put(C.Ride.ex(r2), 2, Arches.of(rest)))

def Arches.find(+ar: +List<U32>, +e: U32) -> U32:
  match ar:
    case []:
      0
    case a <> rest:
      sel(U32.is_eq((a >> 4n : U32), e), (a .&. 15 : U32), Arches.find(rest, e))

def is_ride_side(+q: C.Q, +i: U32, +j: U32) -> Bool:
  +o = C.Land.obj(q, i, j)
  U32.is_eq(o, 3) || U32.is_eq(o, 6)

# the arch stands on the edge toward the ride: 0 i-1, 1 i+1, 2 j-1, 3 j+1
def arch_side(on: Bool, +q: C.Q, +i: U32, +j: U32) -> U32:
  match on:
    case True{}:
      sel(is_ride_side(q, (i - 1 : U32), j), 0, sel(is_ride_side(q, (i + 1 : U32), j), 1,
        sel(is_ride_side(q, i, (j - 1 : U32)), 2, 3)))
    case False{}:
      0

def face(+h: U32, +nh: U32, +edge: Bool) -> U32:
  sel(edge, (h * 8 + 6 : U32), sel((h > nh : U32), ((h - nh) * 8 : U32), 0))

def push_tile(+q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>, +i: U32, +j: U32,
  +camx: U32, +camy: U32, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  +t = C.Land.get(q, i, j)
  +ak = Arches.find(ar, (i * 64 + j : U32))
  +arch = ((ak << 6n) .|. (arch_side(Bool.not(U32.is_eq(ak, 0)), q, i, j) << 4n) : U32)
  +h = C.Tile.h(t)
  +sx = scr_x(i, j, camx)
  +sy = scr_y(i, j, h, camy)
  +dl = face(h, C.Land.h(q, i, (j + 1 : U32)), U32.is_eq(j, 63))
  +dr = face(h, C.Land.h(q, (i + 1 : U32), j), U32.is_eq(i, 63))
  +blk = {DBlock{sx, sy, dl, dr, C.Tile.ter(t), C.Tile.obj(t),
    sel(U32.is_eq(hov, (i * 64 + j : U32)), 1, 0), (16 * i - 16 * j : U32),
    (8 * i + 8 * j : U32), (nbmask(q, i, j, C.Tile.obj(t), C.Tile.ter(t)) .|. arch : U32)} : Dr}
  List.append(&2, Dr, obj_dr(t, i, j, sx, sy, rs, gs), blk <> acc)

def row(+n: Nat, +i: U32, +k: U32, +q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>,
  +camx: U32, +camy: U32, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      row(p, (i + 1 : U32), k, q, rs, gs, ar, camx, camy, hov,
        push_tile(q, rs, gs, ar, i, (k - i : U32), camx, camy, hov, acc))

def Dyn.key(a: Dyn) -> U32:
  Dyn{k, d} = a
  k

def heads(+ds: +List<Dyn>, +k: U32) -> Bool:
  match ds:
    case []:
      False{}
    case d <> rest:
      U32.is_eq(Dyn.key(d), k)

def Dyn.dr(a: Dyn) -> Dr:
  Dyn{k, d} = a
  d

type DP is Data:
  DP{ds: List<&2, Dyn>, acc: List<&2, Dr>}

# move the dynamic things standing on diagonal k into the frame
def take(+ds: +List<Dyn>, go: Bool, +k: U32, +acc: +List<Dr>) -> DP:
  match ds go:
    case Con{d, rest} True{}:
      take(rest, heads(rest, k), k, Dyn.dr(d) <> acc)
    case _ _:
      DP{ds, acc}

def DP.ds(p: DP) -> +List<Dyn>:
  DP{ds, acc} = p
  ds

def DP.acc(p: DP) -> +List<Dr>:
  DP{ds, acc} = p
  acc

def diag_rows(+k: U32, +camx: U32, +camy: U32) -> U32:
  +sy0 = ((B() + 512 + 8 * k) - camy : U32)
  +vis = (sy0 + 80 > B() : U32) && (sy0 < B() + 470 : U32)
  +lo0 = C.sub0(((camx + 16 * k + 2048 - 1320) >> 5n : U32), 64)
  +hi0 = C.sub0(((camx + 16 * k + 2048 - 728) >> 5n : U32), 64)
  +lo = U32.max(lo0, C.sub0(k, 63))
  +hi = U32.min(U32.min(hi0, k), 63)
  sel(vis && (hi >= lo : U32), ((hi - lo + 1) * 256 + lo : U32), 0)

def diags(+n: Nat, +k: U32, +q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>,
  +camx: U32, +camy: U32, +hov: U32, +ds: +List<Dyn>, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +r = diag_rows(k, camx, camy)
      +acc2 = row(U32.to_nat((r >> 8n : U32)), (r .&. 255 : U32), k, q, rs, gs, ar,
        camx, camy, hov, acc)
      +dp = take(ds, heads(ds, k), k, acc2)
      diags(p, (k + 1 : U32), q, rs, gs, ar, camx, camy, hov, DP.ds(dp), DP.acc(dp))

# guests on screen, keyed by their diagonal
def shopping(+st: U32, +tgt: U32, +rs: +List<C.Ride>) -> Bool:
  +k = C.Ride.kind(C.Rides.get(rs, tgt))
  U32.is_eq(st, 1) && (U32.is_eq(k, 3) || U32.is_eq(k, 4))

def guest_dyn(+g: C.Guest, +q: C.Q, +rs: +List<C.Ride>, +camx: U32, +camy: U32,
  +t: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  C.Guest{+id, +x, +y, +dir, +st, +tgt, tmr, cash, +hu, +th, +en, +na, +ha, +lk, +mind} = g
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +h = C.Land.h(q, i, j)
  +sx = ((B() + 1280 + x) - (y + camx) : U32)
  +sy = ((B() + 512 + ((x + y) >> 1n)) - (8 * h + camy) : U32)
  +walker = U32.is_eq(st, 0) || U32.is_eq(st, 2) || shopping(st, tgt, rs)
  +vis = (sx + 8 > B() : U32) && (sx < B() + 520 : U32) && (sy + 4 > B() : U32)
    && (sy < B() + 340 : U32) && walker
  # the drawn look: outfit, carried item, stepping (bits 0-9, 16-17, 24),
  # facing (12-13), and now and then a thought (20-22)
  +mood = sel((na > 120 : U32), 3, sel((hu > 170 : U32), 1, sel((th > 170 : U32), 2,
    sel((en < 50 : U32), 4, sel((ha < 70 : U32), 5, sel((ha > 215 : U32), 6, 0))))))
  +think = U32.is_eq((((t + id * 37) >> 6n) .&. 15 : U32), 0)
  # a fresh thought (the last three seconds) shows in the bubble first
  +code = C.Mind.code(mind)
  +fresh = Bool.not(U32.is_eq(code, 0)) && ((((t >> 4n) - C.Mind.when(mind)) .&. 65535) < 12 : U32)
  +evicon = sel(U32.is_eq(code, 1), 7, sel(U32.is_eq(code, 2), 8, sel(U32.is_eq(code, 3), 6, 3)))
  +keep = sel(U32.is_eq(st, 1), 197631, 16974847)
  +look = ((lk .&. keep) .|. ((dir .&. 3) << 12n) .|. (sel(fresh, evicon, sel(think, mood, 0)) << 20n) : U32)
  Bool.pick(+List<Dyn>, vis, Dyn{(i + j : U32), DGuest{sx, sy, look, (t + id : U32)}} <> acc, acc)

def guests_dyn(+gs: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +camx: U32,
  +camy: U32, +t: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  match gs:
    case []:
      acc
    case g <> rest:
      guests_dyn(rest, q, rs, camx, camy, t, guest_dyn(g, q, rs, camx, camy, t, acc))

# a point along the coaster: world position (1/16 tile) and height (px)
def ash8(+v: U32) -> U32:
  sel(A.neg(v), ((v >> 8n) .|. 4278190080 : U32), (v >> 8n : U32))

def entry_u(+x: U32, +d: U32) -> U32:
  (16 * x + sel(U32.is_eq(d, 0), 0, sel(U32.is_eq(d, 2), 16, 8)) : U32)

def entry_v(+y: U32, +d: U32) -> U32:
  (16 * y + sel(U32.is_eq(d, 1), 0, sel(U32.is_eq(d, 3), 16, 8)) : U32)

def exit_u(+x: U32, +d: U32) -> U32:
  (16 * x + sel(U32.is_eq(d, 0), 16, sel(U32.is_eq(d, 2), 0, 8)) : U32)

def exit_v(+y: U32, +d: U32) -> U32:
  (16 * y + sel(U32.is_eq(d, 1), 16, sel(U32.is_eq(d, 3), 0, 8)) : U32)

def car_dyn(+pc: C.Piece, +f: U32, +lead: U32, +camx: U32, +camy: U32, +rd: U32,
  +acc: +List<Dyn>) -> +List<Dyn>:
  C.Piece{+x, +y, +z, +kind, +d} = pc
  +d2 = C.Pose.d(C.Piece.exit(pc))
  +u0 = entry_u(x, d)
  +v0 = entry_v(y, d)
  +u = (u0 + ash8(((exit_u(x, d2) - u0) * f : U32)) : U32)
  +v = (v0 + ash8(((exit_v(y, d2) - v0) * f : U32)) : U32)
  +dz = sel(U32.is_eq(kind, 1) || U32.is_eq(kind, 6), 8, sel(U32.is_eq(kind, 2), (0 - 8 : U32), 0))
  +zp = (z * 8 + ash8((dz * f : U32)) : U32)
  +sx = ((B() + 1280 + u) - (v + camx) : U32)
  +sy = ((B() + 512 + ((u + v) >> 1n)) - (zp + camy) : U32)
  Dyn{((u >> 4n) + (v >> 4n) : U32), DCar{sx, sy, sel((f > 128 : U32), d2, d), lead, rd}} <> acc

def car_riders(+four: U32, +car: U32) -> U32:
  sel(U32.is_eq(car, 0), (four .&. 65535 : U32), (four >> 16n : U32))

def cars_of(+n: Nat, +ps: +List<C.Piece>, +total: U32, +pos: U32, +lead: U32,
  +camx: U32, +camy: U32, +car: U32, +lo: U32, +hi: U32, +acc: +List<Dyn>)
  -> +List<Dyn>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +q = (pos % total : U32)
      +rd = sel((car < 2 : U32), car_riders(lo, car), (hi .&. 65535 : U32))
      cars_of(p, ps, total, ((pos + total - 300) : U32), 0, camx, camy, (car + 1 : U32),
        lo, hi, car_dyn(C.Pieces.get(ps, (q >> 8n : U32)), (q .&. 255 : U32), lead, camx,
          camy, rd, acc))

def trains_one(+s: C.Slot, +ps: +List<C.Piece>, +total: U32, +camx: U32,
  +camy: U32, +rt: RT, +acc: +List<Dyn>) -> +List<Dyn>:
  match s:
    case C.Free{a, n, st}:
      acc
    case C.Held{+a, n, st, t}:
      C.Train{+id, prog, sp, w} = t
      cars_of(3n, ps, total, (a * 256 + prog : U32), 1, camx, camy, 0,
        C.Tab.at(RT.lo(rt), id), C.Tab.at(RT.hi(rt), id), acc)

# Text and the HUD
# ----------------

def trains_dyn(+ss: +List<C.Slot>, +ps: +List<C.Piece>, +total: U32, +camx: U32,
  +camy: U32, +rt: RT, +acc: +List<Dyn>) -> +List<Dyn>:
  match ss:
    case []:
      acc
    case s <> rest:
      trains_dyn(rest, ps, total, camx, camy, rt,
        trains_one(s, ps, total, camx, camy, rt, acc))

def text(s: String, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, rest}:
      DGlyph{x, y, F.Font.glyph(c), col} <> text(rest, (x + 4 : U32), y, col, acc)

def money(+c: U32) -> String:
  Bool.pick(String, A.neg(c), "*-" ++ U32.show((0 - c : U32)), "*" ++ U32.show(c))

def tool_name(+t: U32) -> String:
  match t:
    case 1:
      "PATH  10*"
    case 2:
      "RAISE LAND  20*"
    case 3:
      "LOWER LAND  20*"
    case 4:
      "ENCHANTED TREE  15*   R: KIND"
    case 5:
      "DRAGON CAROUSEL  900*"
    case 6:
      "ARCANE SPIRE  1200*"
    case 7:
      "POTION STALL  300*"
    case 8:
      "TROLL TAVERN  400*"
    case 9:
      "DEMOLISH"
    case 10:
      "WYRM COASTER  40* A PIECE"
    case 11:
      "QUEUE LINE  12*"
    case _:
      "INSPECT: CLICK A RIDE (OR RIGHT-CLICK)"

def msg_text(+m: U32) -> String:
  match m:
    case 1:
      "BUILT!"
    case 2:
      "YOU CAN'T BUILD THAT THERE"
    case 3:
      "THE REALM IS SAVED  (ELDERGROVE.SAV)"
    case 4:
      "SAVE LOADED"
    case 5:
      "NO SAVE FOUND"
    case 6:
      "THE WYRM COASTER OPENS!"
    case 7:
      "THE WYRM COASTER CLOSES"
    case 8:
      "BORROWED 1000 GOLD"
    case 9:
      "REPAID 1000 GOLD"
    case 10:
      "THE BANK SAYS NO"
    case 11:
      "MUSIC ON  (M)"
    case 12:
      "MUSIC OFF  (M)"
    case 13:
      "SOUNDS ON  (N)"
    case 14:
      "SOUNDS OFF  (N)"
    case _:
      ""

def icons(+n: Nat, +k: U32, +tool: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      icons(p, (k + 1 : U32), tool,
        DIcon{(B() + 4 + (k - 1) * 24 : U32), (B() + 294 : U32), k, sel(U32.is_eq(k, tool), 1, 0)} <> acc)

def happy_avg(+gs: +List<C.Guest>, +sum: U32, +n: U32) -> U32:
  match gs:
    case []:
      sel(U32.is_eq(n, 0), 0, (sum * 100 / (n * 255) : U32))
    case g <> rest:
      C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
      happy_avg(rest, (sum + ha : U32), (n + 1 : U32))

def ride_name(+k: U32) -> String:
  match k:
    case 1:
      "DRAGON CAROUSEL"
    case 2:
      "ARCANE SPIRE"
    case 3:
      "POTION STALL"
    case 4:
      "TROLL TAVERN"
    case 5:
      "WYRM COASTER"
    case _:
      "RUINS"

def riders(+gs: +List<C.Guest>, +idx: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
      (sel(U32.is_eq(st, 1) && U32.is_eq(tgt, idx), 1, 0) + riders(rest, idx) : U32)

def ride_state(r: C.Ride) -> String:
  +r2 = r
  +k = C.Ride.kind(r2)
  +ph = C.Ride.ph(r2)
  Bool.pick(String, C.Ride.shop(k), "",
    Bool.pick(String, U32.is_eq(C.Ride.ent(r2), C.NONE()), "  NEEDS AN ENTRANCE (QUEUE)",
    Bool.pick(String, U32.is_eq(C.Ride.ex(r2), C.NONE()), "  NEEDS AN EXIT (PATH)",
    Bool.pick(String, Bool.not(C.Ride.cycles(k)), "",
    Bool.pick(String, U32.is_eq(ph, 0), "  LOADING",
    Bool.pick(String, U32.is_eq(ph, 1), "  RUNNING", "  UNLOADING"))))))

def hover_info(+p: C.Park, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{+map, +guests, +rides, track, cash, time, nid, fin} = p
  +i = (hov >> 6n : U32)
  +j = (hov .&. 63 : U32)
  +t = C.Land.get(map, i, j)
  +isride = U32.is_eq(C.Tile.obj(t), 3) && (hov < 99999 : U32)
  +rd = C.Rides.get(rides, C.Tile.a(t))
  +k = C.Ride.kind(rd)
  +line = ride_name(k) ++ "  RIDERS " ++ U32.show(riders(guests, C.Tile.a(t)))
    ++ "  FEE *" ++ U32.show(C.Ride.price(rd)) ++ ride_state(rd)
  Bool.pick(+List<Dr>, isride,
    DRect{(B() + 110 : U32), (B() + 16 : U32), 300, 10, 2763330}
      <> text(line, (B() + 114 : U32), (B() + 18 : U32), 16777215, acc), acc)

def coaster_help(+tool: U32, +acc: +List<Dr>) -> +List<Dr>:
  Bool.pick(+List<Dr>, U32.is_eq(tool, 10),
    text("CLICK: STATION  W:AHEAD A/D:TURN Q:UP Z:DOWN L:LIFT BKSP:UNDO ENTER:OPEN",
      (B() + 4 : U32), (B() + 284 : U32), 12648447, acc), acc)

def T(s: String, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  text(s, (B() + x : U32), (B() + y : U32), col, acc)

def R(+x: U32, +y: U32, +w: U32, +h: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  DRect{(B() + x : U32), (B() + y : U32), w, h, col} <> acc

def button(label: String, +x: U32, +y: U32, +w: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 2 : U32), (y + 2 : U32), 16777215, R(x, y, w, 9, col, acc))

def hud(+p: C.Park, +ui: UI, +hov: U32) -> +List<Dr>:
  C.Park{map, +guests, rides, track, +cash, +time, nid, fin} = p
  UI{camx, camy, keys, mx, my, md, +tool, var, +sp, +msg, fr, +inc, last, io, +fps, tl} = ui
  +day = ((time / 120) % 30 + 1 : U32)
  +month = (time / 3600 + 1 : U32)
  +spd = sel(U32.is_eq(sp, 0), 0, sp)
  +top = text(money(cash), (B() + 4 : U32), (B() + 3 : U32), 16766282,
    text("GUESTS " ++ U32.show(C.len32(C.Guest, guests)), (B() + 72 : U32), (B() + 3 : U32), 15261888,
    text("HAPPY " ++ U32.show(happy_avg(guests, 0, 0)) ++ "%", (B() + 140 : U32), (B() + 3 : U32), 11468718,
    text("ELDERGROVE FAIRE", (B() + 212 : U32), (B() + 3 : U32), 13674751,
    text("MONTH " ++ U32.show(month) ++ " DAY " ++ U32.show(day), (B() + 300 : U32), (B() + 3 : U32), 15261888,
    text(Bool.pick(String, U32.is_eq(spd, 0), "PAUSED", Bool.pick(String, U32.is_eq(spd, 1), ">", Bool.pick(String, U32.is_eq(spd, 2), ">>", ">>>"))),
      (B() + 480 : U32), (B() + 3 : U32), 16766282,
    text(tool_name(tool), (B() + 298 : U32), (B() + 302 : U32), 16777215,
    text(msg_text(msg), (B() + 298 : U32), (B() + 310 : U32), 16766282,
    text("INCOME " ++ money(inc), (B() + 410 : U32), (B() + 3 : U32), 11468718,
    text(U32.show(fps) ++ " FPS", (B() + 4 : U32), (B() + 14 : U32), 8421504,
    button("PARK", 462, 294, 46, 5913248, button("FINANCES", 462, 305, 46, 5913248, []))))))))))))
  +bars = {DRect{B(), B(), 512, 11, 1973802} <> DRect{B(), (B() + 11 : U32), 512, 1, 13148232}
    <> DRect{B(), (B() + 291 : U32), 512, 1, 13148232}
    <> DRect{B(), (B() + 292 : U32), 512, 28, 1973802} <> [] : +List<Dr>}
  List.append(&2, Dr, top, icons(12n, 1, tool, coaster_help(tool, hover_info(p, hov, bars))))

# Windows
# -------
# kind 1: a ride's window (arg: the ride). The first window in the list is
# the one in front; x, y: its top-left corner in screen pixels.

type Win is Data:
  Win{kind: U32, x: U32, y: U32, arg: U32}

# drag: 1 while the front window is being dragged, gx, gy: where it was grabbed
type WM is Data:
  WM{wins: List<&2, Win>, drag: U32, gx: U32, gy: U32}

def WM.new() -> WM:
  WM{[], 0, 0, 0}

def Win.w(+k: U32) -> U32:
  match k:
    case 1:
      196
    case 2:
      200
    case 3:
      224
    case _:
      210

def Win.h(+k: U32) -> U32:
  match k:
    case 1:
      154
    case 2:
      132
    case 3:
      148
    case _:
      134

def Win.hit(w: Win, +mx: U32, +my: U32) -> Bool:
  Win{+k, +x, +y, a} = w
  (mx >= x : U32) && (mx < x + Win.w(k) : U32) && (my >= y : U32) && (my < y + Win.h(k) : U32)

# the front-most window under the mouse (its place in the list), or NONE
def Wins.at(+ws: +List<Win>, +mx: U32, +my: U32, +i: U32) -> U32:
  match ws:
    case []:
      C.NONE()
    case w <> rest:
      sel(Win.hit(w, mx, my), i, Wins.at(rest, mx, my, (i + 1 : U32)))

def Wins.get(+ws: +List<Win>, +i: U32) -> Win:
  match ws i:
    case Nil{} _:
      Win{0, 0, 0, 0}
    case Con{w, rest} 0:
      w
    case Con{w, rest} _:
      Wins.get(rest, (i - 1 : U32))

def Wins.drop(+ws: +List<Win>, +i: U32) -> +List<Win>:
  match ws:
    case []:
      []
    case w <> rest:
      Bool.pick(+List<Win>, U32.is_eq(i, 0), rest, w <> Wins.drop(rest, (i - 1 : U32)))

# bring window i to the front
def Wins.front(+ws: +List<Win>, +i: U32) -> +List<Win>:
  Wins.get(ws, i) <> Wins.drop(ws, i)

def Win.is(w: Win, +k: U32, +a: U32) -> Bool:
  Win{+wk, x, y, +wa} = w
  U32.is_eq(wk, k) && U32.is_eq(wa, a)

def Wins.find(+ws: +List<Win>, +k: U32, +a: U32, +i: U32) -> U32:
  match ws:
    case []:
      C.NONE()
    case w <> rest:
      sel(Win.is(w, k, a), i, Wins.find(rest, k, a, (i + 1 : U32)))

def Wins.take(+n: Nat, +ws: +List<Win>) -> +List<Win>:
  match n ws:
    case 0n _:
      []
    case 1n+m Con{w, rest}:
      w <> Wins.take(m, rest)
    case 1n+m Nil{}:
      []

# open a window (or bring it to the front if it is open); four at most
def Wins.open(+ws: +List<Win>, +k: U32, +a: U32, +x: U32, +y: U32) -> +List<Win>:
  +i = Wins.find(ws, k, a, 0)
  Bool.pick(+List<Win>, U32.is_eq(i, C.NONE()), Win{k, x, y, a} <> Wins.take(3n, ws), Wins.front(ws, i))

def Win.moved(w: Win, +x: U32, +y: U32) -> Win:
  Win{k, ox, oy, a} = w
  Win{k, x, y, a}

def WM.wins(m: WM) -> +List<Win>:
  WM{ws, d, gx, gy} = m
  ws

# Drawing windows (screen coordinates; front-most items first)

def window_box(title: String, +x: U32, +y: U32, +w: U32, +h: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(title, (x + 4 : U32), (y + 2 : U32), 16766282,
  T("X", (x + w - 7 : U32), (y + 2 : U32), 16777215,
  R((x + w - 10 : U32), (y + 1 : U32), 9, 8, 10498096,
  R((x + 1 : U32), (y + 1 : U32), (w - 2 : U32), 8, 4863024,
  R((x + 1 : U32), (y + 10 : U32), (w - 2 : U32), (h - 11 : U32), 2763330,
  R(x, y, w, h, 13148232, acc))))))

def pm(+x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  button("-", x, y, 11, 5913248, button("+", (x + 14 : U32), y, 11, 5913248, acc))

# ticks as seconds with a tenth: 90 -> "1.5S"
def secs(+t: U32) -> String:
  U32.show((t / 60 : U32)) ++ "." ++ U32.show(((t % 60) / 6 : U32)) ++ "S"

def ride_waits(+wmin: U32, +wmax: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T("MIN WAIT " ++ secs(wmin), (x + 6 : U32), (y + 52 : U32), 15261888, pm((x + 96 : U32), (y + 50 : U32),
  T("MAX WAIT " ++ secs(wmax), (x + 6 : U32), (y + 64 : U32), 15261888, pm((x + 96 : U32), (y + 62 : U32), acc))))

# hundredths as "4.19"
def cents(+v: U32) -> String:
  +c = (v % 100 : U32)
  U32.show((v / 100 : U32)) ++ Bool.pick(String, (c < 10 : U32), ".0", ".") ++ U32.show(c)

def rate_word(+v: U32) -> String:
  Bool.pick(String, (v < 200 : U32), "LOW", Bool.pick(String, (v < 400 : U32), "MEDIUM",
    Bool.pick(String, (v < 600 : U32), "HIGH", Bool.pick(String, (v < 750 : U32), "VERY HIGH", "EXTREME"))))

def rate_line(label: String, +v: U32, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 6 : U32), y, 15261888, T(cents(v) ++ "  " ++ rate_word(v), (x + 70 : U32), y, col, acc))

# excitement, intensity and nausea (shops have none; an unfinished coaster
# has none yet)
def ride_rates(+k: U32, +r: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  Bool.pick(+List<Dr>, C.Ride.shop(k), acc,
    Bool.pick(+List<Dr>, U32.is_eq(r, 0), T("RATINGS: NOT A CIRCUIT YET", (x + 6 : U32), (y + 118 : U32), 15261888, acc),
      rate_line("EXCITEMENT", C.Rate.e(r), x, (y + 116 : U32), 16766282,
      rate_line("INTENSITY", C.Rate.i(r), x, (y + 128 : U32), 16750480,
      rate_line("NAUSEA", C.Rate.n(r), x, (y + 140 : U32), 9498256, acc)))))

def Rides.kind_at(+rs: +List<C.Ride>, +k: U32, +i: U32) -> U32:
  match rs:
    case []:
      C.NONE()
    case r <> rest:
      sel(U32.is_eq(C.Ride.kind(r), k), i, Rides.kind_at(rest, k, (i + 1 : U32)))

# a ride's window: open or closed, price, riders and queue, the loading
# waits (cycling rides), and its record so far
def ride_win(+p: C.Park, +x: U32, +y: U32, +idx: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, +guests, +rides, track, cash, +time, nid, fin} = p
  +rd = C.Rides.get(rides, idx)
  +k = C.Ride.kind(rd)
  +open = U32.is_eq(C.Ride.open_flag(rd), 1)
  +age = ((time - C.Ride.born(rd)) / 3600 : U32)
  +frame = ride_rates(k, C.Ride.rate(rd), x, y, window_box(ride_name(k), x, y, 196, 154, acc))
  +waits = Bool.pick(+List<Dr>, C.Ride.cycles(k), ride_waits(C.Ride.wmin(rd), C.Ride.wmax(rd), x, y, frame), frame)
  button(Bool.pick(String, open, "OPEN", "CLOSED"), (x + 6 : U32), (y + 14 : U32), 44,
    sel(open, 3831360, 10498096),
  T(ride_state(rd), (x + 50 : U32), (y + 16 : U32), 12648447,
  T("PRICE *" ++ U32.show(C.Ride.price(rd)), (x + 6 : U32), (y + 28 : U32), 16766282,
  pm((x + 96 : U32), (y + 26 : U32),
  T("RIDERS " ++ U32.show(riders(guests, idx))
    ++ Bool.pick(String, U32.is_eq(k, 5), " (6 A TRAIN)", "/" ++ U32.show(C.Ride.seats(k)))
    ++ "   IN QUEUE " ++ U32.show(C.Ride.qlen(rd)), (x + 6 : U32), (y + 40 : U32), 15261888,
  T("CUSTOMERS " ++ U32.show(C.Ride.total(rd)), (x + 6 : U32), (y + 78 : U32), 15261888,
  T("INCOME *" ++ U32.show(C.Ride.earned(rd)), (x + 6 : U32), (y + 90 : U32), 11468718,
  T("AGE " ++ U32.show(age) ++ Bool.pick(String, U32.is_eq(age, 1), " MONTH", " MONTHS"),
    (x + 6 : U32), (y + 102 : U32), 15261888, waits))))))))

# Guests' names: from their id and class, always the same
def name_first(+n: U32) -> String:
  match n:
    case 0:
      "ALDRIC"
    case 1:
      "BRYNN"
    case 2:
      "CEDRIC"
    case 3:
      "DAGNY"
    case 4:
      "EIRA"
    case 5:
      "FENWICK"
    case 6:
      "GWEN"
    case 7:
      "HALVARD"
    case 8:
      "ISOLDE"
    case 9:
      "KESTREL"
    case 10:
      "LIORA"
    case 11:
      "MERRICK"
    case 12:
      "NESSA"
    case 13:
      "ORIN"
    case 14:
      "PELL"
    case 15:
      "QUILLON"
    case 16:
      "ROWAN"
    case 17:
      "SAOIRSE"
    case 18:
      "TAMSIN"
    case 19:
      "ULRIC"
    case 20:
      "VESNA"
    case 21:
      "WREN"
    case 22:
      "YSOLDE"
    case _:
      "BRAM"

def name_place(+n: U32) -> String:
  match n:
    case 0:
      "THORNWALL"
    case 1:
      "ASHFORD"
    case 2:
      "MIREFEN"
    case 3:
      "HOLLOWMERE"
    case 4:
      "STONEBRIDGE"
    case 5:
      "WYVERN HILL"
    case 6:
      "OAKHOLLOW"
    case 7:
      "DUNMORROW"
    case 8:
      "BRIARWOOD"
    case 9:
      "COLDHARBOR"
    case 10:
      "FERNDALE"
    case 11:
      "GREYMOOR"
    case 12:
      "HIGHCRAG"
    case 13:
      "MOSSGATE"
    case 14:
      "RAVENSKEEP"
    case _:
      "SILVERBROOK"

def name_epithet(+n: U32) -> String:
  match n:
    case 0:
      "WISE"
    case 1:
      "WANDERER"
    case 2:
      "STARGAZER"
    case 3:
      "UNHURRIED"
    case 4:
      "RED"
    case 5:
      "MUMBLER"
    case 6:
      "LEARNED"
    case _:
      "PATIENT"

def name_clan(+n: U32) -> String:
  match n:
    case 0:
      "IRONBEARD"
    case 1:
      "STONEFIST"
    case 2:
      "COPPERHELM"
    case 3:
      "DEEPDELVER"
    case 4:
      "ANVILSON"
    case 5:
      "GRIMBRAID"
    case 6:
      "OREHAND"
    case _:
      "FLINTBROW"

def guest_name.go(+cls: U32, +h: U32, first: String) -> String:
  match cls:
    case 0:
      first ++ " THE " ++ name_epithet(((h >> 8n) .&. 7 : U32))
    case 1:
      Bool.pick(String, U32.is_eq((h .&. 32 : U32), 0), "SIR ", "DAME ") ++ first ++ " OF " ++ name_place(((h >> 12n) .&. 15 : U32))
    case 2:
      first ++ " OF " ++ name_place(((h >> 16n) .&. 15 : U32))
    case _:
      first ++ " " ++ name_clan(((h >> 20n) .&. 7 : U32))

def guest_name(+id: U32, +lk: U32) -> String:
  +h = C.hash(id, 91)
  guest_name.go((lk .&. 3 : U32), h, name_first((h % 24 : U32)))

# the guest with this id (a nobody with id NONE when they have left)
def Guests.find(+gs: +List<C.Guest>, +id: U32) -> C.Guest:
  match gs:
    case []:
      C.Guest{C.NONE(), 0, 0, 0, 3, C.NONE(), 0, 0, 0, 0, 0, 0, 0, 0, 0}
    case g <> rest:
      Bool.pick(C.Guest, U32.is_eq(C.Guest.id(g), id), g, Guests.find(rest, id))

def the_ride(+rs: +List<C.Ride>, +i: U32) -> String:
  "THE " ++ ride_name(C.Ride.kind(C.Rides.get(rs, i)))

# what a guest is doing
def activity(+st: U32, +tgt: U32, +onq: Bool, +rs: +List<C.Ride>) -> String:
  +shop = C.Ride.shop(C.Ride.kind(C.Rides.get(rs, tgt)))
  Bool.pick(String, U32.is_eq(st, 1), Bool.pick(String, shop, "BUYING AT ", "RIDING ") ++ the_ride(rs, tgt),
    Bool.pick(String, U32.is_eq(st, 2), "HEADING HOME",
      Bool.pick(String, U32.is_eq(tgt, C.NONE()), "WANDERING",
        Bool.pick(String, onq, "QUEUING FOR ", "HEADING FOR ") ++ the_ride(rs, tgt))))

def event_text(+code: U32, nm: String) -> String:
  match code:
    case 1:
      "NOT PAYING THAT FOR " ++ nm
    case 2:
      "WAITED TOO LONG FOR " ++ nm
    case 3:
      nm ++ " WAS GREAT!"
    case _:
      nm ++ " WAS TOO INTENSE"

def opt(on: Bool, s: String, +rest: +List<String>) -> +List<String>:
  Bool.pick(+List<String>, on, s <> rest, rest)

# thoughts: the latest (for a month), then how they feel
def thoughts(+mind: U32, +t: U32, +hu: U32, +th: U32, +na: U32, +en: U32, +ha: U32,
  +rs: +List<C.Ride>) -> +List<String>:
  +code = C.Mind.code(mind)
  +recent = Bool.not(U32.is_eq(code, 0)) && ((((t >> 4n) - C.Mind.when(mind)) .&. 65535) < 225 : U32)
  opt(recent, event_text(code, the_ride(rs, C.Mind.ride(mind))),
  opt((hu > 170 : U32), "I'M HUNGRY", opt((th > 170 : U32), "I'M THIRSTY",
  opt((na > 120 : U32), "I FEEL SICK", opt((en < 50 : U32), "I'M TIRED",
  opt((ha < 70 : U32), "I'M NOT HAVING FUN", opt((ha > 215 : U32), "WHAT A WONDERFUL PARK!", [])))))))

def lines(+n: Nat, +xs: +List<String>, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n xs:
    case 0n _:
      acc
    case 1n+m Nil{}:
      acc
    case 1n+m Con{s, rest}:
      T(s, x, y, 16777215, lines(m, rest, x, (y + 10 : U32), acc))

def need_bar(label: String, +v: U32, +col: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 6 : U32), y, 15261888,
  R((x + 70 : U32), y, U32.max((U32.min(v, 255) * 100 / 255 : U32), 1), 5, col,
  R((x + 70 : U32), y, 100, 5, 4210752, acc)))

def carrying(+lk: U32) -> String:
  +it = ((lk >> 16n) .&. 3 : U32)
  Bool.pick(String, U32.is_eq(it, 1), "A POTION", Bool.pick(String, U32.is_eq(it, 2), "A TANKARD OF ALE", "NOTHING"))

def guest_win.go(g: C.Guest, +p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Guest{+id, +gx, +gy, dir, +st, +tgt, tmr, +cash, +hu, +th, +en, +na, +ha, +lk, +mind} = g
  C.Park{map, guests, +rides, track, cash0, +time, nid, fin} = p
  +gone = U32.is_eq(id, C.NONE())
  +onq = U32.is_eq(C.Land.obj(map, (gx >> 4n : U32), (gy >> 4n : U32)), 7)
  +frame = window_box(Bool.pick(String, gone, "AN ADVENTURER", guest_name(id, lk)), x, y, 210, 134, acc)
  Bool.pick(+List<Dr>, gone, T("HAS LEFT THE PARK", (x + 6 : U32), (y + 16 : U32), 12648447, frame),
    T(activity(st, tgt, onq, rides), (x + 6 : U32), (y + 15 : U32), 12648447,
    lines(3n, thoughts(mind, time, hu, th, na, en, ha, rides), (x + 6 : U32), (y + 28 : U32),
    need_bar("HAPPINESS", ha, 7324480, x, (y + 62 : U32),
    need_bar("ENERGY", en, 16766282, x, (y + 72 : U32),
    need_bar("HUNGER", hu, 14168128, x, (y + 82 : U32),
    need_bar("THIRST", th, 4227327, x, (y + 92 : U32),
    need_bar("NAUSEA", na, 9498256, x, (y + 102 : U32),
    T("GOLD *" ++ U32.show(cash) ++ "   CARRYING " ++ carrying(lk), (x + 6 : U32), (y + 118 : U32), 16766282,
      frame)))))))))

def guest_win(+p: C.Park, +x: U32, +y: U32, +gid: U32, +acc: +List<Dr>) -> +List<Dr>:
  guest_win.go(Guests.find(C.Park.guests(p), gid), p, x, y, acc)

# the guest count over the last four months: 32 bars, newest on the right
def graph(+hs: +List<U32>, +i: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  match hs:
    case []:
      acc
    case v <> rest:
      +h = U32.max(U32.min((v * 50 / 700 : U32), 50), 1)
      graph(rest, (i + 1 : U32), x, y,
        R((x + (31 - i) * 5 : U32), (y + 50 - h : U32), 4, h, 7324480, acc))

# the park: its rating, guests, entry fee, and the guest count graph
def park_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, +guests, +rides, track, cash, time, nid, +fin} = p
  +rating = C.Fin.rating(fin)
  +frame = window_box("ELDERGROVE FAIRE", x, y, 200, 132, acc)
  T("PARK RATING " ++ U32.show(rating), (x + 6 : U32), (y + 15 : U32), 16766282,
  R((x + 96 : U32), (y + 15 : U32), U32.max((rating / 10 : U32), 1), 5, sel((rating < 400 : U32), 14163020, 7324480),
  R((x + 96 : U32), (y + 15 : U32), 100, 5, 4210752,
  T("GUESTS " ++ U32.show(C.len32(C.Guest, guests)) ++ "   HAPPY " ++ U32.show(happy_avg(guests, 0, 0)) ++ "%",
    (x + 6 : U32), (y + 28 : U32), 15261888,
  T("ENTRY FEE *" ++ U32.show(C.Fin.fee(fin)), (x + 6 : U32), (y + 42 : U32), 16766282,
  pm((x + 110 : U32), (y + 40 : U32),
  T("GUESTS, LAST FOUR MONTHS", (x + 6 : U32), (y + 58 : U32), 12648447,
  graph(C.Fin.hist(fin), 0, (x + 20 : U32), (y + 70 : U32),
  R((x + 18 : U32), (y + 70 : U32), 164, 52, 1973802, frame)))))))))

def fin_at(+xs: +List<U32>, +i: U32) -> U32:
  C.Tab.at(xs, i)

def fin_amt(+spend: Bool, +v: U32) -> String:
  Bool.pick(String, spend && (v > 0 : U32), "-*", "*") ++ U32.show(v)

# a row of the books: this month and last month (spend rows show a minus)
def fin_row(label: String, +i: U32, +spend: Bool, +now: +List<U32>, +last: +List<U32>, +x: U32, +y: U32,
  +acc: +List<Dr>) -> +List<Dr>:
  +col = sel(spend, 16750480, 11468718)
  T(label, (x + 6 : U32), y, 15261888,
  T(fin_amt(spend, fin_at(now, i)), (x + 110 : U32), y, col,
  T(fin_amt(spend, fin_at(last, i)), (x + 168 : U32), y, col, acc)))

# takings less costs (loans themselves aside)
def profit(+xs: +List<U32>) -> U32:
  (fin_at(xs, 0) + fin_at(xs, 3) + fin_at(xs, 4) + fin_at(xs, 5) + fin_at(xs, 6)
    - fin_at(xs, 1) - fin_at(xs, 2) - fin_at(xs, 9) : U32)

def fin_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, guests, rides, track, cash, time, nid, +fin} = p
  +now = C.Fin.now(fin)
  +last = C.Fin.last(fin)
  +frame = window_box("FINANCES", x, y, 224, 148, acc)
  T("THIS MONTH", (x + 110 : U32), (y + 14 : U32), 12648447,
  T("LAST MONTH", (x + 168 : U32), (y + 14 : U32), 12648447,
  fin_row("RIDE TICKETS", 0, False{}, now, last, x, (y + 26 : U32),
  fin_row("FOOD", 4, False{}, now, last, x, (y + 35 : U32),
  fin_row("DRINKS", 5, False{}, now, last, x, (y + 44 : U32),
  fin_row("ENTRY FEES", 6, False{}, now, last, x, (y + 53 : U32),
  fin_row("RIDE UPKEEP", 1, True{}, now, last, x, (y + 62 : U32),
  fin_row("CONSTRUCTION", 2, True{}, now, last, x, (y + 71 : U32),
  fin_row("REFUNDS", 3, False{}, now, last, x, (y + 80 : U32),
  fin_row("LOAN INTEREST", 9, True{}, now, last, x, (y + 89 : U32),
  T("PROFIT", (x + 6 : U32), (y + 102 : U32), 16766282,
  T(money(profit(now)), (x + 110 : U32), (y + 102 : U32), 16766282,
  T(money(profit(last)), (x + 168 : U32), (y + 102 : U32), 16766282,
  R((x + 6 : U32), (y + 99 : U32), 212, 1, 8421504,
  T("LOAN *" ++ U32.show(C.Fin.loan(fin)), (x + 6 : U32), (y + 118 : U32), 16750480,
  T("INTEREST 1/80 A MONTH", (x + 6 : U32), (y + 132 : U32), 8421504,
  button("BORROW 1000", (x + 100 : U32), (y + 116 : U32), 54, 5913248,
  button("REPAY 1000", (x + 160 : U32), (y + 116 : U32), 54, 5913248, frame))))))))))))))))))

def win_dr.go(+k: U32, +x: U32, +y: U32, +a: U32, +p: C.Park, +acc: +List<Dr>) -> +List<Dr>:
  match k:
    case 1:
      ride_win(p, x, y, a, acc)
    case 2:
      park_win(p, x, y, acc)
    case 3:
      fin_win(p, x, y, acc)
    case 4:
      guest_win(p, x, y, a, acc)
    case _:
      acc

def wins_dr(+ws: +List<Win>, +p: C.Park, +acc: +List<Dr>) -> +List<Dr>:
  match ws:
    case []:
      acc
    case w <> rest:
      Win{+k, +x, +y, +a} = w
      win_dr.go(k, x, y, a, p, wins_dr(rest, p, acc))

# Clicking in windows: 0 nothing, 1 close, 2 drag, 100 + op: a ride setting

def in_box(+lx: U32, +ly: U32, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  (lx >= x : U32) && (lx < x + w : U32) && (ly >= y : U32) && (ly < y + h : U32)

def ride_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 6, 14, 44, 9), 100,
  sel(in_box(lx, ly, 96, 26, 11, 9), 102, sel(in_box(lx, ly, 110, 26, 11, 9), 101,
  sel(in_box(lx, ly, 96, 50, 11, 9), 104, sel(in_box(lx, ly, 110, 50, 11, 9), 103,
  sel(in_box(lx, ly, 96, 62, 11, 9), 106, sel(in_box(lx, ly, 110, 62, 11, 9), 105, 0)))))))

def park_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 110, 40, 11, 9), 201, sel(in_box(lx, ly, 124, 40, 11, 9), 200, 0))

def fin_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 100, 116, 54, 9), 202, sel(in_box(lx, ly, 160, 116, 54, 9), 203, 0))

def win_code(+k: U32, +lx: U32, +ly: U32) -> U32:
  sel((ly < 10 : U32) && (lx + 10 >= Win.w(k) : U32), 1, sel((ly < 10 : U32), 2,
    sel(U32.is_eq(k, 1), ride_click(lx, ly), sel(U32.is_eq(k, 2), park_click(lx, ly),
      sel(U32.is_eq(k, 3), fin_click(lx, ly), 0)))))

# the act a window button asks for
def ride_act(+p: C.Park, +idx: U32, +op: U32) -> C.Act:
  +k = C.Ride.kind(C.Rides.get(C.Park.rides(p), idx))
  Bool.pick(C.Act, U32.is_eq(op, 0) && U32.is_eq(k, 5), C.TrackOp{8}, C.RideOp{idx, op})

def win_act(+p: C.Park, +arg: U32, +code: U32) -> +List<C.Act>:
  Bool.pick(+List<C.Act>, (code >= 200 : U32), [C.ParkOp{(code - 200 : U32)}],
    Bool.pick(+List<C.Act>, (code >= 100 : U32), [ride_act(p, arg, (code - 100 : U32))], []))

# a ride setting; opening the coaster goes through its track
type Game is Data:
  Game{park: C.Park, ui: UI, wm: WM, snd: Z.Snd}

def Dyn.is_below(+d: Dyn, +k: U32) -> Bool:
  (Dyn.key(d) < k : U32)

def dyn_put(keep: Bool, +d: Dyn, +xs: +List<Dyn>) -> +List<Dyn>:
  match keep:
    case True{}:
      d <> xs
    case False{}:
      xs

# the dynamic things on diagonals below k, and from k on (order kept)
def dyn_below(+ds: +List<Dyn>, +k: U32) -> +List<Dyn>:
  match ds:
    case []:
      []
    case d <> rest:
      dyn_put(Dyn.is_below(d, k), d, dyn_below(rest, k))

def dyn_from(+ds: +List<Dyn>, +k: U32) -> +List<Dyn>:
  match ds:
    case []:
      []
    case d <> rest:
      dyn_put(Bool.not(Dyn.is_below(d, k)), d, dyn_from(rest, k))

def scene(+g: Game) -> +List<Dr>:
  Game{+p, +ui, +wm, snd} = g
  C.Park{+map, +guests, +rides, +track, cash, +time, nid, fin} = p
  C.Track{+ps, open, +bs, st, en} = track
  UI{+camx, +camy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = ui
  +hov = pick(map, ui)
  +total = (C.len32(C.Piece, ps) * 256 : U32)
  +rt = RT.of(guests, rides)
  +dyn = trains_dyn(bs, ps, U32.max(total, 1), camx, camy, rt,
    guests_dyn(guests, map, rides, camx, camy, time, []))
  +sorted = List.sort(~Dyn, ~Dyn.le, dyn)
  +ar = Arches.of(rides)
  # the back and front halves of the map are built in parallel
  hi lo = diags(63n, 64, map, rides, rt, ar, camx, camy, hov, dyn_from(sorted, 64), [])
    diags(64n, 0, map, rides, rt, ar, camx, camy, hov, dyn_below(sorted, 64), [])
  List.append(&2, Dr, wins_dr(WM.wins(wm), p, hud(p, ui, hov)), List.append(&2, Dr, hi, lo))

def Game.park(g: Game) -> C.Park:
  Game{p, ui, wm, snd} = g
  p

def frame(+g: Game) -> Image:
  R.frame(scene(g), C.Park.time(Game.park(g)))

def UI.new() -> UI:
  UI{930, 880, 0, 0, 0, 0, 12, 0, 1, 0, 0, 0, 99999, 0, 0, 0n}

def u32s(+n: U32) -> String:
  U32.show(n)

type EV is Data:
  EV{ui: UI, wm: WM, acts: List<&2, C.Act>, quit: Bool}

def key_bit(+c: U32) -> U32:
  match c:
    case 63232:
      1
    case 63233:
      2
    case 63234:
      4
    case 63235:
      8
    case _:
      0

def track_op(+c: U32) -> U32:
  match c:
    case 119:
      0
    case 113:
      1
    case 122:
      2
    case 97:
      3
    case 100:
      4
    case 108:
      6
    case 127:
      7
    case 8:
      7
    case 13:
      8
    case _:
      99

def paint_tool(+t: U32) -> Bool:
  (t < 5 : U32) || U32.is_eq(t, 9)

def build_act(+q: C.Q, +ui: UI) -> +List<C.Act>:
  UI{camx, camy, keys, mx, my, md, +tool, +var, sp, msg, fr, inc, last, io, fps, tl} = ui
  +hov = pick(q, ui)
  Bool.pick(+List<C.Act>, (hov < 99999 : U32),
    [C.Build{tool, (hov >> 6n : U32), (hov .&. 63 : U32), var}], [])

def on_key(+c: U32, +down: Bool, +ui: UI, +wm: WM, +q: C.Q) -> EV:
  UI{cx, cy, +keys, mx, my, md, +tool, +var, +sp, +msg, fr, inc, last, +io, fps, tl} = ui
  WM{+ws, +dg, +gx, +gy} = wm
  # Esc closes the front window; with none open, it quits
  +esc = down && U32.is_eq(c, 27)
  +haswin = Bool.not(U32.is_eq(C.len32(Win, ws), 0))
  +kb = key_bit(c)
  +keys2 = sel(down, (keys .|. kb : U32), (keys .&. (4294967295 - kb) : U32))
  +digit = (c >= 48 : U32) && (c <= 57 : U32) && down
  +tool2 = sel(digit, sel(U32.is_eq(c, 48), 10, (c - 48 : U32)), sel(down && U32.is_eq(c, 117), 11,
    sel(down && U32.is_eq(c, 105), 12, tool)))
  # M: music on or off (var bit 16); N: effects on or off (bit 17)
  +var2 = (sel(down && U32.is_eq(c, 114), (var + 1 : U32), var)
    .^. sel(down && U32.is_eq(c, 109), 65536, 0) .^. sel(down && U32.is_eq(c, 110), 131072, 0) : U32)
  +sp2 = sel(down && U32.is_eq(c, 32), sel(U32.is_eq(sp, 0), 1, 0),
    sel(down && (U32.is_eq(c, 61) || U32.is_eq(c, 43)), U32.min((sp + 1 : U32), 3),
      sel(down && U32.is_eq(c, 45), U32.max(C.sub0(sp, 1), 1), sp)))
  +op = track_op(c)
  +tact = down && U32.is_eq(tool, 10) && (op < 99 : U32)
  +io2 = sel(down && U32.is_eq(c, 63240), 1, sel(down && U32.is_eq(c, 63244), 2, io))
  +msg2 = sel(down && U32.is_eq(c, 109), sel(U32.is_eq((var2 .&. 65536 : U32), 0), 11, 12),
    sel(down && U32.is_eq(c, 110), sel(U32.is_eq((var2 .&. 131072 : U32), 0), 13, 14), msg))
  EV{UI{cx, cy, keys2, mx, my, md, tool2, var2, sp2, msg2, fr, inc, last, io2, fps, tl},
    WM{Bool.pick(+List<Win>, esc && haswin, Wins.drop(ws, 0),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 112), Wins.open(ws, 2, 0, 150, 40),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 102), Wins.open(ws, 3, 0, 140, 30), ws))), dg, gx, gy},
    Bool.pick(+List<C.Act>, tact, [C.TrackOp{op}], []),
    esc && Bool.not(haswin)}

def UI.with_last(u: UI, +l: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, l, io, fps, tl}

# the front window, moved to (x, y), kept on the screen
def Win.kind(w: Win) -> U32:
  Win{k, x, y, a} = w
  k

def Wins.drag(+ws: +List<Win>, +x: U32, +y: U32) -> +List<Win>:
  match ws:
    case []:
      []
    case w <> rest:
      +k = Win.kind(w)
      Win.moved(w, U32.min(x, (510 - Win.w(k) : U32)), U32.min(U32.max(y, 12), (290 - Win.h(k) : U32))) <> rest

def on_move(+x: U32, +y: U32, +ui: UI, +wm: WM, +q: C.Q) -> EV:
  UI{cx, cy, keys, mx, my, +md, +tool, var, sp, msg, fr, inc, +last, io, fps, tl} = ui
  WM{+ws, +dg, +gx, +gy} = wm
  +lx = (x >> 1n : U32)
  +ly = (y >> 1n : U32)
  +dragging = U32.is_eq(dg, 1)
  +ui2 = {UI{cx, cy, keys, lx, ly, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} : UI}
  +hov = pick(q, ui2)
  +paint = U32.is_eq(md, 1) && paint_tool(tool) && Bool.not(U32.is_eq(hov, last))
    && (hov < 99999 : U32) && Bool.not(dragging)
  EV{UI.with_last(ui2, sel(paint, hov, last)),
    WM{Bool.pick(+List<Win>, dragging, Wins.drag(ws, (lx - gx : U32), (ly - gy : U32)), ws), dg, gx, gy},
    Bool.pick(+List<C.Act>, paint, build_act(q, ui2), []), False{}}

def UI.with_tool(u: UI, +t: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  UI{cx, cy, keys, mx, my, md, t, var, sp, msg, fr, inc, last, io, fps, tl}

# the ride on a tile (a ride's tile, or any coaster track), or NONE
def ride_at(+p: C.Park, +hov: U32) -> U32:
  +t = C.Land.get(C.Park.map(p), (hov >> 6n : U32), (hov .&. 63 : U32))
  +o = C.Tile.obj(t)
  sel((hov >= 99999 : U32), C.NONE(), sel(U32.is_eq(o, 3), C.Tile.a(t),
    sel(U32.is_eq(o, 6), Rides.kind_at(C.Park.rides(p), 5, 0), C.NONE())))

# inspecting: a ride's window opens beside the mouse
def open_at(+ws: +List<Win>, +p: C.Park, +hov: U32, +lx: U32, +ly: U32) -> +List<Win>:
  +idx = ride_at(p, hov)
  Bool.pick(+List<Win>, U32.is_eq(idx, C.NONE()), ws,
    Wins.open(ws, 1, idx, U32.min((lx + 12 : U32), 312), U32.min(U32.max(C.sub0(ly, 30), 14), 136)))

# a click on the map or the toolbar. The inspect tool (or the right button,
# with any tool) opens a ride's window; other tools build.
# the walking guest nearest the mouse (within 7 px), or NONE
def Guests.near(+gs: +List<C.Guest>, +q: C.Q, +camx: U32, +camy: U32, +lx: U32, +ly: U32,
  +best: U32, +bd: U32) -> U32:
  match gs:
    case []:
      best
    case g <> rest:
      C.Guest{+id, +x, +y, dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
      +h = C.Land.h(q, (x >> 4n : U32), (y >> 4n : U32))
      +sx = ((1280 + x) - (y + camx) : U32)
      +sy = ((512 + ((x + y) >> 1n)) - (8 * h + camy + 6) : U32)
      +d = (C.absd(sx, lx) + C.absd(sy, ly) : U32)
      +take = (U32.is_eq(st, 0) || U32.is_eq(st, 2)) && (d < bd : U32)
      Guests.near(rest, q, camx, camy, lx, ly, sel(take, id, best), sel(take, d, bd))

# inspecting: a guest under the mouse opens their window, else a ride's
def inspect_at(+ws: +List<Win>, +p: C.Park, +hov: U32, +lx: U32, +ly: U32, +cx: U32, +cy: U32) -> +List<Win>:
  +gid = Guests.near(C.Park.guests(p), C.Park.map(p), cx, cy, lx, ly, C.NONE(), 7)
  Bool.pick(+List<Win>, U32.is_eq(gid, C.NONE()), open_at(ws, p, hov, lx, ly),
    Wins.open(ws, 4, gid, U32.min((lx + 12 : U32), 300), U32.min(U32.max(C.sub0(ly, 30), 14), 156)))

def on_map(+lx: U32, +ly: U32, +button: U32, +down: Bool, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  UI{+cx, +cy, keys, mx, my, md, +tool, var, sp, msg, fr, inc, last, io, fps, tl} = ui
  +q = C.Park.map(p)
  +ui2 = {UI{cx, cy, keys, lx, ly, sel(down && U32.is_eq(button, 0), 1, 0), tool, var, sp, msg, fr, inc, 99999, io, fps, tl} : UI}
  +bar = (ly >= 292 : U32)
  +slot = ((lx - 4) / 24 + 1 : U32)
  +pickt = down && bar && (slot >= 1 : U32) && (slot <= 12 : U32)
  +click = down && Bool.not(bar)
  +inspect = click && (U32.is_eq(tool, 12) || Bool.not(U32.is_eq(button, 0)))
  +build = click && Bool.not(inspect)
  +hov = pick(q, ui2)
  +ui3 = UI.with_tool(UI.with_last(ui2, sel(build, hov, 99999)), sel(pickt, slot, tool))
  +ws = WM.wins(wm)
  +parkb = down && in_box(lx, ly, 462, 294, 46, 9)
  +finb = down && in_box(lx, ly, 462, 305, 46, 9)
  +ws2 = Bool.pick(+List<Win>, parkb, Wins.open(ws, 2, 0, 150, 40),
    Bool.pick(+List<Win>, finb, Wins.open(ws, 3, 0, 140, 30), ws))
  EV{ui3, WM{Bool.pick(+List<Win>, inspect, inspect_at(ws2, p, hov, lx, ly, cx, cy), ws2), 0, 0, 0},
    Bool.pick(+List<C.Act>, build, build_act(q, ui2), []), False{}}

def Win.x(w: Win) -> U32:
  Win{k, x, y, a} = w
  x

def Win.y(w: Win) -> U32:
  Win{k, x, y, a} = w
  y

def Win.arg(w: Win) -> U32:
  Win{k, x, y, a} = w
  a

# a click in window i: it comes to the front, then its close box, title bar
# (drag) or buttons act
def UI.at(u: UI, +x: U32, +y: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  UI{cx, cy, keys, x, y, md, tool, var, sp, msg, fr, inc, last, io, fps, tl}

def on_win(+wi: U32, +lx: U32, +ly: U32, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  +ws = Wins.front(WM.wins(wm), wi)
  +w = Wins.get(ws, 0)
  +wx = Win.x(w)
  +wy = Win.y(w)
  +code = win_code(Win.kind(w), (lx - wx : U32), (ly - wy : U32))
  EV{UI.at(ui, lx, ly),
    WM{Bool.pick(+List<Win>, U32.is_eq(code, 1), Wins.drop(ws, 0), ws), sel(U32.is_eq(code, 2), 1, 0),
      (lx - wx : U32), (ly - wy : U32)},
    win_act(p, Win.arg(w), code),
    False{}}

def on_mouse.go(inwin: Bool, +wi: U32, +lx: U32, +ly: U32, +button: U32, +down: Bool, +ui: UI,
  +wm: WM, +p: C.Park) -> EV:
  match inwin:
    case True{}:
      on_win(wi, lx, ly, ui, wm, p)
    case False{}:
      on_map(lx, ly, button, down, ui, wm, p)

def on_mouse(+x: U32, +y: U32, +button: U32, +down: Bool, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  +lx = (x >> 1n : U32)
  +ly = (y >> 1n : U32)
  +wi = Wins.at(WM.wins(wm), lx, ly, 0)
  on_mouse.go(down && Bool.not(U32.is_eq(wi, C.NONE())), wi, lx, ly, button, down, ui, wm, p)

def on_event(e: Event, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  match e:
    case Key{c, d}:
      on_key(c, d, ui, wm, C.Park.map(p))
    case Move{x, y}:
      on_move(x, y, ui, wm, C.Park.map(p))
    case Mouse{x, y, b, d}:
      on_mouse(x, y, b, d, ui, wm, p)
    case Close{}:
      EV{ui, wm, [], True{}}

def EV.ui(e: EV) -> UI:
  EV{ui, wm, acts, quit} = e
  ui

def EV.wm(e: EV) -> WM:
  EV{ui, wm, acts, quit} = e
  wm

def EV.acts(e: EV) -> +List<C.Act>:
  EV{ui, wm, acts, quit} = e
  acts

def EV.quit(e: EV) -> Bool:
  EV{ui, wm, acts, quit} = e
  quit

def on_events(es: List<Event>, +ui: UI, +wm: WM, +p: C.Park, +acts: +List<C.Act>, quit: Bool)
  -> EV:
  match es:
    case []:
      EV{ui, wm, acts, quit}
    case e <> rest:
      +r = on_event(e, ui, wm, p)
      on_events(rest, EV.ui(r), EV.wm(r), p, List.append(&2, C.Act, acts, EV.acts(r)),
        quit || EV.quit(r))

# gold earned: the Gain entries of a ledger
def gains1(t: C.Txn) -> U32:
  match t:
    case C.Gain{+k, a}:
      sel(U32.is_eq(k, 1) || U32.is_eq(k, 5) || U32.is_eq(k, 6) || U32.is_eq(k, 7), a, 0)
    case C.Spend{k, a}:
      0

def gains(+xs: +List<C.Txn>) -> U32:
  match xs:
    case []:
      0
    case t <> rest:
      (gains(rest) + gains1(t) : U32)

type Res is Data:
  Res{park: C.Park, msg: U32, inc: U32}

def Res.park(r: Res) -> C.Park:
  Res{p, m, i} = r
  p

def Res.msg(r: Res) -> U32:
  Res{p, m, i} = r
  m

def Res.inc(r: Res) -> U32:
  Res{p, m, i} = r
  i

def paid(+o: C.Out) -> Bool:
  Bool.not(U32.is_eq(C.len32(C.Txn, C.Out.ledger(o)), 0))

def act_msg(+a: C.Act, +o: C.Out) -> U32:
  match a:
    case C.Tick{}:
      0
    case C.Build{t, x, y, v}:
      sel(paid(o), 1, 2)
    case C.TrackOp{+op}:
      sel(U32.is_eq(op, 8), sel(C.Track.open(C.Park.track(C.Out.park(o))), 6, 7),
        sel(paid(o), 0, 2))
    case C.RideOp{r, op}:
      0
    case C.ParkOp{+op}:
      sel(U32.is_eq(op, 2), sel(paid(o), 8, 10), sel(U32.is_eq(op, 3), sel(paid(o), 9, 10), 0))

def apply(+acts: +List<C.Act>, +p: C.Park, +msg: U32, +inc: U32) -> Res:
  match acts:
    case []:
      Res{p, msg, inc}
    case a <> rest:
      +o = C.Park.step(p, a)
      +m = act_msg(a, o)
      apply(rest, C.Out.park(o), sel(U32.is_eq(m, 0), msg, m),
        (inc + gains(C.Out.ledger(o)) : U32))

def ticks(+n: Nat, +p: C.Park, +inc: U32) -> Res:
  match n:
    case 0n:
      Res{p, 0, inc}
    case 1n+k:
      +o = C.Park.step(p, C.Tick{})
      ticks(k, C.Out.park(o), (inc + gains(C.Out.ledger(o)) : U32))

def cam(+keys: U32, +v: U32, +minus: U32, +plus: U32) -> U32:
  +m = Bool.not(U32.is_eq((keys .&. minus : U32), 0))
  +pl = Bool.not(U32.is_eq((keys .&. plus : U32), 0))
  U32.min(U32.max(sel(m, (v - 8 : U32), sel(pl, (v + 8 : U32), v)), 200), 1900)

# Sound events: what changed this frame, for the synthesizer (see Z.Snd.cue)
def Rides.started(+a: +List<C.Ride>, +b: +List<C.Ride>) -> U32:
  match a b:
    case Con{r0, ra} Con{r1, rb}:
      +k = C.Ride.kind(r1)
      +go = Bool.not(U32.is_eq(C.Ride.ph(r0), 1)) && U32.is_eq(C.Ride.ph(r1), 1)
      (sel(go, sel(U32.is_eq(k, 1), 2, sel(U32.is_eq(k, 2), 4, 0)), 0) .|. Rides.started(ra, rb) : U32)
    case _ _:
      0

# the coaster: its fastest train (0..255) | a train climbing a lift hill << 8
def Snd.slot(sl: C.Slot, +ps: +List<C.Piece>, +acc: U32) -> U32:
  match sl:
    case C.Free{a, n, st}:
      acc
    case C.Held{+a, n, st, t}:
      C.Train{id, +prog, +speed, wait} = t
      +k = C.Piece.kind(C.Pieces.get(ps, (a + (prog >> 8n) : U32)))
      +roar = U32.min((speed * 255 / 90 : U32), 255)
      +lift = U32.is_eq(k, 6) && (speed > 0 : U32)
      (U32.max((acc .&. 255 : U32), roar) .|. (acc .&. 256) .|. sel(lift, 256, 0) : U32)

def Snd.slots(+ss: +List<C.Slot>, +ps: +List<C.Piece>, +acc: U32) -> U32:
  match ss:
    case []:
      acc
    case sl <> rest:
      Snd.slots(rest, ps, Snd.slot(sl, ps, acc))

def snd_word(+p0: C.Park, +p1: C.Park, +inc0: U32, +inc1: U32, +msg0: U32, +msg1: U32,
  +clicked: Bool, +var: U32) -> U32:
  C.Park{m0, g0, +rs0, t0, c0, +time0, n0, f0} = p0
  C.Park{m1, +gs1, +rs1, +tr1, c1, +time1, n1, f1} = p1
  C.Track{+ps, open, +ss, st, en} = tr1
  +fresh = Bool.not(U32.is_eq(msg1, msg0))
  +coin = (inc1 > inc0 : U32) || fresh && (U32.is_eq(msg1, 8) || U32.is_eq(msg1, 9))
  +thud = fresh && U32.is_eq(msg1, 1)
  +buzz = fresh && (U32.is_eq(msg1, 2) || U32.is_eq(msg1, 10))
  +go = Rides.started(rs0, rs1)
  +bell = Bool.not(U32.is_eq((go .&. 2 : U32), 0)) || fresh && U32.is_eq(msg1, 6)
  +whoosh = Bool.not(U32.is_eq((go .&. 4 : U32), 0))
  +chime = Bool.not(U32.is_eq((time0 / 3600 : U32), (time1 / 3600 : U32)))
  +crowd = U32.min((C.len32(C.Guest, gs1) / 3 : U32), 255)
  +tr = Snd.slots(ss, ps, 0)
  (sel(coin, 1, 0) .|. sel(clicked, 2, 0) .|. sel(thud, 4, 0) .|. sel(buzz, 8, 0) .|. sel(bell, 16, 0)
    .|. sel(whoosh, 32, 0) .|. sel(chime, 64, 0) .|. (crowd << 8n) .|. ((tr .&. 255) << 16n)
    .|. (((tr >> 8n) .&. 1) << 24n) .|. (((var >> 16n) .&. 3) << 25n) : U32)

def step_game.go(+p: C.Park, +ui: UI, +wm: WM, +acts: +List<C.Act>, quit: Bool,
  snd: Z.Snd, +clicked: Bool) -> Maybe<Game>:
  UI{+cx, +cy, +keys, mx, my, md, tool, +var, +sp, +msg, +fr, +inc, last, io, fps, tl} = ui
  +r1 = apply(acts, p, msg, inc)
  +r2 = ticks(U32.to_nat(sp), Res.park(r1), Res.inc(r1))
  +time = C.Park.time(Res.park(r2))
  +newmonth = U32.is_eq((time % 3600 : U32), 0)
  +m2 = sel(U32.is_eq((fr .&. 255 : U32), 0), 0, Res.msg(r1))
  +ui2 = {UI{cam(keys, cx, 4, 8), cam(keys, cy, 1, 2), keys, mx, my, md, tool,
    var, sp, sel(U32.is_eq(Res.msg(r1), msg), m2, Res.msg(r1)), (fr + 1 : U32),
    sel(newmonth, 0, Res.inc(r2)), last, io, fps, tl} : UI}
  +word = snd_word(p, Res.park(r2), inc, Res.inc(r2), msg, Res.msg(r1), clicked, var)
  Bool.pick(Maybe<Game>, quit, None{}, Some{Game{Res.park(r2), ui2, wm, Z.Snd.cue(snd, word)}})

def UI.tool(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  tool

def step_game(+g: Game, events: List<Event>) -> Maybe<Game>:
  Game{+p, +ui, +wm, snd} = g
  +ev = on_events(events, ui, wm, p, [], False{})
  # a click: an act, a window opened or closed, or another tool
  +clicked = Bool.not(U32.is_eq(C.len32(C.Act, EV.acts(ev)), 0))
    || Bool.not(U32.is_eq(C.len32(Win, WM.wins(EV.wm(ev))), C.len32(Win, WM.wins(wm))))
    || Bool.not(U32.is_eq(UI.tool(EV.ui(ev)), UI.tool(ui)))
  step_game.go(p, EV.ui(ev), EV.wm(ev), EV.acts(ev), EV.quit(ev), snd, clicked)

# The starting park
# -----------------

def coaster_acts() -> List<C.Act>:
  [C.Build{10, 16, 38, 0}, C.TrackOp{5}, C.TrackOp{5}, C.TrackOp{6},
   C.TrackOp{6}, C.TrackOp{6}, C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{2},
   C.TrackOp{2}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{0},
   C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0},
   C.TrackOp{2}, C.TrackOp{4}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0},
   C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{8}]

def start_acts() -> List<C.Act>:
  [C.Build{5, 33, 30, 0}, C.Build{6, 31, 40, 0}, C.Build{7, 33, 44, 0},
   C.Build{8, 31, 48, 0}, C.Build{7, 13, 26, 0}, C.Build{6, 33, 24, 0},
   C.Build{8, 51, 30, 0}, C.Build{5, 47, 37, 0}]

def Game.new() -> Game:
  +p0 = C.Park.run(start_acts(), C.Park.new())
  +p1 = C.Park.run(coaster_acts(), p0)
  Game{p1, UI.new(), WM.new(), Z.Snd.new()}

# The app
# -------

def view(g: Game) -> Game & Image:
  +g2 = g
  (g2, frame(g2))

def UI.clock(u: UI, +now: Nat) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, +fr, inc, last, io, +fps, +tl} = u
  +due = U32.is_eq((fr .&. 31 : U32), 0)
  +dt = U32.from_nat(Nat.sub(now, tl))
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io,
    sel(due, (32000 / U32.max(dt, 1) : U32), fps), Bool.pick(Nat, due, now, tl)}

def Game.clock(g: Game, +now: Nat) -> Game:
  Game{p, ui, wm, snd} = g
  Game{p, UI.clock(ui, now), wm, snd}

def Game.clock_m(m: Maybe<Game>, +now: Nat) -> Maybe<Game>:
  match m:
    case None{}:
      None{}
    case Some{g}:
      Some{Game.clock(g, now)}

def Game.fps(g: Game) -> U32:
  Game{p, ui, wm, snd} = g
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = ui
  sel(U32.is_eq((fr .&. 127 : U32), 1), fps, 0)

def Game.say.go(quiet: Bool, +f: U32, g: Game) -> IO(Maybe<Game>):
  match quiet:
    case True{}:
      IO.pure(Maybe<Game>, Some{g})
    case False{}:
      do IO<Maybe<Game>>:
        IO.print("fps " ++ U32.show(f))
        return Some{g}

def Game.say(+f: U32, m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{g}:
      Game.say.go(U32.is_eq(f, 0), f, g)

def Game.report(m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{+g}:
      Game.say(Game.fps(g), Some{g})

# Saving and loading (F5 / F9)
# ----------------------------

def UI.io(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  io

def UI.done(u: UI, +m: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, m, fr, inc, last, 0, fps, tl}

def Game.done(g: Game, +m: U32) -> Game:
  Game{p, ui, wm, snd} = g
  Game{p, UI.done(ui, m), wm, snd}

def Game.io(g: Game) -> U32:
  Game{p, ui, wm, snd} = g
  UI.io(ui)

def SAVE_PATH() -> String:
  "eldergrove.sav"

def save.put(r: File & Result<&1, &1, U32 & String, Unit>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return Some{Game.done(g, 3)}

def save.with(r: Result<&1, &1, U32 & String, File>, +g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 5)})
    case Done{f}:
      do IO<Maybe<Game>>:
        w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, S.Save.file(Game.park(g)))
        save.put(w, g)

def load.got(m: Maybe<&2, C.Park>, g: Game) -> Maybe<Game>:
  match m:
    case None{}:
      Some{Game.done(g, 5)}
    case Some{p}:
      Game{old, ui, wm, snd} = g
      Some{Game{p, UI.done(ui, 4), WM.new(), snd}}

def load.bytes(res: Result<&1, &1, U32 & String, List<&2, U32>>, g: Game)
  -> Maybe<Game>:
  match res:
    case Fail{e}:
      Some{Game.done(g, 5)}
    case Done{bs}:
      load.got(S.Load.file(bs), g)

def load.read(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, g: Game)
  -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return load.bytes(res, g)

def load.sized.go(res: Result<&1, &1, U32 & String, U32>, f: File, g: Game)
  -> IO(Maybe<Game>):
  match res:
    case Fail{e}:
      do IO<Maybe<Game>>:
        File.close(f)
        return Some{Game.done(g, 5)}
    case Done{n}:
      do IO<Maybe<Game>>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, n)
        load.read(r, g)

def load.sized(r: File & Result<&1, &1, U32 & String, U32>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  load.sized.go(res, f, g)

def load.with(r: Result<&1, &1, U32 & String, File>, g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 5)})
    case Done{f}:
      do IO<Maybe<Game>>:
        z : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        load.sized(z, g)

def Game.do_io(+w: U32, g: Game) -> IO(Maybe<Game>):
  match w:
    case 1:
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(SAVE_PATH(), "w")
        save.with(r, g)
    case 2:
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(SAVE_PATH(), "r")
        load.with(r, g)
    case _:
      IO.pure(Maybe<Game>, Some{g})

def Game.io_m(m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{+g}:
      Game.do_io(Game.io(g), g)

def tick(events: List<Event>, g: Game) -> IO(Maybe<Game>):
  +g2 = g
  do IO<Maybe<Game>>:
    now : Nat <- IO.now()
    m : Maybe<Game> <- Game.io_m(Game.clock_m(step_game(g2, events), now))
    return m

# headless screenshots: sample the frame at logical resolution into a PPM

def sample(+d: Nat, img: Image, +x: U32, +y: U32) -> U32:
  match d img:
    case _ Pix{c}:
      c
    case 0n Qua{a, b, c, e}:
      0
    case 1n+p Qua{a, b, c, e}:
      +m = U32.shln(1, p)
      +bx = Bool.not(U32.is_eq((x .&. m : U32), 0))
      +by = Bool.not(U32.is_eq((y .&. m : U32), 0))
      sample(p, Bool.pick(Image, by, Bool.pick(Image, bx, e, c), Bool.pick(Image, bx, b, a)), x, y)

def bytes(+n: Nat, +img: Image, +i: U32, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +x = (i .&. 511 : U32)
      +y = (i >> 9n : U32)
      +c = sample(9n, img, x, y)
      bytes(p, img, (i - 1 : U32),
        ((c >> 16n) .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> (c .&. 255 : U32) <> acc)

def str_bytes(s: String) -> +List<U32>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{c}, rest}:
      c <> str_bytes(rest)

def arg_nat(s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 600n)

def arg_or(s: String, +d: U32) -> U32:
  Maybe.default(&2, U32, U32.read(s), d)

def arg_u32(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 1)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, res) = r
  File.close(f)

def shot.write(path: String, +px: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f,
      List.append(&2, U32, str_bytes("P6\n512 320\n255\n"), px))
    close_pair(r)

def UI.cam(u: UI, +x: U32, +y: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl} = u
  UI{x, y, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl}

# win: a window to show (kind * 256 + arg; 0 for none)
def shot.go(g: Game, path: String, n: Nat, +tool: U32, +cx: U32, +cy: U32, +win: U32) -> IO(Unit):
  Game{+p, ui, wm, snd} = g
  +p2 = Res.park(ticks(n, p, 0))
  +ws = Bool.pick(+List<Win>, U32.is_eq(win, 0), [], [Win{(win >> 8n : U32), 300, 40, (win .&. 255 : U32)}])
  +g2 = {Game{p2, UI.cam(UI.with_tool(UI.at(ui, 256, 150), tool), cx, cy), WM{ws, 0, 0, 0}, snd} : Game}
  shot.write(path, bytes(163840n, frame(g2), 163839, []))

def shot(path: String, n: Nat, +tool: U32, +cx: U32, +cy: U32, +win: U32) -> IO(Unit):
  shot.go(Game.new(), path, n, tool, cx, cy, win)

def is_shot(+args: +List<String>) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, "--shot")

def nth(+args: +List<String>, +i: U32) -> String:
  match args:
    case []:
      ""
    case a <> rest:
      Bool.pick(String, U32.is_eq(i, 0), a, nth(rest, (i - 1 : U32)))

# headless timing: n frames of simulation plus rendering
def bench.one(+mode: U32, +g: Game) -> U32:
  match mode:
    case 0:
      (sample(9n, frame(g), 200, 150) .&. 1 : U32)
    case 1:
      0
    case _:
      C.len32(Dr, scene(g))

def bench.loop(+n: Nat, +mode: U32, +g: Game) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      +g2 = Maybe.default(&1, Game, step_game(g, []), g)
      (bench.one(mode, g2) + bench.loop(p, mode, g2) : U32)

def bench.go(g: Game, +n: Nat, +mode: U32) -> IO(Unit):
  +g2 = g
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : U32 = bench.loop(n, mode, g2)
    t1 : Nat <- IO.now()
    IO.print(Nat.show(n) ++ " frames in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ U32.show(r) ++ "), guests " ++ U32.show(C.len32(C.Guest, C.Park.guests(Game.park(g2)))))

# stress testing: a crowd of n extra adventurers at the gate
def crowd.go(+n: Nat, +id: U32, +t: U32, +acc: +List<C.Guest>) -> +List<C.Guest>:
  match n:
    case 0n:
      acc
    case 1n+k:
      crowd.go(k, (id + 1 : U32), t, C.Guest.new(id, (t + id * 7 : U32), 0) <> acc)

def crowd(g: Game, +n: U32) -> Game:
  Game{p, ui, wm, snd} = g
  C.Park{map, guests, rides, track, cash, +time, +nid, fin} = p
  Game{C.Park{map, crowd.go(U32.to_nat(n), nid, time, guests), rides, track, cash, time,
    (nid + n : U32), fin}, ui, wm, snd}

def warm(g: Game, +n: Nat) -> Game:
  Game{+p, +ui, wm, snd} = g
  Game{Res.park(ticks(n, p, 0)), ui, wm, snd}

def is_bench(+args: +List<String>) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, "--bench")

# The window effect: Base's Linux window with a parallel blit (win_frame.c)
def Win.frame(window: Window, image: Image) ->
  IO(Window & Image & List<Event>):
  import "./win_frame.c"
  import "./win_frame.js"

# The frame loop, pipelined: while Win.frame fills and shows frame n on a
# helper thread, a forked computation steps the game and draws frame n+1 on
# the worker pool (from the input of frame n-1: one frame of latency).
type Nx is Type:
  Nx{m: Maybe<Game>, img: Image}

def Loop.nx(m: Maybe<Game>) -> Nx:
  match m:
    case None{}:
      Nx{None{}, Pix{0}}
    case Some{g}:
      +g2 = g
      Nx{Some{g2}, frame(g2)}

def Loop.pure.go(u: Unit, +g: Game, evs: List<Event>) -> Nx:
  match u:
    case Unit{}:
      Loop.nx(step_game(g, evs))

# the next frame: drop the frame before last, step the game, draw it
def Loop.pure(old: Image, +g: Game, evs: List<Event>) -> Nx:
  Loop.pure.go(Image.drop(old), g, evs)

def Loop.compute(old: Image, g: Game, evs: List<Event>) -> IO(Nx):
  IO.bind(Unit, Nx, IO.pure(Unit, Unit{}), u => IO.pure(Nx, Loop.pure(old, g, evs)))

# the next samples, and the game with the synthesizer's state after them
def Game.sound.go(pr: Z.Snd & List<&2, F32>, p: C.Park, ui: UI, wm: WM) -> Game & List<&2, F32>:
  (s2, xs) = pr
  (Game{p, ui, wm, s2}, xs)

def Game.sound(g: Game) -> Game & List<&2, F32>:
  Game{p, ui, wm, snd} = g
  Game.sound.go(Z.Snd.render(snd), p, ui, wm)

def Game.heard(g: Game, +q: U32) -> Game:
  Game{p, ui, wm, snd} = g
  Game{p, ui, wm, Z.Snd.heard(snd, q)}

def Loop.heard(r: Audio & U32, window: Window, g: Game, img: Image, events: List<Event>,
  shown: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  (au, q) = r
  rest(window, au, Game.heard(g, q), img, events, shown)

def Loop.play(pr: Game & List<&2, F32>, window: Window, au: Audio, img: Image, events: List<Event>,
  shown: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  (g, xs) = pr
  do IO<Unit>:
    r : Audio & U32 <- Z.Snd.write(au, xs)
    Loop.heard(r, window, g, img, events, shown, rest)

def Loop.again(m: Maybe<Game>, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match m:
    case None{}:
      Window.close(window)
    case Some{g}:
      Loop.play(Game.sound(g), window, au, img, events, shown, rest)

def Loop.after.go(m: Maybe<Game>, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match m:
    case None{}:
      Window.close(window)
    case Some{g}:
      do IO<Unit>:
        now : Nat <- IO.now()
        m2 : Maybe<Game> <- Game.io_m(Game.clock_m(Some{g}, now))
        Loop.again(m2, window, au, shown, events, img, rest)

def Loop.after(shown: Window & Image & List<Event>, nx: Nx, au: Audio,
  rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit)) -> IO(Unit):
  (window, simg, events) = shown
  Nx{m, img} = nx
  Loop.after.go(m, window, au, simg, events, img, rest)

def Loop.go(fuel: Nat, window: Window, au: Audio, g: Game, img: Image, evs: List<Event>,
  old: Image) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(window)
    case 1n+f:
      do IO<Unit>:
        chan : Chan(Nx) <- IO.fork(Nx, Loop.compute(old, g, evs))
        shown : Window & Image & List<Event> <- Win.frame(window, img)
        nx : Nx <- IO.join(Nx, chan)
        Loop.after(shown, nx, au, w => a => g2 => i2 => e2 => o2 => Loop.go(f, w, a, g2, i2, e2, o2))

def Loop.run(g: Game) -> IO(Unit):
  +g2 = g
  do IO<Unit>:
    window : Window <- IO.try(Window, Window.open("Eldergrove Faire", 1024, 640))
    au : Audio <- Z.Snd.open(22050)
    Loop.go(U32.to_nat(4294967295), window, au, g2, frame(g2), [], Pix{0})

def is_arg(+args: +List<String>, s: String) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, s)

def wav.write(path: String, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes)
    close_pair(r)

def run.live(wav: Bool, +args: +List<String>) -> IO(Unit):
  match wav:
    case True{}:
      wav.write(nth(args, 1), Z.Wav.file((arg_or(nth(args, 2), 10) * 22050 : U32)))
    case False{}:
      Loop.run(Bool.pick(Game, is_arg(args, "--live"),
        warm(crowd(Game.new(), arg_or(nth(args, 1), 0)), arg_nat(nth(args, 2))), Game.new()))

def run(go: Bool, +args: +List<String>) -> IO(Unit):
  match go:
    case True{}:
      shot(nth(args, 1), arg_nat(nth(args, 2)), arg_u32(nth(args, 3)),
        arg_or(nth(args, 4), 930), arg_or(nth(args, 5), 880), arg_or(nth(args, 6), 0))
    case False{}:
      run.live(is_arg(args, "--wav"), args)

def share(xs: List<String>) -> +List<String>:
  match xs:
    case []:
      []
    case +h <> t:
      h <> share(t)

# a save/load check on a real park: save to disk, load back, compare
def words_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && words_eq(xs, ys)
    case _ _:
      False{}

def heading(+gs: +List<C.Guest>, +idx: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
      (sel(U32.is_eq(st, 0) && U32.is_eq(tgt, idx), 1, 0) + heading(rest, idx) : U32)

def ride_report(+rs: +List<C.Ride>, +gs: +List<C.Guest>, +i: U32) -> String:
  match rs:
    case []:
      ""
    case r <> rest:
      " [" ++ U32.show(i) ++ " k" ++ U32.show(C.Ride.kind(r)) ++ " open" ++ Bool.show(C.Ride.is_open(r))
        ++ " riding " ++ U32.show(riders(gs, i)) ++ " heading " ++ U32.show(heading(gs, i))
        ++ " ph" ++ U32.show(C.Ride.ph(r)) ++ " q" ++ U32.show(C.Ride.qlen(r)) ++ " total " ++ U32.show(C.Ride.total(r))
        ++ ride_state(r) ++ "]"
        ++ ride_report(rest, gs, (i + 1 : U32))

def savetest.cmp(m: Maybe<&2, C.Park>, +p: C.Park) -> String:
  match m:
    case None{}:
      "load FAILED"
    case Some{q}:
      Bool.pick(String, words_eq(S.save(q), S.save(p)), "round trip OK: "
        ++ U32.show(C.len32(U32, S.save(p))) ++ " words, "
        ++ U32.show(C.len32(C.Guest, C.Park.guests(p))) ++ " guests; riding now: carousel "
        ++ U32.show(riders(C.Park.guests(p), 0)) ++ ", spire " ++ U32.show(riders(C.Park.guests(p), 1))
        ++ ", gold " ++ U32.show(C.Park.cash(p)) ++ ride_report(C.Park.rides(p), C.Park.guests(p), 0),
        "round trip MISMATCH")

def savetest.res(res: Result<&1, &1, U32 & String, List<&2, U32>>, +p: C.Park) -> String:
  match res:
    case Fail{e}:
      "read FAILED"
    case Done{bs}:
      savetest.cmp(S.Load.file(bs), p)

def savetest.read(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +p: C.Park)
  -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    IO.print(savetest.res(res, p))

def savetest.go(+p: C.Park) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("savetest.sav", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, S.Save.file(p))
    close_pair(w)
    g : File <- IO.try(File, File.open("savetest.sav", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(g, 16000000)
    savetest.read(r, p)

def start.test(test: Bool, +args: +List<String>) -> IO(Unit):
  match test:
    case True{}:
      savetest.go(Game.park(warm(Game.new(), arg_nat(nth(args, 1)))))
    case False{}:
      run(is_shot(args), args)

# UI test: feed clicks and keys through step_game and report what changed.
# The default camera puts the carousel's tile at screen (398, 136); its
# window opens at (312, 106), so price + is at (427, 136).
def ui.step(g: Game, es: List<Event>) -> Game:
  +g2 = g
  Maybe.default(&1, Game, step_game(g2, es), g2)

def ui.click(+x: U32, +y: U32, +b: U32) -> List<Event>:
  [Mouse{(x * 2 : U32), (y * 2 : U32), b, True{}}, Mouse{(x * 2 : U32), (y * 2 : U32), b, False{}}]

def ui.report(g: Game) -> String:
  Game{+p, ui, +wm, snd} = g
  +r0 = C.Rides.get(C.Park.rides(p), 0)
  "windows " ++ U32.show(C.len32(Win, WM.wins(wm))) ++ " (front kind " ++ U32.show(Win.kind(Wins.get(WM.wins(wm), 0))) ++ "), carousel price " ++ U32.show(C.Ride.price(r0))
    ++ ", open " ++ U32.show(C.Ride.open_flag(r0)) ++ ", max wait " ++ U32.show(C.Ride.wmax(r0))
    ++ ", fee " ++ U32.show(C.Fin.fee(C.Park.fin(p))) ++ ", loan " ++ U32.show(C.Fin.loan(C.Park.fin(p)))
    ++ ", gold " ++ U32.show(C.Park.cash(p))

# each stage: what it did, then the game after it
def ui.s1(g: Game) -> Game:
  ui.step(g, ui.click(398, 136, 0))

def ui.s2(g: Game) -> Game:
  ui.step(ui.step(g, ui.click(427, 136, 0)), ui.click(427, 136, 0))

def ui.s3(g: Game) -> Game:
  ui.step(ui.step(g, ui.click(318, 124, 0)), ui.click(427, 172, 0))

def ui.s4(g: Game) -> Game:
  ui.step(g, [Key{27, True{}}])

# F opens the finances window at (140, 30): BORROW 1000 at (240, 146)
def ui.s5(g: Game) -> Game:
  ui.step(ui.step(g, [Key{102, True{}}]), ui.click(245, 150, 0))

# the PARK button, then entry fee + twice at (150 + 124, 40 + 40)
def ui.s6(g: Game) -> Game:
  ui.step(ui.step(ui.step(g, ui.click(470, 297, 0)), ui.click(278, 84, 0)), ui.click(278, 84, 0))

# where the first walking guest on screen stands (x << 16 | y, screen px)
def ui.guest_at(+gs: +List<C.Guest>, +q: C.Q, +cx: U32, +cy: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, +x, +y, dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
      +h = C.Land.h(q, (x >> 4n : U32), (y >> 4n : U32))
      +sx = ((1280 + x) - (y + cx) : U32)
      +sy = ((512 + ((x + y) >> 1n)) - (8 * h + cy + 6) : U32)
      +ok = U32.is_eq(st, 0) && (sx > 20 : U32) && (sx < 490 : U32) && (sy > 20 : U32) && (sy < 280 : U32)
      sel(ok, ((sx << 16n) .|. sy : U32), ui.guest_at(rest, q, cx, cy))

# clicking the first walking guest on screen opens their window
def ui.s7(g: Game) -> Game:
  +g2 = g
  +pos = ui.guest_at(C.Park.guests(Game.park(g2)), C.Park.map(Game.park(g2)), 930, 880)
  ui.step(g2, ui.click((pos >> 16n : U32), (pos .&. 65535 : U32), 0))

def ui.next(+k: U32, g: Game) -> Game:
  match k:
    case 1:
      ui.s2(g)
    case 2:
      ui.s3(g)
    case 3:
      ui.s4(g)
    case 4:
      ui.s5(g)
    case 5:
      ui.s6(g)
    case 6:
      ui.s7(warm(ui.step(g, [Key{27, True{}}, Key{27, True{}}]), 1500n))
    case _:
      g

# stages: 1 inspect the carousel, 2 price + twice, 3 close it and max wait +,
# 4 Esc, 5 F and borrow, 6 PARK and entry fee + twice
def ui.run(+n: Nat, +k: U32, +g: Game) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        IO.print("after stage " ++ U32.show(k) ++ ": " ++ ui.report(g))
        ui.run(m, (k + 1 : U32), ui.next(k, g))

def ui.test() -> IO(Unit):
  ui.run(7n, 1, ui.s1(Game.new()))

def start.go(bench: Bool, +args: +List<String>) -> IO(Unit):
  match bench:
    case True{}:
      bench.go(warm(crowd(Game.new(), arg_or(nth(args, 4), 0)), arg_nat(nth(args, 2))),
        arg_nat(nth(args, 1)), arg_or(nth(args, 3), 0))
    case False{}:
      Bool.pick(IO(Unit), is_arg(args, "--uitest"), ui.test(), start.test(is_arg(args, "--savetest"), args))

def start(+args: +List<String>) -> IO(Unit):
  start.go(is_bench(args), args)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(share(args))
