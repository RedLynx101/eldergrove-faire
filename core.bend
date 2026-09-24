# Eldergrove Faire -- the park simulation. Pure: no IO, no drawing.
#
# Every change to a park goes through Park.step (time passing, building,
# coaster track edits), and LAWS.bend constrains it. The code is shaped so
# the laws stay provable: each field of the park is updated by its own
# function (so a proof about one field never has to look at the others),
# money only moves through ledger entries, and coaster trains only move by
# swapping with an empty neighbouring block.
import Base

# Utilities
# ---------

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def absd(+a: U32, +b: U32) -> U32:
  sel((a > b : U32), (a - b : U32), (b - a : U32))

def sub0(+a: U32, +b: U32) -> U32:
  sel((a > b : U32), (a - b : U32), 0)

def hash(+x: U32, +y: U32) -> U32:
  +h = ((x * 374761393) + (y * 668265263) + 1442695041 : U32)
  +h2 = ((h .^. (h >> 13n)) * 1274126177 : U32)
  (h2 .^. (h2 >> 16n) : U32)

def hash3(+x: U32, +y: U32, +z: U32) -> U32:
  hash(hash(x, y), z)

# a wrapped U32 read as signed: negative when the top bit is set
def neg(+a: U32) -> Bool:
  (a >= 2147483648 : U32)

# the stat clamp: the same test the stats law checks
def cl255(+x: U32) -> U32:
  sel(U32.is_le(x, 255), x, 255)

def imp(a: Bool, b: Bool) -> Bool:
  Bool.not(a) || b

def len32(-A: Data, +xs: +List<A>) -> U32:
  match xs:
    case []:
      0
    case h <> t:
      (1 + len32(A, t) : U32)

# Tiles and the map
# -----------------
# The map is 64 x 64 tiles, kept as a depth-6 quadtree so every lookup and
# update is 6 steps and the renderer can share it freely.

def TER_GRASS() -> U32:
  0

def TER_DIRT() -> U32:
  1

def TER_WATER() -> U32:
  2

def TER_WILD() -> U32:
  4

def OBJ_NONE() -> U32:
  0

def OBJ_PATH() -> U32:
  1

def OBJ_TREE() -> U32:
  2

def OBJ_RIDE() -> U32:
  3

def OBJ_GATE() -> U32:
  5

def OBJ_TRACK() -> U32:
  6

def GATE_X() -> U32:
  32

def GATE_Y() -> U32:
  57

def NONE() -> U32:
  255

# h: height (8 px a level), ter: terrain, obj: what stands on it, a/b: its
# details (tree variant; ride index and 1 on the ride's anchor tile; track
# shape and height)
type Tile is Data:
  Tile{h: U32, ter: U32, obj: U32, a: U32, b: U32}

type Q is Data:
  QL{t: Tile}
  QN{a: Q, b: Q, c: Q, d: Q}

