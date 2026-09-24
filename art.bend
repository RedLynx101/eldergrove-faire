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

# a tuft of long grass in a 4 x 4 cell (x, y: position in the cell)
def Art.tuft(on: Bool, +x: U32, +y: U32) -> U32:
  match on:
    case True{}:
      +lite = U32.is_eq(y, 0) && U32.is_eq(x, 1) || U32.is_eq(y, 1) && (U32.is_eq(x, 0) || U32.is_eq(x, 2))
      +mid = U32.is_eq(y, 1) && U32.is_eq(x, 1) || U32.is_eq(y, 2) && (x < 3 : U32)
      +dark = U32.is_eq(y, 3) && (U32.is_eq(x, 1) || U32.is_eq(x, 2))
      sel(lite, 8047936, sel(mid, 5411896, sel(dark, 2980914, TR())))
    case False{}:
      TR()

def Art.grass(+n: U32, +edge: U32, +tip: Bool) -> U32:
  +f = (n .&. 255 : U32)
  +base = sel((f < 90 : U32), 5150266, sel((f < 200 : U32), 4626999, 5875263))
  +m = (n .&. 1023 : U32)
  +bloom = sel(U32.is_eq(m, 7), 15895224, sel(U32.is_eq(m, 19), 16179290,
    sel(U32.is_eq(m, 31), 16053480, sel(U32.is_eq(m, 43), 9086207, TR()))))
  +flower = sel(opaque(bloom), sel(tip, bloom, 3707946), TR())
  +blade = U32.is_eq((n .&. 28 : U32), 12) && ((n >> 10n .&. 3 : U32) < 3 : U32)
  over(flower, shade(sel(blade, sel(tip, 7324480, 3509046), base), edge))

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
  +turf = sel(wild, 3104300, 4626999)
  +root = U32.is_eq(d, 2) && ((((px * 5) + 3) .&. 7 : U32) < 2 : U32)
    || U32.is_eq(d, 3) && U32.is_eq((((px * 5) + 3) .&. 15 : U32), 0)
  sel(U32.is_eq(d, 0), shade(turf, 300), sel(U32.is_eq(d, 1), shade(turf, 150),
    sel(root, shade(turf, 120), sel(left, c, shade(c, 190)))))

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
      +tuft = U32.is_eq((hash((wx >> 2n : U32), (wy >> 2n : U32)) .&. 31 : U32), 0)
      over(Art.tuft(tuft, (wx .&. 3 : U32), (wy .&. 3 : U32)), Art.grass(n, edge, U32.is_eq((wy .&. 1 : U32), 0)))

def Art.flag(+u: U32, +v: U32, +seed: U32) -> U32:
  +off = sel(U32.is_eq(((v >> 3n) .&. 1 : U32), 1), 4, 0)
  +uu = (u + off : U32)
  +joint = U32.is_eq((uu .&. 7 : U32), 0) || U32.is_eq((v .&. 7 : U32), 0)
  +c = (hash(((uu >> 3n) + seed * 5 : U32), ((v >> 3n) + seed : U32)) .&. 3 : U32)
  sel(joint, 6970184, sel(U32.is_eq(c, 0), 10125936, sel(U32.is_eq(c, 1), 9468520, 10783352)))

def Art.open_edge(+nb: U32, +u: U32, +v: U32, +w: U32) -> Bool:
  (U32.is_eq((nb .&. 1 : U32), 0) && (u < w : U32)) || (U32.is_eq((nb .&. 2 : U32), 0) && (u + w > 15 : U32))
    || (U32.is_eq((nb .&. 4 : U32), 0) && (v < w : U32)) || (U32.is_eq((nb .&. 8 : U32), 0) && (v + w > 15 : U32))

def Art.paving(+obj: U32, +u: U32, +v: U32, +seed: U32, +nb: U32) -> U32:
  match obj:
    case 7:
      Art.flag(u, v, seed)
    case _:
      sel(Art.open_edge(nb, u, v, 2), shade(Art.cobble(u, v, seed), 176), Art.cobble(u, v, seed))

# foam where water meets land (the edges whose neighbour is not water)
def Art.foam(+nb: U32, +u: U32, +v: U32, +t: U32, +c: U32) -> U32:
  +band = Art.open_edge(nb, u, v, 2)
  +edge = Art.open_edge(nb, u, v, 1)
  +ripple = U32.is_eq((((u + v + (t >> 3n)) >> 1n) .&. 1 : U32), 0)
  sel(edge, 14676463, sel(band && ripple, 10406879, c))

def Art.surface(paved: Bool, +ter: U32, +u: U32, +v: U32, +wx: U32, +wy: U32,
  +t: U32, +obj: U32, +nb: U32) -> U32:
  match paved:
    case True{}:
      Art.paving(obj, u, v, ((wx - u + v) >> 4n : U32), nb)
    case False{}:
      +n = hash(wx, (wy >> 1n : U32))
      +edge = sel((u < 1 : U32) || (v < 1 : U32), 272, sel((u > 14 : U32) || (v > 14 : U32), 236, 256))
      +g = Art.ground(ter, n, edge, wx, wy, t)
      sel(U32.is_eq(ter, 2), Art.foam(nb, u, v, t, g), g)

def Art.top(outline: Bool, +ter: U32, +obj: U32, +u: U32, +v: U32, +wx: U32,
  +wy: U32, +t: U32, +nb: U32) -> U32:
  match outline:
    case True{}:
      16769126
    case False{}:
      Art.surface(U32.is_eq(obj, 1) || U32.is_eq(obj, 5) || U32.is_eq(obj, 7), ter, u, v, wx, wy, t, obj, nb)

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
  +u: U32, +v: U32, +nb: U32) -> U32:
  match top:
    case True{}:
      +outline = U32.is_eq(hov, 1) && ((u < 1 : U32) || (v < 1 : U32) || (u > 14 : U32) || (v > 14 : U32))
      Art.top(outline, ter, obj, u, v, (wx + (px - x) : U32), (wy + (py - y) : U32), t, nb)
    case False{}:
      +lx = (px - (x - 16) : U32)
      +le = (y + 8 + (lx >> 1n) : U32)
      +rx = (px - x : U32)
      +re = (y + 16 - (rx >> 1n) : U32)
      Art.faces((lx < 16 : U32) && (py >= le : U32) && (py < le + dl : U32),
        (rx < 16 : U32) && (py >= re : U32) && (py < re + dr : U32), dl, dr, le, re,
        px, py, U32.is_eq(ter, 4))

