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
    case C.Park{map, guests, rides, track, cash, time, nid}:
      match a:
        case C.Tick{}:
          {==}
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
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
  +pl: +List<C.Board>, +sn: C.Stn)
  -> {glen(C.Guests.step(g, q, rs, t, pl, sn)) == glen(g) : Nat}:
  match g:
    case []:
      {==}
    case x <> r:
      %len_step(r, q, rs, t, pl, sn) : {1n+glen(C.Guests.step(r, q, rs, t, pl, sn)) == 1n+_ : Nat}
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
  +t: U32, +pl: +List<C.Board>, +sn: C.Stn)
  -> {Nat.add(glen(List.append(&2, C.Guest, arr, C.Guests.stay(C.Guests.step(g, q, rs, t, pl, sn)))),
    glen(C.Guests.left(C.Guests.step(g, q, rs, t, pl, sn)))) == Nat.add(glen(g), glen(arr)) : Nat}:
  +m = C.Guests.step(g, q, rs, t, pl, sn)
  +st = C.Guests.stay(m)
  +lf = C.Guests.left(m)
  +lhs = Nat.add(glen(List.append(&2, C.Guest, arr, st)), glen(lf))
  %add_comm(glen(arr), glen(g)) : {lhs == _ : Nat}
  %len_step(g, q, rs, t, pl, sn) : {lhs == Nat.add(glen(arr), _) : Nat}
  %part(m) : {lhs == Nat.add(glen(arr), _) : Nat}
  %add_assoc(glen(arr), glen(st), glen(lf)) : {lhs == _ : Nat}
  %len_app(arr, st) : {lhs == Nat.add(_, glen(lf)) : Nat}
  {==}

def Laws.headcount_conserved(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          hc_tick(C.Guests.arrivals(guests, rides, time, nid), guests, map, rides, time,
            C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, []), sn)
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
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
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk}:
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
  +pl: +List<C.Board>, +sn: C.Stn)
  -> {Laws.all_needs_ok(C.Guests.step(g, q, rs, t, pl, sn)) == True{} : Bool}:
  match g:
    case []:
      {==}
    case x <> r:
      and_i(Laws.needs_ok(C.Guest.step(x, q, rs, t, pl, sn)),
        Laws.all_needs_ok(C.Guests.step(r, q, rs, t, pl, sn)),
        ok_clamp(C.Guest.needs(C.Guest.move(x, q, rs, t, pl, sn), t)), all_step(r, q, rs, t, pl, sn))

def all_arrive(+go: Bool, +id: U32, +t: U32)
  -> {Laws.all_needs_ok(C.Guests.arrive(go, id, t)) == True{} : Bool}:
  match go:
    case True{}:
      and_i(Laws.needs_ok(C.Guest.new(id, t)), True{}, ok_clamp(C.Guest.raw(id, t)), {==})
    case False{}:
      {==}

def Laws.needs_bounded(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid}:
      match a:
        case C.Tick{}:
          +sn = C.Track.stn(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          +m = C.Guests.step(guests, map, rides, time, pl, sn)
          all_app(C.Guests.arrivals(guests, rides, time, nid), C.Guests.stay(m),
            all_arrive(C.Guests.come(guests, rides, time), nid, time),
            all_stay(m, all_step(guests, map, rides, time, pl, sn)))
        case C.Build{tool, x, y, v}:
          h
        case C.TrackOp{op}:
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
    case C.Park{map, guests, rides, track, cash, time, nid}:
      match a:
        case C.Tick{}:
          circ_tick(track, h)
        case C.Build{tool, x, y, v}:
          circ_build(C.Build.ok(map, track, cash, tool, x, y), map, track, tool, x, y, v, h)
        case C.TrackOp{op}:
          circ_op(track, op, C.TrackOp.ok(map, track, cash, op), h)

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
    case C.Guest{id, x, y, dir, gs, tgt, tmr, cash, hu, th, en, na, ha, lk}:
      {==}

def rt_ride(+r: C.Ride, +rest: List<&2, U32>, +more: List<&2, C.Ride>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ride(r, rest), S.IR{more} <> st) == S.dec(rest, S.IR{r <> more} <> st) : List<&2, S.Item>}:
  match r:
    case C.Ride{kind, x, y, w, h, price, open}:
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

def rt_park(+p: C.Park, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.park(p, rest), st) == S.dec(rest, S.IK{p} <> st) : List<&2, S.Item>}:
  match p:
    case C.Park{q, gs, rs, t, cash, time, nid}:
      +r13 = {13 <> cash <> time <> nid <> rest : List<&2, U32>}
      +rt = S.Enc.track(t, r13)
      +rr = S.Enc.rs(rs, rt)
      +rg = S.Enc.gs(gs, rr)
      +lhs = S.dec(S.Enc.park(C.Park{q, gs, rs, t, cash, time, nid}, rest), st)
      %rt_track(t, r13, S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_rs(rs, rt, S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_gs(gs, rr, S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_q(q, rg, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def Laws.save_load_roundtrip(p):
  %Equal.sym(List<&2, S.Item>, S.dec(S.Enc.park(p, []), []), S.dec([], S.IK{p} <> []), rt_park(p, [], []))
    : {S.Load.fin(_) == Some{p} : Maybe<&2, C.Park>}
  {==}
