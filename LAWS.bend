# Eldergrove Faire -- the laws.
#
# The human owns this file: each law is a claim about the real game code,
# and PROOF.bend must prove every one of them. `bend PROOF.bend` fails while
# any law is open or false, and prints "All terms check." once all hold.
#
# Every change to a park goes through C.Park.step (a clock tick, a build, a
# coaster track edit), so a law over Park.step covers everything that can
# ever happen to a park.
import Base
import ./core.bend as C
import ./save.bend as S

# 1. MONEY. The park's gold after any step is its gold before, with the
# step's ledger applied: no gold is made or lost off the books.
law money_conserved:
  for +p: C.Park
  for +a: C.Act
  {C.Park.cash(C.Out.park(C.Park.step(p, a)))
    == C.Ledger.apply(C.Out.ledger(C.Park.step(p, a)), C.Park.cash(p)) : U32}

# 2. HEADCOUNT. Guests after + guests who left = guests before + guests who
# arrived: no adventurer appears or vanishes unaccounted for.
def count(gs: +List<C.Guest>) -> Nat:
  List.length(&2, C.Guest, gs)

law headcount_conserved:
  for +p: C.Park
  for +a: C.Act
  {Nat.add(count(C.Park.guests(C.Out.park(C.Park.step(p, a)))),
    count(C.Out.departed(C.Park.step(p, a))))
    == Nat.add(count(C.Park.guests(p)), count(C.Out.arrived(C.Park.step(p, a))))
    : Nat}

# 3. NEEDS. Every guest's hunger, thirst, energy, nausea and happiness stay
# within 0..255 -- if they did before the step, they do after it.
def needs_ok(g: C.Guest) -> Bool:
  C.Guest{id, x, y, dir, st, tgt, tmr, cash, hunger, thirst, energy, nausea,
    happy, look} = g
  U32.is_le(hunger, 255) && U32.is_le(thirst, 255) && U32.is_le(energy, 255)
    && U32.is_le(nausea, 255) && U32.is_le(happy, 255)

def all_needs_ok(gs: +List<C.Guest>) -> Bool:
  match gs:
    case []:
      True{}
    case g <> rest:
      needs_ok(g) && all_needs_ok(rest)

law needs_bounded:
  for +p: C.Park
  for +a: C.Act
  for h: {all_needs_ok(C.Park.guests(p)) == True{} : Bool}
  {all_needs_ok(C.Park.guests(C.Out.park(C.Park.step(p, a)))) == True{} : Bool}

# 4. THE COASTER RUNS ONLY ON A CLOSED CIRCUIT. A coaster that is open has
# a track that closes back on its station (at least four pieces, ending
# where it began) -- and no step can open one that does not.
def circuit_ok(t: C.Track) -> Bool:
  +t2 = t
  Bool.not(C.Track.open(t2)) || C.Track.closed(t2)

law coaster_on_circuit:
  for +p: C.Park
  for +a: C.Act
  for h: {circuit_ok(C.Park.track(p)) == True{} : Bool}
  {circuit_ok(C.Park.track(C.Out.park(C.Park.step(p, a)))) == True{} : Bool}

# 5. NO COLLISIONS. A block section holds one train at most (a block either
# holds a train or is free), and running the block signals never loses or
# duplicates a train: the number of trains on the track never changes.
law no_collisions:
  for +blocks: List<&2, C.Slot>
  for +pieces: List<&2, C.Piece>
  {C.Blocks.trains(C.Blocks.step(blocks, pieces)) == C.Blocks.trains(blocks) : Nat}

# 6. SAVES. Loading a save gives back exactly the park that was saved.
law save_load_roundtrip:
  for +p: C.Park
  {S.load(S.save(p)) == Some{p} : Maybe<&2, C.Park>}