def Tile.h(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  h

def Tile.ter(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  ter

def Tile.obj(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  obj

def Tile.a(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  a

def Tile.b(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  b

def Q.pick(bx: Bool, by: Bool, +a: Q, +b: Q, +c: Q, +d: Q) -> Q:
  match bx by:
    case False{} False{}:
      a
    case True{} False{}:
      b
    case False{} True{}:
      c
    case True{} True{}:
      d

def Q.place(bx: Bool, by: Bool, n: Q, a: Q, b: Q, c: Q, d: Q) -> Q:
  match bx by:
    case False{} False{}:
      QN{n, b, c, d}
    case True{} False{}:
      QN{a, n, c, d}
    case False{} True{}:
      QN{a, b, n, d}
    case True{} True{}:
      QN{a, b, c, n}

def Q.bit(+x: U32, +m: U32) -> Bool:
  Bool.not(U32.is_eq((x .&. m : U32), 0))

def Q.get(+d: Nat, +q: Q, +x: U32, +y: U32, +m: U32) -> Tile:
  match d q:
    case _ QL{t}:
      t
    case 0n QN{a, b, c, e}:
      Tile{0, 0, 0, 0, 0}
    case 1n+p QN{a, b, c, e}:
      Q.get(p, Q.pick(Q.bit(x, m), Q.bit(y, m), a, b, c, e), x, y,
        (m >> 1n : U32))

def Q.set(+d: Nat, +q: Q, +x: U32, +y: U32, +m: U32, t: Tile) -> Q:
  match d q:
    case _ QL{old}:
      QL{t}
    case 0n QN{a, b, c, e}:
      QN{a, b, c, e}
    case 1n+p QN{a, b, c, e}:
      +bx = Q.bit(x, m)
      +by = Q.bit(y, m)
      Q.place(bx, by, Q.set(p, Q.pick(bx, by, a, b, c, e), x, y,
        (m >> 1n : U32), t), a, b, c, e)

def inmap(+x: U32, +y: U32) -> Bool:
  ((x < 64) && (y < 64) : U32)

def Land.get(+q: Q, +x: U32, +y: U32) -> Tile:
  Bool.pick(Tile, inmap(x, y), Q.get(6n, q, x, y, 32), Tile{0, 4, 0, 0, 0})

def Land.set(+q: Q, +x: U32, +y: U32, t: Tile) -> Q:
  Q.set(6n, q, x, y, 32, t)

def Land.h(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.h(Land.get(q, x, y))

def Land.obj(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.obj(Land.get(q, x, y))

# a guest may step onto a path or the gate at the same height
def Land.walk(+q: Q, +x: U32, +y: U32, +h: U32) -> Bool:
  +t = Land.get(q, x, y)
  +o = Tile.obj(t)
  inmap(x, y) && (U32.is_eq(o, 1) || U32.is_eq(o, 5)) && U32.is_eq(Tile.h(t), h)

# Map generation: the starting land of Eldergrove
# -----------------------------------------------

def in_rect(+x: U32, +y: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> Bool:
  ((x >= x0) && (x <= x1) && (y >= y0) && (y <= y1) : U32)

def Gen.is_path(+x: U32, +y: U32) -> Bool:
  (U32.is_eq(x, 32) && (y >= 20) && (y <= 56) : U32)
    || (U32.is_eq(y, 36) && (x >= 12) && (x <= 52) : U32)
    || (U32.is_eq(y, 20) && (x >= 12) && (x <= 52) : U32)
    || (U32.is_eq(x, 12) && (y >= 20) && (y <= 36) : U32)
    || (U32.is_eq(x, 52) && (y >= 20) && (y <= 36) : U32)
    || (U32.is_eq(y, 46) && (x >= 26) && (x <= 38) : U32)
    || in_rect(x, y, 16, 37, 16, 37)

def Gen.wild(+x: U32, +y: U32) -> Bool:
  ((x < 6) || (y < 6) || (x > 57) || (y > 57) : U32)

def Gen.lake(+x: U32, +y: U32) -> Bool:
  +dx = absd(x, 22)
  +dy = absd(y, 27)
  ((dx * dx + dy * dy) < 22 : U32) || in_rect(x, y, 14, 42, 22, 45)

def Gen.hill(+x: U32, +y: U32) -> U32:
  +dx = absd(x, 44)
  +dy = absd(y, 12)
  +d2 = (dx * dx + dy * dy : U32)
  sel((d2 < 9 : U32), 4, sel((d2 < 25 : U32), 3, sel((d2 < 49 : U32), 2, 0)))

# places the first builds need free of trees
def Gen.clear(+x: U32, +y: U32) -> Bool:
  in_rect(x, y, 13, 37, 25, 45) || in_rect(x, y, 27, 21, 37, 50)
    || in_rect(x, y, 13, 21, 18, 35) || in_rect(x, y, 30, 55, 34, 58)

def Gen.near_path(+x: U32, +y: U32) -> Bool:
  Gen.is_path(x, y) || Gen.is_path((x + 1 : U32), y)
    || Gen.is_path((x - 1 : U32), y) || Gen.is_path(x, (y + 1 : U32))
    || Gen.is_path(x, (y - 1 : U32))

def Gen.tree(+x: U32, +y: U32, +h: U32, +r: U32) -> Tile:
  Tile{h, 0, 2, (r >> 8n .&. 3 : U32), 0}

def Gen.inner(+x: U32, +y: U32) -> Tile:
  +r = hash(x, y)
  +hh = Gen.hill(x, y)
  +h = sel(Gen.lake(x, y), 0, sel((hh > 0 : U32), hh, 1))
  +gate = U32.is_eq(x, GATE_X()) && U32.is_eq(y, GATE_Y())
  +tree = Bool.not(Gen.near_path(x, y)) && Bool.not(Gen.clear(x, y))
    && Bool.not(Gen.lake(x, y)) && U32.is_eq((r .&. 7 : U32), 0)
  Bool.pick(Tile, gate, Tile{1, 1, 5, 0, 0},
    Bool.pick(Tile, Gen.lake(x, y), Tile{0, 2, 0, 0, 0},
      Bool.pick(Tile, Gen.is_path(x, y), Tile{h, 1, 1, 0, 0},
        Bool.pick(Tile, tree, Gen.tree(x, y, h, r), Tile{h, 0, 0, 0, 0}))))

def Gen.outer(+x: U32, +y: U32) -> Tile:
  +r = hash(x, y)
  +h = sel(U32.is_eq((r .&. 3 : U32), 0), 2, 1)
  +tree = Bool.not(U32.is_eq((r .&. 3 : U32), 3))
  Bool.pick(Tile, tree, Tile{h, 4, 2, (r >> 8n .&. 1 : U32), 0},
    Tile{h, 4, 0, 0, 0})

def Gen.tile(+x: U32, +y: U32) -> Tile:
  Bool.pick(Tile, Gen.wild(x, y) && Bool.not(U32.is_eq(x, GATE_X())
    && U32.is_eq(y, GATE_Y())), Gen.outer(x, y), Gen.inner(x, y))

def Q.build(+d: Nat, +x0: U32, +y0: U32) -> Q:
  match d:
    case 0n:
      QL{Gen.tile(x0, y0)}
    case 1n+p:
      +s = U32.shln(1, p)
      +x1 = (x0 + s : U32)
      +y1 = (y0 + s : U32)
      a b c e = Q.build(p, x0, y0) Q.build(p, x1, y0) Q.build(p, x0, y1)
        Q.build(p, x1, y1)
      QN{a, b, c, e}

# Rides
# -----
# kind: 0 demolished, 1 Dragon Carousel (2x2), 2 Arcane Spire, 3 Potion
# Stall, 4 Troll Tavern, 5 Wyrm Coaster (its station tile)

type Ride is Data:
  Ride{kind: U32, x: U32, y: U32, w: U32, h: U32, price: U32, open: U32}

def Ride.size(+k: U32) -> U32:
  sel(U32.is_eq(k, 1), 2, 1)

def Ride.cost(+k: U32) -> U32:
  match k:
    case 1:
      900
    case 2:
      1200
    case 3:
      300
    case 4:
      400
    case _:
      0

def Ride.fee(+k: U32) -> U32:
  match k:
    case 1:
      3
    case 2:
      4
    case 3:
      2
    case 4:
      4
    case 5:
      6
    case _:
      0

def Ride.upkeep(+k: U32) -> U32:
  match k:
    case 1:
      25
    case 2:
      35
    case 3:
      10
    case 4:
      12
    case 5:
      60
    case _:
      0

def Ride.duration(+k: U32) -> U32:
  match k:
    case 1:
      240
    case 2:
      200
    case 3:
      20
    case 4:
      40
    case 5:
      360
    case _:
      10

def Ride.fun(+k: U32) -> U32:
  match k:
    case 1:
      35
    case 2:
      45
    case 5:
      80
    case _:
      5

def Ride.thrill(+k: U32) -> U32:
  match k:
    case 1:
      8
    case 2:
      40
    case 5:
      55
    case _:
      0

def Ride.kind(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open} = r
  kind

def Ride.is_open(r: Ride) -> Bool:
  Ride{kind, x, y, w, h, price, open} = r
  U32.is_eq(open, 1) && Bool.not(U32.is_eq(kind, 0))

def Ride.price(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open} = r
  price

def Ride.cx(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open} = r
  x

def Ride.cy(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open} = r
  y

# distance from a tile to the nearest tile of the ride's footprint
def Ride.dist(r: Ride, +i: U32, +j: U32) -> U32:
  Ride{kind, +x, +y, +w, +h, price, open} = r
  +ci = U32.min(U32.max(i, x), (x + w - 1 : U32))
  +cj = U32.min(U32.max(j, y), (y + h - 1 : U32))
  (absd(i, ci) + absd(j, cj) : U32)

def Rides.get(+rs: +List<Ride>, +i: U32) -> Ride:
  match rs:
    case []:
      Ride{0, 0, 0, 1, 1, 0, 0}
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), r, Rides.get(rest, (i - 1 : U32)))

# Guests: the adventurers
# -----------------------
# x, y: position in 1/16 tile; dir: 0 +x, 1 +y, 2 -x, 3 -y; st: 0 walking,
# 1 riding (ride tgt, tmr ticks left), 2 heading home, 3 gone; tgt: the ride
# they want (NONE: none); tmr: ride time or patience; look: class/colours

type Guest is Data:
  Guest{id: U32, x: U32, y: U32, dir: U32, st: U32, tgt: U32, tmr: U32,
    cash: U32, hunger: U32, thirst: U32, energy: U32, nausea: U32,
    happy: U32, look: U32}

def Guest.clamp(g: Guest) -> Guest:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk} = g
  Guest{id, x, y, dir, st, tgt, tmr, cash, cl255(hu), cl255(th), cl255(en),
    cl255(na), cl255(ha), lk}

def Guest.ok(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk} = g
  U32.is_le(hu, 255) && U32.is_le(th, 255) && U32.is_le(en, 255)
    && U32.is_le(na, 255) && U32.is_le(ha, 255)

def Guest.gone(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk} = g
  U32.is_eq(st, 3)

def Guest.raw(+id: U32, +t: U32) -> Guest:
  +r = hash(id, t)
  Guest{id, (GATE_X() * 16 + 8 : U32), (GATE_Y() * 16 + 8 : U32),
    3, 0, NONE(), 0, (40 + (r .&. 127) : U32), (r >> 7n .&. 63 : U32),
    (r >> 13n .&. 63 : U32), (190 + (r >> 19n .&. 63) : U32), 0, 200, r}

def Guest.new(+id: U32, +t: U32) -> Guest:
  Guest.clamp(Guest.raw(id, t))

def dx_of(+d: U32) -> U32:
  match d:
    case 0:
      1
    case 2:
      4294967295
    case _:
      0

def dy_of(+d: U32) -> U32:
  match d:
    case 1:
      1
    case 3:
      4294967295
    case _:
      0

# how far from (tx, ty) a guest can get by walking on from tile (i, j),
# heading d, within n more steps (never turning straight back). A branch
# that dead-ends away from the target is worthless (99999), so guests stop
# walking into dead-end spurs. `ok`: whether (i, j) can be walked at all.
def Guest.reach(+n: Nat, ok: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +d: U32,
  +tx: U32, +ty: U32) -> U32:
  match n ok:
    case _ False{}:
      99999
    case 0n True{}:
      (absd(i, tx) + absd(j, ty) : U32)
    case 1n+p True{}:
      +back = ((d + 2) .&. 3 : U32)
      +i1 = (i + 1 : U32)
      +i0 = (i - 1 : U32)
      +j1 = (j + 1 : U32)
      +j0 = (j - 1 : U32)
      +r0 = Guest.reach(p, Bool.not(U32.is_eq(back, 0)) && Land.walk(q, i1, j, h), q, i1, j, h, 0, tx, ty)
      +r1 = Guest.reach(p, Bool.not(U32.is_eq(back, 1)) && Land.walk(q, i, j1, h), q, i, j1, h, 1, tx, ty)
      +r2 = Guest.reach(p, Bool.not(U32.is_eq(back, 2)) && Land.walk(q, i0, j, h), q, i0, j, h, 2, tx, ty)
      +r3 = Guest.reach(p, Bool.not(U32.is_eq(back, 3)) && Land.walk(q, i, j0, h), q, i, j0, h, 3, tx, ty)
      +best = U32.min(U32.min(r0, r1), U32.min(r2, r3))
      +d0 = (absd(i, tx) + absd(j, ty) : U32)
      sel((d0 <= 1 : U32), d0, sel((best < 99999 : U32), U32.min(d0, best), 99999))

# how much a guest likes stepping from tile (i, j) in direction d, heading
# for tile (tx, ty): lower is better; 99999 when it cannot step there
def Guest.score(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32, +back: U32,
  +tx: U32, +ty: U32, +r: U32) -> U32:
  +ni = (i + dx_of(d) : U32)
  +nj = (j + dy_of(d) : U32)
  +ok = Land.walk(q, ni, nj, h)
  +v = Guest.reach(12n, ok, q, ni, nj, h, d, tx, ty)
  +pen = sel(U32.is_eq(d, back), 7, 0)
  +jit = (hash(r, d) .&. 7 : U32)
  sel(ok, sel((v >= 99999 : U32), (90000 + pen : U32), (v * 4 + pen + jit : U32)), 99999)

def best2(+da: U32, +sa: U32, +db: U32, +sb: U32) -> U32:
  sel((sb < sa : U32), db, da)

def min2(+sa: U32, +sb: U32) -> U32:
  U32.min(sa, sb)

# the direction to take at a tile centre (the current one if nothing works)
def Guest.choose(+q: Q, +i: U32, +j: U32, +h: U32, +dir: U32, +tx: U32,
  +ty: U32, +r: U32) -> U32:
  +back = ((dir + 2) .&. 3 : U32)
  +s0 = Guest.score(q, i, j, h, 0, back, tx, ty, r)
  +s1 = Guest.score(q, i, j, h, 1, back, tx, ty, r)
  +s2 = Guest.score(q, i, j, h, 2, back, tx, ty, r)
  +s3 = Guest.score(q, i, j, h, 3, back, tx, ty, r)
  +d01 = best2(0, s0, 1, s1)
  +d23 = best2(2, s2, 3, s3)
  +best = best2(d01, min2(s0, s1), d23, min2(s2, s3))
  sel((min2(min2(s0, s1), min2(s2, s3)) < 99999 : U32), best, dir)

def Guest.can_step(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32) -> Bool:
  Land.walk(q, (i + dx_of(d) : U32), (j + dy_of(d) : U32), h)

# which ride a guest heads for: the best-scoring open one they can afford
# of the kind they want (0: any attraction)
def Guest.want_ok(+want: U32, +k: U32) -> Bool:
  match want:
    case 0:
      U32.is_eq(k, 1) || U32.is_eq(k, 2) || U32.is_eq(k, 5)
    case _:
      U32.is_eq(k, want)

def Guest.pick(+rs: +List<Ride>, +idx: U32, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32, +best: U32, +bs: U32) -> U32:
  match rs:
    case []:
      best
    case rd <> rest:
      +k = Ride.kind(rd)
      +ok = Ride.is_open(rd) && Guest.want_ok(want, k)
        && U32.is_le(Ride.price(rd), cash)
      +s = (Ride.dist(rd, i, j) + (hash(r, idx) .&. 31 : U32) : U32)
      +take = ok && (s < bs : U32)
      Guest.pick(rest, (idx + 1 : U32), want, i, j, cash, r,
        sel(take, idx, best), sel(take, s, bs))

# only a guest who needs a target, or stands at a tile centre about to step,
# pays for the search
def Guest.pick_if(need: Bool, +rs: +List<Ride>, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32) -> U32:
  match need:
    case True{}:
      Guest.pick(rs, 0, want, i, j, cash, r, NONE(), 99999)
    case False{}:
      NONE()

def Guest.steer(now: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +dir: U32,
  +tx: U32, +ty: U32, +r: U32) -> U32:
  match now:
    case True{}:
      Guest.choose(q, i, j, h, dir, tx, ty, r)
    case False{}:
      dir

def Guest.at_center(+x: U32, +y: U32) -> Bool:
  U32.is_eq((x .&. 15 : U32), 8) && U32.is_eq((y .&. 15 : U32), 8)

# whether a walking guest boards (or buys at) their target ride this tick
def Guest.boards(g: Guest, +q: Q, +rs: +List<Ride>) -> Bool:
  Guest{id, +x, +y, dir, +st, +tgt, tmr, +cash, hu, th, en, na, ha, lk} = g
  +rd = Rides.get(rs, tgt)
  U32.is_eq(st, 0) && Bool.not(U32.is_eq(tgt, NONE())) && Guest.at_center(x, y)
    && Ride.is_open(rd) && U32.is_le(Ride.price(rd), cash)
    && U32.is_eq(Ride.dist(rd, (x >> 4n : U32), (y >> 4n : U32)), 1)

def Guest.fee(g: Guest, +rs: +List<Ride>) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk} = g
  Ride.price(Rides.get(rs, tgt))

# boarding: pay, then the ride's effects
def Guest.board(g: Guest, +rs: +List<Ride>) -> Guest:
  Guest{id, x, y, dir, st, +tgt, tmr, +cash, +hu, +th, en, +na, +ha, lk} = g
  +rd = Rides.get(rs, tgt)
  +k = Ride.kind(rd)
  Guest{id, x, y, dir, 1, tgt, Ride.duration(k), sub0(cash, Ride.price(rd)),
    sel(U32.is_eq(k, 4), sub0(hu, 160), hu),
    sel(U32.is_eq(k, 3), sub0(th, 160), th), en,
    (na + Ride.thrill(k) : U32), (ha + Ride.fun(k) : U32), lk}

def Guest.riding(g: Guest) -> Guest:
  Guest{id, x, y, dir, st, tgt, +tmr, cash, hu, th, en, na, ha, lk} = g
  +done = (tmr <= 1 : U32)
  Guest{id, x, y, dir, sel(done, 0, 1), sel(done, NONE(), tgt),
    sel(done, 0, (tmr - 1 : U32)), cash, hu, th, en, na, ha, lk}

# needs drift a little every 16 ticks
def Guest.needs(g: Guest, +t: U32) -> Guest:
  Guest{+id, x, y, dir, st, tgt, tmr, cash, +hu, +th, +en, +na, +ha, lk} = g
  +due = U32.is_eq(((t + id) .&. 15 : U32), 0)
  +bad = ((hu > 200) || (th > 200) || (na > 170) || (en < 40) : U32)
  +good = ((hu < 120) && (th < 120) && (na < 90) : U32)
  +ha2 = sel(bad, sub0(ha, 2), sel(good, (ha + 1 : U32), ha))
  Guest{id, x, y, dir, st, tgt, tmr, cash,
    sel(due, (hu + 2 : U32), hu), sel(due, (th + 3 : U32), th),
    sel(due, sub0(en, 1), en), sel(due, sub0(na, 3), na),
    sel(due, ha2, ha), lk}

# walking: at a tile centre pick a target and a direction; move every
# other tick
def Guest.walk(g: Guest, +q: Q, +rs: +List<Ride>, +t: U32) -> Guest:
  Guest{+id, +x, +y, +dir, +st, +tgt, +tmr, +cash, +hu, +th, +en, na, +ha,
    lk} = g
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +h = Land.h(q, i, j)
  +r = hash3(id, t, x)
  +ctr = Guest.at_center(x, y)
  +home = U32.is_eq(st, 2)
  # decide to go home
  +tired = ((ha < 50) || (en < 30) || (cash < 2) : U32)
  +st2 = sel(ctr && U32.is_eq(st, 0) && tired, 2, st)
  +athome = ctr && home && U32.is_eq(i, GATE_X()) && U32.is_eq(j, GATE_Y())
  +st3 = sel(athome, 3, st2)
  # targets: food, drink, or any attraction; patience runs out
  +want = sel((hu > 150 : U32), 4, sel((th > 150 : U32), 3, 0))
  +needt = ctr && U32.is_eq(st2, 0) && U32.is_eq(tgt, NONE())
    && U32.is_eq((r .&. 3 : U32), 0)
  +pick = Guest.pick_if(needt, rs, want, i, j, cash, r)
  +giveup = U32.is_eq(tmr, 0) || Bool.not(U32.is_eq(st2, 0))
  +tgt2 = sel(needt, pick, sel(giveup, NONE(), tgt))
  +tmr2 = sel(needt, 1500, sub0(tmr, 1))
  # steering
  +trd = Rides.get(rs, tgt2)
  +tx = sel(home, GATE_X(), sel(U32.is_eq(tgt2, NONE()), i, Ride.cx(trd)))
  +ty = sel(home, GATE_Y(), sel(U32.is_eq(tgt2, NONE()), j, Ride.cy(trd)))
  +tick = U32.is_eq(((t + id) .&. 1 : U32), 0)
  +dir2 = Guest.steer(ctr && tick, q, i, j, h, dir, tx, ty, r)
  +go = tick
    && (Bool.not(ctr) || Guest.can_step(q, i, j, h, dir2))
    && Bool.not(U32.is_eq(st3, 3))
  +x2 = sel(go, (x + dx_of(dir2) : U32), x)
  +y2 = sel(go, (y + dy_of(dir2) : U32), y)
  Guest{id, x2, y2, dir2, st3, tgt2, tmr2, cash, hu, th, en, na, ha, lk}

def Guest.st(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk} = g
  st

def Guest.move.go(riding: Bool, boards: Bool, +g: Guest, +q: Q,
  +rs: +List<Ride>, +t: U32) -> Guest:
  match riding boards:
    case True{} _:
      Guest.riding(g)
    case False{} True{}:
      Guest.board(g, rs)
    case False{} False{}:
      Guest.walk(g, q, rs, t)

def Guest.move(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32) -> Guest:
  Guest.move.go(U32.is_eq(Guest.st(g), 1), Guest.boards(g, q, rs), g, q, rs, t)

# a guest's whole tick; the final clamp keeps every stat in 0..255
def Guest.step(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32) -> Guest:
  Guest.clamp(Guest.needs(Guest.move(g, q, rs, t), t))

def Guests.step(+gs: +List<Guest>, +q: Q, +rs: +List<Ride>, +t: U32)
  -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guest.step(g, q, rs, t) <> Guests.step(rest, q, rs, t)

def Guests.put(keep: Bool, g: Guest, +gs: +List<Guest>) -> +List<Guest>:
  match keep:
    case True{}:
      g <> gs
    case False{}:
      gs

# the guests still in the park, and the ones who just left
def Guests.stay(+gs: +List<Guest>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guests.put(Bool.not(Guest.gone(g)), g, Guests.stay(rest))

def Guests.left(+gs: +List<Guest>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guests.put(Guest.gone(g), g, Guests.left(rest))

def Guests.arrive(go: Bool, +id: U32, +t: U32) -> +List<Guest>:
  match go:
    case True{}:
      [Guest.new(id, t)]
    case False{}:
      []

def Rides.attractions(+rs: +List<Ride>) -> U32:
  match rs:
    case []:
      0
    case r <> rest:
      (sel(Ride.is_open(r), 1, 0) + Rides.attractions(rest) : U32)

# a new adventurer comes through the gate now and then; more rides draw more
def Guests.come(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32) -> Bool:
  +rate = U32.min((2 + Rides.attractions(rs) * 3 : U32), 24)
  +roll = (hash(t, 77) .&. 255 : U32)
  (roll < rate : U32) && (len32(Guest, gs) < 700 : U32)

def Guests.arrivals(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +nid: U32)
  -> +List<Guest>:
  Guests.arrive(Guests.come(gs, rs, t), nid, t)

# Money: every change to the park's gold is a ledger entry
# ---------------------------------------------------------
# kind: 1 ride tickets and shop sales, 2 upkeep, 3 construction, 4 refunds

type Txn is Data:
  Gain{kind: U32, amt: U32}
  Spend{kind: U32, amt: U32}

def Txn.apply(+cash: U32, t: Txn) -> U32:
  match t:
    case Gain{k, a}:
      (cash + a : U32)
    case Spend{k, a}:
      (cash - a : U32)

def Ledger.apply(+xs: +List<Txn>, +cash: U32) -> U32:
  match xs:
    case []:
      cash
    case t <> rest:
      Ledger.apply(rest, Txn.apply(cash, t))

def Ledger.put(keep: Bool, t: Txn, +xs: +List<Txn>) -> +List<Txn>:
  match keep:
    case True{}:
      t <> xs
    case False{}:
      xs

def Ledger.sales(+gs: +List<Guest>, +q: Q, +rs: +List<Ride>) -> +List<Txn>:
  match gs:
    case []:
      []
    case g <> rest:
      Ledger.put(Guest.boards(g, q, rs), Gain{1, Guest.fee(g, rs)},
        Ledger.sales(rest, q, rs))

def Ledger.upkeep(+rs: +List<Ride>) -> +List<Txn>:
  match rs:
    case []:
      []
    case r <> rest:
      +k = Ride.kind(r)
      Ledger.put(Bool.not(U32.is_eq(k, 0)), Spend{2, Ride.upkeep(k)},
        Ledger.upkeep(rest))

def MONTH() -> U32:
  3600

def Ledger.tick(+gs: +List<Guest>, +q: Q, +rs: +List<Ride>, +t: U32)
  -> +List<Txn>:
  +monthly = U32.is_eq((t % MONTH() : U32), 0) && (t > 0 : U32)
  List.append(&2, Txn, Ledger.sales(gs, q, rs),
    Bool.pick(+List<Txn>, monthly, Ledger.upkeep(rs), []))

# The Wyrm Coaster: track pieces and block sections
# -------------------------------------------------
# A piece stands on tile (x, y), entered at height z heading dir. kind: 0
# straight, 1 up, 2 down, 3 turn left, 4 turn right, 5 station, 6 lift hill.

type Piece is Data:
  Piece{x: U32, y: U32, z: U32, kind: U32, dir: U32}

type Pose is Data:
  Pose{x: U32, y: U32, z: U32, dir: U32}

def Piece.exit(p: Piece) -> Pose:
  Piece{+x, +y, +z, +kind, +dir} = p
  +d2 = sel(U32.is_eq(kind, 3), ((dir + 3) .&. 3 : U32),
    sel(U32.is_eq(kind, 4), ((dir + 1) .&. 3 : U32), dir))
  +z2 = sel(U32.is_eq(kind, 1) || U32.is_eq(kind, 6), (z + 1 : U32),
    sel(U32.is_eq(kind, 2), (z - 1 : U32), z))
  Pose{(x + dx_of(d2) : U32), (y + dy_of(d2) : U32), z2, d2}

def Pose.eq(a: Pose, b: Pose) -> Bool:
  Pose{ax, ay, az, ad} = a
  Pose{bx, by, bz, bd} = b
  U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(az, bz)
    && U32.is_eq(ad, bd)

# 1/256 of a piece per unit of progress
type Train is Data:
  Train{prog: U32, speed: U32, wait: U32}

# a block: `len` pieces from piece `start`; st is 1 on the station block.
# Holding a train *is* the block's occupancy, so a block can never hold two.
type Slot is Data:
  Free{start: U32, len: U32, st: U32}
  Held{start: U32, len: U32, st: U32, t: Train}

def Pieces.get(+ps: +List<Piece>, +i: U32) -> Piece:
  match ps:
    case []:
      Piece{0, 0, 0, 0, 0}
    case p <> rest:
      Bool.pick(Piece, U32.is_eq(i, 0), p, Pieces.get(rest, (i - 1 : U32)))

def Piece.kind(p: Piece) -> U32:
  Piece{x, y, z, kind, dir} = p
  kind

# physics inside a block: lift hills pull, slopes accelerate, the station
# holds the train while it loads
def Train.adv(t: Train, +start: U32, +len: U32, +st: U32, +ps: +List<Piece>)
  -> Train:
  Train{+prog, +speed, +wait} = t
  +k = Piece.kind(Pieces.get(ps, (start + (prog >> 8n) : U32)))
  +hold = U32.is_eq(st, 1) && (wait > 0 : U32)
  +s1 = sel(U32.is_eq(k, 6), 20, sel(U32.is_eq(k, 2), (speed + 3 : U32),
    sel(U32.is_eq(k, 1), sub0(speed, 3), sub0(speed, 1))))
  +s2 = sel(hold, 0, U32.min(U32.max(s1, 10), 90))
  +end = (len * 256 : U32)
  Train{U32.min((prog + s2 : U32), end), s2, sub0(wait, 1)}

def Slot.adv(s: Slot, +ps: +List<Piece>) -> Slot:
  match s:
    case Free{a, n, st}:
      Free{a, n, st}
    case Held{+a, +n, +st, t}:
      Held{a, n, st, Train.adv(t, a, n, st, ps)}

def Slots.adv(+ss: +List<Slot>, +ps: +List<Piece>) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      Slot.adv(s, ps) <> Slots.adv(rest, ps)

def Train.ready(t: Train, +len: U32) -> Bool:
  Train{prog, speed, wait} = t
  (prog >= len * 256 : U32)

def Slot.ready(s: Slot) -> Bool:
  match s:
    case Free{a, n, st}:
      False{}
    case Held{a, +n, st, t}:
      Train.ready(t, n)

# a train that reached the end of its block enters the next one if free:
# cfst is what becomes of the block it leaves, csnd of the block it enters
def Train.enter(t: Train, +len: U32, +st: U32) -> Train:
  Train{prog, speed, wait} = t
  Train{(prog - len * 256 : U32), speed, sel(U32.is_eq(st, 1), 150, 0)}

def Slot.cfst(+a: Slot, +b: Slot) -> Slot:
  match a b:
    case Held{sa, na, ta, t} Free{sb, nb, tb}:
      Bool.pick(Slot, Train.ready(t, na), Free{sa, na, ta}, a)
    case _ _:
      a

def Slot.csnd(+a: Slot, +b: Slot) -> Slot:
  match a b:
    case Held{sa, +na, ta, +t} Free{sb, +nb, +tb}:
      Bool.pick(Slot, Train.ready(t, na), Held{sb, nb, tb, Train.enter(t, na, tb)},
        b)
    case _ _:
      b

# one pass along the blocks, carrying the block just processed
def Slots.pass(+ss: +List<Slot>, +c: Slot) -> +List<Slot>:
  match ss:
    case []:
      [c]
    case b <> rest:
      Slot.cfst(c, b) <> Slots.pass(rest, Slot.csnd(c, b))

# the ring rotates by one each tick, so every pair of neighbours (the last
# and the first included) takes its turn
def Slots.rot(+ss: +List<Slot>) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      List.append(&2, Slot, rest, [s])

def Blocks.step(+ss: +List<Slot>, +ps: +List<Piece>) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      Slots.rot(Slots.pass(Slots.adv(rest, ps), Slot.adv(s, ps)))

def Slot.count(s: Slot) -> Nat:
  match s:
    case Free{a, n, st}:
      0n
    case Held{a, n, st, t}:
      1n

def Blocks.trains(+ss: +List<Slot>) -> Nat:
  match ss:
    case []:
      0n
    case s <> rest:
      Nat.add(Slot.count(s), Blocks.trains(rest))

# blocks of 4 pieces; a train waits in every third block
def Blocks.make(+n: Nat, +start: U32, +total: U32, +k: U32) -> +List<Slot>:
  match n:
    case 0n:
      []
    case 1n+p:
      +left = (total - start : U32)
      +len = sel((left < 8 : U32), left, 4)
      +st = sel(U32.is_eq(start, 0), 1, 0)
      +more = (start + len < total : U32)
      +train = U32.is_eq((k % 3 : U32), 0)
      +rest = Bool.pick(+List<Slot>, more,
        Blocks.make(p, (start + len : U32), total, (k + 1 : U32)), [])
      Bool.pick(Slot, train, Held{start, len, st, Train{0, 0, 60}},
        Free{start, len, st}) <> rest

type Track is Data:
  Track{pieces: List<&2, Piece>, open: Bool, blocks: List<&2, Slot>,
    start: Pose, end: Pose}

def Track.empty() -> Track:
  Track{[], False{}, [], Pose{0, 0, 0, 0}, Pose{0, 0, 0, 0}}

def Track.closed(t: Track) -> Bool:
  Track{pieces, open, blocks, start, end} = t
  (len32(Piece, pieces) >= 4 : U32) && Pose.eq(start, end)

def Track.open(t: Track) -> Bool:
  Track{pieces, open, blocks, start, end} = t
  open

# a coaster only runs on a closed circuit
def Track.safe(+t: Track) -> Bool:
  imp(Track.open(t), Track.closed(t))

def Track.tick.go(open: Bool, +ps: +List<Piece>, +bs: +List<Slot>, s: Pose,
  e: Pose) -> Track:
  match open:
    case True{}:
      Track{ps, True{}, Blocks.step(bs, ps), s, e}
    case False{}:
      Track{ps, False{}, bs, s, e}

def Track.tick(t: Track) -> Track:
  Track{+pieces, open, blocks, start, end} = t
  Track.tick.go(open, pieces, blocks, start, end)

# The park
# --------

type Park is Data:
  Park{map: Q, guests: List<&2, Guest>, rides: List<&2, Ride>, track: Track,
    cash: U32, time: U32, nid: U32}

type Act is Data:
  Tick{}
  Build{tool: U32, x: U32, y: U32, v: U32}
  TrackOp{op: U32}

type Out is Data:
  Out{park: Park, ledger: List<&2, Txn>, arrived: List<&2, Guest>,
    departed: List<&2, Guest>}

def Park.tick(p: Park) -> Out:
  Park{+map, +guests, +rides, track, cash, +time, +nid} = p
  +moved = Guests.step(guests, map, rides, time)
  +arr = Guests.arrivals(guests, rides, time, nid)
  +led = Ledger.tick(guests, map, rides, time)
  Out{Park{map, List.append(&2, Guest, arr, Guests.stay(moved)), rides,
    Track.tick(track), Ledger.apply(led, cash), (time + 1 : U32),
    (nid + len32(Guest, arr) : U32)}, led, arr, Guests.left(moved)}

# Building
# --------
# tool: 1 path, 2 raise land, 3 lower land, 4 tree (v: variant), 5..8 rides
# of kind 1..4, 9 demolish, 10 start the coaster (station facing v)

def Tile.free(+t: Tile, +h: U32) -> Bool:
  U32.is_eq(Tile.obj(t), 0) && U32.is_eq(Tile.h(t), h)
    && Bool.not(U32.is_eq(Tile.ter(t), 2)) && Bool.not(U32.is_eq(Tile.ter(t), 4))

def Land.free(+q: Q, +x: U32, +y: U32, +h: U32) -> Bool:
  inmap(x, y) && Tile.free(Land.get(q, x, y), h)

def Build.fits(+q: Q, +k: U32, +x: U32, +y: U32) -> Bool:
  +h = Land.h(q, x, y)
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  Land.free(q, x, y, h) && (U32.is_eq(Ride.size(k), 1) || (Land.free(q, x1, y, h)
    && Land.free(q, x, y1, h) && Land.free(q, x1, y1, h)))

def Build.cost(+tool: U32) -> U32:
  match tool:
    case 1:
      10
    case 2:
      20
    case 3:
      20
    case 4:
      15
    case 9:
      0
    case 10:
      40
    case _:
      Ride.cost((tool - 4 : U32))

def Build.can_pay(+cash: U32, +cost: U32) -> Bool:
  Bool.not(neg(cash)) && (cash >= cost : U32)

def Track.pieces(t: Track) -> +List<Piece>:
  Track{pieces, open, blocks, start, end} = t
  pieces

def Build.legal.go(+tool: U32, +q: Q, +trk: Track, +x: U32, +y: U32, +o: U32,
  +h: U32, +dry: Bool, +empty: Bool) -> Bool:
  match tool:
    case 1:
      empty && dry
    case 2:
      empty && (h < 6 : U32)
    case 3:
      empty && ((h > 0 : U32) || dry)
    case 4:
      empty && dry
    case 9:
      U32.is_eq(o, 1) || U32.is_eq(o, 2) || U32.is_eq(o, 3)
    case 10:
      empty && dry && U32.is_eq(len32(Piece, Track.pieces(trk)), 0)
    case _:
      (tool >= 5 : U32) && (tool <= 8 : U32) && Build.fits(q, (tool - 4 : U32), x, y)

def Build.legal(+q: Q, +trk: Track, +tool: U32, +x: U32, +y: U32) -> Bool:
  +t = Land.get(q, x, y)
  +o = Tile.obj(t)
  +ter = Tile.ter(t)
  +h = Tile.h(t)
  +dry = Bool.not(U32.is_eq(ter, 2)) && Bool.not(U32.is_eq(ter, 4))
  +empty = U32.is_eq(o, 0) && Bool.not(U32.is_eq(ter, 4))
  Build.legal.go(tool, q, trk, x, y, o, h, dry, empty)

def Build.ok(+q: Q, +trk: Track, +cash: U32, +tool: U32, +x: U32, +y: U32)
  -> Bool:
  inmap(x, y) && Build.legal(q, trk, tool, x, y)
    && Build.can_pay(cash, Build.cost(tool))

# a demolished ride hands back half its price; paths and trees a little
def Build.refund(+q: Q, +rs: +List<Ride>, +x: U32, +y: U32) -> U32:
  +t = Land.get(q, x, y)
  sel(U32.is_eq(Tile.obj(t), 3),
    (Ride.cost(Ride.kind(Rides.get(rs, Tile.a(t)))) >> 1n : U32), 4)

def Build.ledger(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32,
  +y: U32) -> +List<Txn>:
  match ok:
    case True{}:
      Bool.pick(+List<Txn>, U32.is_eq(tool, 9),
        [Gain{4, Build.refund(q, rs, x, y)}], [Spend{3, Build.cost(tool)}])
    case False{}:
      []

def Land.put(+q: Q, +x: U32, +y: U32, +obj: U32, +a: U32, +b: U32) -> Q:
  +t = Land.get(q, x, y)
  Land.set(q, x, y, Tile{Tile.h(t), Tile.ter(t), obj, a, b})

def Land.ride(+q: Q, +k: U32, +x: U32, +y: U32, +idx: U32) -> Q:
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  Bool.pick(Q, U32.is_eq(Ride.size(k), 1), Land.put(q, x, y, 3, idx, 1),
    Land.put(Land.put(Land.put(Land.put(q, x, y, 3, idx, 0), x1, y, 3, idx, 0),
      x, y1, 3, idx, 0), x1, y1, 3, idx, 1))

def Land.clear_ride(+q: Q, r: Ride) -> Q:
  Ride{kind, +x, +y, +w, h, price, open} = r
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  +one = Land.put(q, x, y, 0, 0, 0)
  Bool.pick(Q, U32.is_eq(w, 1), one,
    Land.put(Land.put(Land.put(one, x1, y, 0, 0, 0), x, y1, 0, 0, 0), x1, y1,
      0, 0, 0))

def Build.demolish(+q: Q, +rs: +List<Ride>, +x: U32, +y: U32) -> Q:
  +t = Land.get(q, x, y)
  Bool.pick(Q, U32.is_eq(Tile.obj(t), 3),
    Land.clear_ride(q, Rides.get(rs, Tile.a(t))), Land.put(q, x, y, 0, 0, 0))

def Build.land.go(+tool: U32, +q: Q, +rs: +List<Ride>, +x: U32, +y: U32,
  +v: U32, +h: U32, +ter: U32) -> Q:
  match tool:
    case 1:
      Land.set(q, x, y, Tile{h, 1, 1, 0, 0})
    case 2:
      Land.set(q, x, y, Tile{sel(U32.is_eq(ter, 2), h, (h + 1 : U32)), 0, 0, 0, 0})
    case 3:
      Land.set(q, x, y, Tile{sub0(h, 1), sel(U32.is_eq(h, 0), 2, ter), 0, 0, 0})
    case 4:
      Land.set(q, x, y, Tile{h, ter, 2, (v .&. 3 : U32), 0})
    case 9:
      Build.demolish(q, rs, x, y)
    case 10:
      Land.set(q, x, y, Tile{h, ter, 6, (5 + (v .&. 3) * 8 : U32), h})
    case _:
      Land.ride(q, (tool - 4 : U32), x, y, len32(Ride, rs))

def Build.land(+q: Q, +rs: +List<Ride>, +tool: U32, +x: U32, +y: U32,
  +v: U32) -> Q:
  +t = Land.get(q, x, y)
  Build.land.go(tool, q, rs, x, y, v, Tile.h(t), Tile.ter(t))

def Build.map(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32, +y: U32,
  +v: U32) -> Q:
  match ok:
    case True{}:
      Build.land(q, rs, tool, x, y, v)
    case False{}:
      q

def Ride.killed(r: Ride) -> Ride:
  Ride{kind, x, y, w, h, price, open} = r
  Ride{0, x, y, w, h, price, 0}

def Rides.kill(+rs: +List<Ride>, +i: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), Ride.killed(r), r)
        <> Rides.kill(rest, (i - 1 : U32))

def Build.rides(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32,
  +y: U32) -> +List<Ride>:
  match ok:
    case True{}:
      +t = Land.get(q, x, y)
      +k = (tool - 4 : U32)
      +s = Ride.size(k)
      Bool.pick(+List<Ride>, U32.is_eq(tool, 9) && U32.is_eq(Tile.obj(t), 3),
        Rides.kill(rs, Tile.a(t)),
        Bool.pick(+List<Ride>, (tool >= 5 : U32) && (tool <= 8 : U32),
          List.append(&2, Ride, rs, [Ride{k, x, y, s, s, Ride.fee(k), 1}]),
          Bool.pick(+List<Ride>, U32.is_eq(tool, 10),
            List.append(&2, Ride, rs, [Ride{5, x, y, 1, 1, Ride.fee(5), 0}]),
            rs)))
    case False{}:
      rs

def Track.begin(+q: Q, +x: U32, +y: U32, +v: U32) -> Track:
  +h = Land.h(q, x, y)
  +pc = {Piece{x, y, h, 5, (v .&. 3 : U32)} : Piece}
  Track{[pc], False{}, [], Pose{x, y, h, (v .&. 3 : U32)}, Piece.exit(pc)}

def Build.track(ok: Bool, +q: Q, +trk: Track, +tool: U32, +x: U32, +y: U32,
  +v: U32) -> Track:
  match ok:
    case True{}:
      Bool.pick(Track, U32.is_eq(tool, 10), Track.begin(q, x, y, v), trk)
    case False{}:
      trk

def Park.build(p: Park, +tool: U32, +x: U32, +y: U32, +v: U32) -> Out:
  Park{+map, guests, +rides, +track, +cash, time, nid} = p
  +ok = Build.ok(map, track, cash, tool, x, y)
  +led = Build.ledger(ok, map, rides, tool, x, y)
  Out{Park{Build.map(ok, map, rides, tool, x, y, v), guests,
    Build.rides(ok, map, rides, tool, x, y), Build.track(ok, map, track, tool,
    x, y, v), Ledger.apply(led, cash), time, nid}, led, [], []}

# Coaster track editing
# ---------------------
# op 0..6: add a piece of that kind at the end; 7: remove the last piece;
# 8: open or close the coaster

def Track.end(t: Track) -> Pose:
  Track{pieces, open, blocks, start, end} = t
  end

def Pose.x(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  x

def Pose.y(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  y

def Pose.z(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  z

def Pose.d(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  d

def Pieces.last(+ps: +List<Piece>) -> Piece:
  Pieces.get(ps, (len32(Piece, ps) - 1 : U32))

def Pieces.init(+ps: +List<Piece>) -> +List<Piece>:
  match ps:
    case []:
      []
    case p <> rest:
      Bool.pick(+List<Piece>, U32.is_eq(len32(Piece, rest), 0), [],
        p <> Pieces.init(rest))

def Piece.pose(p: Piece) -> Pose:
  Piece{x, y, z, kind, dir} = p
  Pose{x, y, z, dir}

def Track.room(+q: Q, +e: Pose, +op: U32) -> Bool:
  +x = Pose.x(e)
  +y = Pose.y(e)
  +z = Pose.z(e)
  +t = Land.get(q, x, y)
  +low = sel(U32.is_eq(op, 2), sub0(z, 1), z)
  inmap(x, y) && U32.is_eq(Tile.obj(t), 0) && Bool.not(U32.is_eq(Tile.ter(t), 4))
    && (Tile.h(t) <= low : U32) && (z < 13 : U32)
    && Bool.not(U32.is_eq(op, 2) && U32.is_eq(z, 0))

def TrackOp.ok(+q: Q, +trk: Track, +cash: U32, +op: U32) -> Bool:
  +n = len32(Piece, Track.pieces(trk))
  +shut = Bool.not(Track.open(trk))
  +add = (op < 7 : U32) && shut && (n > 0 : U32) && Bool.not(Track.closed(trk))
    && Track.room(q, Track.end(trk), op) && Build.can_pay(cash, 40)
  +del = U32.is_eq(op, 7) && shut && (n > 1 : U32)
  add || del || U32.is_eq(op, 8)

def TrackOp.ledger(ok: Bool, +op: U32) -> +List<Txn>:
  match ok:
    case True{}:
      Bool.pick(+List<Txn>, (op < 7 : U32), [Spend{3, 40}],
        Bool.pick(+List<Txn>, U32.is_eq(op, 7), [Gain{4, 20}], []))
    case False{}:
      []

def Piece.code(p: Piece) -> U32:
  Piece{x, y, z, kind, dir} = p
  (kind + dir * 8 : U32)

def TrackOp.map(ok: Bool, +q: Q, +trk: Track, +op: U32) -> Q:
  match ok:
    case True{}:
      +e = Track.end(trk)
      +pc = {Piece{Pose.x(e), Pose.y(e), Pose.z(e), op, Pose.d(e)} : Piece}
      +last = Pieces.last(Track.pieces(trk))
      +lp = Piece.pose(last)
      Bool.pick(Q, (op < 7 : U32),
        Land.put(q, Pose.x(e), Pose.y(e), 6, Piece.code(pc), Pose.z(e)),
        Bool.pick(Q, U32.is_eq(op, 7), Land.put(q, Pose.x(lp), Pose.y(lp), 0, 0, 0),
          q))
    case False{}:
      q

# opening builds the blocks and puts the trains on; closing takes them off
def Track.toggle.go(open: Bool, +ps: +List<Piece>, bs: +List<Slot>, +s: Pose,
  +e: Pose) -> Track:
  match open:
    case True{}:
      Track{ps, False{}, [], s, e}
    case False{}:
      +n = len32(Piece, ps)
      +shut = {Track{ps, False{}, [], s, e} : Track}
      Track{ps, Track.closed(shut), Blocks.make(U32.to_nat(n), 0, n, 0), s, e}

def Track.toggle(t: Track) -> Track:
  Track{+ps, open, bs, +s, +e} = t
  Track.toggle.go(open, ps, bs, s, e)

def Track.edit(t: Track, +op: U32) -> Track:
  Track{+ps, open, bs, +s, +e} = t
  +pc = {Piece{Pose.x(e), Pose.y(e), Pose.z(e), op, Pose.d(e)} : Piece}
  Bool.pick(Track, (op < 7 : U32),
    Track{List.append(&2, Piece, ps, [pc]), False{}, [], s, Piece.exit(pc)},
    Track{Pieces.init(ps), False{}, [], s, Piece.pose(Pieces.last(ps))})

def Track.op(+t: Track, +op: U32, ok: Bool) -> Track:
  match ok:
    case True{}:
      Bool.pick(Track, U32.is_eq(op, 8), Track.toggle(t), Track.edit(t, op))
    case False{}:
      t

def Rides.coaster(+rs: +List<Ride>, +open: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Ride{+kind, x, y, w, h, price, op} = r
      Ride{kind, x, y, w, h, price, sel(U32.is_eq(kind, 5), open, op)}
        <> Rides.coaster(rest, open)

def Park.track_op(p: Park, +op: U32) -> Out:
  Park{+map, guests, +rides, +track, +cash, time, nid} = p
  +ok = TrackOp.ok(map, track, cash, op)
  +led = TrackOp.ledger(ok, op)
  +trk2 = Track.op(track, op, ok)
  Out{Park{TrackOp.map(ok, map, track, op), guests,
    Rides.coaster(rides, sel(Track.open(trk2), 1, 0)), trk2,
    Ledger.apply(led, cash), time, nid}, led, [], []}

# the one door every change comes through
def Park.step(p: Park, a: Act) -> Out:
  match a:
    case Tick{}:
      Park.tick(p)
    case Build{tool, x, y, v}:
      Park.build(p, tool, x, y, v)
    case TrackOp{op}:
      Park.track_op(p, op)

def Park.new() -> Park:
  Park{Q.build(6n, 0, 0), [], [], Track.empty(), 30000, 0, 1}

def Out.park(o: Out) -> Park:
  Out{p, l, ar, de} = o
  p

def Out.ledger(o: Out) -> +List<Txn>:
  Out{p, l, ar, de} = o
  l

def Out.arrived(o: Out) -> +List<Guest>:
  Out{p, l, ar, de} = o
  ar

def Out.departed(o: Out) -> +List<Guest>:
  Out{p, l, ar, de} = o
  de

def Park.run(acts: List<Act>, +p: Park) -> Park:
  match acts:
    case []:
      p
    case a <> rest:
      Park.run(rest, Out.park(Park.step(p, a)))

def Park.map(p: Park) -> Q:
  Park{map, guests, rides, track, cash, time, nid} = p
  map

def Park.guests(p: Park) -> +List<Guest>:
  Park{map, guests, rides, track, cash, time, nid} = p
  guests

def Park.track(p: Park) -> Track:
  Park{map, guests, rides, track, cash, time, nid} = p
  track

def Park.cash(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid} = p
  cash

def Park.time(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid} = p
  time

def Park.rides(p: Park) -> +List<Ride>:
  Park{map, guests, rides, track, cash, time, nid} = p
  rides
