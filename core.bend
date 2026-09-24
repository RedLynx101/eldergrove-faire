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

def OBJ_QUEUE() -> U32:
  7

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

# (bx, by: this level's bits of x and y; descending into just the one child
# keeps lookups free of reference-count work on the other three)
def Q.find(+d: Nat, +q: Q, bx: Bool, by: Bool, +x: U32, +y: U32, +m: U32) -> Tile:
  match d q bx by:
    case _ QL{t} _ _:
      t
    case 0n QN{a, b, c, e} _ _:
      Tile{0, 0, 0, 0, 0}
    case 1n+p QN{a, b, c, e} False{} False{}:
      Q.find(p, a, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} True{} False{}:
      Q.find(p, b, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} False{} True{}:
      Q.find(p, c, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} True{} True{}:
      Q.find(p, e, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))

def Q.get(+d: Nat, +q: Q, +x: U32, +y: U32, +m: U32) -> Tile:
  Q.find(d, q, Q.bit(x, m), Q.bit(y, m), x, y, m)

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

def Land.get.go(in: Bool, +q: Q, +x: U32, +y: U32) -> Tile:
  match in:
    case True{}:
      Q.get(6n, q, x, y, 32)
    case False{}:
      Tile{0, 4, 0, 0, 0}

def Land.get(+q: Q, +x: U32, +y: U32) -> Tile:
  Land.get.go(inmap(x, y), q, x, y)

def Land.set(+q: Q, +x: U32, +y: U32, t: Tile) -> Q:
  Q.set(6n, q, x, y, 32, t)

