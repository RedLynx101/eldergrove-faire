# Eldergrove Faire -- the art. Every pixel is painted by code: each shade
# function answers the colour of one pixel of one thing, or TR() where the
# thing is see-through. Coordinates are logical pixels (2x2 screen pixels).
import Base
import ./font.bend as F

# Helpers
# -------

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def TR() -> U32:
  16777216

def opaque(+c: U32) -> Bool:
  Bool.not(U32.is_eq(c, 16777216))

# first opaque of two layers
def over(+a: U32, +b: U32) -> U32:
  sel(opaque(a), a, b)

def hash(+x: U32, +y: U32) -> U32:
  +h = ((x * 374761393) + (y * 668265263) + 1442695041 : U32)
  +h2 = ((h .^. (h >> 13n)) * 1274126177 : U32)
  (h2 .^. (h2 >> 16n) : U32)

def neg(+a: U32) -> Bool:
  (a >= 2147483648 : U32)

def sabs(+a: U32) -> U32:
  sel(neg(a), (0 - a : U32), a)

# signed a < b for wrapped values
def slt(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

def sle(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) <= (b .^. 2147483648) : U32)

def between(+a: U32, +lo: U32, +hi: U32) -> Bool:
  sle(lo, a) && sle(a, hi)

# scale a colour by k/256
def shade(+c: U32, +k: U32) -> U32:
  +r = U32.min((((c >> 16n) .&. 255) * k >> 8n : U32), 255)
  +g = U32.min((((c >> 8n) .&. 255) * k >> 8n : U32), 255)
  +b = U32.min((((c .&. 255) * k) >> 8n : U32), 255)
  ((r << 16n) .|. (g << 8n) .|. b : U32)

# inside the ellipse (dx/rx)^2 + (dy/ry)^2 <= 1 (dx, dy signed)
def ell(+dx: U32, +dy: U32, +rx: U32, +ry: U32) -> Bool:
  ((dx * dx * ry * ry + dy * dy * rx * rx) <= (rx * rx * ry * ry) : U32)

def div3(+n: U32) -> U32:
  ((n * 43691) >> 17n : U32)

# a smooth-ish wave: 0..64..0 over a period of 256
def tri(+a: U32) -> U32:
  +m = (a .&. 255 : U32)
  sel((m < 128 : U32), (m >> 1n : U32), ((255 - m) >> 1n : U32))

# sine-like in -r..r (as wrapped) for an angle in 0..255
def wsin(+a: U32, +r: U32) -> U32:
  +m = (a .&. 127 : U32)
  +p = ((m * (128 - m) * r) >> 12n : U32)
  sel(((a .&. 128) > 0 : U32), (0 - p : U32), p)

def wcos(+a: U32, +r: U32) -> U32:
  wsin((a + 64 : U32), r)

# tile-local iso coordinates of screen offset (X, Y2 = 2*dy): u, v in 0..16
def iso_u(+X: U32, +Y: U32) -> U32:
  +s = (X + Y : U32)
  ((s >> 1n) .|. (s .&. 2147483648) : U32)

def iso_v(+X: U32, +Y: U32) -> U32:
  +s = (Y - X : U32)
  ((s >> 1n) .|. (s .&. 2147483648) : U32)

# Terrain
# -------

def Art.grass(+n: U32, +edge: U32) -> U32:
  +f = (n .&. 255 : U32)
  +base = sel((f < 90 : U32), 5150266, sel((f < 200 : U32), 4626999, 5875263))
  +flower = sel(U32.is_eq((n .&. 1023 : U32), 7), 15895224, sel(U32.is_eq((n .&. 1023 : U32), 19), 16179290,
    sel(U32.is_eq((n .&. 1023 : U32), 31), 16053480, sel(U32.is_eq((n .&. 1023 : U32), 43), 9086207, TR()))))
  over(flower, shade(base, edge))

def Art.wild(+n: U32, +edge: U32) -> U32:
  +f = (n .&. 255 : U32)
  +base = sel((f < 100 : U32), 3104300, sel((f < 210 : U32), 3828531, 2640419))
  +leaf = sel(U32.is_eq((f .&. 31 : U32), 5), 7031338, TR())
  over(leaf, shade(base, edge))

def Art.dirt(+n: U32, +edge: U32) -> U32:
  +f = (n .&. 255 : U32)
  shade(sel((f < 120 : U32), 10124874, sel((f < 220 : U32), 9138758, 11177304)),
    edge)

def Art.water(+wx: U32, +wy: U32, +t: U32) -> U32:
  +w1 = (((wx + (wy * 2) + (t >> 2n)) .&. 31) : U32)
  +w2 = (((wx * 3 + (0 - wy) * 2 + (t >> 3n)) .&. 63) : U32)
  +spark = U32.is_eq((hash((wx >> 1n : U32), (wy + (t >> 4n) : U32)) .&. 511 : U32), 3)
  sel(spark, 16119285, sel(U32.is_eq(w1, 0) || U32.is_eq(w2, 0), 7320038,
    sel((w1 < 12 : U32), 3108784, 2645916)))

