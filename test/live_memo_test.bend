import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/app/layout.bend as L

# A streamed reply in the window: its settled prefix is laid out once and
# kept (TL.live.get), the text after it each frame; the lines are the ones
# of the whole reply laid out at once. Layout runs with the bitmap face.

def para(+i: Nat) -> String:
  "Paragraph " ++ Nat.show(i) ++ " of *streamed* text, `code`, and enough words to wrap over a narrow column of the timeline.\n\n"

def paras(+n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      paras(k) ++ para(n)

# the lines the window shows with a memo held from the last frame
def frame(+ty: L.Ty, +ph: M.Phase, +text: String, lm: L.LiveMemo) -> List<&2, L.TLine>:
  L.TL.live.m(ty, False{}, ph, text, lm, 360)

def whole(+ty: L.Ty, +ph: M.Phase, +text: String) -> List<&2, L.TLine>:
  L.TL.live.k(ty, False{}, ph, text, 360)

def same.line(a: L.TLine, b: L.TLine) -> Bool:
  match a b:
    case L.TLine{ta, ca, ka, pa, wa} L.TLine{tb, cb, kb, pb, wb}:
      Bool.and(Bool.and(String.eq(ta, tb), String.eq(pa, pb)), Bool.and(U32.is_eq(ca, cb), Bool.and(U32.is_eq(ka, kb), U32.is_eq(wa, wb))))

def same(a: List<&2, L.TLine>, b: List<&2, L.TLine>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case x <> xs y <> ys:
      Bool.and(same.line(x, y), same(xs, ys))
    case _ _:
      False{}

def first(ls: List<&2, L.TLine>) -> String:
  match ls:
    case L.TLine{t, _, _, _, _} <> _:
      t
    case Nil{}:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    +ph : M.Phase = M.PhWorking{}
    +t1 : String = paras(8n) ++ "tail words"
    +t2 : String = paras(8n) ++ "tail words keep coming"
    +t3 : String = paras(9n) ++ "tail"
    +lm0 : L.LiveMemo = L.TL.live.none()
    +lm1 : L.LiveMemo = L.TL.live.get(ty, lm0, U.Live.head(t1), 360)
    +lm2 : L.LiveMemo = L.TL.live.get(ty, lm1, U.Live.head(t2), 360)
    +lm3 : L.LiveMemo = L.TL.live.get(ty, lm2, U.Live.head(t3), 360)
    C.Check.str("no memo: the lines are the whole's", Bool.show(same(frame(ty, ph, t1, lm0), whole(ty, ph, t1))), "True")
    C.Check.str("a memo made for the text: the whole's", Bool.show(same(frame(ty, ph, t1, lm1), whole(ty, ph, t1))), "True")
    C.Check.str("the tail grows, the prefix is kept", Bool.show(same(frame(ty, ph, t2, lm2), whole(ty, ph, t2))), "True")
    C.Check.str("a new paragraph settles", Bool.show(same(frame(ty, ph, t3, lm3), whole(ty, ph, t3))), "True")
    C.Check.str("a stale memo is not used", Bool.show(same(frame(ty, ph, t3, lm1), whole(ty, ph, t3))), "True")
    +fake : L.LiveMemo = L.LiveMemo{360, U.Live.head(t2), True{}, [L.TLine{"kept", 0, 3, "", 0}]}
    C.Check.str("a memo for this text and width is taken as it is", first(frame(ty, ph, t2, fake)), "kept")
    C.Check.str("another width lays it out again", Bool.show(String.eq(first(L.TL.live.m(ty, False{}, ph, t2, fake, 400)), "kept")), "False")