def Land.h(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.h(Land.get(q, x, y))

def Land.obj(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.obj(Land.get(q, x, y))

def Land.qn(+q: Q, +x: U32, +y: U32) -> U32:
  sel(U32.is_eq(Land.obj(q, x, y), 7), 1, 0)

# a ride or coaster track beside a queue marks the queue's front
def Land.rn(+q: Q, +x: U32, +y: U32) -> U32:
  +o = Land.obj(q, x, y)
  sel(U32.is_eq(o, 3) || U32.is_eq(o, 6), 1, 0)

# a queue's free end: a lone queue tile, or a line's last tile away from
# the ride (checked only when needed: stepping onto a queue from outside it)
def Land.qend(need: Bool, +q: Q, +x: U32, +y: U32) -> Bool:
  match need:
    case True{}:
      +x1 = (x + 1 : U32)
      +x0 = (x - 1 : U32)
      +y1 = (y + 1 : U32)
      +y0 = (y - 1 : U32)
      +n = (Land.qn(q, x1, y) + Land.qn(q, x0, y) + Land.qn(q, x, y1) + Land.qn(q, x, y0) : U32)
      +r = (Land.rn(q, x1, y) + Land.rn(q, x0, y) + Land.rn(q, x, y1) + Land.rn(q, x, y0) : U32)
      U32.is_eq(n, 0) || U32.is_eq(n, 1) && U32.is_eq(r, 0)
    case False{}:
      True{}

# Every queue tile's `a` is 1 at a free end, 0 elsewhere; worked out again
# after each build or track edit (they can change which tiles are ends)
def Land.fix.go(isq: Bool, +q: Q, +x: U32, +y: U32, +t: Tile) -> Q:
  match isq:
    case True{}:
      Tile{+h, +ter, obj, a, +b} = t
      Land.set(q, x, y, Tile{h, ter, 7, sel(Land.qend(True{}, q, x, y), 1, 0), b})
    case False{}:
      q

def Land.fix.row(+n: Nat, +x: U32, +y: U32, +q: Q) -> Q:
  match n:
    case 0n:
      q
    case 1n+m:
      +t = Land.get(q, x, y)
      Land.fix.row(m, (x + 1 : U32), y, Land.fix.go(U32.is_eq(Tile.obj(t), 7), q, x, y, t))

def Land.fix.rows(+n: Nat, +y: U32, +q: Q) -> Q:
  match n:
    case 0n:
      q
    case 1n+m:
      Land.fix.rows(m, (y + 1 : U32), Land.fix.row(64n, 0, y, q))

def Land.fix(+q: Q) -> Q:
  Land.fix.rows(64n, 0, q)

# a guest may step onto a path or the gate at the same height -- from a
# queue (fq) only at its free end (fe) -- and onto a queue tile only when
# heading for a ride (qok), from outside it only at its free end.
# 0: blocked, 1: path, 2: queue, 3: a queue's free end (a queue tile's `a`
# says so; see Land.fix)
def Land.step(+q: Q, +x: U32, +y: U32, +h: U32, +qok: Bool, +fq: Bool, +fe: Bool) -> U32:
  +t = Land.get(q, x, y)
  +o = Tile.obj(t)
  +isq = U32.is_eq(o, 7)
  +end = isq && U32.is_eq(Tile.a(t), 1)
  +ok = inmap(x, y) && U32.is_eq(Tile.h(t), h)
    && ((U32.is_eq(o, 1) || U32.is_eq(o, 5)) && (Bool.not(fq) || fe)
      || qok && isq && (fq || end))
  sel(ok, sel(isq, sel(end, 3, 2), 1), 0)

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
    || in_rect(x, y, 17, 37, 17, 37)

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
  +queue = in_rect(x, y, 34, 27, 34, 29) || in_rect(x, y, 33, 27, 33, 27)
    || in_rect(x, y, 31, 38, 31, 39) || in_rect(x, y, 33, 21, 33, 23)
    || in_rect(x, y, 49, 37, 49, 37) || in_rect(x, y, 13, 37, 16, 37)
  Bool.pick(Tile, gate, Tile{1, 1, 5, 0, 0},
    Bool.pick(Tile, queue, Tile{h, 1, 7, 0, 0},
    Bool.pick(Tile, Gen.lake(x, y), Tile{0, 2, 0, 0, 0},
      Bool.pick(Tile, Gen.is_path(x, y), Tile{h, 1, 1, 0, 0},
        Bool.pick(Tile, tree, Gen.tree(x, y, h, r), Tile{h, 0, 0, 0, 0})))))

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

# kind 1 carousel, 2 spire, 3 potion stall, 4 tavern, 5 coaster (0: gone);
# x, y, w, h: footprint; open: 1 when open. The cycle: ph 0 loading, 1 running,
# 2 unloading, tm ticks into it (loading: since the first rider sat down).
# ent, ex: entrance (a queue tile) and exit (a path tile), packed i * 64 + j
# or NONE, and qlen: guests in its queue, all refreshed every tick. wmin,
# wmax: the loading waits. total, earned: customers and gold so far; born:
# the tick it was built. rate: its ratings, excitement | intensity << 10 |
# nausea << 20, each in hundredths (see Ride.rating).
type Ride is Data:
  Ride{kind: U32, x: U32, y: U32, w: U32, h: U32, price: U32, open: U32,
    ph: U32, tm: U32, ent: U32, ex: U32, qlen: U32, wmin: U32, wmax: U32,
    total: U32, earned: U32, born: U32, rate: U32}

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

# how long a ride runs; a shop's serving time
def Ride.duration(+k: U32) -> U32:
  match k:
    case 1:
      448
    case 2:
      512
    case 3:
      20
    case 4:
      40
    case 5:
      360
    case _:
      10

# Ratings, in hundredths: excitement (how much fun), intensity (how wild),
# nausea (how queasy it leaves you), packed E | I << 10 | N << 20
def Rate.pack(+e: U32, +i: U32, +n: U32) -> U32:
  (U32.min(e, 999) .|. (U32.min(i, 999) << 10n) .|. (U32.min(n, 999) << 20n) : U32)

def Rate.e(+r: U32) -> U32:
  (r .&. 1023 : U32)

def Rate.i(+r: U32) -> U32:
  ((r >> 10n) .&. 1023 : U32)

def Rate.n(+r: U32) -> U32:
  ((r >> 20n) .&. 1023 : U32)

# the fixed rides' ratings (the coaster's come from its track)
def Ride.rate0(+k: U32) -> U32:
  match k:
    case 1:
      Rate.pack(160, 60, 30)
    case 2:
      Rate.pack(260, 210, 130)
    case _:
      0

def Ride.shop(+k: U32) -> Bool:
  U32.is_eq(k, 3) || U32.is_eq(k, 4)

# the rides that run in cycles
def Ride.cycles(+k: U32) -> Bool:
  U32.is_eq(k, 1) || U32.is_eq(k, 2)

# prices: 0..20 gold; the entry fee: 0..40
def Price.cap(+v: U32) -> U32:
  sel(U32.is_le(v, 20), v, 20)

def Fee.cap(+v: U32) -> U32:
  sel(U32.is_le(v, 40), v, 40)

def Ride.new(+k: U32, +x: U32, +y: U32, +s: U32, +open: U32, +t: U32) -> Ride:
  Ride{k, x, y, s, s, Price.cap(Ride.fee(k)), open, 0, 0, NONE(), NONE(), 0, 60, 420, 0, 0, t, Ride.rate0(k)}

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
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  kind

# open, standing, and (shops aside) with both an entrance and an exit
def Ride.is_open(r: Ride) -> Bool:
  Ride{+kind, x, y, w, h, price, open, ph, tm, +ent, +ex, qlen, wmin, wmax, total, earned, born, rate} = r
  U32.is_eq(open, 1) && Bool.not(U32.is_eq(kind, 0))
    && (Ride.shop(kind) || Bool.not(U32.is_eq(ent, NONE())) && Bool.not(U32.is_eq(ex, NONE())))

def Ride.price(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  price

def Ride.cx(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  x

def Ride.cy(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  y

def Ride.wd(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  w

def Ride.ph(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  ph

def Ride.tm(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  tm

def Ride.ent(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  ent

def Ride.ex(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  ex

def Ride.qlen(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  qlen

def Ride.wmin(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  wmin

def Ride.wmax(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  wmax

def Ride.total(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  total

def Ride.earned(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  earned

def Ride.born(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  born

def Ride.rate(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  rate

def Ride.open_flag(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  open

# distance from a tile to the nearest tile of the ride's footprint
def Ride.dist(r: Ride, +i: U32, +j: U32) -> U32:
  Ride{kind, +x, +y, +w, +h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  +ci = U32.min(U32.max(i, x), (x + w - 1 : U32))
  +cj = U32.min(U32.max(j, y), (y + h - 1 : U32))
  (absd(i, ci) + absd(j, cj) : U32)

# the i-th ride (stops there; past the end, a demolished nothing)
def Rides.get(+rs: +List<Ride>, +i: U32) -> Ride:
  match rs i:
    case Nil{} _:
      Ride{0, 0, 0, 1, 1, 0, 0, 0, 0, NONE(), NONE(), 0, 0, 0, 0, 0, 0, 0}
    case Con{r, rest} 0:
      r
    case Con{r, rest} _:
      Rides.get(rest, (i - 1 : U32))

# Guests: the adventurers
# -----------------------
# x, y: position in 1/16 tile; dir: 0 +x, 1 +y, 2 -x, 3 -y; st: 0 walking,
# 1 riding (ride tgt, tmr ticks left), 2 heading home, 3 gone; tgt: the ride
# they want (NONE: none); tmr: ride time or patience; look: class/colours

type Guest is Data:
  Guest{id: U32, x: U32, y: U32, dir: U32, st: U32, tgt: U32, tmr: U32,
    cash: U32, hunger: U32, thirst: U32, energy: U32, nausea: U32, happy: U32,
    look: U32, mind: U32}

# a guest's latest thought: code | ride << 8 | (tick / 16) << 16. Codes: 1
# "not paying that much for" the ride, 2 "waited too long for", 3 "was
# great", 4 "was too intense"
def Mind.make(+code: U32, +ride: U32, +t: U32) -> U32:
  (code .|. ((ride .&. 255) << 8n) .|. (((t >> 4n) .&. 65535) << 16n) : U32)

def Mind.code(+m: U32) -> U32:
  (m .&. 255 : U32)

def Mind.ride(+m: U32) -> U32:
  ((m >> 8n) .&. 255 : U32)

def Mind.when(+m: U32) -> U32:
  (m >> 16n : U32)

def Guest.clamp(g: Guest) -> Guest:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  Guest{id, x, y, dir, st, tgt, tmr, cash, cl255(hu), cl255(th), cl255(en),
    cl255(na), cl255(ha), lk, mind}

def Guest.ok(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  U32.is_le(hu, 255) && U32.is_le(th, 255) && U32.is_le(en, 255)
    && U32.is_le(na, 255) && U32.is_le(ha, 255)

def Guest.gone(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  U32.is_eq(st, 3)

# a new adventurer, their gold already less the entry fee (at most 40, and
# everyone brings at least 40)
def Guest.raw(+id: U32, +t: U32, +fee: U32) -> Guest:
  +r = hash(id, t)
  Guest{id, (GATE_X() * 16 + 8 : U32), (GATE_Y() * 16 + 8 : U32),
    3, 0, NONE(), 0, (40 + (r .&. 127) - U32.min(fee, 40) : U32), (r >> 7n .&. 63 : U32),
    (r >> 13n .&. 63 : U32), (190 + (r >> 19n .&. 63) : U32), 0, 200, (r .&. 1023 : U32), 0}

def Guest.new(+id: U32, +t: U32, +fee: U32) -> Guest:
  Guest.clamp(Guest.raw(id, t, fee))

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
def Guest.arr(+i: U32, +j: U32, +tx: U32, +ty: U32, +lim: U32) -> Bool:
  ((absd(i, tx) + absd(j, ty)) <= lim : U32)

# (arr: (i, j) is already within lim of the target, so the search stops)
def Guest.reach(+n: Nat, ok: Bool, arr: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +d: U32,
  +tx: U32, +ty: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  match n ok arr:
    case _ False{} _:
      99999
    case _ True{} True{}:
      (absd(i, tx) + absd(j, ty) : U32)
    case 0n True{} False{}:
      (absd(i, tx) + absd(j, ty) : U32)
    case 1n+p True{} False{}:
      +back = ((d + 2) .&. 3 : U32)
      +i1 = (i + 1 : U32)
      +i0 = (i - 1 : U32)
      +j1 = (j + 1 : U32)
      +j0 = (j - 1 : U32)
      +c0 = Land.step(q, i1, j, h, qok, fq, fe)
      +r0 = Guest.reach(p, Bool.not(U32.is_eq(back, 0)) && Bool.not(U32.is_eq(c0, 0)),
        Guest.arr(i1, j, tx, ty, lim), q, i1, j, h, 0, tx, ty, qok,
        U32.is_eq(c0, 2) || U32.is_eq(c0, 3), Bool.not(U32.is_eq(c0, 2)), lim)
      +c1 = Land.step(q, i, j1, h, qok, fq, fe)
      +r1 = Guest.reach(p, Bool.not(U32.is_eq(back, 1)) && Bool.not(U32.is_eq(c1, 0)),
        Guest.arr(i, j1, tx, ty, lim), q, i, j1, h, 1, tx, ty, qok,
        U32.is_eq(c1, 2) || U32.is_eq(c1, 3), Bool.not(U32.is_eq(c1, 2)), lim)
      +c2 = Land.step(q, i0, j, h, qok, fq, fe)
      +r2 = Guest.reach(p, Bool.not(U32.is_eq(back, 2)) && Bool.not(U32.is_eq(c2, 0)),
        Guest.arr(i0, j, tx, ty, lim), q, i0, j, h, 2, tx, ty, qok,
        U32.is_eq(c2, 2) || U32.is_eq(c2, 3), Bool.not(U32.is_eq(c2, 2)), lim)
      +c3 = Land.step(q, i, j0, h, qok, fq, fe)
      +r3 = Guest.reach(p, Bool.not(U32.is_eq(back, 3)) && Bool.not(U32.is_eq(c3, 0)),
        Guest.arr(i, j0, tx, ty, lim), q, i, j0, h, 3, tx, ty, qok,
        U32.is_eq(c3, 2) || U32.is_eq(c3, 3), Bool.not(U32.is_eq(c3, 2)), lim)
      +best = U32.min(U32.min(r0, r1), U32.min(r2, r3))
      +d0 = (absd(i, tx) + absd(j, ty) : U32)
      sel((best < 99999 : U32), U32.min(d0, best), 99999)

# how much a guest likes stepping from tile (i, j) in direction d, heading
# for tile (tx, ty): lower is better; 99999 when it cannot step there
def Guest.score(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32, +back: U32,
  +tx: U32, +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  +ni = (i + dx_of(d) : U32)
  +nj = (j + dy_of(d) : U32)
  +c = Land.step(q, ni, nj, h, qok, fq, fe)
  +ok = Bool.not(U32.is_eq(c, 0))
  +v = Guest.reach(12n, ok, Guest.arr(ni, nj, tx, ty, lim), q, ni, nj, h, d, tx, ty, qok,
    U32.is_eq(c, 2) || U32.is_eq(c, 3), Bool.not(U32.is_eq(c, 2)), lim)
  +pen = sel(U32.is_eq(d, back), 7, 0)
  +jit = (hash(r, d) .&. 7 : U32)
  sel(ok, sel((v >= 99999 : U32), (90000 + pen : U32), (v * 4 + pen + jit : U32)), 99999)

def best2(+da: U32, +sa: U32, +db: U32, +sb: U32) -> U32:
  sel((sb < sa : U32), db, da)

def min2(+sa: U32, +sb: U32) -> U32:
  U32.min(sa, sb)

# the direction to take at a tile centre (the current one if nothing works)
def Guest.choose(+q: Q, +i: U32, +j: U32, +h: U32, +dir: U32, +tx: U32,
  +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  +back = ((dir + 2) .&. 3 : U32)
  +s0 = Guest.score(q, i, j, h, 0, back, tx, ty, r, qok, fq, fe, lim)
  +s1 = Guest.score(q, i, j, h, 1, back, tx, ty, r, qok, fq, fe, lim)
  +s2 = Guest.score(q, i, j, h, 2, back, tx, ty, r, qok, fq, fe, lim)
  +s3 = Guest.score(q, i, j, h, 3, back, tx, ty, r, qok, fq, fe, lim)
  +d01 = best2(0, s0, 1, s1)
  +d23 = best2(2, s2, 3, s3)
  +best = best2(d01, min2(s0, s1), d23, min2(s2, s3))
  sel((min2(min2(s0, s1), min2(s2, s3)) < 99999 : U32), best, dir)

def Guest.can_step(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32, +qok: Bool, +fq: Bool, +fe: Bool) -> Bool:
  Bool.not(U32.is_eq(Land.step(q, (i + dx_of(d) : U32), (j + dy_of(d) : U32), h, qok, fq, fe), 0))

# which ride a guest heads for: the best-scoring open one they can afford
# of the kind they want (0: any attraction)
def Guest.want_ok(+want: U32, +k: U32) -> Bool:
  match want:
    case 0:
      U32.is_eq(k, 1) || U32.is_eq(k, 2) || U32.is_eq(k, 5)
    case _:
      U32.is_eq(k, want)

def Ride.seats(+k: U32) -> U32:
  match k:
    case 1:
      8
    case 2:
      8
    case 5:
      6
    case _:
      4

def Guest.tol(+lk: U32) -> U32:
  (220 + (((lk * 37) + (lk >> 4n)) .&. 511) : U32)

# a ride's effect on a rider's happiness: its excitement, less a penalty when
# it is wilder than they like
# what a ride is worth to a guest, in gold: its excitement, or for a potion
# or a meal how thirsty or hungry they are
def Guest.worth(+k: U32, +rate: U32, +hu: U32, +th: U32) -> U32:
  match k:
    case 3:
      (2 + th / 64 : U32)
    case 4:
      (3 + hu / 64 : U32)
    case _:
      (1 + Rate.e(rate) * 2 / 100 : U32)

# the best ride to head for (skipping ones too dear when `judge`, and the one
# they last refused to pay for)
def Guest.pick(+rs: +List<Ride>, +idx: U32, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32, +lk: U32, +hu: U32, +th: U32, +judge: Bool, +avoid: U32, +best: U32, +bs: U32) -> U32:
  match rs:
    case []:
      best
    case rd <> rest:
      +k = Ride.kind(rd)
      +ql = Ride.qlen(rd)
      +rate = Ride.rate(rd)
      +ok = Ride.is_open(rd) && Guest.want_ok(want, k)
        && U32.is_le(Ride.price(rd), cash) && (ql < Ride.seats(k) * 3 : U32)
        && (Rate.i(rate) <= Guest.tol(lk) + 100 : U32)
        && (Bool.not(judge) || U32.is_le(Ride.price(rd), Guest.worth(k, rate, hu, th)) && Bool.not(U32.is_eq(idx, avoid)))
      +s = sub0((Ride.dist(rd, i, j) + ql + (hash(r, idx) .&. 31 : U32) + 40 : U32), (Rate.e(rate) / 12 : U32))
      +take = ok && (s < bs : U32)
      Guest.pick(rest, (idx + 1 : U32), want, i, j, cash, r, lk, hu, th, judge, avoid,
        sel(take, idx, best), sel(take, s, bs))

# only a guest who needs a target, or stands at a tile centre about to step,
# pays for the search
# the choice | what they would have chosen, price aside << 8
def Guest.pick_if(need: Bool, +rs: +List<Ride>, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32, +lk: U32, +hu: U32, +th: U32, +avoid: U32) -> U32:
  match need:
    case True{}:
      (Guest.pick(rs, 0, want, i, j, cash, r, lk, hu, th, True{}, avoid, NONE(), 99999)
        .|. (Guest.pick(rs, 0, want, i, j, cash, r, lk, hu, th, False{}, NONE(), NONE(), 99999) << 8n) : U32)
    case False{}:
      (NONE() .|. (NONE() << 8n) : U32)

def Guest.steer(now: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +dir: U32,
  +tx: U32, +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  match now:
    case True{}:
      Guest.choose(q, i, j, h, dir, tx, ty, r, qok, fq, fe, lim)
    case False{}:
      dir

def Guest.at_center(+x: U32, +y: U32) -> Bool:
  U32.is_eq((x .&. 15 : U32), 8) && U32.is_eq((y .&. 15 : U32), 8)

# Seats and boarding
# ------------------
# Every tick, one pass over the guests (Boards.plan) seats whoever is ready
# to board, in order, into free seats -- so no two guests ever share a seat
# and no ride is filled past its seats. The guest updates, the ticket sales
# and the riders drawn on the rides all read that one plan. A rider keeps
# their seat in `dir` (coaster: train id * 8 + seat).

def bit8(+n: U32) -> U32:
  match n:
    case 0:
      1
    case 1:
      2
    case 2:
      4
    case 3:
      8
    case 4:
      16
    case 5:
      32
    case 6:
      64
    case 7:
      128
    case _:
      256

def Seat.has(+f: U32, +b: U32) -> Bool:
  Bool.not(U32.is_eq((f .&. b : U32), 0))

type Board is Data:
  Board{gid: U32, ride: U32, seat: U32}

def Board.at(b: Board, +r: U32, +s: U32) -> Bool:
  Board{g, ride, seat} = b
  U32.is_eq(ride, r) && U32.is_eq(seat, s)

# whether the plan already gave seat s of ride r to someone
def Boards.taken(+bs: +List<Board>, +r: U32, +s: U32) -> Bool:
  match bs:
    case []:
      False{}
    case b <> rest:
      Board.at(b, r, s) || Boards.taken(rest, r, s)

# seat k of ride r if no rider sits there (f: the seats free of riders), it
# is below cap, and the plan (acc) hasn't handed it out yet; else `rest`
def Seat.pick(+f: U32, +acc: +List<Board>, +r: U32, +cap: U32, +k: U32, +rest: U32) -> U32:
  sel(Seat.has(f, bit8(k)) && (U32.is_lt(k, cap) && Bool.not(Boards.taken(acc, r, k))), k, rest)

def Seat.first(+f: U32, +acc: +List<Board>, +r: U32, +cap: U32) -> U32:
  Seat.pick(f, acc, r, cap, 0, Seat.pick(f, acc, r, cap, 1, Seat.pick(f, acc, r, cap, 2,
    Seat.pick(f, acc, r, cap, 3, Seat.pick(f, acc, r, cap, 4, Seat.pick(f, acc, r, cap, 5,
    Seat.pick(f, acc, r, cap, 6, Seat.pick(f, acc, r, cap, 7, NONE()))))))))

# the lowest free seat of ride r below cap (m: the seats riders hold), or NONE
def Seat.free(+m: U32, +acc: +List<Board>, +r: U32, +cap: U32) -> U32:
  Seat.first((m .^. 255 : U32), acc, r, cap)

# the coaster's station: whether it runs, and the train loading there
type Stn is Data:
  Stn{open: U32, id: U32, wait: U32}

def Stn.id(s: Stn) -> U32:
  Stn{o, id, w} = s
  id

type Train is Data:
  Train{id: U32, prog: U32, speed: U32, wait: U32}

# a block: `len` pieces from piece `start`; st is 1 on the station block.
# Holding a train *is* the block's occupancy, so a block can never hold two.
type Slot is Data:
  Free{start: U32, len: U32, st: U32}
  Held{start: U32, len: U32, st: U32, t: Train}

def Stn.of(s: Slot, +acc: Stn) -> Stn:
  match s:
    case Free{a, n, st}:
      acc
    case Held{a, n, +st, t}:
      Train{id, prog, speed, wait} = t
      Bool.pick(Stn, U32.is_eq(st, 1), Stn{1, id, wait}, acc)

def Stn.find(+ss: +List<Slot>, +acc: Stn) -> Stn:
  match ss:
    case []:
      acc
    case s <> rest:
      Stn.find(rest, Stn.of(s, acc))

type Piece is Data:
  Piece{x: U32, y: U32, z: U32, kind: U32, dir: U32}

type Pose is Data:
  Pose{x: U32, y: U32, z: U32, dir: U32}

type Track is Data:
  Track{pieces: List<&2, Piece>, open: Bool, blocks: List<&2, Slot>,
    start: Pose, end: Pose}

def Track.stn(t: Track) -> Stn:
  Track{pieces, open, blocks, start, end} = t
  Stn.find(blocks, Stn{sel(open, 1, 0), NONE(), 0})

def Guest.id(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  id

def Guest.tgt(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  tgt

def Guest.dir(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  dir

def Guest.tmr(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  tmr

def Tab.zero.go(+n: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Tab.zero.go(p, 0 <> acc)

def Tab.zero(+n: U32, +acc: +List<U32>) -> +List<U32>:
  Tab.zero.go(U32.to_nat(n), acc)

def Tab.or(+xs: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match xs:
    case []:
      []
    case x <> rest:
      sel(U32.is_eq(i, 0), (x .|. v : U32), x) <> Tab.or(rest, (i - 1 : U32), v)

def Tab.at(+xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case []:
      0
    case x <> rest:
      sel(U32.is_eq(i, 0), x, Tab.at(rest, (i - 1 : U32)))

# the seats taken on each ride (the coaster: on the train loading now)
def Occ.put(on: Bool, +tab: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match on:
    case True{}:
      Tab.or(tab, i, v)
    case False{}:
      tab

def Occ.add.go(riding: Bool, +dir: U32, +tgt: U32, +rs: +List<Ride>, +sid: U32,
  +tab: +List<U32>) -> +List<U32>:
  match riding:
    case True{}:
      +k = Ride.kind(Rides.get(rs, tgt))
      +on = Bool.not(U32.is_eq(k, 5)) || U32.is_eq((dir >> 3n : U32), sid)
      Occ.put(on, tab, tgt, bit8((dir .&. 7 : U32)))
    case False{}:
      tab

def Occ.add(g: Guest, +rs: +List<Ride>, +sid: U32, +tab: +List<U32>) -> +List<U32>:
  Guest{id, x, y, +dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  Occ.add.go(U32.is_eq(st, 1), dir, tgt, rs, sid, tab)

def Occ.fill(+gs: +List<Guest>, +rs: +List<Ride>, +sid: U32, +tab: +List<U32>)
  -> +List<U32>:
  match gs:
    case []:
      tab
    case g <> rest:
      Occ.fill(rest, rs, sid, Occ.add(g, rs, sid, tab))

def Occ.table(+gs: +List<Guest>, +rs: +List<Ride>, +stn: Stn) -> +List<U32>:
  Occ.fill(gs, rs, Stn.id(stn), Tab.zero(len32(Ride, rs), []))

def Board.bit(b: Board, +r: U32) -> U32:
  Board{g, ride, +seat} = b
  sel(U32.is_eq(ride, r), bit8(seat), 0)

def Boards.mask(+bs: +List<Board>, +r: U32, +acc: U32) -> U32:
  match bs:
    case []:
      acc
    case b <> rest:
      Boards.mask(rest, r, (acc .|. Board.bit(b, r) : U32))

def Board.is(b: Board, +id: U32) -> Bool:
  Board{g, ride, seat} = b
  U32.is_eq(g, id)

def Board.ride(b: Board) -> U32:
  Board{g, ride, seat} = b
  ride

def Board.seat(b: Board) -> U32:
  Board{g, ride, seat} = b
  seat

def Boards.has(+bs: +List<Board>, +id: U32) -> Bool:
  match bs:
    case []:
      False{}
    case b <> rest:
      Board.is(b, id) || Boards.has(rest, id)

def Boards.seat(+bs: +List<Board>, +id: U32) -> U32:
  match bs:
    case []:
      0
    case b <> rest:
      sel(Board.is(b, id), Board.seat(b), Boards.seat(rest, id))

# Queues, entrances and exits
# ---------------------------
# A queue tile beside a ride is its entrance: a ride with one boards only
# guests standing in its queue. Riders get off onto a path tile beside the
# ride (its exit). In a queue, a guest steps forward only when nobody is
# within half a tile ahead, so lines form single file.

def pk(+i: U32, +j: U32) -> U32:
  (i * 64 + j : U32)

# the n-th tile around a w x w footprint at (x, y), packed i * 64 + j
def Ride.cand(+x: U32, +y: U32, +w: U32, +n: U32) -> U32:
  match n:
    case 0:
      pk(x, (y - 1 : U32))
    case 1:
      pk((x + w : U32), y)
    case 2:
      pk(x, (y + w : U32))
    case 3:
      pk((x - 1 : U32), y)
    case 4:
      pk((x + w - 1 : U32), (y - 1 : U32))
    case 5:
      pk((x + w : U32), (y + w - 1 : U32))
    case 6:
      pk((x + w - 1 : U32), (y + w : U32))
    case _:
      pk((x - 1 : U32), (y + w - 1 : U32))

def Land.obj_at(+q: Q, +e: U32) -> U32:
  Land.obj(q, (e >> 6n : U32), (e .&. 63 : U32))

def Ride.is_at(+q: Q, +x: U32, +y: U32, +w: U32, +n: U32, +o: U32) -> Bool:
  U32.is_eq(Land.obj_at(q, Ride.cand(x, y, w, n)), o)

# the first tile around a w x w footprint holding object o, or NONE
def Ride.find(+q: Q, +x: U32, +y: U32, +w: U32, +o: U32) -> U32:
  sel(Ride.is_at(q, x, y, w, 0, o), Ride.cand(x, y, w, 0), sel(Ride.is_at(q, x, y, w, 1, o), Ride.cand(x, y, w, 1),
    sel(Ride.is_at(q, x, y, w, 2, o), Ride.cand(x, y, w, 2), sel(Ride.is_at(q, x, y, w, 3, o), Ride.cand(x, y, w, 3),
    sel(Ride.is_at(q, x, y, w, 4, o), Ride.cand(x, y, w, 4), sel(Ride.is_at(q, x, y, w, 5, o), Ride.cand(x, y, w, 5),
    sel(Ride.is_at(q, x, y, w, 6, o), Ride.cand(x, y, w, 6), sel(Ride.is_at(q, x, y, w, 7, o), Ride.cand(x, y, w, 7),
    NONE()))))))))

def Coaster.at.go(st: Bool, +q: Q, +x: U32, +y: U32, +o: U32) -> U32:
  match st:
    case True{}:
      Ride.find(q, x, y, 1, o)
    case False{}:
      NONE()

def Coaster.at(p: Piece, +q: Q, +o: U32) -> U32:
  Piece{+x, +y, z, +kind, dir} = p
  Coaster.at.go(U32.is_eq(kind, 5), q, x, y, o)

# the first tile holding object o beside any of the coaster's station pieces
def Coaster.near(+ps: +List<Piece>, +q: Q, +o: U32) -> U32:
  match ps:
    case []:
      NONE()
    case p <> rest:
      +here = Coaster.at(p, q, o)
      sel(U32.is_eq(here, NONE()), Coaster.near(rest, q, o), here)

# a ride's door: its entrance (o = 7, a queue tile) or its exit (o = 1, a
# path tile). Shops have neither; the coaster's are beside its station.
def Ride.door(+k: U32, +q: Q, +ps: +List<Piece>, +x: U32, +y: U32, +w: U32, +o: U32) -> U32:
  match k:
    case 0:
      NONE()
    case 3:
      NONE()
    case 4:
      NONE()
    case 5:
      Coaster.near(ps, q, o)
    case _:
      Ride.find(q, x, y, w, o)

# where queued guests stand, for the spacing rule: packed (x << 16) | y
# a queued guest: facing << 30 | x << 15 | y
def Queue.put(on: Bool, +x: U32, +y: U32, +d: U32, +acc: +List<U32>) -> +List<U32>:
  match on:
    case True{}:
      (((d .&. 3) << 30n) .|. (x << 15n) .|. y : U32) <> acc
    case False{}:
      acc

def Queue.add(g: Guest, +q: Q, +acc: +List<U32>) -> +List<U32>:
  Guest{id, +x, +y, +dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  Queue.put(U32.is_eq(st, 0) && U32.is_eq(Land.obj(q, (x >> 4n : U32), (y >> 4n : U32)), 7), x, y, dir, acc)

def Queue.list(+gs: +List<Guest>, +q: Q, +acc: +List<U32>) -> +List<U32>:
  match gs:
    case []:
      acc
    case g <> rest:
      Queue.list(rest, q, Queue.add(g, q, acc))

# someone in the queue within six units ahead (in direction d) of (x, y),
# not coming the other way (guests squeeze past those)
def QP.ahead(+p: U32, +x: U32, +y: U32, +d: U32) -> Bool:
  +px = ((p >> 15n) .&. 32767 : U32)
  +py = (p .&. 32767 : U32)
  +facing = Bool.not(U32.is_eq((p >> 30n : U32), ((d + 2) .&. 3 : U32)))
  +fx = sel(U32.is_eq(d, 0), (px - x : U32), sel(U32.is_eq(d, 2), (x - px : U32),
    sel(U32.is_eq(d, 1), (py - y : U32), (y - py : U32))))
  +sx = sel(U32.is_eq((d .&. 1 : U32), 0), (py - y : U32), (px - x : U32))
  ((fx - 1) < 6 : U32) && ((sx + 4) <= 8 : U32) && facing

# (hit carries the previous test, so the scan stops at the first match)
def Queue.blocked(+qs: +List<U32>, hit: Bool, +x: U32, +y: U32, +d: U32) -> Bool:
  match qs:
    case []:
      hit
    case p <> rest:
      match hit:
        case True{}:
          True{}
        case False{}:
          Queue.blocked(rest, QP.ahead(p, x, y, d), x, y, d)

def Queue.wait(check: Bool, +qs: +List<U32>, +x: U32, +y: U32, +d: U32) -> Bool:
  match check:
    case True{}:
      Queue.blocked(qs, False{}, x, y, d)
    case False{}:
      False{}

# whether a ride takes riders now: a cycling ride while loading; the coaster
# while a train stands in the station after its riders got off; shops always
def Ride.loading.go(+k: U32, +ph: U32, +sid: U32, +sw: U32) -> Bool:
  match k:
    case 1:
      U32.is_eq(ph, 0)
    case 2:
      U32.is_eq(ph, 0)
    case 5:
      Bool.not(U32.is_eq(sid, NONE())) && (sw > 20 : U32) && (sw <= 100 : U32)
    case _:
      True{}

def Ride.loading(r: Ride, stn: Stn) -> Bool:
  Ride{+kind, x, y, w, h, price, open, +ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  Stn{so, +sid, +sw} = stn
  Ride.loading.go(kind, ph, sid, sw)

# whether a rider gets off now: a cycling ride while unloading; a coaster
# rider when their own train is back in the station (and has stood long
# enough to unload), or the coaster closes; a shop's buyer when served; and
# anyone whose ride was demolished
def Ride.unloading.go(+k: U32, +ph: U32, +so: U32, +sid: U32, +sw: U32, +dir: U32,
  +tmr: U32) -> Bool:
  match k:
    case 0:
      True{}
    case 1:
      U32.is_eq(ph, 2)
    case 2:
      U32.is_eq(ph, 2)
    case 5:
      U32.is_eq(so, 0) || U32.is_eq((dir >> 3n : U32), sid) && (sw > 110 : U32) && (tmr < 2800 : U32)
    case _:
      (tmr <= 1 : U32)

def Ride.unloading(r: Ride, stn: Stn, +dir: U32, +tmr: U32) -> Bool:
  Ride{+kind, x, y, w, h, price, open, +ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  Stn{+so, +sid, +sw} = stn
  Ride.unloading.go(kind, ph, so, sid, sw, dir, tmr)

# standing where the ride is boarded: at its entrance (a shop: beside it)
def Ride.at_door(r: Ride, +i: U32, +j: U32) -> Bool:
  Ride{+kind, +x, +y, +w, +h, price, open, ph, tm, +ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  +ci = U32.min(U32.max(i, x), (x + w - 1 : U32))
  +cj = U32.min(U32.max(j, y), (y + h - 1 : U32))
  Ride.shop(kind) && U32.is_eq((absd(i, ci) + absd(j, cj) : U32), 1)
    || Bool.not(Ride.shop(kind)) && U32.is_eq(pk(i, j), ent)

def Guest.affords(+rd: Ride, +cash: U32) -> Bool:
  U32.is_le(Ride.price(rd), cash)

def Guest.at_ride(+rd: Ride, +st: U32, +tgt: U32, +x: U32, +y: U32) -> Bool:
  U32.is_eq(st, 0) && Bool.not(U32.is_eq(tgt, NONE())) && Guest.at_center(x, y)
    && Ride.is_open(rd) && Ride.at_door(rd, (x >> 4n : U32), (y >> 4n : U32))

def Guest.ready(+rd: Ride, +st: U32, +tgt: U32, +x: U32, +y: U32, +cash: U32) -> Bool:
  Guest.affords(rd, cash) && Guest.at_ride(rd, st, tgt, x, y)

# whether a walking guest boards (or buys at) their target ride now: it is
# loading, and they stand at its door, open, with the fare
def Guest.wants(g: Guest, +q: Q, +rs: +List<Ride>, +stn: Stn) -> Bool:
  Guest{id, +x, +y, dir, +st, +tgt, tmr, +cash, hu, th, en, na, ha, lk, mind} = g
  +rd = Rides.get(rs, tgt)
  Ride.loading(rd, stn) && Guest.ready(rd, st, tgt, x, y, cash)

def Boards.put(+s: U32, +id: U32, +r: U32, +acc: +List<Board>) -> +List<Board>:
  Bool.pick(+List<Board>, U32.is_eq(s, NONE()), acc, Board{id, r, s} <> acc)

def Boards.try(want: Bool, +g: Guest, +occ: +List<U32>, +rs: +List<Ride>,
  +stn: Stn, +acc: +List<Board>) -> +List<Board>:
  match want:
    case True{}:
      +r = Guest.tgt(g)
      +k = Ride.kind(Rides.get(rs, r))
      Boards.put(Seat.free(Tab.at(occ, r), acc, r, Ride.seats(k)), Guest.id(g), r, acc)
    case False{}:
      acc

def Boards.plan(+gs: +List<Guest>, +occ: +List<U32>, +q: Q, +rs: +List<Ride>,
  +stn: Stn, +acc: +List<Board>) -> +List<Board>:
  match gs:
    case []:
      acc
    case g <> rest:
      Boards.plan(rest, occ, q, rs, stn, Boards.try(Guest.wants(g, q, rs, stn), g, occ,
        rs, stn, acc))


def Guest.fee(g: Guest, +rs: +List<Ride>) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  Ride.price(Rides.get(rs, tgt))

# boarding: take the seat, pay, then the ride's effects
# gold after paying p (the guests who board can always afford it)
def Guest.pay(+cash: U32, +p: U32) -> U32:
  sel(U32.is_le(p, cash), (cash - p : U32), 0)

# how much intensity a guest enjoys (hundredths): set by their look, so the
# same adventurer always likes the same rides
def Ride.joy(+rate: U32, +lk: U32) -> U32:
  +over = sub0(Rate.i(rate), Guest.tol(lk))
  sub0((Rate.e(rate) / 10 : U32), (over / 6 : U32))

def Guest.board(g: Guest, +rs: +List<Ride>, +seat: U32, +stn: Stn) -> Guest:
  Guest{id, x, y, dir, st, +tgt, tmr, +cash, +hu, +th, en, +na, +ha, +lk, mind} = g
  +rd = Rides.get(rs, tgt)
  +k = Ride.kind(rd)
  +rate = Ride.rate(rd)
  +coaster = U32.is_eq(k, 5)
  +item = sel(U32.is_eq(k, 3), 65536, sel(U32.is_eq(k, 4), 131072, 0))
  Guest{id, x, y, sel(coaster, (Stn.id(stn) * 8 + seat : U32), seat), 1, tgt,
    sel(coaster, 3000, Ride.duration(k)), Guest.pay(cash, Ride.price(rd)),
    sel(U32.is_eq(k, 4), sub0(hu, 160), hu),
    sel(U32.is_eq(k, 3), sub0(th, 160), th), en,
    (na + Rate.n(rate) / 4 : U32), (ha + Ride.joy(rate, lk) : U32), ((lk .&. 4294770687) .|. item : U32), mind}

# a ride is over for this rider (see Ride.unloading)
def Guest.done(+tmr: U32, +dir: U32, +tgt: U32, +rs: +List<Ride>, +stn: Stn) -> Bool:
  Ride.unloading(Rides.get(rs, tgt), stn, dir, tmr)

# where a rider steps off: onto the exit tile at its edge by the ride, facing
# away (packed x << 16 | y << 4 | dir, in 1/16 tile)
def Guest.alight(+e: U32, +rx: U32, +ry: U32, +w: U32) -> U32:
  +ei = (e >> 6n : U32)
  +ej = (e .&. 63 : U32)
  +west = (ei < rx : U32)
  +east = (ei >= rx + w : U32)
  +north = (ej < ry : U32)
  +px = sel(west, (ei * 16 + 12 : U32), sel(east, (ei * 16 + 4 : U32), (ei * 16 + 8 : U32)))
  +py = sel(west || east, (ej * 16 + 8 : U32), sel(north, (ej * 16 + 12 : U32), (ej * 16 + 4 : U32)))
  +d = sel(west, 2, sel(east, 0, sel(north, 3, 1)))
  ((px << 16n) .|. (py << 4n) .|. d : U32)

# what a rider thinks of a ride as they get off: too intense, or great
def Guest.verdict(+rd: Ride, +tgt: U32, +lk: U32, +mind: U32, +t: U32) -> U32:
  +rate = Ride.rate(rd)
  +k = Ride.kind(rd)
  sel(Ride.shop(k) || U32.is_eq(k, 0), mind,
    sel((Rate.i(rate) > Guest.tol(lk) : U32), Mind.make(4, tgt, t),
      sel((Ride.joy(rate, lk) >= 14 : U32), Mind.make(3, tgt, t), mind)))

# getting off: at the ride's exit (a shop's buyers stay where they stand)
def Guest.off(done: Bool, +id: U32, +x: U32, +y: U32, +dir: U32, +tgt: U32, +tmr: U32,
  +cash: U32, +hu: U32, +th: U32, +en: U32, +na: U32, +ha: U32, +lk: U32, +mind: U32, +q: Q,
  +rs: +List<Ride>, +t: U32) -> Guest:
  match done:
    case True{}:
      +rd = Rides.get(rs, tgt)
      +e = Ride.ex(rd)
      +out = Bool.not(U32.is_eq(e, NONE()))
      +a = Guest.alight(e, Ride.cx(rd), Ride.cy(rd), Ride.wd(rd))
      Guest{id, sel(out, (a >> 16n : U32), x), sel(out, ((a >> 4n) .&. 4095 : U32), y),
        sel(out, (a .&. 3 : U32), 0), 0, NONE(), 0, cash, hu, th, en, na, ha, lk,
        Guest.verdict(rd, tgt, lk, mind, t)}
    case False{}:
      Guest{id, x, y, dir, 1, tgt, (tmr - 1 : U32), cash, hu, th, en, na, ha, lk, mind}

def Guest.riding(g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +stn: Stn) -> Guest:
  Guest{+id, +x, +y, +dir, st, +tgt, +tmr, +cash, +hu, +th, +en, +na, +ha, +lk, +mind} = g
  Guest.off(Guest.done(tmr, dir, tgt, rs, stn), id, x, y, dir, tgt, tmr, cash, hu, th,
    en, na, ha, lk, mind, q, rs, t)

# needs drift a little every 16 ticks
def Guest.needs(g: Guest, +t: U32) -> Guest:
  Guest{+id, x, y, dir, st, tgt, tmr, cash, +hu, +th, +en, +na, +ha, lk, mind} = g
  +due = U32.is_eq(((t + id) .&. 15 : U32), 0)
  +bad = ((hu > 200) || (th > 200) || (na > 170) || (en < 40) : U32)
  +good = ((hu < 120) && (th < 120) && (na < 90) : U32)
  +ha2 = sel(bad, sub0(ha, 2), sel(good, (ha + 1 : U32), ha))
  Guest{id, x, y, dir, st, tgt, tmr, cash,
    sel(due, (hu + 1 : U32), hu), sel(due, (th + 2 : U32), th),
    sel(due, sub0(en, 1), en), sel(due, sub0(na, 3), na),
    sel(due, ha2, ha), lk, mind}

# walking: at a tile centre pick a target and a direction; move every
# other tick
def Guest.walk(g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +qs: +List<U32>) -> Guest:
  Guest{+id, +x, +y, +dir, +st, +tgt, +tmr, +cash, +hu, +th, +en, na, +ha,
    +lk, +mind} = g
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +here = Land.get(q, i, j)
  +h = Tile.h(here)
  +r = hash3(id, t, x)
  +ctr = Guest.at_center(x, y)
  +onq = U32.is_eq(Tile.obj(here), 7)
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
  +avoid = sel(U32.is_eq(Mind.code(mind), 1), Mind.ride(mind), NONE())
  +picks = Guest.pick_if(needt, rs, want, i, j, cash, r, lk, hu, th, avoid)
  +pick = (picks .&. 255 : U32)
  +wish = (picks >> 8n : U32)
  # priced out: they wanted a ride but won't pay what it costs
  +dear = needt && U32.is_eq(pick, NONE()) && Bool.not(U32.is_eq(wish, NONE()))
  +giveup = U32.is_eq(tmr, 0) || Bool.not(U32.is_eq(st2, 0))
  # waited too long in a queue
  +fed_up = onq && U32.is_eq(tmr, 0) && Bool.not(U32.is_eq(tgt, NONE()))
  +mind2 = sel(dear, Mind.make(1, wish, t), sel(fed_up, Mind.make(2, tgt, t), mind))
  +tgt2 = sel(needt, pick, sel(giveup, NONE(), tgt))
  +slow = onq && Bool.not(U32.is_eq(((t + id) .&. 3 : U32), 0))
  +tmr2 = sel(needt, 1500, sel(slow, tmr, sub0(tmr, 1)))
  # steering
  +trd = Rides.get(rs, tgt2)
  # a ride with a queue is reached at its entrance, where its riders wait
  +ent = Ride.ent(trd)
  +queued = Bool.not(home) && Bool.not(U32.is_eq(tgt2, NONE())) && Bool.not(U32.is_eq(ent, NONE()))
  +tx = sel(home, GATE_X(), sel(U32.is_eq(tgt2, NONE()), i, sel(queued, (ent >> 6n : U32), Ride.cx(trd))))
  +ty = sel(home, GATE_Y(), sel(U32.is_eq(tgt2, NONE()), j, sel(queued, (ent .&. 63 : U32), Ride.cy(trd))))
  +lim = sel(queued, 0, 1)
  +there = queued && ctr && U32.is_eq(pk(i, j), ent)
  # only a guest bound for a ride with a queue may step into one
  +qok = onq || queued && U32.is_eq(st3, 0)
  +tick = U32.is_eq(((t + id) .&. 1 : U32), 0)
  # in a queue, a guest may step off only at its free end
  +fe = Bool.not(onq) || U32.is_eq(Tile.a(here), 1)
  +dir2 = Guest.steer(ctr && tick && Bool.not(there), q, i, j, h, dir, tx, ty, r, qok, onq, fe, lim)
  +ahead = U32.is_eq(Land.obj(q, ((x + dx_of(dir2) * 8) >> 4n : U32), ((y + dy_of(dir2) * 8) >> 4n : U32)), 7)
  +go = tick
    && (Bool.not(ctr) || Guest.can_step(q, i, j, h, dir2, qok, onq, fe))
    && Bool.not(there)
    && Bool.not(U32.is_eq(st3, 3))
    && Bool.not(Queue.wait(tick && (onq || ahead) && Bool.not(U32.is_eq(tgt2, NONE())), qs, x, y, dir2))
  +x2 = sel(go, (x + dx_of(dir2) : U32), x)
  +y2 = sel(go, (y + dy_of(dir2) : U32), y)
  +finish = U32.is_eq(((r >> 8n) .&. 1023 : U32), 0)
  +lk2 = (sel(finish, (lk .&. 4277993471 : U32), (lk .&. 4278190079 : U32)) .|. sel(go, 16777216, 0) : U32)
  Guest{id, x2, y2, dir2, st3, tgt2, tmr2, cash, hu, th, en, na, sel(dear || fed_up, sub0(ha, 6), ha), lk2, mind2}

def Guest.st(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  st

def Guest.move.go(riding: Bool, boards: Bool, +g: Guest, +q: Q,
  +rs: +List<Ride>, +t: U32, +plan: +List<Board>, +stn: Stn, +qs: +List<U32>) -> Guest:
  match riding boards:
    case True{} _:
      Guest.riding(g, q, rs, t, stn)
    case False{} True{}:
      Guest.board(g, rs, Boards.seat(plan, Guest.id(g)), stn)
    case False{} False{}:
      Guest.walk(g, q, rs, t, qs)

def Guest.move(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +stn: Stn, +qs: +List<U32>) -> Guest:
  Guest.move.go(U32.is_eq(Guest.st(g), 1), Boards.has(plan, Guest.id(g)), g, q, rs, t,
    plan, stn, qs)

# a guest's whole tick; the final clamp keeps every stat in 0..255
def Guest.step(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +stn: Stn, +qs: +List<U32>) -> Guest:
  Guest.clamp(Guest.needs(Guest.move(g, q, rs, t, plan, stn, qs), t))

def Guests.step(+gs: +List<Guest>, +q: Q, +rs: +List<Ride>, +t: U32,
  +plan: +List<Board>, +stn: Stn, +qs: +List<U32>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guest.step(g, q, rs, t, plan, stn, qs) <> Guests.step(rest, q, rs, t, plan, stn, qs)

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

def Guests.arrive(go: Bool, +id: U32, +t: U32, +fee: U32) -> +List<Guest>:
  match go:
    case True{}:
      [Guest.new(id, t, fee)]
    case False{}:
      []

def Rides.attractions(+rs: +List<Ride>) -> U32:
  match rs:
    case []:
      0
    case r <> rest:
      (sel(Ride.is_open(r), 1, 0) + Rides.attractions(rest) : U32)

# a new adventurer comes through the gate now and then: more rides and a
# better park rating draw more, a steep entry fee fewer
type Fin is Data:
  Fin{fee: U32, loan: U32, rating: U32, now: List<&2, U32>, last: List<&2, U32>,
    hist: List<&2, U32>}

def Fin.fee(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist} = f
  fee

def Fin.rating(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist} = f
  rating

def Guests.come(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +f: Fin) -> Bool:
  +base = U32.min((2 + Rides.attractions(rs) * 3 : U32), 24)
  +fee = Fin.fee(f)
  +rate = sub0((base * (200 + Fin.rating(f)) / 800 : U32), (fee * fee / 16 : U32))
  +roll = (hash(t, 77) .&. 255 : U32)
  (roll < rate : U32) && (len32(Guest, gs) < 700 : U32)

def Guests.arrivals(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +nid: U32, +f: Fin)
  -> +List<Guest>:
  Guests.arrive(Guests.come(gs, rs, t, f), nid, t, U32.min(Fin.fee(f), 40))

# Rides each tick: doors, queue lengths, the cycle, and the tallies
# -----------------------------------------------------------------

def Tab.add(+xs: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match xs:
    case []:
      []
    case x <> rest:
      sel(U32.is_eq(i, 0), (x + v : U32), x) <> Tab.add(rest, (i - 1 : U32), v)

def Qlen.put(on: Bool, +tab: +List<U32>, +i: U32) -> +List<U32>:
  match on:
    case True{}:
      Tab.add(tab, i, 1)
    case False{}:
      tab

def Qlen.add(g: Guest, +q: Q, +tab: +List<U32>) -> +List<U32>:
  Guest{id, +x, +y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind} = g
  Qlen.put(U32.is_eq(st, 0) && Bool.not(U32.is_eq(tgt, NONE()))
    && U32.is_eq(Land.obj(q, (x >> 4n : U32), (y >> 4n : U32)), 7), tab, tgt)

# guests standing in a queue, counted by the ride they want
def Qlen.fill(+gs: +List<Guest>, +q: Q, +tab: +List<U32>) -> +List<U32>:
  match gs:
    case []:
      tab
    case g <> rest:
      Qlen.fill(rest, q, Qlen.add(g, q, tab))

# counted every 16 ticks (then the rides keep their last count)
def Qlen.fill_if(now: Bool, +gs: +List<Guest>, +q: Q, +n: U32) -> +List<U32>:
  match now:
    case True{}:
      Qlen.fill(gs, q, Tab.zero(n, []))
    case False{}:
      []

def Seat.count(+m: U32) -> U32:
  ((m .&. 1) + ((m >> 1n) .&. 1) + ((m >> 2n) .&. 1) + ((m >> 3n) .&. 1)
    + ((m >> 4n) .&. 1) + ((m >> 5n) .&. 1) + ((m >> 6n) .&. 1) + ((m >> 7n) .&. 1) : U32)

def Boards.count(+bs: +List<Board>, +r: U32, +acc: U32) -> U32:
  match bs:
    case []:
      acc
    case b <> rest:
      Boards.count(rest, r, (acc + sel(U32.is_eq(Board.ride(b), r), 1, 0) : U32))

# the cycle: loading until full, or until the first rider has waited wmax
# (never before wmin); running for the ride's duration; unloading for half
# a second; then loading again
def Ride.next_ph(+ph: U32, +tm: U32, +go: Bool, +dur: U32) -> U32:
  match ph:
    case 0:
      sel(go, 1, 0)
    case 1:
      sel((tm + 1 >= dur : U32), 2, 1)
    case _:
      sel((tm + 1 >= 30 : U32), 0, 2)

def Ride.next_tm(+ph: U32, +ph2: U32, +tm: U32, +n: U32) -> U32:
  sel(Bool.not(U32.is_eq(ph, ph2)), 0,
    sel(U32.is_eq(ph, 0), sel((n > 0 : U32), U32.min((tm + 1 : U32), 60000), 0), (tm + 1 : U32)))

def Track.tally(+ps: +List<Piece>, +t: U32, +zs: U32) -> U32 & U32:
  match ps:
    case []:
      (t, zs)
    case p <> rest:
      Piece{x, y, +z, +kind, dir} = p
      +turn = sel(U32.is_eq(kind, 3) || U32.is_eq(kind, 4), 1, 0)
      +drop = sel(U32.is_eq(kind, 2), 256, 0)
      +lo = U32.min((zs .&. 255 : U32), z)
      +hi = U32.max((zs >> 8n : U32), z)
      Track.tally(rest, (t + turn + drop + 65536 : U32), (lo .|. (hi << 8n) : U32))

def Track.rate.go(pr: U32 & U32) -> U32:
  (+t, +zs) = pr
  +turns = (t .&. 255 : U32)
  +drops = ((t >> 8n) .&. 255 : U32)
  +n = (t >> 16n : U32)
  +height = sub0((zs >> 8n : U32), (zs .&. 255 : U32))
  sel(U32.is_eq(n, 0), 0, Rate.pack((60 + 12 * turns + 30 * drops + 30 * height + 2 * n : U32),
    (40 + 12 * turns + 25 * drops + 35 * height : U32), (20 + 8 * turns + 15 * drops + 15 * height : U32)))

def Track.rating(+ps: +List<Piece>) -> U32:
  Track.rate.go(Track.tally(ps, 0, 255))

def Ride.rating(+k: U32, +ps: +List<Piece>) -> U32:
  match k:
    case 5:
      Track.rating(ps)
    case _:
      Ride.rate0(k)

# Money: every change to the park's gold is a ledger entry
# ---------------------------------------------------------
# kind: 1 ride tickets, 2 upkeep, 3 construction, 4 refunds, 5 food, 6 drinks,
# 7 entry fees, 8 loans taken, 9 loans repaid, 10 loan interest

def Ride.tick(r: Ride, +idx: U32, +q: Q, +ps: +List<Piece>, +occ: +List<U32>,
  +plan: +List<Board>, +qt: +List<U32>, +fresh: Bool) -> Ride:
  Ride{+kind, +x, +y, +w, h, +price, open, +ph, +tm, ent, ex, +qlen, +wmin, +wmax, +total, +earned, born, rate} = r
  +n = Seat.count((Tab.at(occ, idx) .|. Boards.mask(plan, idx, 0) : U32))
  +nb = Boards.count(plan, idx, 0)
  +go = (n > 0 : U32) && (tm >= wmin : U32) && ((n >= Ride.seats(kind) : U32) || (tm >= wmax : U32))
  +ph2 = sel(Ride.cycles(kind), Ride.next_ph(ph, tm, go, Ride.duration(kind)), 0)
  Ride{kind, x, y, w, h, price, open, ph2, sel(Ride.cycles(kind), Ride.next_tm(ph, ph2, tm, n), 0),
    Ride.door(kind, q, ps, x, y, w, 7), Ride.door(kind, q, ps, x, y, w, 1), sel(fresh, Tab.at(qt, idx), qlen),
    wmin, wmax, (total + nb : U32), (earned + nb * price : U32), born, Ride.rating(kind, ps)}

def Rides.tick(+rs: +List<Ride>, +idx: U32, +q: Q, +ps: +List<Piece>, +occ: +List<U32>,
  +plan: +List<Board>, +qt: +List<U32>, +fresh: Bool) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Ride.tick(r, idx, q, ps, occ, plan, qt, fresh) <> Rides.tick(rest, (idx + 1 : U32), q, ps, occ, plan, qt, fresh)

# The coaster's ratings from its track: turns and drops thrill, height
# thrills most, length adds a little; a track that isn't a circuit yet has
# none. Tally: turns | drops << 8 | pieces << 16, and heights lo | hi << 8.
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

# what a sale counts as: the tavern sells food, the potion stall drinks
def Ride.cat(+k: U32) -> U32:
  match k:
    case 3:
      6
    case 4:
      5
    case _:
      1

# a board is a sale: the price of its ride (the same Guest.fee its guest pays)
def Board.sale(b: Board, +rs: +List<Ride>) -> Txn:
  Board{g, +ride, seat} = b
  +rd = Rides.get(rs, ride)
  Gain{Ride.cat(Ride.kind(rd)), Ride.price(rd)}

def Ledger.sales(+plan: +List<Board>, +rs: +List<Ride>) -> +List<Txn>:
  match plan:
    case []:
      []
    case b <> rest:
      Board.sale(b, rs) <> Ledger.sales(rest, rs)

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

# a tick's gold: sales, the arrivals' entry fees, and each month the rides'
# upkeep and the loan's interest (1/80 of it)
def Fin.loan(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist} = f
  loan

def Ledger.tick(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +narr: U32, +f: Fin) -> +List<Txn>:
  +monthly = U32.is_eq((t % MONTH() : U32), 0) && (t > 0 : U32)
  +fees = (narr * U32.min(Fin.fee(f), 40) : U32)
  +interest = (Fin.loan(f) / 80 : U32)
  Ledger.put(Bool.not(U32.is_eq(fees, 0)), Gain{7, fees},
    List.append(&2, Txn, Ledger.sales(plan, rs),
      Bool.pick(+List<Txn>, monthly,
        Ledger.put(Bool.not(U32.is_eq(interest, 0)), Spend{10, interest}, Ledger.upkeep(rs)), [])))

# The books: every ledger entry is added to this month's column
def Txn.book(t: Txn, +tab: +List<U32>) -> +List<U32>:
  match t:
    case Gain{+k, +a}:
      Tab.add(tab, (k - 1 : U32), a)
    case Spend{+k, +a}:
      Tab.add(tab, (k - 1 : U32), a)

def Fin.book_all(+xs: +List<Txn>, +tab: +List<U32>) -> +List<U32>:
  match xs:
    case []:
      tab
    case t <> rest:
      Fin.book_all(rest, Txn.book(t, tab))

def Fin.book(f: Fin, +xs: +List<Txn>) -> Fin:
  Fin{fee, loan, rating, +now, last, hist} = f
  Fin{fee, loan, rating, Fin.book_all(xs, now), last, hist}

# The park rating: happy guests and open rides raise it, queasy guests lower
# it (worked out every 64 ticks)
def Guests.happy_sum(+gs: +List<Guest>, +acc: U32) -> U32:
  match gs:
    case []:
      acc
    case g <> rest:
      Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, +ha, lk, mind} = g
      Guests.happy_sum(rest, (acc + ha : U32))

def Guests.sick_sum(+gs: +List<Guest>, +acc: U32) -> U32:
  match gs:
    case []:
      acc
    case g <> rest:
      Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, +na, ha, lk, mind} = g
      Guests.sick_sum(rest, (acc + na : U32))

def Park.rate(+gs: +List<Guest>, +rs: +List<Ride>) -> U32:
  +n = len32(Guest, gs)
  +happy = sel(U32.is_eq(n, 0), 200, (Guests.happy_sum(gs, 0) / U32.max(n, 1) : U32))
  +sick = sel(U32.is_eq(n, 0), 0, (Guests.sick_sum(gs, 0) / U32.max(n, 1) : U32))
  U32.min(sub0((150 + happy * 2 + U32.min((Rides.attractions(rs) * 30 : U32), 240) : U32), sick), 999)

def Park.rate_if(now: Bool, +gs: +List<Guest>, +rs: +List<Ride>, +old: U32) -> U32:
  match now:
    case True{}:
      Park.rate(gs, rs)
    case False{}:
      old

def Wins32.take(+n: Nat, +xs: +List<U32>) -> +List<U32>:
  match n xs:
    case 0n _:
      []
    case 1n+m Con{x, rest}:
      x <> Wins32.take(m, rest)
    case 1n+m Nil{}:
      []

def Fin.fresh(month: Bool, +now: +List<U32>) -> +List<U32>:
  match month:
    case True{}:
      Tab.zero(10, [])
    case False{}:
      now

def Fin.roll(month: Bool, +now: +List<U32>, +last: +List<U32>) -> +List<U32>:
  match month:
    case True{}:
      now
    case False{}:
      last

def Fin.sample(go: Bool, +gs: +List<Guest>, +hist: +List<U32>) -> +List<U32>:
  match go:
    case True{}:
      Wins32.take(32n, len32(Guest, gs) <> hist)
    case False{}:
      hist

# each tick: the rating now and then, the guest count sampled, and at a
# month's turn this month's column becomes last month's
def Fin.tick(f: Fin, +t: U32, +gs: +List<Guest>, +rs: +List<Ride>) -> Fin:
  Fin{fee, loan, +rating, +now, +last, +hist} = f
  +month = U32.is_eq((t % MONTH() : U32), 0) && (t > 0 : U32)
  +sample = U32.is_eq((t % 450 : U32), 0)
  Fin{fee, loan, Park.rate_if(U32.is_eq((t .&. 63 : U32), 0), gs, rs, rating),
    Fin.fresh(month, now), Fin.roll(month, now, last), Fin.sample(sample, gs, hist)}

# The Wyrm Coaster: track pieces and block sections
# -------------------------------------------------
# A piece stands on tile (x, y), entered at height z heading dir. kind: 0
# straight, 1 up, 2 down, 3 turn left, 4 turn right, 5 station, 6 lift hill.

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
  Train{id, +prog, +speed, +wait} = t
  +k = Piece.kind(Pieces.get(ps, (start + (prog >> 8n) : U32)))
  +hold = U32.is_eq(st, 1) && (wait > 0 : U32)
  +s1 = sel(U32.is_eq(k, 6), 20, sel(U32.is_eq(k, 2), (speed + 3 : U32),
    sel(U32.is_eq(k, 1), sub0(speed, 3), sub0(speed, 1))))
  +s2 = sel(hold, 0, U32.min(U32.max(s1, 10), 90))
  +end = (len * 256 : U32)
  Train{id, U32.min((prog + s2 : U32), end), s2, sub0(wait, 1)}

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
  Train{id, prog, speed, wait} = t
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
  Train{id, prog, speed, wait} = t
  Train{id, (prog - len * 256 : U32), speed, sel(U32.is_eq(st, 1), 150, 0)}

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
      Bool.pick(Slot, train, Held{start, len, st, Train{k, 0, 0, 60}},
        Free{start, len, st}) <> rest

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

# The park's books and standing: fee: the entry fee; loan: gold owed;
# rating: the park rating (0..999); now, last: this month's and last month's
# gold by ledger kind (index kind - 1); hist: the guest count, sampled eight
# times a month, newest first (32 samples)
def Fin.new() -> Fin:
  Fin{0, 0, 600, Tab.zero(10, []), Tab.zero(10, []), []}

def Fin.now(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist} = f
  now

def Fin.last(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist} = f
  last

def Fin.hist(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist} = f
  hist

type Park is Data:
  Park{map: Q, guests: List<&2, Guest>, rides: List<&2, Ride>, track: Track,
    cash: U32, time: U32, nid: U32, fin: Fin}

type Act is Data:
  Tick{}
  Build{tool: U32, x: U32, y: U32, v: U32}
  TrackOp{op: U32}
  RideOp{ride: U32, op: U32}
  ParkOp{op: U32}

type Out is Data:
  Out{park: Park, ledger: List<&2, Txn>, arrived: List<&2, Guest>,
    departed: List<&2, Guest>}

def Track.pieces(t: Track) -> +List<Piece>:
  Track{pieces, open, blocks, start, end} = t
  pieces

def Park.tick(p: Park) -> Out:
  Park{+map, +guests, +rides, +track, cash, +time, +nid, +fin} = p
  +stn = Track.stn(track)
  +occ = Occ.table(guests, rides, stn)
  +plan = Boards.plan(guests, occ, map, rides, stn, [])
  +moved = Guests.step(guests, map, rides, time, plan, stn, Queue.list(guests, map, []))
  +arr = Guests.arrivals(guests, rides, time, nid, fin)
  +led = Ledger.tick(guests, rides, time, plan, len32(Guest, arr), fin)
  Out{Park{map, List.append(&2, Guest, arr, Guests.stay(moved)),
    Rides.tick(rides, 0, map, Track.pieces(track), occ, plan,
      Qlen.fill_if(U32.is_eq((time .&. 15 : U32), 0), guests, map, len32(Ride, rides)), U32.is_eq((time .&. 15 : U32), 0)),
    Track.tick(track), Ledger.apply(led, cash), (time + 1 : U32),
    (nid + len32(Guest, arr) : U32), Fin.tick(fin, time, guests, rides)}, led, arr, Guests.left(moved)}

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
    case 11:
      12
    case _:
      Ride.cost((tool - 4 : U32))

def Build.can_pay(+cash: U32, +cost: U32) -> Bool:
  Bool.not(neg(cash)) && (cash >= cost : U32)

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
      U32.is_eq(o, 1) || U32.is_eq(o, 2) || U32.is_eq(o, 3) || U32.is_eq(o, 7)
    case 11:
      empty && dry
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
  Ride{kind, +x, +y, +w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
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
    case 11:
      Land.set(q, x, y, Tile{h, 1, 7, 0, 0})
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
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
  Ride{0, x, y, w, h, price, 0, 0, 0, NONE(), NONE(), 0, wmin, wmax, total, earned, born, 0}

def Rides.kill(+rs: +List<Ride>, +i: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), Ride.killed(r), r)
        <> Rides.kill(rest, (i - 1 : U32))

def Build.rides(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32,
  +y: U32, +time: U32) -> +List<Ride>:
  match ok:
    case True{}:
      +t = Land.get(q, x, y)
      +k = (tool - 4 : U32)
      +s = Ride.size(k)
      Bool.pick(+List<Ride>, U32.is_eq(tool, 9) && U32.is_eq(Tile.obj(t), 3),
        Rides.kill(rs, Tile.a(t)),
        Bool.pick(+List<Ride>, (tool >= 5 : U32) && (tool <= 8 : U32),
          List.append(&2, Ride, rs, [Ride.new(k, x, y, s, 1, time)]),
          Bool.pick(+List<Ride>, U32.is_eq(tool, 10),
            List.append(&2, Ride, rs, [Ride.new(5, x, y, 1, 0, time)]),
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
  Park{+map, guests, +rides, +track, +cash, +time, nid, fin} = p
  +ok = Build.ok(map, track, cash, tool, x, y)
  +led = Build.ledger(ok, map, rides, tool, x, y)
  Out{Park{Land.fix(Build.map(ok, map, rides, tool, x, y, v)), guests,
    Build.rides(ok, map, rides, tool, x, y, time), Build.track(ok, map, track, tool,
    x, y, v), Ledger.apply(led, cash), time, nid, fin}, led, [], []}

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
      Ride{+kind, x, y, w, h, price, op, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate} = r
      Ride{kind, x, y, w, h, price, sel(U32.is_eq(kind, 5), open, op), ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate}
        <> Rides.coaster(rest, open)

def Park.track_op(p: Park, +op: U32) -> Out:
  Park{+map, guests, +rides, +track, +cash, time, nid, fin} = p
  +ok = TrackOp.ok(map, track, cash, op)
  +led = TrackOp.ledger(ok, op)
  +trk2 = Track.op(track, op, ok)
  Out{Park{Land.fix(TrackOp.map(ok, map, track, op)), guests,
    Rides.coaster(rides, sel(Track.open(trk2), 1, 0)), trk2,
    Ledger.apply(led, cash), time, nid, fin}, led, [], []}

# Ride settings (the ride window)
# -------------------------------
# op 0: open or close (the coaster opens through its track instead); 1, 2:
# price up, down; 3, 4: minimum wait up, down; 5, 6: maximum wait up, down

def MAX_PRICE() -> U32:
  20

def Ride.set(r: Ride, +op: U32) -> Ride:
  Ride{+kind, x, y, w, h, +price, +open, ph, tm, ent, ex, qlen, +wmin, +wmax, total, earned, born, rate} = r
  +flip = U32.is_eq(op, 0) && Bool.not(U32.is_eq(kind, 5))
  +price2 = Price.cap(sel(U32.is_eq(op, 1), (price + 1 : U32), sel(U32.is_eq(op, 2), sub0(price, 1), price)))
  +wmin2 = sel(U32.is_eq(op, 3), U32.min((wmin + 30 : U32), wmax),
    sel(U32.is_eq(op, 4), sub0(wmin, 30), wmin))
  +wmax2 = sel(U32.is_eq(op, 5), U32.min((wmax + 60 : U32), 3600),
    sel(U32.is_eq(op, 6), U32.max(sub0(wmax, 60), wmin), wmax))
  Ride{kind, x, y, w, h, price2, sel(flip, sel(U32.is_eq(open, 1), 0, 1), open), ph, tm, ent, ex, qlen, wmin2, wmax2, total, earned, born, rate}

def Rides.set(+rs: +List<Ride>, +i: U32, +op: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), Ride.set(r, op), r) <> Rides.set(rest, (i - 1 : U32), op)

def Park.ride_op(p: Park, +ride: U32, +op: U32) -> Out:
  Park{map, guests, +rides, track, cash, time, nid, fin} = p
  Out{Park{map, guests, Rides.set(rides, ride, op), track, cash, time, nid, fin}, [], [], []}

# Park settings (the park and finances windows)
# ---------------------------------------------
# op 0, 1: entry fee up, down (0..40); 2: borrow 1000 gold (owing at most
# 20000); 3: repay 1000 (with the gold in hand)

def Fin.set(f: Fin, +op: U32, +borrow: Bool, +repay: Bool) -> Fin:
  Fin{+fee, +loan, rating, now, last, hist} = f
  Fin{Fee.cap(sel(U32.is_eq(op, 0), (fee + 1 : U32), sel(U32.is_eq(op, 1), sub0(fee, 1), fee))),
    sel(borrow, (loan + 1000 : U32), sel(repay, (loan - 1000 : U32), loan)), rating, now, last, hist}

def Park.park_op(p: Park, +op: U32) -> Out:
  Park{map, guests, rides, track, +cash, time, nid, +fin} = p
  +loan = Fin.loan(fin)
  +borrow = U32.is_eq(op, 2) && (loan + 1000 <= 20000 : U32)
  +repay = U32.is_eq(op, 3) && (loan >= 1000 : U32) && Bool.not(neg(cash)) && (cash >= 1000 : U32)
  +led = Bool.pick(+List<Txn>, borrow, [Gain{8, 1000}], Bool.pick(+List<Txn>, repay, [Spend{9, 1000}], []))
  Out{Park{map, guests, rides, track, Ledger.apply(led, cash), time, nid, Fin.set(fin, op, borrow, repay)},
    led, [], []}

# every step's ledger goes into the books
def Out.book(o: Out) -> Out:
  Out{p, +l, ar, de} = o
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  Out{Park{map, guests, rides, track, cash, time, nid, Fin.book(fin, l)}, l, ar, de}

def Park.step0(p: Park, a: Act) -> Out:
  match a:
    case Tick{}:
      Park.tick(p)
    case Build{tool, x, y, v}:
      Park.build(p, tool, x, y, v)
    case TrackOp{op}:
      Park.track_op(p, op)
    case RideOp{ride, op}:
      Park.ride_op(p, ride, op)
    case ParkOp{op}:
      Park.park_op(p, op)

# the one door every change comes through
def Park.step(p: Park, a: Act) -> Out:
  Out.book(Park.step0(p, a))

def Park.new() -> Park:
  Park{Land.fix(Q.build(6n, 0, 0)), [], [], Track.empty(), 30000, 0, 1, Fin.new()}

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
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  map

def Park.guests(p: Park) -> +List<Guest>:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  guests

def Park.track(p: Park) -> Track:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  track

def Park.cash(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  cash

def Park.time(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  time

def Park.rides(p: Park) -> +List<Ride>:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  rides

def Park.fin(p: Park) -> Fin:
  Park{map, guests, rides, track, cash, time, nid, fin} = p
  fin