# cobblestones laid on the iso grid
def Art.cobble(+u: U32, +v: U32, +seed: U32) -> U32:
  +off = sel(U32.is_eq(((v >> 2n) .&. 1 : U32), 1), 2, 0)
  +uu = (u + off : U32)
  +mortar = U32.is_eq((uu .&. 3 : U32), 0) || U32.is_eq((v .&. 3 : U32), 0)
  +c = (hash(((uu >> 2n) + seed * 7 : U32), ((v >> 2n) + seed : U32)) .&. 3 : U32)
  sel(mortar, 8155746, sel(U32.is_eq(c, 0), 12168597, sel(U32.is_eq(c, 1),
    11050116, sel(U32.is_eq(c, 2), 13155750, 12037249))))

def Art.cliff(+d: U32, +px: U32, +left: Bool, +wild: Bool) -> U32:
  +row = (d >> 2n : U32)
  +mortar = U32.is_eq((d .&. 3 : U32), 0)
    || U32.is_eq(((px + row * 3) .&. 7 : U32), 0)
  +stone = sel(wild, 7031342, 9076856)
  +c = sel(mortar, shade(stone, 170), stone)
  +lip = U32.is_eq(d, 0)
  sel(lip, sel(wild, 3104300, 4626999), sel(left, c, shade(c, 190)))

# the ground block: top face (terrain, path, hover outline) and cliff faces
# dl/dr px down. wx, wy: world-screen position of the top vertex. Each stage
# dispatches with a match, so a pixel only pays for the branch it takes.
def Art.ground(+ter: U32, +n: U32, +edge: U32, +wx: U32, +wy: U32, +t: U32)
  -> U32:
  match ter:
    case 2:
      Art.water(wx, wy, t)
    case 1:
      Art.dirt(n, edge)
    case 4:
      Art.wild(n, edge)
    case _:
      Art.grass(n, edge)

def Art.surface(paved: Bool, +ter: U32, +u: U32, +v: U32, +wx: U32, +wy: U32,
  +t: U32) -> U32:
  match paved:
    case True{}:
      Art.cobble(u, v, ((wx - u + v) >> 4n : U32))
    case False{}:
      +n = hash(wx, wy)
      +edge = sel((u < 1 : U32) || (v < 1 : U32), 272, sel((u > 14 : U32) || (v > 14 : U32), 236, 256))
      Art.ground(ter, n, edge, wx, wy, t)

def Art.top(outline: Bool, +ter: U32, +obj: U32, +u: U32, +v: U32, +wx: U32,
  +wy: U32, +t: U32) -> U32:
  match outline:
    case True{}:
      16769126
    case False{}:
      Art.surface(U32.is_eq(obj, 1) || U32.is_eq(obj, 5), ter, u, v, wx, wy, t)

def Art.faces(onl: Bool, onr: Bool, +dl: U32, +dr: U32, +le: U32, +re: U32,
  +px: U32, +py: U32, +wild: Bool) -> U32:
  match onl onr:
    case True{} _:
      Art.cliff((py - le : U32), px, True{}, wild)
    case False{} True{}:
      Art.cliff((py - re : U32), px, False{}, wild)
    case False{} False{}:
      TR()

def Art.block.go(top: Bool, +x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32,
  +obj: U32, +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32,
  +u: U32, +v: U32) -> U32:
  match top:
    case True{}:
      +outline = U32.is_eq(hov, 1) && ((u < 1 : U32) || (v < 1 : U32) || (u > 14 : U32) || (v > 14 : U32))
      Art.top(outline, ter, obj, u, v, (wx + (px - x) : U32), (wy + (py - y) : U32), t)
    case False{}:
      +lx = (px - (x - 16) : U32)
      +le = (y + 8 + (lx >> 1n) : U32)
      +rx = (px - x : U32)
      +re = (y + 16 - (rx >> 1n) : U32)
      Art.faces((lx < 16 : U32) && (py >= le : U32) && (py < le + dl : U32),
        (rx < 16 : U32) && (py >= re : U32) && (py < re + dr : U32), dl, dr, le, re,
        px, py, U32.is_eq(ter, 4))

def Art.block(+x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32, +obj: U32,
  +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32) -> U32:
  +X = (px - x : U32)
  +Y = ((py - y) * 2 : U32)
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  Art.block.go((u < 16 : U32) && (v < 16 : U32), x, y, dl, dr, ter, obj, hov,
    wx, wy, t, px, py, u, v)

# Trees (anchored at the tile centre)
# -----------------------------------

def Art.leafy(+dx: U32, +dy: U32, +cx: U32, +cy: U32, +r: U32, +n: U32,
  +c: U32) -> U32:
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +d2 = (ex * ex + ey * ey : U32)
  +l = (ex + ey : U32)
  +k = sel(slt(l, (0 - r / 2 : U32)), 300, sel(slt((r / 2 : U32), l), 170, 230))
  +rim = ((d2 + r * 2) > (r * r) : U32) && slt(0, l)
  sel((d2 <= r * r : U32), sel(rim, shade(c, 110),
    shade(c, sel(U32.is_eq((n .&. 7 : U32), 0), (k + 40 : U32), k))), TR())