# queue railings: posts at the corners and a rope 4 px up along each edge
# that joins nothing
def Art.rails.go(on: Bool, +x: U32, +y: U32, +nb: U32, +px: U32, +py: U32) -> U32:
  match on:
    case True{}:
      +X = (px - x : U32)
      +Y = ((py + 4 - y) * 2 : U32)
      +u = iso_u(X, Y)
      +v = iso_v(X, Y)
      +in = (u < 17 : U32) && (v < 17 : U32)
      +rope = in && Art.open_edge(nb, u, v, 1)
      +cx = sabs(X)
      +post = (U32.is_eq(X, 0) && (between((py - y : U32), (0 - 6 : U32), 0) && ((nb .&. 5 : U32) < 5 : U32)
          || between((py - y : U32), 10, 16) && ((nb .&. 10 : U32) < 10 : U32)))
        || U32.is_eq(cx, 16) && between((py - y : U32), 2, 8)
      +knob = post && (U32.is_eq((py - y : U32), (0 - 6 : U32)) || U32.is_eq((py - y : U32), 10)
        || U32.is_eq((py - y : U32), 2))
      sel(knob, 14725184, sel(post, 7031339, sel(rope, sel(U32.is_eq(((u + v) .&. 1 : U32), 0), 8011680, 5582448), TR())))
    case False{}:
      TR()

# a ride's entrance or exit arch on the path tile's edge toward the ride
# (nb bits 4-5: that edge, 6-7: 1 entrance, 2 exit): two posts and a banner,
# green in, red out
def Art.arch.go(on: Bool, +x: U32, +y: U32, +nb: U32, +px: U32, +py: U32) -> U32:
  match on:
    case True{}:
      +side = ((nb >> 4n) .&. 3 : U32)
      +kind = ((nb >> 6n) .&. 3 : U32)
      +X = (px - x : U32)
      +Y = (py - y : U32)
      +e = sel(U32.is_eq(side, 0), (0 - X : U32), sel(U32.is_eq(side, 1), (16 - X : U32),
        sel(U32.is_eq(side, 2), X, (X + 16 : U32))))
      +yb = sel(U32.is_eq(side, 1) || U32.is_eq(side, 3), (8 + (e >> 1n) : U32), (e >> 1n : U32))
      +rel = (Y - yb : U32)
      +post = (between(e, 1, 3) || between(e, 13, 15)) && between(rel, (0 - 20 : U32), 0)
      +knob = post && between(rel, (0 - 21 : U32), (0 - 20 : U32)) && (U32.is_eq(e, 2) || U32.is_eq(e, 14))
      +banner = between(e, 1, 15) && between(rel, (0 - 19 : U32), (0 - 13 : U32))
      +trim = banner && (U32.is_eq(rel, (0 - 19 : U32)) || U32.is_eq(rel, (0 - 13 : U32)))
      +mark = banner && (U32.is_eq(rel, (0 - 16 : U32)) && between(e, 6, 10)
        || U32.is_eq(rel, (0 - 17 : U32)) && between(e, 7, 9) && U32.is_eq(kind, 1)
        || U32.is_eq(rel, (0 - 15 : U32)) && between(e, 7, 9) && U32.is_eq(kind, 2))
      +col = sel(U32.is_eq(kind, 1), 3831360, 12595248)
      sel(knob, 14725184, sel(post, sel(U32.is_eq(e, 1) || U32.is_eq(e, 13), 8014378, 5125410),
        sel(trim, 14725184, sel(mark, 16316664, sel(banner, col, TR())))))
    case False{}:
      TR()

def Art.block(+x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32, +obj: U32,
  +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32, +nb: U32) -> U32:
  +X = (px - x : U32)
  +Y = ((py - y) * 2 : U32)
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  over(Art.arch.go(Bool.not(U32.is_eq((nb >> 6n : U32), 0)), x, y, nb, px, py),
    over(Art.rails.go(U32.is_eq(obj, 7), x, y, nb, px, py),
    Art.block.go((u < 16 : U32) && (v < 16 : U32), x, y, dl, dr, ter, obj, hov,
      wx, wy, t, px, py, u, v, nb)))

# Trees (anchored at the tile centre)
# -----------------------------------
# Leaves and caps are shaded as small lit volumes (light from the top
# left): a highlight rim, three body tones with dithered edges, a deep
# outline on the shadowed side, and a soft ground shadow under each tree.

def Art.checker(+x: U32, +y: U32) -> Bool:
  U32.is_eq(((x + y) .&. 1 : U32), 0)

# a soft ground shadow: dark meadow tones, dithered
def Art.shadow(+dx: U32, +dy: U32, +rx: U32, +ry: U32) -> U32:
  +in = ell(dx, dy, rx, ry)
  +edge = in && Bool.not(ell(dx, dy, (rx - 2 : U32), U32.max((ry - 1 : U32), 1)))
  sel(in, sel(edge && Art.checker(dx, dy), TR(), sel(Art.checker(dx, dy), 3310120, 3574314)), TR())

# one clump of leaves of radius r centred at (cx, cy): 5 tones
def Art.leaf(+k: U32) -> U32:
  match k:
    case 0:
      8833118
    case 1:
      5938756
    case 2:
      4161332
    case 3:
      2908969
    case _:
      1786397

def Art.clump.go(in: Bool, +dx: U32, +dy: U32, +ex: U32, +ey: U32, +d2: U32, +r: U32,
  +n: U32) -> U32:
  match in:
    case True{}:
      +v = (ex + ey : U32)
      +h = (r >> 1n : U32)
      +q = (h >> 1n : U32)
      +rim = ((d2 + r + r) > (r * r) : U32)
      +dith = Art.checker(dx, dy)
      +tone = sel(slt(v, (0 - h - 1 : U32)), 1, sel(slt(v, (0 - h + 1 : U32)), sel(dith, 1, 2),
        sel(slt(v, q), 2, sel(slt(v, (q + 2 : U32)), sel(dith, 2, 3), 3))))
      +speck = U32.is_eq((hash((ex + n : U32), (ey * 7 + n : U32)) .&. 7 : U32), 0)
      +t2 = sel(speck, U32.min((tone + 1 : U32), 3), tone)
      Art.leaf(sel(rim && slt(0, v), 4, sel(rim && slt(v, (0 - q : U32)), 0, t2)))
    case False{}:
      TR()

