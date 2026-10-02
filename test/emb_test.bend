import Base
import ./check.bend as C
import ../src/core/vt.bend as VT
import ../src/core/emb.bend as E
import ../src/core/utf8.bend as U8

def esc(+s: String) -> String:
  E.Emb.e() ++ s

# colored text, a bold word, a cursor moved and application keys on
def screen() -> VT.Vt:
  VT.Vt.feed(VT.Vt.new(30, 6), U8.Utf8.encode("hello " ++ esc("[31mred") ++ esc("[0m ") ++ esc("[1mbold") ++ esc("[0m\r\nline two") ++ esc("[?1h") ++ esc("[5;3H")))

def again(+v: VT.Vt) -> VT.Vt:
  VT.Vt.feed(VT.Vt.new(VT.Vt.cols(v), VT.Vt.rows(v)), E.Emb.snap(v))

def Show.runs(rs: List<&2, VT.VRun>) -> String:
  match rs:
    case Nil{}:
      ""
    case VT.VRun{t, +fg, +bg, bo, ul} <> r:
      "[" ++ t ++ "," ++ U32.show(fg) ++ "," ++ U32.show(bg) ++ "," ++ Bool.show(bo) ++ "," ++ Bool.show(ul) ++ "]" ++ Show.runs(r)

def Show.lines(ls: List<&2, VT.VLine>) -> String:
  match ls:
    case Nil{}:
      ""
    case VT.VLine{rs} <> t:
      Show.runs(rs) ++ "|" ++ Show.lines(t)

def Show.cur(c: VT.VCur) -> String:
  match c:
    case VT.VCur{x, y, on}:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ Bool.show(on)

def Show.vt(+v: VT.Vt) -> String:
  Show.lines(VT.Vt.lines(v, 0n)) ++ " @" ++ Show.cur(VT.Vt.cursor(v)) ++ " appk=" ++ Bool.show(VT.Vt.appk(v)) ++ " alt=" ++ Bool.show(VT.Vt.alt(v))

def full() -> VT.Vt:
  VT.Vt.feed(VT.Vt.new(20, 4), U8.Utf8.encode(esc("[?1049h") ++ esc("[44m") ++ "top" ++ esc("[0m") ++ esc("[?25l") ++ esc("]2;tool") ++ SCon{Chr{7}, SNil{}}))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("text", E.Emb.text(screen()), "hello red bold\nline two")
    C.Check.str("snap redraws the screen", Show.vt(again(screen())), Show.vt(screen()))
    C.Check.str("snap keeps the alternate screen, hidden cursor, title", Show.vt(again(full())) ++ VT.Vt.title(again(full())), Show.vt(full()) ++ "tool")
    C.Check.str("summary", E.Emb.summary("Picker", 100, 30, "python3 pick.py\n--all"), "Picker\n100x30\npython3 pick.py\n--all")
    C.Check.str("meta", E.Emb.title("Picker\n100x30\nx\ny") ++ "|" ++ U32.show(E.Emb.wide("Picker\n100x30\nx")) ++ "|" ++ U32.show(E.Emb.tall("Picker\n100x30\nx")) ++ "|" ++ E.Emb.cmd("Picker\n100x30\nx\ny"), "Picker|100|30|x\ny")
    C.Check.str("sizes clamp", U32.show(E.Emb.wide("a\n0x0\nb")) ++ "x" ++ U32.show(E.Emb.tall("a\n0x0\nb")) ++ " " ++ U32.show(E.Emb.wide("a\n999x1\nb")) ++ "x" ++ U32.show(E.Emb.tall("a\n999x1\nb")), "80x24 200x3")
    C.Check.str("note empty", E.Emb.note(Nil{}), "")
    C.Check.str("key", E.Emb.key("t1", "a5") ++ " " ++ Bool.show(E.Emb.is_key("x:t1:a5")) ++ " " ++ E.Emb.focused(E.Emb.focus("x:t1:a5")), "x:t1:a5 True x:t1:a5")