def Art.oak(+dx: U32, +dy: U32, +n: U32) -> U32:
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 9 : U32), 0)
  +bark = sel(U32.is_eq(dx, 1), 5388834, 7031339)
  +leaf = {4557110 : U32}
  over(Art.leafy(dx, dy, 0, (0 - 19 : U32), 8, n, leaf),
    over(Art.leafy(dx, dy, (0 - 5 : U32), (0 - 13 : U32), 6, n, leaf),
      over(Art.leafy(dx, dy, 5, (0 - 12 : U32), 6, n, leaf),
        sel(trunk, bark, TR()))))

def Art.pine_tier(+dx: U32, +dy: U32, +apex: U32, +h: U32, +w: U32) -> U32:
  +d = (dy - apex : U32)
  +inside = (d < h : U32) && ((sabs(dx) * h) <= (d * w) : U32)
  +frost = (d < 2 : U32)
  sel(inside, sel(frost, 13625574, sel(neg(dx), 4889226, sel((sabs(dx) * 3 < w : U32),
    2977384, 2051914))), TR())

def Art.pine(+dx: U32, +dy: U32, +n: U32) -> U32:
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 5 : U32), 0)
  over(Art.pine_tier(dx, dy, (0 - 34 : U32), 12, 4),
    over(Art.pine_tier(dx, dy, (0 - 26 : U32), 13, 6),
      over(Art.pine_tier(dx, dy, (0 - 18 : U32), 14, 8),
        sel(trunk, 5913891, TR()))))

