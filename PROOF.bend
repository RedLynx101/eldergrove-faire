# Eldergrove Faire -- the proofs of LAWS.bend.
import Base
import ./core.bend as C
import ./save.bend as S
import ./LAWS.bend as Laws

# Money: every branch of Park.step computes the ledger once and sets the
# gold to the ledger applied to it, so both sides compute to the same term.
# Proof kit
# ---------

# case analysis on any boolean, with the goal as a function of it
def bcase(+b: Bool, -P: Bool -> Type, t: P(True{}), f: P(False{})) -> P(b):
  match b:
    case True{}:
      t
    case False{}:
      f

# Nat arithmetic
def add_zero_r(+a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero_r(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def add_succ_r(+a: Nat, +b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

def add_comm(+a: Nat, +b: Nat) -> {Nat.add(a, b) == Nat.add(b, a) : Nat}:
  match a:
    case 0n:
      %add_zero_r(b) : {_ == Nat.add(b, 0n) : Nat}
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(b, 1n+p), 1n+Nat.add(b, p), add_succ_r(b, p))
        : {1n+Nat.add(p, b) == _ : Nat}
      %add_comm(p, b) : {1n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

def add_assoc(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, b, c) : {1n+Nat.add(Nat.add(p, b), c) == 1n+_ : Nat}
      {==}

def add_assoc_r(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.add(a, Nat.add(b, c)) == Nat.add(Nat.add(a, b), c) : Nat}:
  Equal.sym(Nat, Nat.add(Nat.add(a, b), c), Nat.add(a, Nat.add(b, c)),
    add_assoc(a, b, c))

# No collisions
# -------------
# A block holds at most one train by construction; these lemmas show each
# stage of Blocks.step keeps the number of trains: advancing trains inside
# their blocks, handing a train to the next block (a swap), the pass along
# the ring, and the ring's rotation.

def cnt_adv(+s: C.Slot, +ps: +List<C.Piece>)
  -> {C.Slot.count(C.Slot.adv(s, ps)) == C.Slot.count(s) : Nat}:
  match s:
    case C.Free{a, n, st}:
      {==}
    case C.Held{a, n, st, t}:
      {==}

def trains_adv(+xs: +List<C.Slot>, +ps: +List<C.Piece>)
  -> {C.Blocks.trains(C.Slots.adv(xs, ps)) == C.Blocks.trains(xs) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      %cnt_adv(s, ps) : {Nat.add(C.Slot.count(C.Slot.adv(s, ps)), C.Blocks.trains(C.Slots.adv(rest, ps)))
        == Nat.add(_, C.Blocks.trains(rest)) : Nat}
      %trains_adv(rest, ps) : {Nat.add(C.Slot.count(C.Slot.adv(s, ps)), C.Blocks.trains(C.Slots.adv(rest, ps)))
        == Nat.add(C.Slot.count(C.Slot.adv(s, ps)), _) : Nat}
      {==}

def cnt_pair(+c: C.Slot, +b: C.Slot)
  -> {Nat.add(C.Slot.count(C.Slot.cfst(c, b)), C.Slot.count(C.Slot.csnd(c, b)))
    == Nat.add(C.Slot.count(c), C.Slot.count(b)) : Nat}:
  match c b:
    case C.Held{sa, na, ta, t} C.Free{sb, nb, tb}:
      bcase(C.Train.ready(t, na), r => {Nat.add(C.Slot.count(Bool.pick(C.Slot, r,
        C.Free{sa, na, ta}, C.Held{sa, na, ta, t})), C.Slot.count(Bool.pick(C.Slot, r,
        C.Held{sb, nb, tb, C.Train.enter(t, na, tb)}, C.Free{sb, nb, tb}))) == 1n : Nat},
        {==}, {==})
    case C.Held{sa, na, ta, t} C.Held{sb, nb, tb, u}:
      {==}
    case C.Free{sa, na, ta} C.Held{sb, nb, tb, u}:
      {==}
    case C.Free{sa, na, ta} C.Free{sb, nb, tb}:
      {==}

def trains_pass(+xs: +List<C.Slot>, +c: C.Slot)
  -> {C.Blocks.trains(C.Slots.pass(xs, c)) == Nat.add(C.Slot.count(c), C.Blocks.trains(xs)) : Nat}:
  match xs:
    case []:
      {==}
    case b <> rest:
      +cf = C.Slot.count(C.Slot.cfst(c, b))
      +cs = C.Slot.count(C.Slot.csnd(c, b))
      +r = C.Blocks.trains(rest)
      +lhs = C.Blocks.trains(C.Slots.pass(b <> rest, c))
      %add_assoc(C.Slot.count(c), C.Slot.count(b), r) : {lhs == _ : Nat}
      %cnt_pair(c, b) : {lhs == Nat.add(_, r) : Nat}
      %add_assoc_r(cf, cs, r) : {lhs == _ : Nat}
      %trains_pass(rest, C.Slot.csnd(c, b)) : {lhs == Nat.add(cf, _) : Nat}
      {==}

def trains_app(+xs: +List<C.Slot>, +ys: +List<C.Slot>)
  -> {C.Blocks.trains(List.append(&2, C.Slot, xs, ys))
    == Nat.add(C.Blocks.trains(xs), C.Blocks.trains(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      +lhs = C.Blocks.trains(List.append(&2, C.Slot, s <> rest, ys))
      %add_assoc_r(C.Slot.count(s), C.Blocks.trains(rest), C.Blocks.trains(ys)) : {lhs == _ : Nat}
      %trains_app(rest, ys) : {lhs == Nat.add(C.Slot.count(s), _) : Nat}
      {==}

def trains_rot(+xs: +List<C.Slot>)
  -> {C.Blocks.trains(C.Slots.rot(xs)) == C.Blocks.trains(xs) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      +lhs = C.Blocks.trains(C.Slots.rot(s <> rest))
      %add_comm(C.Blocks.trains(rest), C.Slot.count(s)) : {lhs == _ : Nat}
      %add_zero_r(C.Slot.count(s)) : {lhs == Nat.add(C.Blocks.trains(rest), _) : Nat}
      %trains_app(rest, [s]) : {lhs == _ : Nat}
      {==}

# Money
# -----

def Laws.money_conserved(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          {==}
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Headcount
# ---------
# A tick steps every guest (the list keeps its length), splits the stepped
# guests into those still here and those who just left (together, all of
# them), and puts the arrivals in front. Builds and track edits leave the
# guests alone.

def glen(gs: +List<C.Guest>) -> Nat:
  List.length(&2, C.Guest, gs)

def len_app(+xs: +List<C.Guest>, +ys: +List<C.Guest>)
  -> {glen(List.append(&2, C.Guest, xs, ys)) == Nat.add(glen(xs), glen(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case x <> r:
      %len_app(r, ys) : {1n+glen(List.append(&2, C.Guest, r, ys)) == 1n+_ : Nat}
      {==}

def len_step(+g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +t: U32,
  +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {glen(C.Guests.step(g, q, rs, t, pl, sn, qs)) == glen(g) : Nat}:
  match g:
    case []:
      {==}
    case x <> r:
      %len_step(r, q, rs, t, pl, sn, qs) : {1n+glen(C.Guests.step(r, q, rs, t, pl, sn, qs)) == 1n+_ : Nat}
      {==}

def part_t(+r: +List<C.Guest>,
  ih: {Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == glen(r) : Nat})
  -> {Nat.add(glen(C.Guests.stay(r)), 1n+glen(C.Guests.left(r))) == 1n+glen(r) : Nat}:
  +sl = Nat.add(glen(C.Guests.stay(r)), 1n+glen(C.Guests.left(r)))
  %ih : {sl == 1n+_ : Nat}
  %add_succ_r(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) : {sl == _ : Nat}
  {==}

def part_f(+r: +List<C.Guest>,
  ih: {Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == glen(r) : Nat})
  -> {Nat.add(1n+glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == 1n+glen(r) : Nat}:
  %ih : {1n+Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == 1n+_ : Nat}
  {==}

def part(+m: +List<C.Guest>)
  -> {Nat.add(glen(C.Guests.stay(m)), glen(C.Guests.left(m))) == glen(m) : Nat}:
  match m:
    case []:
      {==}
    case x <> r:
      bcase(C.Guest.gone(x), b => {Nat.add(glen(C.Guests.put(Bool.not(b), x, C.Guests.stay(r))),
        glen(C.Guests.put(b, x, C.Guests.left(r)))) == 1n+glen(r) : Nat},
        part_t(r, part(r)), part_f(r, part(r)))

def hc_tick(+arr: +List<C.Guest>, +g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>,
  +t: U32, +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {Nat.add(glen(List.append(&2, C.Guest, arr, C.Guests.stay(C.Guests.step(g, q, rs, t, pl, sn, qs)))),
    glen(C.Guests.left(C.Guests.step(g, q, rs, t, pl, sn, qs)))) == Nat.add(glen(g), glen(arr)) : Nat}:
  +m = C.Guests.step(g, q, rs, t, pl, sn, qs)
  +st = C.Guests.stay(m)
  +lf = C.Guests.left(m)
  +lhs = Nat.add(glen(List.append(&2, C.Guest, arr, st)), glen(lf))
  %add_comm(glen(arr), glen(g)) : {lhs == _ : Nat}
  %len_step(g, q, rs, t, pl, sn, qs) : {lhs == Nat.add(glen(arr), _) : Nat}
  %part(m) : {lhs == Nat.add(glen(arr), _) : Nat}
  %add_assoc(glen(arr), glen(st), glen(lf)) : {lhs == _ : Nat}
  %len_app(arr, st) : {lhs == Nat.add(_, glen(lf)) : Nat}
  {==}

def Laws.headcount_conserved(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          hc_tick(C.Guests.arrivals(guests, rides, time, nid, fin), guests, map, rides, time,
            C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, []), sn,
            C.Queue.list(guests, map, []))
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Needs
# -----
# Every guest a tick produces went through Guest.clamp (stepped guests and
# new arrivals alike), and the clamp is the very test the law checks. The
# guests who stay are a subset of the stepped ones; builds and track edits
# do not touch guests, so the hypothesis carries over.

def Tt(b: Bool) -> Data:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def no_ft(h: {False{} == True{} : Bool}) -> Tt(False{}):
  %Equal.sym(Bool, False{}, True{}, h) : Tt(_)
  Unit{}

def bcase_eq(+b: Bool, -P: Bool -> Type, t: {True{} == b : Bool} -> P(True{}),
  f: {False{} == b : Bool} -> P(False{})) -> P(b):
  match b:
    case True{}:
      t({==})
    case False{}:
      f({==})

def and_l(+a: Bool, -b: Bool, h: {a && b == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, no_ft(h))

def and_r(+a: Bool, -b: Bool, h: {a && b == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case True{}:
      h
    case False{}:
      Empty.absurd({b == True{} : Bool}, no_ft(h))

def and_i(+a: Bool, +b: Bool, ha: {a == True{} : Bool}, hb: {b == True{} : Bool})
  -> {a && b == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ha) : {_ && b == True{} : Bool}
  hb

# the clamp: cl255(x) = x when x <= 255, else 255
def le_cl(+x: U32) -> {True{} == U32.is_le(C.cl255(x), 255) : Bool}:
  bcase_eq(U32.is_le(x, 255), c => {True{} == U32.is_le(C.sel(c, x, 255), 255) : Bool},
    e => e, e => {==})

def ok_clamp(+g: C.Guest) -> {Laws.needs_ok(C.Guest.clamp(g)) == True{} : Bool}:
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %le_cl(hu) : {_ && U32.is_le(C.cl255(th), 255) && U32.is_le(C.cl255(en), 255)
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) == True{} : Bool}
      %le_cl(th) : {True{} && _ && U32.is_le(C.cl255(en), 255)
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) == True{} : Bool}
      %le_cl(en) : {True{} && True{} && _
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) == True{} : Bool}
      %le_cl(na) : {True{} && True{} && True{}
        && _ && U32.is_le(C.cl255(ha), 255) == True{} : Bool}
      %le_cl(ha) : {True{} && True{} && True{} && True{} && _ == True{} : Bool}
      {==}

def all_app(+xs: +List<C.Guest>, +ys: +List<C.Guest>,
  +hx: {Laws.all_needs_ok(xs) == True{} : Bool}, hy: {Laws.all_needs_ok(ys) == True{} : Bool})
  -> {Laws.all_needs_ok(List.append(&2, C.Guest, xs, ys)) == True{} : Bool}:
  match xs:
    case []:
      hy
    case x <> r:
      and_i(Laws.needs_ok(x), Laws.all_needs_ok(List.append(&2, C.Guest, r, ys)),
        and_l(Laws.needs_ok(x), Laws.all_needs_ok(r), hx),
        all_app(r, ys, and_r(Laws.needs_ok(x), Laws.all_needs_ok(r), hx), hy))

def all_stay_t(+x: C.Guest, +r: +List<C.Guest>,
  ih: {Laws.all_needs_ok(C.Guests.stay(r)) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.put(False{}, x, C.Guests.stay(r))) == True{} : Bool}:
  ih

def all_stay_f(+x: C.Guest, +r: +List<C.Guest>, hx: {Laws.needs_ok(x) == True{} : Bool},
  ih: {Laws.all_needs_ok(C.Guests.stay(r)) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.put(True{}, x, C.Guests.stay(r))) == True{} : Bool}:
  and_i(Laws.needs_ok(x), Laws.all_needs_ok(C.Guests.stay(r)), hx, ih)

def all_stay(+m: +List<C.Guest>, +h: {Laws.all_needs_ok(m) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.stay(m)) == True{} : Bool}:
  match m:
    case []:
      {==}
    case x <> r:
      +ih = all_stay(r, and_r(Laws.needs_ok(x), Laws.all_needs_ok(r), h))
      bcase(C.Guest.gone(x), b => {Laws.all_needs_ok(C.Guests.put(Bool.not(b), x,
        C.Guests.stay(r))) == True{} : Bool},
        all_stay_t(x, r, ih),
        all_stay_f(x, r, and_l(Laws.needs_ok(x), Laws.all_needs_ok(r), h), ih))

def all_step(+g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +t: U32,
  +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {Laws.all_needs_ok(C.Guests.step(g, q, rs, t, pl, sn, qs)) == True{} : Bool}:
  match g:
    case []:
      {==}
    case x <> r:
      and_i(Laws.needs_ok(C.Guest.step(x, q, rs, t, pl, sn, qs)),
        Laws.all_needs_ok(C.Guests.step(r, q, rs, t, pl, sn, qs)),
        ok_clamp(C.Guest.needs(C.Guest.move(x, q, rs, t, pl, sn, qs), t)), all_step(r, q, rs, t, pl, sn, qs))

def all_arrive(+go: Bool, +id: U32, +t: U32, +fee: U32)
  -> {Laws.all_needs_ok(C.Guests.arrive(go, id, t, fee)) == True{} : Bool}:
  match go:
    case True{}:
      and_i(Laws.needs_ok(C.Guest.new(id, t, fee)), True{}, ok_clamp(C.Guest.raw(id, t, fee)), {==})
    case False{}:
      {==}

def Laws.needs_bounded(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          +m = C.Guests.step(guests, map, rides, time, pl, sn, C.Queue.list(guests, map, []))
          all_app(C.Guests.arrivals(guests, rides, time, nid, fin), C.Guests.stay(m),
            all_arrive(C.Guests.come(guests, rides, time, fin), nid, time, U32.min(C.Fin.fee(fin), 40)),
            all_stay(m, all_step(guests, map, rides, time, pl, sn, C.Queue.list(guests, map, []))))
        case C.Build{tool, x, y, v}:
          h
        case C.TrackOp{op}:
          h
        case C.RideOp{ride, op}:
          h
        case C.ParkOp{op}:
          h

# The coaster runs only on a closed circuit
# ----------------------------------------
# A tick moves trains but never touches `open` or the pieces; building only
# ever starts a track closed; editing a track closes it; and opening sets
# `open` to the circuit check itself -- so "not open, or closed" survives.

def excl(+b: Bool) -> {Bool.not(b) || b == True{} : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def circ_tick(+t: C.Track, h: {Laws.circuit_ok(t) == True{} : Bool})
  -> {Laws.circuit_ok(C.Track.tick(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e}:
      match open:
        case True{}:
          h
        case False{}:
          {==}

def circ_build(+ok: Bool, +q: C.Q, +trk: C.Track, +tool: U32, +x: U32, +y: U32,
  +v: U32, h: {Laws.circuit_ok(trk) == True{} : Bool})
  -> {Laws.circuit_ok(C.Build.track(ok, q, trk, tool, x, y, v)) == True{} : Bool}:
  match ok:
    case True{}:
      bcase(U32.is_eq(tool, 10), b => {Laws.circuit_ok(Bool.pick(C.Track, b,
        C.Track.begin(q, x, y, v), trk)) == True{} : Bool}, {==}, h)
    case False{}:
      h

def circ_toggle(+t: C.Track) -> {Laws.circuit_ok(C.Track.toggle(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e}:
      match open:
        case True{}:
          {==}
        case False{}:
          excl(C.Track.closed(C.Track{ps, False{}, [], s, e}))

def circ_edit(+t: C.Track, +op: U32) -> {Laws.circuit_ok(C.Track.edit(t, op)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e}:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), op, C.Pose.d(e)} : C.Piece}
      bcase(U32.is_lt(op, 7), b => {Laws.circuit_ok(Bool.pick(C.Track, b,
        C.Track{List.append(&2, C.Piece, ps, [pc]), False{}, [], s, C.Piece.exit(pc)},
        C.Track{C.Pieces.init(ps), False{}, [], s, C.Piece.pose(C.Pieces.last(ps))}))
        == True{} : Bool}, {==}, {==})

def circ_op(+t: C.Track, +op: U32, +ok: Bool, h: {Laws.circuit_ok(t) == True{} : Bool})
  -> {Laws.circuit_ok(C.Track.op(t, op, ok)) == True{} : Bool}:
  match ok:
    case True{}:
      bcase(U32.is_eq(op, 8), b => {Laws.circuit_ok(Bool.pick(C.Track, b,
        C.Track.toggle(t), C.Track.edit(t, op))) == True{} : Bool},
        circ_toggle(t), circ_edit(t, op))
    case False{}:
      h

def Laws.coaster_on_circuit(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          circ_tick(track, h)
        case C.Build{tool, x, y, v}:
          circ_build(C.Build.ok(map, track, cash, tool, x, y), map, track, tool, x, y, v, h)
        case C.TrackOp{op}:
          circ_op(track, op, C.TrackOp.ok(map, track, cash, op), h)
        case C.RideOp{ride, op}:
          h
        case C.ParkOp{op}:
          h

def Laws.no_collisions(blocks, pieces):
  match blocks:
    case []:
      {==}
    case s <> rest:
      +a1 = C.Slot.adv(s, pieces)
      +ar = C.Slots.adv(rest, pieces)
      +lhs = C.Blocks.trains(C.Blocks.step(s <> rest, pieces))
      %trains_adv(rest, pieces) : {lhs == Nat.add(C.Slot.count(s), _) : Nat}
      %cnt_adv(s, pieces) : {lhs == Nat.add(_, C.Blocks.trains(ar)) : Nat}
      %trains_pass(ar, a1) : {lhs == _ : Nat}
      %trains_rot(C.Slots.pass(ar, a1)) : {lhs == _ : Nat}
      {==}

# Saves
# -----
# Decoding the words of a value, followed by anything, pushes the value and
# carries on with what follows. Each lemma is an induction over the value;
# the save of a park chains them, and the final stack is just the park.

def rt_q(+q: C.Q, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.q(q, rest), st) == S.dec(rest, S.IQ{q} <> st) : List<&2, S.Item>}:
  match q:
    case C.QL{t}:
      match t:
        case C.Tile{h, ter, obj, a, b}:
          {==}
    case C.QN{a, b, c, d}:
      +r3 = S.Enc.q(d, 2 <> rest)
      +r2 = S.Enc.q(c, r3)
      +r1 = S.Enc.q(b, r2)
      +s1 = {S.IQ{a} <> st : List<&2, S.Item>}
      +s2 = {S.IQ{b} <> s1 : List<&2, S.Item>}
      +s3 = {S.IQ{c} <> s2 : List<&2, S.Item>}
      +lhs = S.dec(S.Enc.q(C.QN{a, b, c, d}, rest), st)
      %rt_q(d, 2 <> rest, s3) : {lhs == _ : List<&2, S.Item>}
      %rt_q(c, r3, s2) : {lhs == _ : List<&2, S.Item>}
      %rt_q(b, r2, s1) : {lhs == _ : List<&2, S.Item>}
      %rt_q(a, r1, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_guest(+g: C.Guest, +rest: List<&2, U32>, +more: List<&2, C.Guest>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.guest(g, rest), S.IG{more} <> st) == S.dec(rest, S.IG{g <> more} <> st) : List<&2, S.Item>}:
  match g:
    case C.Guest{id, x, y, dir, gs, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      {==}

def rt_ride(+r: C.Ride, +rest: List<&2, U32>, +more: List<&2, C.Ride>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ride(r, rest), S.IR{more} <> st) == S.dec(rest, S.IR{r <> more} <> st) : List<&2, S.Item>}:
  match r:
    case C.Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
      {==}

def rt_piece(+p: C.Piece, +rest: List<&2, U32>, +more: List<&2, C.Piece>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.piece(p, rest), S.IP{more} <> st) == S.dec(rest, S.IP{p <> more} <> st) : List<&2, S.Item>}:
  match p:
    case C.Piece{x, y, z, kind, dir}:
      {==}

def rt_slot(+s: C.Slot, +rest: List<&2, U32>, +more: List<&2, C.Slot>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.slot(s, rest), S.IS{more} <> st) == S.dec(rest, S.IS{s <> more} <> st) : List<&2, S.Item>}:
  match s:
    case C.Free{a, n, k}:
      {==}
    case C.Held{a, n, k, t}:
      match t:
        case C.Train{id, prog, speed, wait}:
          {==}

def rt_gs(+xs: List<&2, C.Guest>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.gs(xs, rest), st) == S.dec(rest, S.IG{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.gs(x <> more, rest), st)
      %rt_guest(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_gs(more, S.Enc.guest(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_rs(+xs: List<&2, C.Ride>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.rs(xs, rest), st) == S.dec(rest, S.IR{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.rs(x <> more, rest), st)
      %rt_ride(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_rs(more, S.Enc.ride(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_ps(+xs: List<&2, C.Piece>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ps(xs, rest), st) == S.dec(rest, S.IP{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ps(x <> more, rest), st)
      %rt_piece(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(more, S.Enc.piece(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_ss(+xs: List<&2, C.Slot>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ss(xs, rest), st) == S.dec(rest, S.IS{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ss(x <> more, rest), st)
      %rt_slot(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ss(more, S.Enc.slot(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_track_go(+ps: List<&2, C.Piece>, +open: Bool, +ss: List<&2, C.Slot>,
  +sx: U32, +sy: U32, +sz: U32, +sd: U32, +ex: U32, +ey: U32, +ez: U32, +ed: U32,
  +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.track(C.Track{ps, open, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}}, rest), st)
    == S.dec(rest, S.IT{C.Track{ps, open, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}}} <> st) : List<&2, S.Item>}:
  match open:
    case True{}:
      +r12 = {12 <> 1 <> sx <> sy <> sz <> sd <> ex <> ey <> ez <> ed <> rest : List<&2, U32>}
      +lhs = S.dec(S.Enc.track(C.Track{ps, True{}, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}}, rest), st)
      %rt_ss(ss, r12, S.IP{ps} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(ps, S.Enc.ss(ss, r12), st) : {lhs == _ : List<&2, S.Item>}
      {==}
    case False{}:
      +r12 = {12 <> 0 <> sx <> sy <> sz <> sd <> ex <> ey <> ez <> ed <> rest : List<&2, U32>}
      +lhs = S.dec(S.Enc.track(C.Track{ps, False{}, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}}, rest), st)
      %rt_ss(ss, r12, S.IP{ps} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(ps, S.Enc.ss(ss, r12), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_track(+t: C.Track, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.track(t, rest), st) == S.dec(rest, S.IT{t} <> st) : List<&2, S.Item>}:
  match t:
    case C.Track{ps, open, ss, s, e}:
      match s:
        case C.Pose{sx, sy, sz, sd}:
          match e:
            case C.Pose{ex, ey, ez, ed}:
              rt_track_go(ps, open, ss, sx, sy, sz, sd, ex, ey, ez, ed, rest, st)

def rt_w(+w: U32, +rest: List<&2, U32>, +more: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(16 <> w <> rest, S.IW{more} <> st) == S.dec(rest, S.IW{w <> more} <> st) : List<&2, S.Item>}:
  {==}

def rt_ws(+xs: List<&2, U32>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ws(xs, rest), st) == S.dec(rest, S.IW{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ws(x <> more, rest), st)
      %rt_w(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(more, 16 <> x <> rest, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_fin(+f: C.Fin, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.fin(f, rest), st) == S.dec(rest, S.IF{f} <> st) : List<&2, S.Item>}:
  match f:
    case C.Fin{fee, loan, rating, now, last, hist}:
      +r14 = {14 <> fee <> loan <> rating <> rest : List<&2, U32>}
      +rh = S.Enc.ws(hist, r14)
      +rl = S.Enc.ws(last, rh)
      +lhs = S.dec(S.Enc.fin(C.Fin{fee, loan, rating, now, last, hist}, rest), st)
      %rt_ws(hist, r14, S.IW{last} <> S.IW{now} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(last, rh, S.IW{now} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(now, rl, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_staff(+s: C.Staff, +rest: List<&2, U32>, +more: List<&2, C.Staff>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.staff1(s, rest), S.IStf{more} <> st) == S.dec(rest, S.IStf{s <> more} <> st) : List<&2, S.Item>}:
  match s:
    case C.Staff{id, x, y, dir, kind, st, tgt, tmr, zone, look}:
      {==}

def rt_stf(+xs: List<&2, C.Staff>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.stf(xs, rest), st) == S.dec(rest, S.IStf{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.stf(x <> more, rest), st)
      %rt_staff(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_stf(more, S.Enc.staff1(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_park(+p: C.Park, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.park(p, rest), st) == S.dec(rest, S.IK{p} <> st) : List<&2, S.Item>}:
  match p:
    case C.Park{q, gs, rs, t, cash, time, nid, fin, mess, staff}:
      +r13 = {13 <> cash <> time <> nid <> rest : List<&2, U32>}
      +rsf = S.Enc.stf(staff, r13)
      +rm = S.Enc.ws(mess, rsf)
      +rf = S.Enc.fin(fin, rm)
      +rt = S.Enc.track(t, rf)
      +rr = S.Enc.rs(rs, rt)
      +rg = S.Enc.gs(gs, rr)
      +lhs = S.dec(S.Enc.park(C.Park{q, gs, rs, t, cash, time, nid, fin, mess, staff}, rest), st)
      %rt_stf(staff, r13, S.IW{mess} <> S.IF{fin} <> S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(mess, rsf, S.IF{fin} <> S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_fin(fin, rm, S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_track(t, rf, S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_rs(rs, rt, S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_gs(gs, rr, S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_q(q, rg, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def Laws.save_load_roundtrip(p):
  %Equal.sym(List<&2, S.Item>, S.dec(S.Enc.park(p, []), []), S.dec([], S.IK{p} <> []), rt_park(p, [], []))
    : {S.Load.fin(_) == Some{p} : Maybe<&2, C.Park>}
  {==}

# Capacity: Seat.first is a chain of Seat.pick steps, each taking seat k only
# when k < cap, so whatever it returns is NONE or below cap; Boards.put drops
# NONE; the plan only ever adds such boards to its accumulator.
def or_r(+a: Bool, +b: Bool, hb: {b == True{} : Bool}) -> {a || b == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      hb

def or_f(+a: Bool, +b: Bool, e: {False{} == a : Bool}, h: {a || b == True{} : Bool})
  -> {b == True{} : Bool}:
  %Equal.sym(Bool, False{}, a, e) : {_ || b == True{} : Bool}
  h

# P(s): s is NONE, or below cap and not yet handed out by the plan acc
def pick_ok(+f: U32, +acc: +List<C.Board>, +r: U32, +cap: U32, +k: U32, +rest: U32,
  +hr: {U32.is_eq(rest, C.NONE()) || (U32.is_lt(rest, cap) && Bool.not(C.Boards.taken(acc, r, rest))) == True{} : Bool})
  -> {U32.is_eq(C.Seat.pick(f, acc, r, cap, k, rest), C.NONE()) || (U32.is_lt(C.Seat.pick(f, acc, r, cap, k, rest), cap) && Bool.not(C.Boards.taken(acc, r, C.Seat.pick(f, acc, r, cap, k, rest)))) == True{} : Bool}:
  bcase_eq(C.Seat.has(f, C.bit8(k)) && (U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k))),
    c => {U32.is_eq(C.sel(c, k, rest), C.NONE()) || (U32.is_lt(C.sel(c, k, rest), cap) && Bool.not(C.Boards.taken(acc, r, C.sel(c, k, rest)))) == True{} : Bool},
    e => or_r(U32.is_eq(k, C.NONE()), U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k)),
      and_r(C.Seat.has(f, C.bit8(k)), U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k)),
        Equal.sym(Bool, True{}, C.Seat.has(f, C.bit8(k)) && (U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k))), e))),
    e => hr)

def seat_ok(+m: U32, +acc: +List<C.Board>, +r: U32, +cap: U32)
  -> {U32.is_eq(C.Seat.free(m, acc, r, cap), C.NONE()) || (U32.is_lt(C.Seat.free(m, acc, r, cap), cap) && Bool.not(C.Boards.taken(acc, r, C.Seat.free(m, acc, r, cap)))) == True{} : Bool}:
  +f = (m .^. 255 : U32)
  pick_ok(f, acc, r, cap, 0, C.Seat.pick(f, acc, r, cap, 1, C.Seat.pick(f, acc, r, cap, 2, C.Seat.pick(f, acc, r, cap, 3, C.Seat.pick(f, acc, r, cap, 4, C.Seat.pick(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE()))))))),
  pick_ok(f, acc, r, cap, 1, C.Seat.pick(f, acc, r, cap, 2, C.Seat.pick(f, acc, r, cap, 3, C.Seat.pick(f, acc, r, cap, 4, C.Seat.pick(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE())))))),
  pick_ok(f, acc, r, cap, 2, C.Seat.pick(f, acc, r, cap, 3, C.Seat.pick(f, acc, r, cap, 4, C.Seat.pick(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE()))))),
  pick_ok(f, acc, r, cap, 3, C.Seat.pick(f, acc, r, cap, 4, C.Seat.pick(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE())))),
  pick_ok(f, acc, r, cap, 4, C.Seat.pick(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE()))),
  pick_ok(f, acc, r, cap, 5, C.Seat.pick(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE())),
  pick_ok(f, acc, r, cap, 6, C.Seat.pick(f, acc, r, cap, 7, C.NONE()),
  pick_ok(f, acc, r, cap, 7, C.NONE(), {==}))))))))

def put_ok(+s: U32, +id: U32, +r: U32, +rs: +List<C.Ride>, +acc: +List<C.Board>,
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, C.Ride.seats(C.Ride.kind(C.Rides.get(rs, r))))
    && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool},
  +h: {Laws.all_boards_ok(rs, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  +cap = C.Ride.seats(C.Ride.kind(C.Rides.get(rs, r)))
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.all_boards_ok(rs, Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(U32.is_lt(s, cap), Laws.all_boards_ok(rs, acc),
      and_l(U32.is_lt(s, cap), Bool.not(C.Boards.taken(acc, r, s)),
        or_f(U32.is_eq(s, C.NONE()), U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s)), e, hs)), h))

def try_ok(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_ok(rs, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.seats(C.Ride.kind(C.Rides.get(rs, r)))
      put_ok(C.Seat.free(C.Tab.at(occ, r), acc, r, cap), C.Guest.id(g), r, rs, acc,
        seat_ok(C.Tab.at(occ, r), acc, r, cap), h)
    case False{}:
      h

def plan_ok(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_ok(rs, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      plan_ok(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc),
        try_ok(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc, h))

def Laws.capacity_respected(gs, occ, q, rs, stn):
  plan_ok(gs, occ, q, rs, stn, [], {==})

# Riders: a rider's tick is Guest.off, which sets st to 0 (got off) or 1
# (still riding) -- never 3 (gone) -- and the needs and clamp keep st.
def riders_one(+id: U32, +x: U32, +y: U32, +dir: U32, +tgt: U32, +tmr: U32, +cash: U32,
  +hu: U32, +th: U32, +en: U32, +na: U32, +ha: U32, +lk: U32, +mind: U32, +bl: U32, +q: C.Q, +rs: +List<C.Ride>,
  +t: U32, +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {C.Guest.gone(C.Guest.step(C.Guest{id, x, y, dir, 1, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl},
    q, rs, t, pl, sn, qs)) == False{} : Bool}:
  bcase(C.Guest.done(tmr, dir, tgt, rs, sn),
    b => {C.Guest.gone(C.Guest.clamp(C.Guest.needs(C.Guest.off(b, id, x, y, dir, tgt, tmr, cash,
      hu, th, en, na, ha, lk, mind, bl, q, rs, t), t))) == False{} : Bool},
    {==}, {==})

def Laws.riders_conserved(g, q, rs, t, plan, stn, qs, h):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %Equal.sym(U32, st, 1, h) : {C.Guest.gone(C.Guest.step(C.Guest{id, x, y, dir, _, tgt, tmr, cash,
        hu, th, en, na, ha, lk, mind, bl}, q, rs, t, plan, stn, qs)) == False{} : Bool}
      riders_one(id, x, y, dir, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl, q, rs, t, plan, stn, qs)

# Boarding only while loading: Guest.wants puts Ride.loading first, so a
# guest the plan seats has a loading ride; the plan keeps that for every
# board it adds (the same shape as capacity).
def load_put(+s: U32, +id: U32, +r: U32, +rs: +List<C.Ride>, +sn: C.Stn, +acc: +List<C.Board>,
  +hl: {C.Ride.loading(C.Rides.get(rs, r), sn) == True{} : Bool},
  +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.all_boards_loading(rs, sn, Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(C.Ride.loading(C.Rides.get(rs, r), sn), Laws.all_boards_loading(rs, sn, acc), hl, h))

def load_try(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool},
  hw: {want == True{} : Bool} -> {C.Ride.loading(C.Rides.get(rs, C.Guest.tgt(g)), sn) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.seats(C.Ride.kind(C.Rides.get(rs, r)))
      load_put(C.Seat.free(C.Tab.at(occ, r), acc, r, cap), C.Guest.id(g), r, rs, sn, acc, hw({==}), h)
    case False{}:
      h

def load_plan(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      match g:
        case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
          +gg = {C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} : C.Guest}
          load_plan(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(gg, q, rs, sn), gg, occ, rs, sn, acc),
            load_try(C.Guest.wants(gg, q, rs, sn), gg, occ, rs, sn, acc, h,
              e => and_l(C.Ride.loading(C.Rides.get(rs, tgt), sn),
                C.Guest.ready(C.Rides.get(rs, tgt), st, tgt, x, y, cash), e)))

def Laws.board_only_when_loading(gs, occ, q, rs, stn):
  load_plan(gs, occ, q, rs, stn, [], {==})

# Riding until unloading: a rider's tick is Guest.off(Guest.done(...)), and
# Guest.done is Ride.unloading; while that is False, Guest.off keeps st at 1.
def Laws.ride_until_unloading(g, q, rs, t, plan, stn, qs, h, u):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %Equal.sym(U32, st, 1, h) : {C.Guest.st(C.Guest.step(C.Guest{id, x, y, dir, _, tgt, tmr, cash,
        hu, th, en, na, ha, lk, mind, bl}, q, rs, t, plan, stn, qs)) == 1 : U32}
      %Equal.sym(Bool, C.Ride.unloading(C.Rides.get(rs, tgt), stn, dir, tmr), False{}, u)
        : {C.Guest.st(C.Guest.clamp(C.Guest.needs(C.Guest.off(_, id, x, y, dir, tgt, tmr, cash,
          hu, th, en, na, ha, lk, mind, bl, q, rs, t), t))) == 1 : U32}
      {==}

# Seats: every seat the plan hands out passed "not taken by acc" (P above),
# and the law's taken is the plan's own check, so each new board is distinct
# from all before it.
def taken_eq(+bs: +List<C.Board>, +r: U32, +s: U32)
  -> {Laws.taken(bs, r, s) == C.Boards.taken(bs, r, s) : Bool}:
  match bs:
    case []:
      {==}
    case b <> rest:
      match b:
        case C.Board{g, ride, seat}:
          %Equal.sym(Bool, Laws.taken(rest, r, s), C.Boards.taken(rest, r, s), taken_eq(rest, r, s))
            : {(U32.is_eq(ride, r) && U32.is_eq(seat, s)) || _
              == (U32.is_eq(ride, r) && U32.is_eq(seat, s)) || C.Boards.taken(rest, r, s) : Bool}
          {==}

def uniq_new(+s: U32, +r: U32, +cap: U32, +acc: +List<C.Board>, +e: {False{} == U32.is_eq(s, C.NONE()) : Bool},
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool})
  -> {Bool.not(Laws.taken(acc, r, s)) == True{} : Bool}:
  %Equal.sym(Bool, Laws.taken(acc, r, s), C.Boards.taken(acc, r, s), taken_eq(acc, r, s))
    : {Bool.not(_) == True{} : Bool}
  and_r(U32.is_lt(s, cap), Bool.not(C.Boards.taken(acc, r, s)),
    or_f(U32.is_eq(s, C.NONE()), U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s)), e, hs))

def uniq_put(+s: U32, +id: U32, +r: U32, +cap: U32, +acc: +List<C.Board>,
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool},
  +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.distinct(Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(Bool.not(Laws.taken(acc, r, s)), Laws.distinct(acc), uniq_new(s, r, cap, acc, e, hs), h))

def uniq_try(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.seats(C.Ride.kind(C.Rides.get(rs, r)))
      uniq_put(C.Seat.free(C.Tab.at(occ, r), acc, r, cap), C.Guest.id(g), r, cap, acc,
        seat_ok(C.Tab.at(occ, r), acc, r, cap), h)
    case False{}:
      h

def uniq_plan(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      uniq_plan(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc),
        uniq_try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc, h))

def Laws.seats_unique(gs, occ, q, rs, stn):
  uniq_plan(gs, occ, q, rs, stn, [], {==})

# Purchases: Guest.wants puts Guest.affords (price <= gold) right after
# Ride.loading, and Guest.board pays with Guest.pay, which takes exactly the
# price whenever it is affordable.
def Laws.purchase_is_transfer(g, q, rs, seat, stn, h):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      +rd = C.Rides.get(rs, tgt)
      +hp = and_l(C.Guest.affords(rd, cash), C.Guest.at_ride(rd, st, tgt, x, y),
        and_r(C.Ride.loading(rd, stn), C.Guest.ready(rd, st, tgt, x, y, cash), h))
      %Equal.sym(Bool, U32.is_le(C.Ride.price(rd), cash), True{}, hp)
        : {C.sel(_, (cash - C.Ride.price(rd) : U32), 0) == (cash - C.Ride.price(rd) : U32) : U32}
      {==}

# Prices: every price a step can make passes through Price.cap (or keeps an
# old price); the entry fee through Fee.cap.
def cap_ok(+v: U32) -> {U32.is_le(C.Price.cap(v), 20) == True{} : Bool}:
  bcase_eq(U32.is_le(v, 20), c => {U32.is_le(C.sel(c, v, 20), 20) == True{} : Bool},
    e => Equal.sym(Bool, True{}, U32.is_le(v, 20), e), e => {==})

def fee_cap_ok(+v: U32) -> {U32.is_le(C.Fee.cap(v), 40) == True{} : Bool}:
  bcase_eq(U32.is_le(v, 40), c => {U32.is_le(C.sel(c, v, 40), 40) == True{} : Bool},
    e => Equal.sym(Bool, True{}, U32.is_le(v, 40), e), e => {==})

def tick_ok(+rs: +List<C.Ride>, +idx: U32, +q: C.Q, +ps: +List<C.Piece>, +occ: +List<U32>,
  +plan: +List<C.Board>, +qt: +List<U32>, +fr: Bool, +t: U32, +fx: +List<U32>, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.tick(rs, idx, q, ps, occ, plan, qt, fr, t, fx)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.tick(rest, (idx + 1 : U32), q, ps, occ, plan, qt, fr, t, fx)),
            and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h),
            tick_ok(rest, (idx + 1 : U32), q, ps, occ, plan, qt, fr, t, fx, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h)))

def coaster_ok(+rs: +List<C.Ride>, +op: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.coaster(rs, op)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.coaster(rest, op)),
            and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h),
            coaster_ok(rest, op, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h)))

def set_ok(+rs: +List<C.Ride>, +i: U32, +op: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.set(rs, i, op)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          +rr = {C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} : C.Ride}
          +tail = set_ok(rest, (i - 1 : U32), op, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h))
          bcase(U32.is_eq(i, 0),
            c => {Laws.prices_ok(Bool.pick(C.Ride, c, C.Ride.set(rr, op), rr) <> C.Rides.set(rest, (i - 1 : U32), op)) == True{} : Bool},
            and_i(U32.is_le(C.Ride.price(C.Ride.set(rr, op)), 20), Laws.prices_ok(C.Rides.set(rest, (i - 1 : U32), op)),
              cap_ok(C.sel(U32.is_eq(op, 1), (price + 1 : U32), C.sel(U32.is_eq(op, 2), C.sub0(price, 1), price))), tail),
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.set(rest, (i - 1 : U32), op)),
              and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h), tail))

def kill_ok(+rs: +List<C.Ride>, +i: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.kill(rs, i)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          +rr = {C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} : C.Ride}
          +hp = and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h)
          +tail = kill_ok(rest, (i - 1 : U32), and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h))
          bcase(U32.is_eq(i, 0),
            c => {Laws.prices_ok(Bool.pick(C.Ride, c, C.Ride.killed(rr), rr) <> C.Rides.kill(rest, (i - 1 : U32))) == True{} : Bool},
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.kill(rest, (i - 1 : U32))), hp, tail),
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.kill(rest, (i - 1 : U32))), hp, tail))

def app_ok(+rs: +List<C.Ride>, +n: C.Ride, +h: {Laws.prices_ok(rs) == True{} : Bool},
  +hn: {U32.is_le(C.Ride.price(n), 20) == True{} : Bool})
  -> {Laws.prices_ok(List.append(&2, C.Ride, rs, [n])) == True{} : Bool}:
  match rs:
    case []:
      and_i(U32.is_le(C.Ride.price(n), 20), True{}, hn, {==})
    case r <> rest:
      and_i(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(List.append(&2, C.Ride, rest, [n])),
        and_l(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(rest), h),
        app_ok(rest, n, and_r(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(rest), h), hn))

def new_ok(+k: U32, +x: U32, +y: U32, +s: U32, +o: U32, +t: U32)
  -> {U32.is_le(C.Ride.price(C.Ride.new(k, x, y, s, o, t)), 20) == True{} : Bool}:
  cap_ok(C.Ride.fee(k))

def build_ok(+ok: Bool, +q: C.Q, +rs: +List<C.Ride>, +tool: U32, +x: U32, +y: U32, +time: U32,
  +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Build.rides(ok, q, rs, tool, x, y, time)) == True{} : Bool}:
  match ok:
    case True{}:
      +t = C.Land.get(q, x, y)
      +k = C.Tool.kind(tool)
      +s = C.Ride.size(k)
      +coast = Bool.pick(+List<C.Ride>, U32.is_eq(tool, 10), List.append(&2, C.Ride, rs, [C.Ride.new(5, x, y, 1, 0, time)]), rs)
      +add = Bool.pick(+List<C.Ride>, Bool.not(U32.is_eq(k, 0)),
        List.append(&2, C.Ride, rs, [C.Ride.new(k, x, y, s, 1, time)]), coast)
      bcase(U32.is_eq(tool, 9) && U32.is_eq(C.Tile.obj(t), 3),
        c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, C.Rides.kill(rs, C.Tile.a(t)), add)) == True{} : Bool},
        kill_ok(rs, C.Tile.a(t), h),
        bcase(Bool.not(U32.is_eq(k, 0)),
          c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, List.append(&2, C.Ride, rs, [C.Ride.new(k, x, y, s, 1, time)]), coast)) == True{} : Bool},
          app_ok(rs, C.Ride.new(k, x, y, s, 1, time), h, new_ok(k, x, y, s, 1, time)),
          bcase(U32.is_eq(tool, 10),
            c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, List.append(&2, C.Ride, rs, [C.Ride.new(5, x, y, 1, 0, time)]), rs)) == True{} : Bool},
            app_ok(rs, C.Ride.new(5, x, y, 1, 0, time), h, new_ok(5, x, y, 1, 0, time)),
            h)))
    case False{}:
      h

def pb_go(+a: C.Act, +map: C.Q, +guests: +List<C.Guest>, +rides: +List<C.Ride>, +track: C.Track,
  +cash: U32, +time: U32, +nid: U32, +fee: U32, +loan: U32, +rating: U32, +now: +List<U32>,
  +last: +List<U32>, +hist: +List<U32>, +mess: +List<U32>, +staff: +List<C.Staff>,
  +h: {Laws.prices_ok(rides) && U32.is_le(fee, 40) == True{} : Bool})
  -> {Laws.park_prices_ok(C.Out.park(C.Park.step(C.Park{map, guests, rides, track, cash, time, nid,
    C.Fin{fee, loan, rating, now, last, hist}, mess, staff}, a))) == True{} : Bool}:
  match a:
    case C.Tick{}:
      +sn = C.Track.stn(track)
      +occ = C.Occ.table(guests, rides, sn)
      +pl = C.Boards.plan(guests, occ, map, rides, sn, [])
      +fr = U32.is_eq((time .&. 15 : U32), 0)
      +qt = C.Qlen.fill_if(fr, guests, map, C.len32(C.Ride, rides))
      and_i(Laws.prices_ok(C.Rides.tick(rides, 0, map, C.Track.pieces(track), occ, pl, qt, fr, time, C.Staff.fixing(staff))), U32.is_le(fee, 40),
        tick_ok(rides, 0, map, C.Track.pieces(track), occ, pl, qt, fr, time, C.Staff.fixing(staff), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.Build{tool, x, y, v}:
      and_i(Laws.prices_ok(C.Build.rides(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y, time)),
        U32.is_le(fee, 40), build_ok(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y, time, and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.TrackOp{op}:
      +trk2 = C.Track.op(track, op, C.TrackOp.ok(map, track, cash, op))
      and_i(Laws.prices_ok(C.Rides.coaster(rides, C.sel(C.Track.open(trk2), 1, 0))), U32.is_le(fee, 40),
        coaster_ok(rides, C.sel(C.Track.open(trk2), 1, 0), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.RideOp{ride, op}:
      and_i(Laws.prices_ok(C.Rides.set(rides, ride, op)), U32.is_le(fee, 40), set_ok(rides, ride, op, and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.ParkOp{op}:
      +f2 = C.sel(U32.is_eq(op, 0), (fee + 1 : U32), C.sel(U32.is_eq(op, 1), C.sub0(fee, 1), fee))
      and_i(Laws.prices_ok(rides), U32.is_le(C.Fee.cap(f2), 40), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h), fee_cap_ok(f2))

def Laws.prices_bounded(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match fin:
        case C.Fin{fee, loan, rating, now, last, hist}:
          pb_go(a, map, guests, rides, track, cash, time, nid, fee, loan, rating, now, last, hist, mess, staff, h)

# Litter: a tick's mess is the drops put in front of what wasn't swept, and
# the kept and swept pieces split the old mess between them (as the guests
# who stay and leave do); other steps leave the mess alone.
def mlen_app(+xs: +List<U32>, +ys: +List<U32>)
  -> {Laws.mcount(List.append(&2, U32, xs, ys)) == Nat.add(Laws.mcount(xs), Laws.mcount(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case x <> r:
      %mlen_app(r, ys) : {1n+Laws.mcount(List.append(&2, U32, r, ys)) == 1n+_ : Nat}
      {==}

def mpart_t(+r: +List<U32>, +ss: +List<C.Staff>,
  ih: {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == Laws.mcount(r) : Nat})
  -> {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), 1n+Laws.mcount(C.Mess.swept(r, ss))) == 1n+Laws.mcount(r) : Nat}:
  +sl = Nat.add(Laws.mcount(C.Mess.kept(r, ss)), 1n+Laws.mcount(C.Mess.swept(r, ss)))
  %ih : {sl == 1n+_ : Nat}
  %add_succ_r(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) : {sl == _ : Nat}
  {==}

def mpart_f(+r: +List<U32>, +ss: +List<C.Staff>,
  ih: {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == Laws.mcount(r) : Nat})
  -> {Nat.add(1n+Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == 1n+Laws.mcount(r) : Nat}:
  %ih : {1n+Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == 1n+_ : Nat}
  {==}

def mpart(+ms: +List<U32>, +ss: +List<C.Staff>)
  -> {Nat.add(Laws.mcount(C.Mess.kept(ms, ss)), Laws.mcount(C.Mess.swept(ms, ss))) == Laws.mcount(ms) : Nat}:
  match ms:
    case []:
      {==}
    case m <> r:
      bcase(C.Mess.sweeps(m, ss), b => {Nat.add(Laws.mcount(C.Mess.put(Bool.not(b), m, C.Mess.kept(r, ss))),
        Laws.mcount(C.Mess.put(b, m, C.Mess.swept(r, ss)))) == 1n+Laws.mcount(r) : Nat},
        mpart_t(r, ss, mpart(r, ss)), mpart_f(r, ss, mpart(r, ss)))

def mc_tick(+d: +List<U32>, +ms: +List<U32>, +ss: +List<C.Staff>)
  -> {Nat.add(Laws.mcount(List.append(&2, U32, d, C.Mess.kept(ms, ss))), Laws.mcount(C.Mess.swept(ms, ss)))
    == Nat.add(Laws.mcount(ms), Laws.mcount(d)) : Nat}:
  +k = C.Mess.kept(ms, ss)
  +sw = C.Mess.swept(ms, ss)
  +lhs = Nat.add(Laws.mcount(List.append(&2, U32, d, k)), Laws.mcount(sw))
  %add_comm(Laws.mcount(d), Laws.mcount(ms)) : {lhs == _ : Nat}
  %mpart(ms, ss) : {lhs == Nat.add(Laws.mcount(d), _) : Nat}
  %add_assoc(Laws.mcount(d), Laws.mcount(k), Laws.mcount(sw)) : {lhs == _ : Nat}
  %mlen_app(d, k) : {lhs == Nat.add(_, Laws.mcount(sw)) : Nat}
  {==}

def Laws.litter_accounted(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          mc_tick(C.Mess.drops(C.Mess.events(guests, pl, map, time), (C.len32(U32, mess) < 600 : U32)), mess, staff)
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Wages
# -----
# Only one entry any step books has kind 11: the monthly wage bill in
# Ledger.tick. Sales and fees are gains; upkeep (2), construction (3),
# loans repaid (9) and interest (10) are other kinds. So the wage list of a
# step's ledger is that bill, or nothing.
def wl_upkeep(+rs: +List<C.Ride>) -> {Laws.wage_list(C.Ledger.upkeep(rs)) == [] : List<U32>}:
  match rs:
    case []:
      {==}
    case r <> rest:
      bcase(Bool.not(U32.is_eq(C.Ride.kind(r), 0)),
        b => {Laws.wage_list(C.Ledger.put(b, C.Spend{2, C.Ride.upkeep(C.Ride.kind(r))}, C.Ledger.upkeep(rest))) == [] : List<U32>},
        wl_upkeep(rest), wl_upkeep(rest))

def wl_sales(+pl: +List<C.Board>, +rs: +List<C.Ride>, +ys: +List<C.Txn>)
  -> {Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), ys)) == Laws.wage_list(ys) : List<U32>}:
  match pl:
    case []:
      {==}
    case b <> rest:
      match b:
        case C.Board{g, ride, seat}:
          wl_sales(rest, rs, ys)

# the bill itself: there when there is one
def wl_bill(+w: Bool, +v: U32, +rs: +List<C.Ride>)
  -> {Laws.wage_list(C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))) == Bool.pick(List<U32>, w, [v], []) : List<U32>}:
  bcase(w, b => {Laws.wage_list(C.Ledger.put(b, C.Spend{11, v}, C.Ledger.upkeep(rs))) == Bool.pick(List<U32>, b, [v], []) : List<U32>},
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.upkeep(rs)), [], wl_upkeep(rs)) : {v <> _ == [v] : List<U32>}
    {==},
    wl_upkeep(rs))

def wl_month(+c: Bool, +i: U32, +w: Bool, +v: U32, +rs: +List<C.Ride>)
  -> {Laws.wage_list(C.Ledger.put(c, C.Spend{10, i}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>}:
  bcase(c, b => {Laws.wage_list(C.Ledger.put(b, C.Spend{10, i}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>},
    wl_bill(w, v, rs), wl_bill(w, v, rs))

def wl_fees(+c: Bool, +f: U32, +ys: +List<C.Txn>)
  -> {Laws.wage_list(C.Ledger.put(c, C.Gain{7, f}, ys)) == Laws.wage_list(ys) : List<U32>}:
  bcase(c, b => {Laws.wage_list(C.Ledger.put(b, C.Gain{7, f}, ys)) == Laws.wage_list(ys) : List<U32>}, {==}, {==})

def wl_tick(+gs: +List<C.Guest>, +rs: +List<C.Ride>, +t: U32, +pl: +List<C.Board>, +narr: U32, +f: C.Fin,
  +ss: +List<C.Staff>)
  -> {Laws.wage_list(C.Ledger.tick(gs, rs, t, pl, narr, f, ss))
      == Bool.pick(List<U32>, U32.is_eq((t % 3600 : U32), 0) && (t > 0 : U32) && Bool.not(U32.is_eq(C.Staff.wages(ss), 0)),
        [C.Staff.wages(ss)], []) : List<U32>}:
  +fees = (narr * U32.min(C.Fin.fee(f), 40) : U32)
  +i = (C.Fin.loan(f) / 80 : U32)
  +w = Bool.not(U32.is_eq(C.Staff.wages(ss), 0))
  +inner = C.Ledger.put(Bool.not(U32.is_eq(i, 0)), C.Spend{10, i}, C.Ledger.put(w, C.Spend{11, C.Staff.wages(ss)}, C.Ledger.upkeep(rs)))
  bcase(U32.is_eq((t % 3600 : U32), 0) && (t > 0 : U32),
    m => {Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees},
        List.append(&2, C.Txn, C.Ledger.sales(pl, rs), Bool.pick(+List<C.Txn>, m, inner, []))))
      == Bool.pick(List<U32>, m && w, [C.Staff.wages(ss)], []) : List<U32>},
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees}, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner))),
        Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner)),
        wl_fees(Bool.not(U32.is_eq(fees, 0)), fees, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner))) : {_ == Bool.pick(List<U32>, w, [C.Staff.wages(ss)], []) : List<U32>}
    %Equal.sym(List<U32>, Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner)), Laws.wage_list(inner),
        wl_sales(pl, rs, inner)) : {_ == Bool.pick(List<U32>, w, [C.Staff.wages(ss)], []) : List<U32>}
    wl_month(Bool.not(U32.is_eq(i, 0)), i, w, C.Staff.wages(ss), rs),
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees}, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), []))),
        Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), [])),
        wl_fees(Bool.not(U32.is_eq(fees, 0)), fees, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), []))) : {_ == [] : List<U32>}
    wl_sales(pl, rs, []))