# one clump of leaves of radius r centred at (cx, cy): 5 tones
def Art.clump(+dx: U32, +dy: U32, +cx: U32, +cy: U32, +r: U32, +n: U32) -> U32:
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +d2 = (ex * ex + ey * ey : U32)
  Art.clump.go((d2 <= r * r : U32), dx, dy, ex, ey, d2, r, n)

def Art.bark(+dx: U32, +dy: U32) -> U32:
  sel(U32.is_eq(dx, (0 - 1 : U32)), 9068600, sel(U32.is_eq(dx, 1), 4862492,
    sel(U32.is_eq(((dy + 64) .&. 3 : U32), 0), 5913634, 7031339)))

def Art.oak(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  # the crown sways a pixel or two in the wind
  +sw = wsin(((t * 3) + n : U32), 2)
  +cx = (dx - sw : U32)
  +flare = sle((0 - 2 : U32), dy) && (sabs(dx) <= 2 : U32)
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 12 : U32), 0) || flare && sle(dy, 0)
  +k = (0 - dy - 9 : U32)
  +bl = (k <= 7 : U32) && U32.is_eq(dx, (0 - (k >> 1n) : U32))
  +br = (k <= 6 : U32) && U32.is_eq(dx, (k >> 1n : U32))
  +wood = sel(trunk, Art.bark(dx, dy), sel(bl || br, 5913634, TR()))
  +crown = over(Art.clump(cx, dy, 4, (0 - 11 : U32), 5, n), over(Art.clump(cx, dy, (0 - 3 : U32), (0 - 12 : U32), 5, n),
    over(Art.clump(cx, dy, 8, (0 - 12 : U32), 4, n), over(Art.clump(cx, dy, (0 - 8 : U32), (0 - 12 : U32), 4, n),
    over(Art.clump(cx, dy, 6, (0 - 17 : U32), 5, n), over(Art.clump(cx, dy, (0 - 6 : U32), (0 - 17 : U32), 5, n),
    over(Art.clump(cx, dy, 0, (0 - 16 : U32), 6, n), Art.clump(cx, dy, 0, (0 - 22 : U32), 6, n))))))))
  over(crown, over(wood, Art.shadow((dx - 1 : U32), (dy - 1 : U32), 10, 4)))

# a moonpine tier: serrated edges, moonlit from the left, frosted tips
def Art.pine_tier(+dx: U32, +dy: U32, +apex: U32, +h: U32, +w: U32, +n: U32) -> U32:
  +d = (dy - apex : U32)
  +ax = sabs(dx)
  +dw = (d * w : U32)
  +edge = ((ax + 1) * h >= dw : U32)
  +jag = U32.is_eq(((ax + d + n) .&. 1 : U32), 1) && edge
  +inside = (d < h : U32) && (ax * h <= dw : U32) && Bool.not(jag)
  +frost = (d + 1 >= h : U32) && U32.is_eq(((dx + n) .&. 1 : U32), 0)
    || (d < 1 : U32)
  +tone = sel(neg(dx), sel((ax * 2 * h > dw : U32), 6270621, 3834744), sel((ax * 3 * h < dw : U32), 3834744,
    sel(edge, 1522233, 2382419)))
  sel(inside, sel(frost, 14217193, tone), TR())

def Art.pine(+dx: U32, +dy: U32, +n: U32) -> U32:
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 6 : U32), 0)
  over(Art.pine_tier(dx, dy, (0 - 38 : U32), 10, 3, n),
    over(Art.pine_tier(dx, dy, (0 - 31 : U32), 11, 5, n),
      over(Art.pine_tier(dx, dy, (0 - 24 : U32), 12, 7, n),
        over(Art.pine_tier(dx, dy, (0 - 17 : U32), 12, 9, n),
          over(sel(trunk, Art.bark(dx, dy), TR()), Art.shadow((dx - 1 : U32), (dy - 1 : U32), 8, 3))))))

# a glowcap: domed cap with a highlight, glowing spots, gills beneath, and
# a fibrous stem with a skirt; sometimes a small one beside it
def Art.cap(+dx: U32, +dy: U32, +cy: U32, +rx: U32, +ry: U32, +n: U32, +t: U32) -> U32:
  +ey = (dy - cy : U32)
  +dome = ell(dx, ey, rx, ry) && sle(ey, 0)
  +gill = ell(dx, (ey - 1 : U32), (rx - 1 : U32), U32.max(div3(ry), 1)) && sle(0, ey)
  +gstripe = U32.is_eq((((dx + 64) >> 1n) .&. 1 : U32), 0)
  +hi = ell((dx + div3(rx) : U32), (ey + (ry >> 1n) + 1 : U32), U32.max((rx >> 2n : U32), 1), U32.max((ry >> 2n : U32), 1))
  +cellx = div3((dx + 66 : U32))
  +celly = div3((ey + 66 : U32))
  +spoton = U32.is_eq((hash((cellx + n : U32), celly) .&. 1 : U32), 0)
  +sx = ((dx + 66) - cellx * 3 : U32)
  +sy = ((ey + 66) - celly * 3 : U32)
  +spot = spoton && (sx >= 1 : U32) && (sy >= 1 : U32) && slt(ey, (0 - 1 : U32))
  +spotsh = spot && U32.is_eq(sx, 2) && U32.is_eq(sy, 2)
  +pulse = (tri(((t * 4) + n : U32)) > 32 : U32)
  +rimk = Bool.not(ell(dx, ey, (rx - 1 : U32), U32.max((ry - 1 : U32), 1)))
  +body = sel(slt(ey, (0 - div3((ry * 2 : U32)) : U32)), 16738906, sel(neg(dx), 14172218, 11546154))
  +capc = sel(hi, 16761008, sel(spotsh, 14207168, sel(spot, sel(pulse, 16776144, 16774378),
    sel(rimk && slt(0, dx), 9052192, body))))
  sel(dome, capc, sel(gill, sel(gstripe, 15259312, 13218956), TR()))

def Art.stem(+dx: U32, +dy: U32, +top: U32, +w: U32) -> U32:
  +bulge = sel(sle((0 - 2 : U32), dy), (w + 1 : U32), w)
  +in = (sabs(dx) <= bulge : U32) && between(dy, top, 0)
  +skirt = U32.is_eq(dy, (top + 3 : U32)) && (sabs(dx) <= (w + 1 : U32) : U32)
  +c = sel(U32.is_eq(sabs(dx), bulge) && slt(0, dx), 12100738, sel(U32.is_eq((dx .&. 1 : U32), 0), 14207140, 15787208))
  sel(skirt, 13218956, sel(in, c, TR()))