def Art.glowcap(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  +stem = (sabs(dx) <= 2 : U32) && between(dy, (0 - 11 : U32), 0)
  +cap = ell(dx, (dy + 12 : U32), 10, 7) && sle(dy, (0 - 10 : U32))
  +spot = U32.is_eq((hash(((dx + 64) >> 1n : U32), ((dy + 64) >> 1n : U32)) .&. 7 : U32), 0)
  +under = between(dy, (0 - 11 : U32), (0 - 10 : U32)) && ell(dx, (dy + 12 : U32), 10, 7)
  +glow = U32.is_eq((hash(n, (t >> 4n : U32)) .&. 3 : U32), 0)
  sel(cap, sel(under, 11874348, sel(spot, sel(glow, 16777215, 16314600),
    sel(neg(dx), 14696506, 12070962))), sel(stem, sel(neg(dx), 15261888, 12627616), TR()))

def Art.spike(+dx: U32, +dy: U32, +ox: U32, +h: U32) -> U32:
  +ex = (dx - ox : U32)
  +inside = (sabs(ex) <= 2 : U32) && sle((0 - h + sabs(ex) * 2 : U32), dy) && sle(dy, 0)
  +tip = sle(dy, (0 - h + 3 : U32))
  sel(inside, sel(tip && U32.is_eq(ex, 0), 16777215, sel(neg(ex), 13674751,
    sel(U32.is_eq(ex, 0), 10182117, 6962352))), TR())

def Art.crystal(+dx: U32, +dy: U32) -> U32:
  over(Art.spike(dx, dy, 0, 20), over(Art.spike(dx, dy, (0 - 5 : U32), 13),
    Art.spike(dx, (dy - 1 : U32), 5, 11)))

def Art.tree(+v: U32, +dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  match v:
    case 0:
      Art.oak(dx, dy, n)
    case 1:
      Art.pine(dx, dy, n)
    case 2:
      Art.glowcap(dx, dy, n, t)
    case _:
      Art.crystal(dx, dy)

# Shapes for buildings
# --------------------

# an upright cylinder standing on (0, base), radius r, height h
def Art.cyl(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32) -> U32:
  +ry = (r >> 1n : U32)
  +body = (sabs(dx) <= r : U32) && between(dy, (base - h : U32), base)
  +bot = ell(dx, (dy - base : U32), r, U32.max(ry, 1))
  +topc = ell(dx, (dy - (base - h) : U32), r, U32.max(ry, 1))
  +k = sel(slt(dx, (0 - r / 3 : U32)), 290, sel(slt((r / 3 : U32), dx), 175, 230))
  sel(topc, shade(c, 320), sel(body || bot, shade(c, k), TR()))

# a cone with its base ellipse centred at (0, base)
def Art.cone(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32,
  +c2: U32) -> U32:
  +apex = (base - h : U32)
  +d = (dy - apex : U32)
  +inside = sle(apex, dy) && sle(dy, base) && ((sabs(dx) * h) <= (d * r) : U32)
  +rim = ell(dx, (dy - base : U32), r, U32.max((r >> 1n : U32), 1)) && sle(base, dy)
  +stripe = U32.is_eq(((((dx + 256) : U32) / 6 : U32) .&. 1 : U32), 0)
  +k = sel(slt(dx, (0 - r / 3 : U32)), 290, sel(slt((r / 3 : U32), dx), 180, 235))
  sel(inside || rim, shade(sel(stripe, c, c2), k), TR())

# an iso box on (0, base): footprint diamond half-width r, height h
def Art.box(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +top: U32,
  +left: U32, +right: U32) -> U32:
  +X = dx
  +Yt = ((dy - (base - h - r / 2)) * 2 : U32)
  +tu = iso_u((X + r : U32), Yt)
  +tv = iso_v((X + r : U32), Yt)
  +ontop = (tu < r : U32) && (tv < r : U32)
  # side faces: below the top diamond's lower edges, above the bottom ones
  +ax = sabs(dx)
  +lowtop = (base - h + (r / 2) - (ax / 2) : U32)
  +lowbot = (base + (r / 2) - (ax / 2) : U32)
  +side = (ax <= r : U32) && sle(lowtop, dy) && sle(dy, lowbot)
  sel(ontop, top, sel(side, sel(neg(dx), left, right), TR()))

# Buildings and rides
# -------------------

def Art.gate(+dx: U32, +dy: U32, +t: U32) -> U32:
  +tl = Art.cyl((dx + 12 : U32), dy, 2, 5, 28, 11051168)
  +tr = Art.cyl((dx - 12 : U32), dy, 2, 5, 28, 11051168)
  +rl = Art.cone((dx + 12 : U32), dy, (0 - 26 : U32), 7, 13, 12073530, 10036266)
  +rr = Art.cone((dx - 12 : U32), dy, (0 - 26 : U32), 7, 13, 12073530, 10036266)
  +fl = (sabs((dx - 12 : U32)) <= 0 : U32) && between(dy, (0 - 46 : U32), (0 - 39 : U32))
  +flag = between((dx - 12 : U32), 1, 6) && between(dy, (0 - 46 : U32),
    ((0 - 43) + ((dx + (t >> 3n)) .&. 1) : U32))
  +wall = (sabs(dx) <= 9 : U32) && between(dy, (0 - 20 : U32), 3)
  +arch = (sabs(dx) <= 4 : U32) && between(dy, (0 - 10 : U32), 3)
    || (sabs(dx) <= 3 : U32) && between(dy, (0 - 12 : U32), 3)
  +battl = between(dy, (0 - 23 : U32), (0 - 21 : U32)) && (sabs(dx) <= 9 : U32)
    && U32.is_eq((((dx + 64) >> 1n) .&. 1 : U32), 0)
  +wallc = sel(arch, 3813162, sel(U32.is_eq((((dy + 64) >> 2n) .&. 1 : U32), 0), 10000032, 9210004))
  over(rl, over(rr, over(sel(fl, 5911040, sel(flag, 16766282, TR())),
    over(tl, over(tr, sel(wall || battl, wallc, TR()))))))

def Art.dragon(+dx: U32, +dy: U32, +a: U32) -> U32:
  +cx = wcos(a, 18)
  +cy = (wsin(a, 9) - 12 : U32)
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +body = between(ex, (0 - 3 : U32), 2) && between(ey, (0 - 2 : U32), 0)
  +head = between(ex, 2, 4) && between(ey, (0 - 4 : U32), (0 - 2 : U32))
  +wing = between(ex, (0 - 1 : U32), 1) && U32.is_eq(ey, (0 - 3 : U32))
  +pole = U32.is_eq(ex, 0) && between(ey, (0 - 10 : U32), 6)
  sel(head, 4175450, sel(body, 3120973, sel(wing, 15253568, sel(pole, 14725184, TR()))))

def Art.carousel(+dx: U32, +dy: U32, +t: U32) -> U32:
  +canopy = Art.cone(dx, dy, (0 - 30 : U32), 28, 16, 8077216, 15253568)
  +pole = (sabs(dx) <= 1 : U32) && between(dy, (0 - 32 : U32), (0 - 4 : U32))
  +top = ell(dx, (dy + 4 : U32), 26, 13)
  +side = ell(dx, dy, 26, 13) && sle((0 - 4 : U32), dy)
  +plank = U32.is_eq(((dx + dy * 2 + 256) .&. 7 : U32), 0)
  +flagp = U32.is_eq(dx, 0) && between(dy, (0 - 53 : U32), (0 - 46 : U32))
  +flag = between(dx, 1, 5) && between(dy, (0 - 53 : U32), (0 - 50 : U32))
  +a0 = (t * 2 : U32)
  +f0 = Art.dragon(dx, dy, a0)
  +f1 = Art.dragon(dx, dy, (a0 + 64 : U32))
  +f2 = Art.dragon(dx, dy, (a0 + 128 : U32))
  +f3 = Art.dragon(dx, dy, (a0 + 192 : U32))
  +posts = U32.is_eq(((dx + 256) .&. 15 : U32), 0) && between(dy, (0 - 30 : U32), (0 - 6 : U32))
    && (sabs(dx) < 26 : U32)
  over(canopy, over(sel(flagp, 14737632, sel(flag, 13643824, TR())),
    over(f0, over(f1, over(f2, over(f3, sel(pole, 14725184, sel(posts, 14725184,
      sel(top, sel(plank, 8014378, 11565637), sel(side, 7031338, TR()))))))))))

def Art.spire(+dx: U32, +dy: U32, +t: U32) -> U32:
  +base = Art.box(dx, dy, 0, 12, 5, 9602196, 8418172, 6708076)
  +tower = Art.cyl(dx, dy, (0 - 4 : U32), 5, 60, 7100042)
  +rune = (sabs(dx) <= 1 : U32) && U32.is_eq((((dy + 1024) + (t >> 1n)) % 12 : U32), 0)
  +orb = ell(dx, (dy + 70 : U32), 4, 4)
  +core = ell(dx, (dy + 71 : U32), 1, 1)
  +ph = (t % 400 : U32)
  +up = sel((ph < 300 : U32), (ph / 6 : U32), ((400 - ph) / 2 : U32))
  +ringy = (0 - 8 - up : U32)
  +ring = ell(dx, (dy - ringy : U32), 10, 5) && Bool.not(ell(dx, (dy - ringy : U32), 6, 3))
  +ringside = ell(dx, (dy - ringy - 2 : U32), 10, 5) && Bool.not(ell(dx, (dy - ringy : U32), 10, 5))
    && sle(ringy, dy)
  +seat = ring && U32.is_eq(((dx + 64) .&. 3 : U32), 0)
  # the ring's far half passes behind the tower, its near half in front
  +far = slt(dy, ringy)
  +ringc = sel(seat, 12594224, sel(ring, 14198840, sel(ringside, 10122274, TR())))
  +front = sel(far, TR(), ringc)
  +back = sel(far, ringc, TR())
  over(sel(core, 16777215, sel(orb, 12122367, TR())),
    over(front, over(sel(rune && opaque(tower), 6287592, tower), over(back, base))))

def Art.potion(+dx: U32, +dy: U32, +t: U32) -> U32:
  +booth = Art.box(dx, dy, 0, 9, 9, 13144154, 10512954, 8015402)
  +awn = Art.box(dx, dy, (0 - 14 : U32), 11, 2, 4176048, 3316368, 2524016)
  +stripe = U32.is_eq(((((dx + dy * 2) + 256) >> 2n) .&. 1 : U32), 0)
  +awning = sel(opaque(awn), sel(stripe, awn, 15660784), TR())
  +post = (U32.is_eq(dx, (0 - 9 : U32)) || U32.is_eq(dx, 9)) && between(dy, (0 - 14 : U32), (0 - 4 : U32))
  +b1 = between(dx, (0 - 5 : U32), (0 - 4 : U32)) && between(dy, (0 - 14 : U32), (0 - 11 : U32))
  +b2 = between(dx, (0 - 1 : U32), 0) && between(dy, (0 - 15 : U32), (0 - 11 : U32))
  +b3 = between(dx, 3, 4) && between(dy, (0 - 14 : U32), (0 - 11 : U32))
  +sign = between(dx, (0 - 4 : U32), 4) && between(dy, (0 - 25 : U32), (0 - 20 : U32))
  +star = U32.is_eq(dx, 0) && between(dy, (0 - 24 : U32), (0 - 21 : U32))
    || between(dx, (0 - 1 : U32), 1) && U32.is_eq(dy, (0 - 23 : U32))
  +bub = U32.is_eq((hash((dx + 64 : U32), ((dy + 64 + (t >> 3n)) : U32)) .&. 31 : U32), 0)
    && between(dx, (0 - 2 : U32), 2) && between(dy, (0 - 30 : U32), (0 - 26 : U32))
  over(sel(bub, 12648447, TR()), over(sel(star, 16766282, sel(sign, 6961312, TR())),
    over(awning, over(sel(b1, 14168128, sel(b2, 4176000, sel(b3, 4215008, TR()))),
      over(sel(post, 6961706, TR()), booth)))))

def Art.tavern(+dx: U32, +dy: U32, +t: U32) -> U32:
  +walls = Art.box(dx, dy, 0, 10, 11, 15259824, 15259824, 13154448)
  +beam = U32.is_eq(dx, 0) || U32.is_eq(sabs(dx), 10) || U32.is_eq(sabs(dx), 5)
  +wallc = sel(opaque(walls) && beam, 5913120, walls)
  +door = between(dx, (0 - 7 : U32), (0 - 4 : U32)) && between(dy, (0 - 7 : U32), 3)
    && sle((0 - 7 : U32), dy)
  # the thatched roof: a pyramid over the walls
  +ax = sabs(dx)
  +apex = (0 - 30 : U32)
  +upper = (apex + (ax * 16 / 13) : U32)
  +lower = (0 - 11 + (13 - ax) / 2 : U32)
  +roof = (ax <= 13 : U32) && sle(upper, dy) && sle(dy, lower)
  +thatch = U32.is_eq(((dy + ax + 256) .&. 3 : U32), 0)
  +roofc = sel(neg(dx), sel(thatch, 11045432, 13148232), sel(thatch, 8420896, 10122800))
  +chim = between(dx, 5, 7) && between(dy, (0 - 30 : U32), (0 - 20 : U32))
  +sm = (t .&. 63 : U32)
  +smoke = ell((dx - 6 : U32), (dy + 33 + (sm >> 2n) : U32), 2, 2)
    || ell((dx - 7 : U32), (dy + 38 + (sm >> 3n) : U32), 1, 1)
  over(sel(smoke, 13421772, TR()), over(sel(chim, 8016192, TR()),
    sel(roof, roofc, sel(door, 5913120, wallc))))

def Art.ride(+k: U32, +dx: U32, +dy: U32, +t: U32) -> U32:
  match k:
    case 1:
      Art.carousel(dx, dy, t)
    case 2:
      Art.spire(dx, dy, t)
    case 3:
      Art.potion(dx, dy, t)
    case 4:
      Art.tavern(dx, dy, t)
    case _:
      TR()

# Coaster track
# -------------
# X, Y0 locate the pixel against the track plane; rails run along u (or v)

def Art.rails(+u: U32, +v: U32, +along_u: Bool, +kind: U32, +t: U32) -> U32:
  +a = sel(along_u, u, v)
  +c = sel(along_u, v, u)
  +ok = (u < 16 : U32) && (v < 16 : U32)
  +rail = between(c, 3, 4) || between(c, 11, 12)
  +tie = U32.is_eq((a .&. 3 : U32), 1) && between(c, 2, 13)
  +chain = U32.is_eq(kind, 6) && between(c, 7, 8) && ((((a + (t >> 1n)) .&. 3) < 2) : U32)
  +plat = U32.is_eq(kind, 5) && ((c < 2 : U32) || (c > 13 : U32))
  sel(ok, sel(rail, 13120044, sel(chain, 4210752, sel(tie, 7031339,
    sel(plat, sel(U32.is_eq((a .&. 3 : U32), 0), 8011834, 11041354), TR())))), TR())

def Art.turn(+u: U32, +v: U32, +cu: U32, +cv: U32) -> U32:
  +ok = (u < 16 : U32) && (v < 16 : U32)
  +eu = (u - cu : U32)
  +ev = (v - cv : U32)
  +d2 = (eu * eu + ev * ev : U32)
  +rail = between(d2, 9, 25) || between(d2, 121, 169)
  +deck = between(d2, 26, 120) && U32.is_eq(((u + v) .&. 3 : U32), 0)
  sel(ok, sel(rail, 13120044, sel(deck, 7031339, TR())), TR())

def Art.side_u(+d: U32) -> U32:
  match d:
    case 0:
      0
    case 1:
      0
    case 2:
      16
    case _:
      16

# where the track surface is, for one pixel: slopes solve the projection
def Art.track_top(+kind: U32, +d: U32, +X: U32, +Y0: U32, +t: U32) -> U32:
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +up = U32.is_eq(kind, 1) || U32.is_eq(kind, 6)
  +down = U32.is_eq(kind, 2)
  # slope rising toward +u or +v ("pos"), or toward -u / -v
  +rise_pos = (up && (d < 2 : U32)) || (down && (d >= 2 : U32))
  +slope = up || down
  +Ys = sel(up && (d >= 2 : U32), (Y0 + 16 : U32), sel(down && (d >= 2 : U32), (Y0 - 16 : U32), Y0))
  # rising toward +axis: the other coordinate is Ys; falling: divide by 3
  +n3 = sel(along_u, (Ys + X : U32), (Ys - X : U32))
  +q3 = sel((n3 < 48 : U32), div3(n3), 999)
  +su = sel(rise_pos, sel(along_u, (X + Ys : U32), Ys), sel(along_u, q3, (X + q3 : U32)))
  +sv = sel(rise_pos, sel(along_u, Ys, (Ys - X : U32)), sel(along_u, (q3 - X : U32), q3))
  +fu = iso_u(X, Y0)
  +fv = iso_v(X, Y0)
  +u = sel(slope, su, fu)
  +v = sel(slope, sv, fv)
  +turn = U32.is_eq(kind, 3) || U32.is_eq(kind, 4)
  +d2 = sel(U32.is_eq(kind, 3), ((d + 3) .&. 3 : U32), ((d + 1) .&. 3 : U32))
  # the turn's centre: the corner between its entry and exit sides
  +entry_u = sel(U32.is_eq(d, 0), 0, 16)
  +entry_v = sel(U32.is_eq(d, 1), 0, 16)
  +exit_u = sel(U32.is_eq(d2, 0), 16, 0)
  +exit_v = sel(U32.is_eq(d2, 1), 16, 0)
  +cu = sel(along_u, entry_u, exit_u)
  +cv = sel(along_u, exit_v, entry_v)
  sel(turn, Art.turn(fu, fv, cu, cv), Art.rails(u, v, along_u, kind, t))

# a track piece on a tile whose ground top vertex is (x, y); zr levels up
def Art.track(+x: U32, +y: U32, +code: U32, +zr: U32, +t: U32, +px: U32,
  +py: U32) -> U32:
  +kind = (code .&. 7 : U32)
  +d = (code >> 3n : U32)
  +X = (px - x : U32)
  +Y0 = (((py - y) * 2) + zr * 16 : U32)
  +surf = Art.track_top(kind, d, X, Y0, t)
  +slope = sel(U32.is_eq(kind, 1) || U32.is_eq(kind, 6), 4,
    sel(U32.is_eq(kind, 2), (0 - 4 : U32), 0))
  +stop = (y + 8 - zr * 8 - slope : U32)
  +post = (sabs(X) <= 1 : U32) && sle(stop, py) && sle(py, (y + 8 : U32))
    && (zr > 0 : U32)
  +brace = U32.is_eq(((py + 256 - y) .&. 7 : U32), 0) && (sabs(X) <= 3 : U32)
    && sle(stop, py) && sle(py, (y + 8 : U32)) && (zr > 0 : U32)
  over(surf, sel(post, sel(U32.is_eq(X, 1), 5913890, 8017200), sel(brace, 6964776, TR())))

# a coaster car centred at (0, 0) on the track, heading d
def Art.car_in(+X: U32, +Y: U32, +along_u: Bool) -> Bool:
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  +a = sel(along_u, u, v)
  +c = sel(along_u, v, u)
  (sabs(a) <= 5 : U32) && (sabs(c) <= 3 : U32)

def Art.car(+dx: U32, +dy: U32, +d: U32, +lead: U32) -> U32:
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +topy = ((dy + 5) * 2 : U32)
  +ontop = Art.car_in(dx, topy, along_u)
  +side = Art.car_in(dx, (dy * 2 : U32), along_u) || Art.car_in(dx, ((dy + 1) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 2) * 2 : U32), along_u) || Art.car_in(dx, ((dy + 3) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 4) * 2 : U32), along_u)
  +body = sel(U32.is_eq(lead, 1), 13120044, 4172373)
  +rider = U32.is_eq(sabs(dx), 2) && U32.is_eq(dy, (0 - 7 : U32))
    || U32.is_eq(sabs(dx), 2) && U32.is_eq(dy, (0 - 6 : U32))
  sel(rider, 15779948, sel(ontop, shade(body, 290), sel(side, shade(body, sel(neg(dx), 210, 160)), TR())))