def wl_build(+ok: Bool, +q: C.Q, +rs: +List<C.Ride>, +tool: U32, +x: U32, +y: U32)
  -> {Laws.wage_list(C.Build.ledger(ok, q, rs, tool, x, y)) == [] : List<U32>}:
  match ok:
    case True{}:
      bcase(U32.is_eq(tool, 9),
        b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{4, C.Build.refund(q, rs, x, y)}], [C.Spend{3, C.Build.cost(tool)}])) == [] : List<U32>},
        {==}, {==})
    case False{}:
      {==}

def wl_track(+ok: Bool, +op: U32) -> {Laws.wage_list(C.TrackOp.ledger(ok, op)) == [] : List<U32>}:
  match ok:
    case True{}:
      bcase((op < 7 : U32),
        b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Spend{3, 40}],
          Bool.pick(+List<C.Txn>, U32.is_eq(op, 7), [C.Gain{4, 20}], []))) == [] : List<U32>},
        {==},
        bcase(U32.is_eq(op, 7), b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{4, 20}], [])) == [] : List<U32>},
          {==}, {==}))
    case False{}:
      {==}

def wl_loans(+b: Bool, +r: Bool)
  -> {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{8, 1000}], Bool.pick(+List<C.Txn>, r, [C.Spend{9, 1000}], []))) == [] : List<U32>}:
  bcase(b, c => {Laws.wage_list(Bool.pick(+List<C.Txn>, c, [C.Gain{8, 1000}], Bool.pick(+List<C.Txn>, r, [C.Spend{9, 1000}], []))) == [] : List<U32>},
    {==},
    bcase(r, c => {Laws.wage_list(Bool.pick(+List<C.Txn>, c, [C.Spend{9, 1000}], [])) == [] : List<U32>}, {==}, {==}))

def Laws.wages_booked(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          wl_tick(guests, rides, time, pl, C.len32(C.Guest, C.Guests.arrivals(guests, rides, time, nid, fin)), fin, staff)
        case C.Build{tool, x, y, v}:
          wl_build(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y)
        case C.TrackOp{op}:
          wl_track(C.TrackOp.ok(map, track, cash, op), op)
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          wl_loans(U32.is_eq(op, 2) && (C.Fin.loan(fin) + 1000 <= 20000 : U32),
            U32.is_eq(op, 3) && (C.Fin.loan(fin) >= 1000 : U32) && Bool.not(C.neg(cash)) && (cash >= 1000 : U32))