def Art.glowcap(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  +big = over(Art.cap(dx, dy, (0 - 12 : U32), 12, 9, n, t), Art.stem(dx, dy, (0 - 12 : U32), 2))
  +bx = (dx - 8 : U32)
  +by = (dy - 2 : U32)
  +baby = sel(U32.is_eq((n .&. 1 : U32), 1),
    over(Art.cap(bx, by, (0 - 5 : U32), 4, 3, (n + 5 : U32), t), Art.stem(bx, by, (0 - 5 : U32), 1)), TR())
  over(big, over(baby, Art.shadow((dx - 1 : U32), (dy - 1 : U32), 10, 4)))

# crystals: faceted spikes on a rocky base, their tips twinkling
def Art.spike(+dx: U32, +dy: U32, +ox: U32, +h: U32, +w: U32) -> U32:
  +ex = (dx - ox : U32)
  +ax = sabs(ex)
  +inside = (ax <= w : U32) && sle((0 - h + ax * 2 : U32), dy) && sle(dy, 0)
  +ridge = U32.is_eq(ex, 0)
  +tip = sle(dy, (0 - h + 3 : U32))
  +deep = sle((0 - 2 : U32), dy)
  sel(inside, sel(ridge && tip, 16777215, sel(ridge, 15523071, sel(deep, 5910672,
    sel(neg(ex), sel(U32.is_eq(ax, w), 11828479, 14203135), sel(U32.is_eq(ax, w), 5910672, 9066704))))), TR())

def Art.crystal(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  +glint = ((((t + n * 13) .&. 127) : U32) < 10 : U32)
  +star = glint && (U32.is_eq(dx, 0) && between(dy, (0 - 25 : U32), (0 - 19 : U32))
    || U32.is_eq(dy, (0 - 22 : U32)) && between(dx, (0 - 3 : U32), 3))
  +rocks = ell(dx, (dy - 1 : U32), 7, 3)
  +rockc = sel(Art.checker(dx, dy), 8026760, sel(neg(dx), 9079450, 5921384))
  over(sel(star, 16777215, TR()), over(Art.spike(dx, dy, 0, 21, 2),
    over(Art.spike(dx, dy, (0 - 5 : U32), 14, 2), over(Art.spike(dx, (dy - 1 : U32), 5, 12, 2),
      over(Art.spike(dx, (dy + 1 : U32), 2, 8, 1), sel(rocks, rockc, TR()))))))

def Art.tree(+v: U32, +dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  match v:
    case 0:
      Art.oak(dx, dy, n, t)
    case 1:
      Art.pine(dx, dy, n)
    case 2:
      Art.glowcap(dx, dy, n, t)
    case _:
      Art.crystal(dx, dy, n, t)


def Art.cyl(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32) -> U32:
  +ry = (r >> 1n : U32)
  +body = (sabs(dx) <= r : U32) && between(dy, (base - h : U32), base)
  +bot = ell(dx, (dy - base : U32), r, U32.max(ry, 1))
  +topc = ell(dx, (dy - (base - h) : U32), r, U32.max(ry, 1))
  +k = sel(slt(dx, (0 - div3(r) : U32)), 290, sel(slt(div3(r), dx), 175, 230))
  sel(topc, shade(c, 320), sel(body || bot, shade(c, k), TR()))

# a cone with its base ellipse centred at (0, base)
def Art.cone(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32,
  +c2: U32) -> U32:
  +apex = (base - h : U32)
  +d = (dy - apex : U32)
  +inside = sle(apex, dy) && sle(dy, base) && ((sabs(dx) * h) <= (d * r) : U32)
  +rim = ell(dx, (dy - base : U32), r, U32.max((r >> 1n : U32), 1)) && sle(base, dy)
  +stripe = U32.is_eq(((div3((dx + 256 : U32)) >> 1n) .&. 1 : U32), 0)
  +k = sel(slt(dx, (0 - div3(r) : U32)), 290, sel(slt(div3(r), dx), 180, 235))
  sel(inside || rim, shade(sel(stripe, c, c2), k), TR())

# an iso box on (0, base): footprint diamond half-width r, height h
def Art.box(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +top: U32,
  +left: U32, +right: U32) -> U32:
  +X = dx
  +Yt = ((dy - (base - h - (r >> 1n))) * 2 : U32)
  +tu = iso_u((X + r : U32), Yt)
  +tv = iso_v((X + r : U32), Yt)
  +ontop = (tu < r : U32) && (tv < r : U32)
  # side faces: below the top diamond's lower edges, above the bottom ones
  +ax = sabs(dx)
  +lowtop = (base - h + (r >> 1n) - (ax >> 1n) : U32)
  +lowbot = (base + (r >> 1n) - (ax >> 1n) : U32)
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
  +twist = U32.is_eq((((ey + 64) >> 1n) .&. 1 : U32), 0)
  sel(head, 4175450, sel(body, 3120973, sel(wing, 15253568, sel(pole, sel(twist, 14725184, 16250848), TR()))))

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

# a thought bubble's picture (inner 7 x 5, x in -3..3, y in 0..4 upward)
def Art.thought(+m: U32, +x: U32, +y: U32) -> U32:
  match m:
    case 1:
      # hungry: a drumstick
      +meat = ell((x + 1 : U32), (y - 3 : U32), 2, 1)
      +bone = U32.is_eq(x, 1) && U32.is_eq(y, 1) || U32.is_eq(x, 2) && (y < 2 : U32) || U32.is_eq(x, 3) && U32.is_eq(y, 0)
      sel(meat, 11037752, sel(bone, 15790304, TR()))
    case 2:
      # thirsty: a water drop
      +drop = U32.is_eq(y, 4) && U32.is_eq(x, 0) || between(y, 1, 3) && (sabs(x) <= 1 : U32)
        || U32.is_eq(y, 0) && U32.is_eq(x, 0)
      sel(drop, sel(U32.is_eq(x, (0 - 1 : U32)) && U32.is_eq(y, 2), 12644607, 3712480), TR())
    case 3:
      # queasy: a green swirl
      +ring = ell(x, (y - 2 : U32), 3, 2) && Bool.not(ell(x, (y - 2 : U32), 1, 1))
      sel(ring && Bool.not(U32.is_eq(x, 3) && U32.is_eq(y, 2)), 5613632, sel(U32.is_eq(x, 0) && U32.is_eq(y, 2), 5613632, TR()))
    case 4:
      # tired: z z
      +big = (U32.is_eq(y, 4) || U32.is_eq(y, 1)) && between(x, (0 - 3 : U32), 0)
        || U32.is_eq(y, 3) && U32.is_eq(x, (0 - 1 : U32)) || U32.is_eq(y, 2) && U32.is_eq(x, (0 - 2 : U32))
      +small = (U32.is_eq(y, 3) || U32.is_eq(y, 1)) && between(x, 2, 3) || U32.is_eq(y, 2) && U32.is_eq(x, 2)
      sel(big || small, 4214960, TR())
    case 5:
      # cross: a storm cloud with a bolt
      +cloud = ell((x + 1 : U32), (y - 3 : U32), 2, 1) || ell((x - 1 : U32), (y - 3 : U32), 2, 1)
      +bolt = U32.is_eq(x, 0) && U32.is_eq(y, 1) || U32.is_eq(x, 1) && U32.is_eq(y, 0)
      sel(bolt, 16766282, sel(cloud, 7368816, TR()))
    case _:
      # delighted: a heart
      +heart = U32.is_eq(y, 4) && (sabs(x) >= 1 : U32) && (sabs(x) <= 2 : U32)
        || U32.is_eq(y, 3) && (sabs(x) <= 2 : U32) || U32.is_eq(y, 2) && (sabs(x) <= 1 : U32)
        || between(y, 0, 1) && U32.is_eq(x, 0)
      sel(heart, sel(U32.is_eq(x, (0 - 1 : U32)) && U32.is_eq(y, 3), 16758725, 14163020), TR())

def Art.bubble.go(on: Bool, +m: U32, +dx: U32, +h: U32) -> U32:
  match on:
    case True{}:
      +ax = sabs(dx)
      +box = (ax <= 5 : U32) && between(h, 17, 25) && Bool.not(U32.is_eq(ax, 5) && (U32.is_eq(h, 17) || U32.is_eq(h, 25)))
      +rim = box && (U32.is_eq(ax, 5) || U32.is_eq(h, 17) || U32.is_eq(h, 25)
        || U32.is_eq(ax, 4) && (U32.is_eq(h, 18) || U32.is_eq(h, 24)))
      +tail = U32.is_eq(dx, 0) && U32.is_eq(h, 15) || U32.is_eq(dx, 1) && U32.is_eq(h, 16)
      +pic = Art.thought(m, dx, (h - 19 : U32))
      sel(rim || tail, 5263440, sel(box, over(sel((ax <= 3 : U32) && between(h, 19, 23), pic, TR()), 16316664), TR()))
    case False{}:
      TR()

# what a guest carries in the leading hand (x: forward, y: up from the hand)
def Art.item(+it: U32, +x: U32, +y: U32) -> U32:
  match it:
    case 1:
      # a potion: glass bottle, cork
      +glass = between(x, 0, 1) && between(y, 0, 1)
      +neck = U32.is_eq(x, 0) && U32.is_eq(y, 2)
      sel(neck, 9138758, sel(glass, sel(U32.is_eq(x, 0) && U32.is_eq(y, 1), 14200063, 9844944), TR()))
    case 2:
      # a tankard of ale with its foam
      +mug = between(x, 0, 1) && between(y, 0, 1)
      +foam = between(x, 0, 1) && U32.is_eq(y, 2)
      +grip = U32.is_eq(x, 2) && U32.is_eq(y, 1)
      sel(foam, 16316656, sel(mug, 14721072, sel(grip, 9127187, TR())))
    case _:
      TR()

# a guest seen from the front (facing +x on screen: right, or mirrored) or
# the back. look bits: 0-1 class, 4-6 tunic, 8-9 skin, 12-13 facing, 16-17
# item, 20-22 thought, 24 stepping. Walking takes four frames: legs apart,
# passing (body up a pixel), apart the other way, passing.
def Art.guest(+dx: U32, +dy: U32, +look: U32, +t: U32) -> U32:
  +cls = (look .&. 3 : U32)
  +dw = U32.is_eq(cls, 3)
  +face = ((look >> 12n) .&. 3 : U32)
  +left = U32.is_eq(face, 1) || U32.is_eq(face, 2)
  +backv = (face >= 2 : U32)
  +walk = Bool.not(U32.is_eq((look .&. 16777216 : U32), 0))
  +it = ((look >> 16n) .&. 3 : U32)
  +fr = sel(walk, ((t >> 2n) .&. 3 : U32), 0)
  +bob = sel(U32.is_eq((fr .&. 1 : U32), 1), 1, 0)
  +h0 = (0 - dy : U32)
  +h = (h0 - bob : U32)
  +x = sel(left, (0 - dx : U32), dx)
  +sh = sel(dw, 2, 0)
  +tun = sel(U32.is_eq(cls, 0), 5913248, Art.tunic(((look >> 4n) .&. 7 : U32)))
  +skin = Art.skin(((look >> 8n) .&. 3 : U32))
  +hair = sel(dw, 11559978, 6965290)
  # legs: apart (frames 0, 2) or together (1, 3); the near leg is lighter
  +legtop = (2 - (sh >> 1n) + bob : U32)
  +apart = U32.is_eq((fr .&. 1 : U32), 0)
  +legat = between(h0, 0, legtop) && (apart && (U32.is_eq(x, (0 - 1 : U32)) || U32.is_eq(x, 1))
    || Bool.not(apart) && U32.is_eq(x, 0))
  +near = U32.is_eq(fr, 2) && slt(x, 0) || Bool.not(U32.is_eq(fr, 2)) && Bool.not(slt(x, 0))
  +legc = sel(near || Bool.not(walk), 3811866, 2628880)
  +foot = U32.is_eq(h0, 0) && Bool.not(apart) && U32.is_eq(x, 1)
  +body = between(h, (3 - (sh >> 1n) : U32), (6 - sh : U32)) && between(x, (0 - 2 : U32), 2)
  +belt = U32.is_eq(h, (4 - (sh >> 1n) : U32)) && between(x, (0 - 2 : U32), 2)
  # the leading hand swings with the stride (or holds the item still)
  +hy = (4 - (sh >> 1n) : U32)
  +hx = sel(opaque(Art.item(it, 0, 0)), 3, sel(walk && U32.is_eq(fr, 0), 3, sel(walk && U32.is_eq(fr, 2), (0 - 3 : U32), 3)))
  +hand = U32.is_eq(x, hx) && U32.is_eq(h, hy) && (walk || Bool.not(U32.is_eq(it, 0)))
  +held = Art.item(it, (x - 3 : U32), (h - hy - 1 : U32))
  +head = between(h, (7 - sh : U32), (9 - sh : U32)) && between(x, (0 - 1 : U32), 1)
  +eye = U32.is_eq(h, (8 - sh : U32)) && U32.is_eq(x, 1) && Bool.not(backv)
  +headc = sel(backv, hair, skin)
  # hats
  +wiz = U32.is_eq(cls, 0) && (between(h, 10, 10) && between(x, (0 - 2 : U32), 2)
    || U32.is_eq(h, 11) && between(x, (0 - 1 : U32), 1)
    || U32.is_eq(h, 12) && between(x, (0 - 1 : U32), 0)
    || U32.is_eq(h, 13) && U32.is_eq(x, (0 - 1 : U32)))
  +star = U32.is_eq(cls, 0) && U32.is_eq(h, 11) && U32.is_eq(x, 0) && Bool.not(backv)
  +helm = U32.is_eq(cls, 1) && between(h, 8, 10) && between(x, (0 - 1 : U32), 1)
  +visor = U32.is_eq(cls, 1) && U32.is_eq(h, 8) && between(x, 0, 1) && Bool.not(backv)
  +plume = U32.is_eq(cls, 1) && between(h, 11, 12) && U32.is_eq(x, 0)
  +hood = U32.is_eq(cls, 2) && (between(h, 9, 10) && between(x, (0 - 1 : U32), 1)
    || U32.is_eq(x, (0 - 2 : U32)) && between(h, 7, 9) || backv && head)
  +ear = U32.is_eq(cls, 2) && U32.is_eq(x, 2) && U32.is_eq(h, 8)
  +beard = dw && between(h, 5, 6) && between(x, (0 - 1 : U32), 1) && Bool.not(backv)
  +cap = dw && between(h, 8, 9) && between(x, (0 - 1 : U32), 1)
  +bub = Art.bubble.go(Bool.not(U32.is_eq(((look >> 20n) .&. 7 : U32), 0)) && (h0 >= 15 : U32),
    ((look >> 20n) .&. 7 : U32), dx, h0)
  over(bub, over(held, sel(hand, skin, sel(star, 16766282, sel(wiz, 5913248, sel(visor, 3158064, sel(helm, 11581632,
    sel(plume, 13643824, sel(hood, 3836474, sel(ear, skin, sel(cap, 12595248,
    sel(beard, 11559978, sel(eye, 2105376, sel(head, headc, sel(belt, 4861466,
    sel(body, sel(backv && U32.is_eq(x, 0) && U32.is_eq(cls, 0), shade(tun, 200), tun),
    sel(legat, legc, sel(foot, legc, TR()))))))))))))))))))

# Riders
# ------
# An 8-bit rider code (bit 7 occupied, bits 0-1 class, 2-4 tunic, 5-6 skin)
# turns back into the guest's look; a rider sits with its seat at (0, 0).

def Art.look_of(+code: U32) -> U32:
  ((code .&. 3) .|. (((code >> 2n) .&. 7) << 4n) .|. (((code >> 5n) .&. 3) << 8n) : U32)

def Art.rider.go(on: Bool, +dx: U32, +dy: U32, +code: U32) -> U32:
  match on:
    case True{}:
      Art.guest(dx, (dy - 3 : U32), Art.look_of(code), 0)
    case False{}:
      TR()

def Art.rider(+dx: U32, +dy: U32, +code: U32) -> U32:
  Art.rider.go(Bool.not(U32.is_eq((code .&. 128 : U32), 0)) && sle(dy, 0)
    && (sabs(dx) <= 3 : U32) && sle((0 - 14 : U32), dy), dx, dy, code)

def Art.cseat.go(near: Bool, +dx: U32, +dy: U32, +a: U32, +cx: U32, +cy: U32,
  +code: U32) -> U32:
  match near:
    case True{}:
      over(Art.rider((dx - cx : U32), (dy - cy + 2 : U32), code), Art.dragon(dx, dy, a))
    case False{}:
      TR()

# one dragon and its rider; pixels far from the seat skip the work
def Art.cseat(+dx: U32, +dy: U32, +a: U32, +code: U32) -> U32:
  +cx = wcos(a, 18)
  +cy = (wsin(a, 9) - 12 : U32)
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  Art.cseat.go((sabs(ex) <= 5 : U32) && between(ey, (0 - 16 : U32), 7), dx, dy, a, cx, cy, code)

def Art.front(+a: U32) -> Bool:
  Bool.not(neg(wsin(a, 9)))

def Art.byte(+w: U32, +i: U32) -> U32:
  match i:
    case 0:
      (w .&. 255 : U32)
    case 1:
      ((w >> 8n) .&. 255 : U32)
    case 2:
      ((w >> 16n) .&. 255 : U32)
    case _:
      (w >> 24n : U32)

def Art.code(+ra: U32, +rb: U32, +s: U32) -> U32:
  sel((s < 4 : U32), Art.byte(ra, s), Art.byte(rb, (s - 4 : U32)))

# UI
# --

# the carousel's turn while running: it speeds up, turns, slows down, and
# stops where it started (three turns in 448 ticks)
def Art.spin(+st: U32) -> U32:
  +ph = ((st >> 16n) .&. 3 : U32)
  +tm = U32.min((st .&. 65535 : U32), 447)
  +r = (448 - tm : U32)
  sel(U32.is_eq(ph, 1), sel((tm < 64 : U32), ((tm * tm) >> 6n : U32),
    sel((tm < 384 : U32), (64 + 2 * (tm - 64) : U32), (768 - ((r * r) >> 6n) : U32))), 0)

def Art.carousel(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +canopy = Art.cone(dx, dy, (0 - 30 : U32), 28, 16, 8077216, 15253568)
  +pole = (sabs(dx) <= 1 : U32) && between(dy, (0 - 32 : U32), (0 - 4 : U32))
  +top = ell(dx, (dy + 4 : U32), 26, 13)
  +side = ell(dx, dy, 26, 13) && sle((0 - 4 : U32), dy)
  +plank = U32.is_eq(((dx + dy * 2 + 256) .&. 7 : U32), 0)
  +flagp = U32.is_eq(dx, 0) && between(dy, (0 - 53 : U32), (0 - 46 : U32))
  +flag = between(dx, 1, 5) && between(dy, (0 - 53 : U32), (0 - 50 : U32))
  +a0 = Art.spin(st)
  +a1 = (a0 + 32 : U32)
  +a2 = (a0 + 64 : U32)
  +a3 = (a0 + 96 : U32)
  +a4 = (a0 + 128 : U32)
  +a5 = (a0 + 160 : U32)
  +a6 = (a0 + 192 : U32)
  +a7 = (a0 + 224 : U32)
  +c0 = Art.cseat(dx, dy, a0, Art.code(ra, rb, 0))
  +c1 = Art.cseat(dx, dy, a1, Art.code(ra, rb, 1))
  +c2 = Art.cseat(dx, dy, a2, Art.code(ra, rb, 2))
  +c3 = Art.cseat(dx, dy, a3, Art.code(ra, rb, 3))
  +c4 = Art.cseat(dx, dy, a4, Art.code(ra, rb, 4))
  +c5 = Art.cseat(dx, dy, a5, Art.code(ra, rb, 5))
  +c6 = Art.cseat(dx, dy, a6, Art.code(ra, rb, 6))
  +c7 = Art.cseat(dx, dy, a7, Art.code(ra, rb, 7))
  +f0 = Art.front(a0)
  +f1 = Art.front(a1)
  +f2 = Art.front(a2)
  +f3 = Art.front(a3)
  +f4 = Art.front(a4)
  +f5 = Art.front(a5)
  +f6 = Art.front(a6)
  +f7 = Art.front(a7)
  +fronts = over(sel(f0, c0, TR()), over(sel(f1, c1, TR()), over(sel(f2, c2, TR()),
    over(sel(f3, c3, TR()), over(sel(f4, c4, TR()), over(sel(f5, c5, TR()),
    over(sel(f6, c6, TR()), sel(f7, c7, TR()))))))))
  +backs = over(sel(f0, TR(), c0), over(sel(f1, TR(), c1), over(sel(f2, TR(), c2),
    over(sel(f3, TR(), c3), over(sel(f4, TR(), c4), over(sel(f5, TR(), c5),
    over(sel(f6, TR(), c6), sel(f7, TR(), c7))))))))
  +posts = U32.is_eq(((dx + 256) .&. 15 : U32), 0) && between(dy, (0 - 30 : U32), (0 - 6 : U32))
    && (sabs(dx) < 26 : U32)
  +m = ((dx + 256) .&. 7 : U32)
  +deep = sel(U32.is_eq(m, 0) || U32.is_eq(m, 7), 1, sel(U32.is_eq(m, 1) || U32.is_eq(m, 6), 3, 4))
  +rim0 = ell(dx, (dy + 30 : U32), 28, 14)
  +val = Bool.not(rim0) && ell(dx, (dy + 30 - deep : U32), 28, 14) && sle((0 - 30 : U32), dy)
  +lampy = Bool.not(rim0) && ell(dx, (dy + 29 : U32), 28, 14)
  +lamp = lampy && val && (U32.is_eq(m, 3) || U32.is_eq(m, 4))
  +lit = U32.is_eq(((((dx + 256) >> 3n) + (t >> 4n)) .&. 1 : U32), 0)
  +valc = sel(U32.is_eq((((dx + 256) >> 3n) .&. 1 : U32), 0), 8077216, 15253568)
  +valance = sel(lamp, sel(lit, 16775360, 13148232), sel(val, sel(Bool.not(ell(dx, (dy + 31 - deep : U32), 28, 14)), shade(valc, 150), valc), TR()))
  over(valance, over(canopy, over(sel(flagp, 14737632, sel(flag, 13643824, TR())),
    over(fronts, over(sel(pole, 14725184, sel(posts, 14725184, TR())), over(backs,
      sel(top, sel(plank, 8014378, 11565637), sel(side, 7031338, TR()))))))))

def Art.sseat(+dx: U32, +dy: U32, +ringy: U32, +s: U32, +code: U32) -> U32:
  +a = (s * 32 + 16 : U32)
  +ex = (dx - wcos(a, 9) : U32)
  +ey = (dy - (ringy + wsin(a, 4)) : U32)
  Art.rider(ex, ey, sel((sabs(ex) <= 3 : U32) && between(ey, (0 - 14 : U32), 0), code, 0))

def Art.spire(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +base = Art.box(dx, dy, 0, 12, 5, 9602196, 8418172, 6708076)
  +tower = Art.cyl(dx, dy, (0 - 4 : U32), 5, 60, 7100042)
  +rune = (sabs(dx) <= 1 : U32) && U32.is_eq((((dy + 1024) + (t >> 1n)) .&. 15 : U32), 0)
  +orb = ell(dx, (dy + 70 : U32), 4, 4)
  +core = ell(dx, (dy + 71 : U32), 1, 1)
  # the ring rises slowly while running and drops back at the end
  +ph = U32.min((st .&. 65535 : U32), 511)
  +running = U32.is_eq(((st >> 16n) .&. 3 : U32), 1)
  +up = sel(running, sel((ph < 384 : U32), (div3(ph) >> 1n : U32), ((512 - ph) >> 1n : U32)), 0)
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
  +r0 = Art.sseat(dx, dy, ringy, 0, Art.code(ra, rb, 0))
  +r1 = Art.sseat(dx, dy, ringy, 1, Art.code(ra, rb, 1))
  +r2 = Art.sseat(dx, dy, ringy, 2, Art.code(ra, rb, 2))
  +r3 = Art.sseat(dx, dy, ringy, 3, Art.code(ra, rb, 3))
  +r4 = Art.sseat(dx, dy, ringy, 4, Art.code(ra, rb, 4))
  +r5 = Art.sseat(dx, dy, ringy, 5, Art.code(ra, rb, 5))
  +r6 = Art.sseat(dx, dy, ringy, 6, Art.code(ra, rb, 6))
  +r7 = Art.sseat(dx, dy, ringy, 7, Art.code(ra, rb, 7))
  +frontr = over(r0, over(r1, over(r2, over(r7, TR()))))
  +backr = over(r3, over(r4, over(r5, over(r6, TR()))))
  +glint = Bool.not(orb) && ell(dx, (dy + 70 : U32), 9, 8)
    && U32.is_eq((hash((dx + 64 : U32), ((dy + 128) + (t >> 3n) : U32)) .&. 31 : U32), 0)
  over(sel(core, 16777215, sel(orb, 12122367, sel(glint, 15794175, TR()))),
    over(frontr, over(front, over(sel(rune && opaque(tower), 6287592, tower),
      over(backr, over(back, base))))))

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
  +frame = sign && (U32.is_eq(sabs(dx), 4) || U32.is_eq(dy, (0 - 25 : U32)) || U32.is_eq(dy, (0 - 20 : U32)))
  +hang = U32.is_eq(sabs(dx), 3) && between(dy, (0 - 19 : U32), (0 - 17 : U32))
  +star = U32.is_eq(dx, 0) && between(dy, (0 - 24 : U32), (0 - 21 : U32))
    || between(dx, (0 - 1 : U32), 1) && U32.is_eq(dy, (0 - 23 : U32))
  +bub = U32.is_eq((hash((dx + 64 : U32), ((dy + 64 + (t >> 3n)) : U32)) .&. 31 : U32), 0)
    && between(dx, (0 - 2 : U32), 2) && between(dy, (0 - 30 : U32), (0 - 26 : U32))
  over(sel(bub, 12648447, TR()), over(sel(star, 16766282, sel(frame, 6961706, sel(sign, 6961312, sel(hang, 3813162, TR())))),
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
  +upper = (apex + ((ax * 20) >> 4n) : U32)
  +lower = (0 - 11 + ((13 - ax) >> 1n) : U32)
  +roof = (ax <= 13 : U32) && sle(upper, dy) && sle(dy, lower)
  +thatch = U32.is_eq(((dy + ax + 256) .&. 3 : U32), 0)
  +roofc = sel(neg(dx), sel(thatch, 11045432, 13148232), sel(thatch, 8420896, 10122800))
  +chim = between(dx, 5, 7) && between(dy, (0 - 30 : U32), (0 - 20 : U32))
  +sm = (t .&. 63 : U32)
  +smoke = ell((dx - 6 : U32), (dy + 33 + (sm >> 2n) : U32), 2, 2)
    || ell((dx - 7 : U32), (dy + 38 + (sm >> 3n) : U32), 1, 1)
  +arm = between(dx, 9, 16) && U32.is_eq(dy, (0 - 17 : U32)) || U32.is_eq(dx, 10) && U32.is_eq(dy, (0 - 16 : U32))
  +chain = (U32.is_eq(dx, 12) || U32.is_eq(dx, 15)) && U32.is_eq(dy, (0 - 16 : U32))
  +board = between(dx, 11, 16) && between(dy, (0 - 15 : U32), (0 - 9 : U32))
  +edge = board && (U32.is_eq(dx, 11) || U32.is_eq(dx, 16) || U32.is_eq(dy, (0 - 15 : U32)) || U32.is_eq(dy, (0 - 9 : U32)))
  +mug = between(dx, 13, 14) && between(dy, (0 - 12 : U32), (0 - 11 : U32))
  +foam = between(dx, 13, 14) && U32.is_eq(dy, (0 - 13 : U32))
  +grip = U32.is_eq(dx, 15) && U32.is_eq(dy, (0 - 12 : U32))
  +signc = sel(edge, 5913120, sel(foam, 16316656, sel(mug, 14721072, sel(grip, 14721072, 9127187))))
  over(sel(arm || chain, 3158064, sel(board, signc, TR())),
    over(sel(smoke, 13421772, TR()), over(sel(chim, 8016192, TR()),
    sel(roof, roofc, sel(door, 5913120, wallc)))))

def Art.ride.go(+k: U32, +dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  match k:
    case 1:
      Art.carousel(dx, dy, t, ra, rb, st)
    case 2:
      Art.spire(dx, dy, t, ra, rb, st)
    case 3:
      Art.potion(dx, dy, t)
    case 4:
      Art.tavern(dx, dy, t)
    case _:
      TR()

# a blinking warning over a ride that can't run (no entrance or no exit)
def Art.warn(on: Bool, +dx: U32, +dy: U32, +t: U32) -> U32:
  match on:
    case True{}:
      +cy = (dy + 84 : U32)
      +disc = ell(dx, cy, 5, 5)
      +rim = disc && Bool.not(ell(dx, cy, 4, 4))
      +bang = U32.is_eq(dx, 0) && (between(dy, (0 - 87 : U32), (0 - 83 : U32)) || U32.is_eq(dy, (0 - 81 : U32)))
      +vis = Bool.not(U32.is_eq(((t >> 4n) .&. 3 : U32), 0))
      sel(vis && disc, sel(bang, 16777215, sel(rim, 8392720, 14163020)), TR())
    case False{}:
      TR()

# st: phase << 16 | ticks into it, bit 30 when the ride lacks a door
def Art.ride(+k: U32, +dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  over(Art.warn(Bool.not(U32.is_eq((st .&. 1073741824 : U32), 0)), dx, dy, t),
    Art.ride.go(k, dx, dy, t, ra, rb, st))

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

def Art.car(+dx: U32, +dy: U32, +d: U32, +lead: U32, +rd: U32) -> U32:
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +topy = ((dy + 5) * 2 : U32)
  +ontop = Art.car_in(dx, topy, along_u)
  +side = Art.car_in(dx, (dy * 2 : U32), along_u) || Art.car_in(dx, ((dy + 1) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 2) * 2 : U32), along_u) || Art.car_in(dx, ((dy + 3) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 4) * 2 : U32), along_u)
  +body = sel(U32.is_eq(lead, 1), 13120044, 4172373)
  +sx = sel(along_u, 3, (0 - 3 : U32))
  +front = Art.rider((dx - sx : U32), (dy + 5 - 1 : U32), ((rd >> 8n) .&. 255 : U32))
  +back = Art.rider((dx + sx : U32), (dy + 5 + 1 : U32), (rd .&. 255 : U32))
  over(front, over(back, sel(ontop, shade(body, 290), sel(side, shade(body,
    sel(neg(dx), 210, 160)), TR()))))

# Adventurers
# -----------
# look: bits 0-1 class (wizard, knight, elf, dwarf), 4-6 tunic, 8-9 skin

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
    case 11:
      +posts = (U32.is_eq(sabs(cx), 6) && between(cy, (0 - 5 : U32), 4))
      +rope = between(cx, (0 - 6 : U32), 6) && U32.is_eq(cy, (0 - 2 + (sabs(cx) >> 2n) : U32))
      sel(posts, 7031339, sel(rope, 8011680, sel(Art.dia(cx, (cy - 4 : U32)), 10125936, TR())))
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