# Adventurers
# -----------
# look: bits 0-1 class (wizard, knight, elf, dwarf), 4-6 tunic, 8-9 skin

def Art.tunic(+k: U32) -> U32:
  match k:
    case 0:
      3830704
    case 1:
      10498096
    case 2:
      3181648
    case 3:
      9054256
    case 4:
      2129008
    case 5:
      12609552
    case 6:
      6316160
    case _:
      11546688

def Art.skin(+k: U32) -> U32:
  match k:
    case 0:
      16767148
    case 1:
      14851690
    case 2:
      10045514
    case _:
      15781004

def Art.guest(+dx: U32, +dy: U32, +look: U32, +t: U32) -> U32:
  +cls = (look .&. 3 : U32)
  +dw = U32.is_eq(cls, 3)
  +h = (0 - dy : U32)
  +sh = sel(dw, 2, 0)
  +tun = sel(U32.is_eq(cls, 0), 5913248, Art.tunic(((look >> 4n) .&. 7 : U32)))
  +skin = Art.skin(((look >> 8n) .&. 3 : U32))
  +step = U32.is_eq(((t >> 3n) .&. 1 : U32), 1)
  +legl = sel(step, (0 - 1 : U32), 0)
  +legr = sel(step, 1, 0)
  +legs = between(h, 0, (2 - sh / 2 : U32)) && (U32.is_eq(dx, legl) || U32.is_eq(dx, (legr + 0 : U32)) || U32.is_eq(dx, (legl + 2 : U32)))
  +body = between(h, (3 - sh / 2 : U32), (6 - sh : U32)) && between(dx, (0 - 2 : U32), 2)
  +belt = U32.is_eq(h, (4 - sh / 2 : U32)) && between(dx, (0 - 2 : U32), 2)
  +head = between(h, (7 - sh : U32), (9 - sh : U32)) && between(dx, (0 - 1 : U32), 1)
  +eye = U32.is_eq(h, (8 - sh : U32)) && U32.is_eq(dx, 1)
  # hats
  +wiz = U32.is_eq(cls, 0) && (between(h, 10, 10) && between(dx, (0 - 2 : U32), 2)
    || U32.is_eq(h, 11) && between(dx, (0 - 1 : U32), 1)
    || U32.is_eq(h, 12) && between(dx, (0 - 1 : U32), 0)
    || U32.is_eq(h, 13) && U32.is_eq(dx, 0))
  +star = U32.is_eq(cls, 0) && U32.is_eq(h, 11) && U32.is_eq(dx, 0)
  +helm = U32.is_eq(cls, 1) && between(h, 8, 10) && between(dx, (0 - 1 : U32), 1)
  +visor = U32.is_eq(cls, 1) && U32.is_eq(h, 8) && between(dx, 0, 1)
  +plume = U32.is_eq(cls, 1) && between(h, 11, 12) && U32.is_eq(dx, 0)
  +hood = U32.is_eq(cls, 2) && (between(h, 9, 10) && between(dx, (0 - 1 : U32), 1)
    || U32.is_eq(dx, (0 - 2 : U32)) && between(h, 7, 9))
  +ear = U32.is_eq(cls, 2) && U32.is_eq(dx, 2) && U32.is_eq(h, 8)
  +beard = dw && between(h, 5, 6) && between(dx, (0 - 1 : U32), 1)
  +cap = dw && between(h, 8, 9) && between(dx, (0 - 1 : U32), 1)
  sel(star, 16766282, sel(wiz, 5913248, sel(visor, 3158064, sel(helm, 11581632,
    sel(plume, 13643824, sel(hood, 3836474, sel(ear, skin, sel(cap, 12595248,
    sel(beard, 11559978, sel(eye, 2105376, sel(head, skin, sel(belt, 4861466,
    sel(body, tun, sel(legs, 3811866, TR()))))))))))))))

# UI
# --

def bitmask(+k: U32) -> U32:
  match k:
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
    case 8:
      256
    case 9:
      512
    case 10:
      1024
    case 11:
      2048
    case 12:
      4096
    case 13:
      8192
    case 14:
      16384
    case _:
      0

def glyph_on(+bits: U32, +dx: U32, +dy: U32) -> Bool:
  (dx < 3 : U32) && (dy < 5 : U32)
    && Bool.not(U32.is_eq((bits .&. bitmask((14 - (dy * 3 + dx) : U32)) : U32), 0))

def Art.glyph(+bits: U32, +dx: U32, +dy: U32, +col: U32) -> U32:
  +on = glyph_on(bits, dx, dy)
  +sh = glyph_on(bits, (dx - 1 : U32), (dy - 1 : U32))
  sel(on, col, sel(sh, 1052688, TR()))

def Art.dia(+cx: U32, +cy: U32) -> Bool:
  ((sabs(cx) + sabs(cy) * 2) <= 8 : U32)

def Art.icon_pic(+tool: U32, +cx: U32, +cy: U32, +t: U32) -> U32:
  match tool:
    case 1:
      sel(Art.dia(cx, cy), Art.cobble(((cx + 16) : U32), ((cy * 2 + 16) : U32), 3), TR())
    case 2:
      +tri_up = sle((0 - 6 : U32), cy) && sle(cy, 2) && ((sabs(cx) * 2) <= (cy + 6) : U32)
      sel(tri_up, 6337117, sel(Art.dia(cx, cy) && sle(2, cy), 4626999, TR()))
    case 3:
      +tri_dn = sle((0 - 6 : U32), cy) && sle(cy, 2) && ((sabs(cx) * 2) <= (2 - cy) : U32)
      sel(tri_dn, 11559978, sel(Art.dia(cx, cy) && sle(2, cy), 9138758, TR()))
    case 4:
      Art.glowcap(cx, (cy - 5 : U32), 5, t)
    case 5:
      Art.cone(cx, (cy + 2 : U32), 0, 8, 9, 8077216, 15253568)
    case 6:
      Art.cyl(cx, cy, 6, 3, 12, 7100042)
    case 7:
      +neck = (sabs(cx) <= 1 : U32) && between(cy, (0 - 7 : U32), (0 - 4 : U32))
      +flask = ell(cx, (cy - 1 : U32), 5, 5)
      sel(neck, 13154448, sel(flask, sel(sle(0, cy), 14168128, 12632319), TR()))
    case 8:
      +mug = between(cx, (0 - 4 : U32), 3) && between(cy, (0 - 4 : U32), 6)
      +foam = between(cx, (0 - 5 : U32), 4) && between(cy, (0 - 7 : U32), (0 - 5 : U32))
      +handle = between(cx, 4, 6) && between(cy, (0 - 2 : U32), 3)
        && Bool.not(U32.is_eq(cx, 5) && between(cy, (0 - 1 : U32), 2))
      +band = U32.is_eq(cy, 0) || U32.is_eq(cy, 4)
      sel(foam, 15790320, sel(mug, sel(band, 9138758, 13148232), sel(handle, 10512954, TR())))
    case 9:
      +x = (sabs((cx - cy : U32)) <= 1 : U32) || (sabs((cx + cy : U32)) <= 1 : U32)
      sel(x && (sabs(cx) <= 6 : U32), 14168128, TR())
    case 10:
      +wave = (sabs((cy - wsin((cx * 20 : U32), 5) : U32)) <= 1 : U32) && (sabs(cx) <= 8 : U32)
      sel(wave, 13120044, TR())
    case _:
      TR()
def Art.icon(+tool: U32, +on: U32, +dx: U32, +dy: U32, +t: U32) -> U32:
  +edge = U32.is_eq(dx, 0) || U32.is_eq(dy, 0) || U32.is_eq(dx, 21) || U32.is_eq(dy, 21)
  +frame = sel(U32.is_eq(on, 1), 16766282, 5917290)
  +fill = sel(U32.is_eq(on, 1), 5917216, 3025984)
  +cx = (dx - 11 : U32)
  +cy = (dy - 13 : U32)
  +pic = Art.icon_pic(tool, cx, cy, t)
  sel(edge, frame, over(pic, fill))

