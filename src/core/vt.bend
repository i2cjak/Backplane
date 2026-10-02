import Base
import ./utf8.bend as U

# A VT100/xterm terminal emulator, pure. Bytes from a pty go in (in any
# chunks), a grid of styled cells comes out, plus the replies the host must
# write back (cursor reports, device attributes).
#
# The screen is a balanced tree of rows, each row a balanced tree of cells, so
# printing a character rebuilds one root-to-leaf path in each. The rows sit in
# a ring (a base offset), so scrolling the full screen by a line replaces one
# row. Scrollback is a ring of 2048 rows in the same kind of tree. Runs of
# plain ASCII text collect while a chunk is read; a long run is written a
# row segment at a time.

# Trees
# -----

# a complete binary tree of 2^d leaves, indexed from the left
type Tr<-A: Data> is Data:
  TL{v: A}
  TN{l: Tr<A>, r: Tr<A>}

def Tr.twin(-A: Data, +t: Tr<A>) -> Tr<A>:
  TN{t, t}

# 2^d copies of x, sharing one node per level
def Tr.full(-A: Data, d: Nat, +x: A) -> Tr<A>:
  match d:
    case 0n:
      TL{x}
    case 1n+p:
      Tr.twin(A, Tr.full(A, p, x))

# the leaf at i; lt tells whether i is in the left half (h leaves per half)
def Tr.get(-A: Data, t: Tr<A>, lt: Bool, +i: U32, +h: U32) -> A:
  match t lt:
    case TL{x} _:
      x
    case TN{l, _} True{}:
      Tr.get(A, l, U32.is_lt(i, U32.shr(h)), i, U32.shr(h))
    case TN{_, r} False{}:
      Tr.get(A, r, U32.is_lt((i - h : U32), U32.shr(h)), (i - h : U32), U32.shr(h))

def Tr.set(-A: Data, t: Tr<A>, lt: Bool, +i: U32, +h: U32, x: A) -> Tr<A>:
  match t lt:
    case TL{_} _:
      TL{x}
    case TN{l, r} True{}:
      TN{Tr.set(A, l, U32.is_lt(i, U32.shr(h)), i, U32.shr(h), x), r}
    case TN{l, r} False{}:
      TN{l, Tr.set(A, r, U32.is_lt((i - h : U32), U32.shr(h)), (i - h : U32), U32.shr(h), x)}

# leaf i of a tree with cap leaves
def Tr.at(-A: Data, t: Tr<A>, +i: U32, +cap: U32) -> A:
  Tr.get(A, t, U32.is_lt(i, U32.shr(cap)), i, U32.shr(cap))

def Tr.put(-A: Data, t: Tr<A>, +i: U32, +cap: U32, x: A) -> Tr<A>:
  Tr.set(A, t, U32.is_lt(i, U32.shr(cap)), i, U32.shr(cap), x)

# the leaves in order, in front of acc
def Tr.list(-A: Data, t: Tr<A>, acc: List<&2, A>) -> List<&2, A>:
  match t:
    case TL{x}:
      x <> acc
    case TN{l, r}:
      Tr.list(A, l, Tr.list(A, r, acc))

def Tr.leaves(-A: Data, xs: List<&2, A>) -> List<&2, Tr<A>>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      TL{x} <> Tr.leaves(A, t)

def Tr.pairs(-A: Data, xs: List<&2, Tr<A>>) -> List<&2, Tr<A>>:
  match xs:
    case a <> b <> t:
      TN{a, b} <> Tr.pairs(A, t)
    case t:
      t

def Tr.up(-A: Data, k: Nat, xs: List<&2, Tr<A>>) -> List<&2, Tr<A>>:
  match k:
    case 0n:
      xs
    case 1n+p:
      Tr.up(A, p, Tr.pairs(A, xs))

def Tr.first(-A: Data, xs: List<&2, Tr<A>>, d: Nat, +b: A) -> Tr<A>:
  match xs:
    case h <> _:
      h
    case Nil{}:
      Tr.full(A, d, b)

# a tree of depth d from exactly 2^d leaves
def Tr.of(-A: Data, +d: Nat, xs: List<&2, A>, +b: A) -> Tr<A>:
  Tr.first(A, Tr.up(A, d, Tr.leaves(A, xs)), d, b)

# exactly k items: xs cut or padded with b
def Vt.fit(-A: Data, k: Nat, xs: List<&2, A>, +b: A) -> List<&2, A>:
  match k xs:
    case 0n _:
      Nil{}
    case 1n+p h <> t:
      h <> Vt.fit(A, p, t, b)
    case 1n+p Nil{}:
      b <> Vt.fit(A, p, Nil{}, b)

# the smallest d with 2^d >= n
def Vt.dep(fuel: Nat, ge: Bool, +p: U32, +n: U32) -> Nat:
  match fuel ge:
    case _ True{}:
      0n
    case 0n False{}:
      0n
    case 1n+f False{}:
      1n+Vt.dep(f, U32.is_ge((p * 2 : U32), n), (p * 2 : U32), n)

def Vt.depth(+n: U32) -> Nat:
  Vt.dep(20n, U32.is_ge(1, n), 1, n)

# a - b, or 0 when b > a
def Vt.sub0(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), (a - b : U32), 0)

def Vt.n(x: U32) -> Nat:
  U32.to_nat(x)

# Cells
# -----

# ch 0 is the right half of a wide character. Colors: 0..255 palette,
# 256 default, 0x1000000|rgb true color. at: 1 bold, 2 underline,
# 4 inverse, 8 dim, 16 hidden.
type Cell is Data:
  Cell{ch: U32, fg: U32, bg: U32, at: U32}

type Pen is Data:
  Pen{fg: U32, bg: U32, at: U32}

def Pen.new() -> Pen:
  Pen{256, 256, 0}

def Pen.bg(+p: Pen) -> U32:
  match p:
    case Pen{_, bg, _}:
      bg

def Cell.of(+ch: U32, p: Pen) -> Cell:
  match p:
    case Pen{fg, bg, at}:
      Cell{ch, fg, bg, at}

# an erased cell: a space in the pen's background
def Cell.blank(+bg: U32) -> Cell:
  Cell{32, 256, bg, 0}

# Geometry
# --------

# cols x rows, tree depths and capacities for a row (dc, cc) and the screen
# (dr, cr), and the scroll region top..bot (inclusive)
type Geo is Data:
  Geo{cols: U32, rows: U32, dc: Nat, dr: Nat, cc: U32, cr: U32, top: U32, bot: U32}

def Geo.mk(+cols: U32, +rows: U32, +dc: Nat, +dr: Nat) -> Geo:
  Geo{cols, rows, dc, dr, U32.shln(1, dc), U32.shln(1, dr), 0, (rows - 1 : U32)}

def Geo.new(+cols: U32, +rows: U32) -> Geo:
  Geo.mk(cols, rows, Vt.depth(cols), Vt.depth(rows))

def Geo.cols(+g: Geo) -> U32:
  match g:
    case Geo{c, _, _, _, _, _, _, _}:
      c

def Geo.rows(+g: Geo) -> U32:
  match g:
    case Geo{_, r, _, _, _, _, _, _}:
      r

def Geo.dc(+g: Geo) -> Nat:
  match g:
    case Geo{_, _, d, _, _, _, _, _}:
      d

def Geo.dr(+g: Geo) -> Nat:
  match g:
    case Geo{_, _, _, d, _, _, _, _}:
      d

def Geo.cc(+g: Geo) -> U32:
  match g:
    case Geo{_, _, _, _, c, _, _, _}:
      c

def Geo.cr(+g: Geo) -> U32:
  match g:
    case Geo{_, _, _, _, _, c, _, _}:
      c

def Geo.top(+g: Geo) -> U32:
  match g:
    case Geo{_, _, _, _, _, _, t, _}:
      t

def Geo.bot(+g: Geo) -> U32:
  match g:
    case Geo{_, _, _, _, _, _, _, b}:
      b

def Geo.region(g: Geo, top: U32, bot: U32) -> Geo:
  match g:
    case Geo{c, r, dc, dr, cc, cr, _, _}:
      Geo{c, r, dc, dr, cc, cr, top, bot}

# the region is the whole screen
def Geo.full(+g: Geo) -> Bool:
  U32.is_eq(Geo.top(g), 0) && U32.is_eq(Geo.bot(g), (Geo.rows(g) - 1 : U32))

# Rows
# ----

def Row.blank(+g: Geo, +bg: U32) -> Tr<Cell>:
  Tr.full(Cell, Geo.dc(g), Cell.blank(bg))

# the first cols cells
def Row.cells(row: Tr<Cell>, +g: Geo) -> List<&2, Cell>:
  List.take(&2, Cell, Tr.list(Cell, row, Nil{}), Vt.n(Geo.cols(g)))

# a row from cells (cut or padded with b)
def Row.of(xs: List<&2, Cell>, +g: Geo, +b: Cell) -> Tr<Cell>:
  Tr.of(Cell, Geo.dc(g), Vt.fit(Cell, Vt.n(Geo.cc(g)), xs, b), b)

def Cells.fill(xs: List<&2, Cell>, +i: U32, +a: U32, +b: U32, +c: Cell) -> List<&2, Cell>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Bool.pick(Cell, U32.is_ge(i, a) && U32.is_lt(i, b), c, h) <> Cells.fill(t, (i + 1 : U32), a, b, c)

# cells a..b-1 set to c
def Row.fill(row: Tr<Cell>, +g: Geo, +a: U32, +b: U32, +c: Cell) -> Tr<Cell>:
  Row.of(Cells.fill(Row.cells(row, g), 0, a, b, c), g, c)

# n copies of c inserted at x; the tail falls off the right
def Row.ins(row: Tr<Cell>, +g: Geo, +x: U32, +n: U32, +c: Cell) -> Tr<Cell>:
  +xs = Row.cells(row, g)
  +k = Vt.n(x)
  Row.of(List.append(&2, Cell, List.take(&2, Cell, xs, k), List.append(&2, Cell, List.replicate(Cell, Vt.n(n), c), List.drop(&2, Cell, xs, k))), g, c)

# n cells deleted at x; c fills in from the right
def Row.del(row: Tr<Cell>, +g: Geo, +x: U32, +n: U32, +c: Cell) -> Tr<Cell>:
  +xs = Row.cells(row, g)
  Row.of(List.append(&2, Cell, List.take(&2, Cell, xs, Vt.n(x)), List.drop(&2, Cell, xs, Vt.n((x + n : U32)))), g, c)

# Screen
# ------

# rows in a ring: logical row y is physical row (base + y) mod rows
type Scr is Data:
  Scr{base: U32, t: Tr<Tr<Cell>>}

def Scr.blank(+g: Geo, +bg: U32) -> Scr:
  Scr{0, Tr.full(Tr<Cell>, Geo.dr(g), Row.blank(g, bg))}

def Scr.phys(+base: U32, +y: U32, +rows: U32) -> U32:
  +p = (base + y : U32)
  Bool.pick(U32, U32.is_ge(p, rows), (p - rows : U32), p)

def Scr.row(+s: Scr, +g: Geo, +y: U32) -> Tr<Cell>:
  match s:
    case Scr{base, t}:
      Tr.at(Tr<Cell>, t, Scr.phys(base, y, Geo.rows(g)), Geo.cr(g))

def Scr.put(s: Scr, +g: Geo, +y: U32, row: Tr<Cell>) -> Scr:
  match s:
    case Scr{+base, t}:
      Scr{base, Tr.put(Tr<Cell>, t, Scr.phys(base, y, Geo.rows(g)), Geo.cr(g), row)}

def Scr.rotl(+k: Nat, +xs: List<&2, Tr<Cell>>) -> List<&2, Tr<Cell>>:
  List.append(&2, Tr<Cell>, List.drop(&2, Tr<Cell>, xs, k), List.take(&2, Tr<Cell>, xs, k))

# the rows top to bottom
def Scr.list(s: Scr, +g: Geo) -> List<&2, Tr<Cell>>:
  match s:
    case Scr{base, t}:
      Scr.rotl(Vt.n(base), List.take(&2, Tr<Cell>, Tr.list(Tr<Cell>, t, Nil{}), Vt.n(Geo.rows(g))))

def Scr.of(xs: List<&2, Tr<Cell>>, +g: Geo, +b: Tr<Cell>) -> Scr:
  Scr{0, Tr.of(Tr<Cell>, Geo.dr(g), Vt.fit(Tr<Cell>, Vt.n(Geo.cr(g)), xs, b), b)}

# rows top..bot shifted by k (up drops the top ones), b filling the gap
def Scr.shift.k(up: Bool, mid: List<&2, Tr<Cell>>, +h: Nat, +k: Nat, +b: Tr<Cell>) -> List<&2, Tr<Cell>>:
  match up:
    case True{}:
      List.append(&2, Tr<Cell>, List.drop(&2, Tr<Cell>, mid, k), List.replicate(Tr<Cell>, k, b))
    case False{}:
      List.append(&2, Tr<Cell>, List.replicate(Tr<Cell>, k, b), List.take(&2, Tr<Cell>, mid, Nat.sub(h, k)))

def Scr.shift(s: Scr, +g: Geo, +top: U32, +bot: U32, +n: U32, up: Bool, +b: Tr<Cell>) -> Scr:
  +xs = Scr.list(s, g)
  +h = Vt.n((bot + 1 - top : U32))
  +k = Vt.n(U32.min(n, (bot + 1 - top : U32)))
  +pre = List.take(&2, Tr<Cell>, xs, Vt.n(top))
  +mid = List.take(&2, Tr<Cell>, List.drop(&2, Tr<Cell>, xs, Vt.n(top)), h)
  +post = List.drop(&2, Tr<Cell>, xs, Vt.n((bot + 1 : U32)))
  Scr.of(List.append(&2, Tr<Cell>, pre, List.append(&2, Tr<Cell>, Scr.shift.k(up, mid, h, k, b), post)), g, b)

# k rows from y down set to b
def Scr.clear(k: Nat, s: Scr, +g: Geo, +y: U32, +b: Tr<Cell>) -> Scr:
  match k:
    case 0n:
      s
    case 1n+p:
      Scr.clear(p, Scr.put(s, g, y, b), g, (y + 1 : U32), b)

# the full-screen scroll: the top row becomes the blank bottom row
def Scr.rot(s: Scr, +g: Geo, b: Tr<Cell>) -> Scr:
  match s:
    case Scr{+base, t}:
      Scr{Scr.phys(base, 1, Geo.rows(g)), Tr.put(Tr<Cell>, t, base, Geo.cr(g), b)}

# Scrollback
# ----------

# a ring of 2048 rows: n kept, head the next slot
type Sb is Data:
  Sb{n: U32, head: U32, t: Tr<Tr<Cell>>}

def Sb.new() -> Sb:
  Sb{0, 0, Tr.full(Tr<Cell>, 11n, TL{Cell.blank(256)})}

def Sb.push(sb: Sb, row: Tr<Cell>) -> Sb:
  match sb:
    case Sb{+n, +head, t}:
      Sb{U32.min((n + 1 : U32), 2048), ((head + 1 : U32) .&. 2047 : U32), Tr.put(Tr<Cell>, t, head, 2048, row)}

def Sb.keep(on: Bool, sb: Sb, row: Tr<Cell>) -> Sb:
  match on:
    case True{}:
      Sb.push(sb, row)
    case False{}:
      sb

def Sb.pushes(xs: List<&2, Tr<Cell>>, sb: Sb) -> Sb:
  match xs:
    case Nil{}:
      sb
    case r <> t:
      Sb.pushes(t, Sb.push(sb, r))

def Sb.len(+sb: Sb) -> U32:
  match sb:
    case Sb{n, _, _}:
      n

def Sb.row(+sb: Sb, +at: U32) -> Tr<Cell>:
  match sb:
    case Sb{_, _, t}:
      Tr.at(Tr<Cell>, t, (at .&. 2047 : U32), 2048)

# k rows from slot at onward (slots wrap around the ring)
def Sb.rows(k: Nat, +sb: Sb, +at: U32) -> List<&2, Tr<Cell>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Sb.row(sb, at) <> Sb.rows(p, sb, (at + 1 : U32))

# Cursor, modes, state
# --------------------

# position, a wrap pending at the right margin, the pen, and whether G0 is
# the DEC line-drawing set
type Cur is Data:
  Cur{x: U32, y: U32, wrap: Bool, pen: Pen, dec: Bool}

def Cur.new() -> Cur:
  Cur{0, 0, False{}, Pen.new(), False{}}

def Cur.x(+c: Cur) -> U32:
  match c:
    case Cur{x, _, _, _, _}:
      x

def Cur.y(+c: Cur) -> U32:
  match c:
    case Cur{_, y, _, _, _}:
      y

def Cur.wrap(+c: Cur) -> Bool:
  match c:
    case Cur{_, _, w, _, _}:
      w

def Cur.pen(+c: Cur) -> Pen:
  match c:
    case Cur{_, _, _, p, _}:
      p

def Cur.dec(+c: Cur) -> Bool:
  match c:
    case Cur{_, _, _, _, d}:
      d

def Cur.at(c: Cur, x: U32, y: U32) -> Cur:
  match c:
    case Cur{_, _, _, p, d}:
      Cur{x, y, False{}, p, d}

def Cur.with_pen(c: Cur, p: Pen) -> Cur:
  match c:
    case Cur{x, y, w, _, d}:
      Cur{x, y, w, p, d}

def Cur.with_dec(c: Cur, d: Bool) -> Cur:
  match c:
    case Cur{x, y, w, p, _}:
      Cur{x, y, w, p, d}

# inside the screen
def Cur.clamp(c: Cur, +g: Geo) -> Cur:
  match c:
    case Cur{x, y, w, p, d}:
      Cur{U32.min(x, (Geo.cols(g) - 1 : U32)), U32.min(y, (Geo.rows(g) - 1 : U32)), w, p, d}

# cursor shown, autowrap, application cursor keys, bracketed paste, origin
# mode, insert mode
type Md is Data:
  Md{show: Bool, awm: Bool, appk: Bool, paste: Bool, org: Bool, ins: Bool}

def Md.new() -> Md:
  Md{True{}, True{}, False{}, False{}, False{}, False{}}

def Md.show(+m: Md) -> Bool:
  match m:
    case Md{s, _, _, _, _, _}:
      s

def Md.awm(+m: Md) -> Bool:
  match m:
    case Md{_, a, _, _, _, _}:
      a

def Md.appk(+m: Md) -> Bool:
  match m:
    case Md{_, _, a, _, _, _}:
      a

def Md.paste(+m: Md) -> Bool:
  match m:
    case Md{_, _, _, p, _, _}:
      p

def Md.org(+m: Md) -> Bool:
  match m:
    case Md{_, _, _, _, o, _}:
      o

def Md.ins(+m: Md) -> Bool:
  match m:
    case Md{_, _, _, _, _, i}:
      i

# mode k (0 show, 1 awm, 2 appk, 3 paste, 4 org, 5 ins) set to on
def Md.set(m: Md, k: Nat, on: Bool) -> Md:
  match m k:
    case Md{_, a, b, c, d, e} 0n:
      Md{on, a, b, c, d, e}
    case Md{s, _, b, c, d, e} 1n:
      Md{s, on, b, c, d, e}
    case Md{s, a, _, c, d, e} 2n:
      Md{s, a, on, c, d, e}
    case Md{s, a, b, _, d, e} 3n:
      Md{s, a, b, on, d, e}
    case Md{s, a, b, c, _, e} 4n:
      Md{s, a, b, c, on, e}
    case Md{s, a, b, c, d, _} 5n:
      Md{s, a, b, c, d, on}
    case m _:
      m

# the main screen while the alternate one is shown
type Alt is Data:
  NoAlt{}
  InAlt{scr: Scr}

def Alt.main(+a: Alt) -> Bool:
  match a:
    case NoAlt{}:
      True{}
    case InAlt{_}:
      False{}

# the saved cursor (ESC 7, CSI s, 1049), the window title, and the replies
# owed to the host (newest first)
type Ex is Data:
  Ex{saved: Cur, title: String, out: List<&2, U32>}

type Tm is Data:
  Tm{g: Geo, scr: Scr, cur: Cur, md: Md, alt: Alt, sb: Sb, ex: Ex}

def Tm.new(+g: Geo, sb: Sb) -> Tm:
  Tm{g, Scr.blank(g, 256), Cur.new(), Md.new(), NoAlt{}, sb, Ex{Cur.new(), "", Nil{}}}

def Tm.g(+t: Tm) -> Geo:
  match t:
    case Tm{g, _, _, _, _, _, _}:
      g

def Tm.scr(+t: Tm) -> Scr:
  match t:
    case Tm{_, s, _, _, _, _, _}:
      s

def Tm.cur(+t: Tm) -> Cur:
  match t:
    case Tm{_, _, c, _, _, _, _}:
      c

def Tm.md(+t: Tm) -> Md:
  match t:
    case Tm{_, _, _, m, _, _, _}:
      m

def Tm.alt(+t: Tm) -> Alt:
  match t:
    case Tm{_, _, _, _, a, _, _}:
      a

def Tm.sb(+t: Tm) -> Sb:
  match t:
    case Tm{_, _, _, _, _, s, _}:
      s

def Tm.ex(+t: Tm) -> Ex:
  match t:
    case Tm{_, _, _, _, _, _, e}:
      e

def Tm.set_g(t: Tm, g: Geo) -> Tm:
  match t:
    case Tm{_, s, c, m, a, b, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_scr(t: Tm, s: Scr) -> Tm:
  match t:
    case Tm{g, _, c, m, a, b, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_cur(t: Tm, c: Cur) -> Tm:
  match t:
    case Tm{g, s, _, m, a, b, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_md(t: Tm, m: Md) -> Tm:
  match t:
    case Tm{g, s, c, _, a, b, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_alt(t: Tm, a: Alt) -> Tm:
  match t:
    case Tm{g, s, c, m, _, b, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_sb(t: Tm, b: Sb) -> Tm:
  match t:
    case Tm{g, s, c, m, a, _, e}:
      Tm{g, s, c, m, a, b, e}

def Tm.set_ex(t: Tm, e: Ex) -> Tm:
  match t:
    case Tm{g, s, c, m, a, b, _}:
      Tm{g, s, c, m, a, b, e}

def Tm.x(+t: Tm) -> U32:
  Cur.x(Tm.cur(t))

def Tm.y(+t: Tm) -> U32:
  Cur.y(Tm.cur(t))

def Tm.cols(+t: Tm) -> U32:
  Geo.cols(Tm.g(t))

def Tm.rows(+t: Tm) -> U32:
  Geo.rows(Tm.g(t))

def Tm.bg(+t: Tm) -> U32:
  Pen.bg(Cur.pen(Tm.cur(t)))

# an erased cell and row in the current background
def Tm.bcell(+t: Tm) -> Cell:
  Cell.blank(Tm.bg(t))

def Tm.brow(+t: Tm) -> Tr<Cell>:
  Row.blank(Tm.g(t), Tm.bg(t))

def Tm.row(+t: Tm) -> Tr<Cell>:
  Scr.row(Tm.scr(t), Tm.g(t), Tm.y(t))

# the cursor's row replaced
def Tm.put_row(+t: Tm, row: Tr<Cell>) -> Tm:
  Tm.set_scr(t, Scr.put(Tm.scr(t), Tm.g(t), Tm.y(t), row))

def Tm.emit(t: Tm, bs: List<&2, U32>) -> Tm:
  match t:
    case Tm{g, s, c, m, a, b, Ex{sv, ti, out}}:
      Tm{g, s, c, m, a, b, Ex{sv, ti, List.append(&2, U32, List.reverse(&2, U32, bs), out)}}

# Cursor motion
# -------------

# to (x, y), kept on the screen; clears a pending wrap
def Tm.goto(+t: Tm, +x: U32, +y: U32) -> Tm:
  Tm.set_cur(t, Cur.at(Tm.cur(t), U32.min(x, (Tm.cols(t) - 1 : U32)), U32.min(y, (Tm.rows(t) - 1 : U32))))

def Tm.cr(+t: Tm) -> Tm:
  Tm.goto(t, 0, Tm.y(t))

def Tm.bs(+t: Tm) -> Tm:
  Tm.goto(t, Vt.sub0(Tm.x(t), 1), Tm.y(t))

# n tab stops forward (every 8 columns)
def Tm.tab(+t: Tm, +n: U32) -> Tm:
  Tm.goto(t, U32.shln((U32.shrn(Tm.x(t), 3n) + n : U32), 3n), Tm.y(t))

def Tm.btab(+t: Tm, +n: U32) -> Tm:
  Tm.goto(t, U32.shln(Vt.sub0(U32.shrn((Tm.x(t) + 7 : U32), 3n), n), 3n), Tm.y(t))

# up n, stopping at the region's top when inside it
def Tm.up(+t: Tm, +n: U32) -> Tm:
  +y = Tm.y(t)
  +top = Geo.top(Tm.g(t))
  Tm.goto(t, Tm.x(t), U32.max(Vt.sub0(y, n), Bool.pick(U32, U32.is_ge(y, top), top, 0)))

def Tm.down(+t: Tm, +n: U32) -> Tm:
  +y = Tm.y(t)
  +bot = Geo.bot(Tm.g(t))
  Tm.goto(t, Tm.x(t), U32.min((y + n : U32), Bool.pick(U32, U32.is_le(y, bot), bot, (Tm.rows(t) - 1 : U32))))

# row r counted from the region's top in origin mode
def Tm.orow(+t: Tm, +r: U32) -> U32:
  +g = Tm.g(t)
  Bool.pick(U32, Md.org(Tm.md(t)), U32.min((r + Geo.top(g) : U32), Geo.bot(g)), r)

def Tm.home(+t: Tm) -> Tm:
  Tm.goto(t, 0, Tm.orow(t, 0))

# Scrolling
# ---------

# the full-screen scroll by one: the top row goes to the scrollback (on the
# main screen) and a blank row comes in at the bottom
def Tm.rot1(t: Tm) -> Tm:
  match t:
    case Tm{+g, +s, +c, m, +a, b, e}:
      Tm{g, Scr.rot(s, g, Row.blank(g, Pen.bg(Cur.pen(c)))), c, m, a, Sb.keep(Alt.main(a), b, Scr.row(s, g, 0)), e}

def Tm.rot(k: Nat, t: Tm) -> Tm:
  match k:
    case 0n:
      t
    case 1n+p:
      Tm.rot(p, Tm.rot1(t))

def Sb.keeps(on: Bool, xs: List<&2, Tr<Cell>>, sb: Sb) -> Sb:
  match on:
    case True{}:
      Sb.pushes(xs, sb)
    case False{}:
      sb

# the region scrolled up by n inside a partial region; rows leaving a region
# that starts at the top go to the scrollback on the main screen
def Tm.sup.part(t: Tm, +n: U32) -> Tm:
  match t:
    case Tm{+g, +s, +c, m, +a, b, e}:
      +top = Geo.top(g)
      +bot = Geo.bot(g)
      +k = Vt.n(U32.min(n, (bot + 1 - top : U32)))
      +on = U32.is_eq(top, 0) && Alt.main(a)
      +gone = List.take(&2, Tr<Cell>, List.drop(&2, Tr<Cell>, Scr.list(s, g), Vt.n(top)), k)
      Tm{g, Scr.shift(s, g, top, bot, n, True{}, Row.blank(g, Pen.bg(Cur.pen(c)))), c, m, a, Sb.keeps(on, gone, b), e}

def Tm.sup.k(full: Bool, +t: Tm, +n: U32) -> Tm:
  match full:
    case True{}:
      Tm.rot(Vt.n(U32.min(n, Tm.rows(t))), t)
    case False{}:
      Tm.sup.part(t, n)

def Tm.scroll_up(+t: Tm, +n: U32) -> Tm:
  Tm.sup.k(Geo.full(Tm.g(t)), t, n)

def Tm.scroll_down(+t: Tm, +n: U32) -> Tm:
  +g = Tm.g(t)
  Tm.set_scr(t, Scr.shift(Tm.scr(t), g, Geo.top(g), Geo.bot(g), n, False{}, Tm.brow(t)))

def Tm.nl.k(at_bot: Bool, room: Bool, +t: Tm) -> Tm:
  match at_bot room:
    case True{} _:
      Tm.scroll_up(t, 1)
    case False{} True{}:
      Tm.goto(t, Tm.x(t), (Tm.y(t) + 1 : U32))
    case False{} False{}:
      t

# line feed (IND): down one, scrolling at the region's bottom
def Tm.nl(+t: Tm) -> Tm:
  +y = Tm.y(t)
  Tm.nl.k(U32.is_eq(y, Geo.bot(Tm.g(t))), U32.is_lt((y + 1 : U32), Tm.rows(t)), t)

def Tm.ri.k(at_top: Bool, room: Bool, +t: Tm) -> Tm:
  match at_top room:
    case True{} _:
      Tm.scroll_down(t, 1)
    case False{} True{}:
      Tm.goto(t, Tm.x(t), (Tm.y(t) - 1 : U32))
    case False{} False{}:
      t

# reverse index: up one, scrolling down at the region's top
def Tm.ri(+t: Tm) -> Tm:
  +y = Tm.y(t)
  Tm.ri.k(U32.is_eq(y, Geo.top(Tm.g(t))), U32.is_gt(y, 0), t)

# insert (up False) or delete (up True) n lines at the cursor, inside the region
def Tm.lines.k(inside: Bool, +t: Tm, +n: U32, up: Bool) -> Tm:
  match inside:
    case True{}:
      +g = Tm.g(t)
      Tm.goto(Tm.set_scr(t, Scr.shift(Tm.scr(t), g, Tm.y(t), Geo.bot(g), n, up, Tm.brow(t))), 0, Tm.y(t))
    case False{}:
      t

def Tm.lines(+t: Tm, +n: U32, up: Bool) -> Tm:
  +y = Tm.y(t)
  +g = Tm.g(t)
  Tm.lines.k(U32.is_ge(y, Geo.top(g)) && U32.is_le(y, Geo.bot(g)), t, n, up)

# Erasing
# -------

# cells a..b-1 of the cursor's row erased
def Tm.fill(+t: Tm, +a: U32, +b: U32) -> Tm:
  Tm.put_row(t, Row.fill(Tm.row(t), Tm.g(t), a, b, Tm.bcell(t)))

# EL: 0 to the end, 1 from the start, 2 the whole line
def Tm.el(+t: Tm, +mode: U32) -> Tm:
  Tm.fill(t, Bool.pick(U32, U32.is_eq(mode, 0), Tm.x(t), 0), Bool.pick(U32, U32.is_eq(mode, 1), (Tm.x(t) + 1 : U32), Tm.cols(t)))

def Tm.clear_rows(+t: Tm, k: U32, +y: U32) -> Tm:
  Tm.set_scr(t, Scr.clear(Vt.n(k), Tm.scr(t), Tm.g(t), y, Tm.brow(t)))

# ED: 0 to the end, 1 from the start, 2 the screen, 3 the scrollback
def Tm.ed(m: Nat, +t: Tm) -> Tm:
  match m:
    case 0n:
      Tm.clear_rows(Tm.el(t, 0), (Tm.rows(t) - 1 - Tm.y(t) : U32), (Tm.y(t) + 1 : U32))
    case 1n:
      Tm.clear_rows(Tm.el(t, 1), Tm.y(t), 0)
    case 2n:
      Tm.set_scr(t, Scr.blank(Tm.g(t), Tm.bg(t)))
    case 3n:
      Tm.set_sb(t, Sb.new())
    case _:
      t

# ICH, DCH, ECH
def Tm.ich(+t: Tm, +n: U32) -> Tm:
  Tm.put_row(t, Row.ins(Tm.row(t), Tm.g(t), Tm.x(t), U32.min(n, Tm.cols(t)), Tm.bcell(t)))

def Tm.dch(+t: Tm, +n: U32) -> Tm:
  Tm.put_row(t, Row.del(Tm.row(t), Tm.g(t), Tm.x(t), U32.min(n, Tm.cols(t)), Tm.bcell(t)))

def Tm.ech(+t: Tm, +n: U32) -> Tm:
  Tm.fill(t, Tm.x(t), U32.min((Tm.x(t) + n : U32), Tm.cols(t)))

# Printing
# --------

def Vt.in(+cp: U32, +a: U32, +b: U32) -> Bool:
  U32.is_ge(cp, a) && U32.is_le(cp, b)

# combining marks and zero-width characters
def Vt.zero(+cp: U32) -> Bool:
  Vt.in(cp, 768, 879) || Vt.in(cp, 8203, 8207) || Vt.in(cp, 8400, 8447) || Vt.in(cp, 65024, 65039) || Vt.in(cp, 65056, 65071) || Vt.in(cp, 6832, 6911) || Vt.in(cp, 7616, 7679)

# East Asian wide characters and emoji
def Vt.wide(+cp: U32) -> Bool:
  Vt.in(cp, 4352, 4447) || Vt.in(cp, 11904, 12350) || Vt.in(cp, 12353, 13311) || Vt.in(cp, 13312, 19903) || Vt.in(cp, 19968, 40959) || Vt.in(cp, 40960, 42191) || Vt.in(cp, 44032, 55203) || Vt.in(cp, 63744, 64255) || Vt.in(cp, 65072, 65103) || Vt.in(cp, 65280, 65376) || Vt.in(cp, 65504, 65510) || Vt.in(cp, 127744, 128591) || Vt.in(cp, 128640, 128767) || Vt.in(cp, 129280, 129535) || Vt.in(cp, 131072, 262141)

def Vt.width.w(z: Bool, w: Bool) -> U32:
  match z w:
    case True{} _:
      0
    case False{} True{}:
      2
    case False{} False{}:
      1

def Vt.width.k(small: Bool, +cp: U32) -> U32:
  match small:
    case True{}:
      1
    case False{}:
      Vt.width.w(Vt.zero(cp), Vt.wide(cp))

# the cells a code point takes: 0 (combining), 1, or 2 (wide)
def Vt.width(+cp: U32) -> U32:
  Vt.width.k(U32.is_lt(cp, 768), cp)

# the DEC special graphics set (ESC ( 0), used for line drawing
def Vt.gfx(k: Nat, +cp: U32) -> U32:
  match k:
    case 95n:
      32
    case 96n:
      9670
    case 97n:
      9618
    case 102n:
      176
    case 103n:
      177
    case 106n:
      9496
    case 107n:
      9488
    case 108n:
      9484
    case 109n:
      9492
    case 110n:
      9532
    case 111n:
      9146
    case 112n:
      9147
    case 113n:
      9472
    case 114n:
      9148
    case 115n:
      9149
    case 116n:
      9500
    case 117n:
      9508
    case 118n:
      9524
    case 119n:
      9516
    case 120n:
      9474
    case 121n:
      8804
    case 122n:
      8805
    case 123n:
      960
    case 124n:
      8800
    case 125n:
      163
    case 126n:
      183
    case _:
      cp

def Vt.dmap.k(hit: Bool, +cp: U32) -> U32:
  match hit:
    case True{}:
      Vt.gfx(Vt.n(cp), cp)
    case False{}:
      cp

def Vt.dmap(dec: Bool, +cp: U32) -> U32:
  match dec:
    case True{}:
      Vt.dmap.k(Vt.in(cp, 95, 126), cp)
    case False{}:
      cp

def Cur.adv.k(over: Bool, awm: Bool, +nx: U32, +cols: U32, y: U32, p: Pen, d: Bool) -> Cur:
  match over:
    case True{}:
      Cur{(cols - 1 : U32), y, awm, p, d}
    case False{}:
      Cur{nx, y, False{}, p, d}

# the cursor after writing w cells
def Cur.adv(c: Cur, +cols: U32, awm: Bool, +w: U32) -> Cur:
  match c:
    case Cur{+x, y, _, p, d}:
      Cur.adv.k(U32.is_ge((x + w : U32), cols), awm, (x + w : U32), cols, y, p, d)

def Row.shift_in(on: Bool, row: Tr<Cell>, +g: Geo, +x: U32, +w: U32, +c: Cell) -> Tr<Cell>:
  match on:
    case True{}:
      Row.ins(row, g, x, w, c)
    case False{}:
      row

def Row.cont(on: Bool, row: Tr<Cell>, +x: U32, +cap: U32, c: Cell) -> Tr<Cell>:
  match on:
    case True{}:
      Tr.put(Cell, row, x, cap, c)
    case False{}:
      row

# cp written at the cursor (w cells), the cursor advanced
def Tm.put(t: Tm, +cp: U32, +w: U32) -> Tm:
  match t:
    case Tm{+g, +s, +c, +m, a, b, e}:
      +x = Cur.x(c)
      +p = Cur.pen(c)
      +cc = Geo.cc(g)
      +r1 = Row.shift_in(Md.ins(m), Scr.row(s, g, Cur.y(c)), g, x, w, Cell.blank(Pen.bg(p)))
      +r2 = Tr.put(Cell, r1, x, cc, Cell.of(cp, p))
      +r3 = Row.cont(U32.is_eq(w, 2) && U32.is_lt((x + 1 : U32), Geo.cols(g)), r2, (x + 1 : U32), cc, Cell.of(0, p))
      Tm{g, Scr.put(s, g, Cur.y(c), r3), Cur.adv(c, Geo.cols(g), Md.awm(m), w), m, a, b, e}

def Tm.pre.k(wrap: Bool, +t: Tm) -> Tm:
  match wrap:
    case True{}:
      Tm.nl(Tm.cr(t))
    case False{}:
      t

# a pending wrap (or a wide character that no longer fits) moves to the
# next line first
def Tm.pre(+t: Tm, +w: U32) -> Tm:
  +c = Tm.cur(t)
  Tm.pre.k(Md.awm(Tm.md(t)) && (Cur.wrap(c) || (U32.is_eq(w, 2) && U32.is_ge((Cur.x(c) + 1 : U32), Tm.cols(t)))), t)

def Tm.print.k(zero: Bool, +t: Tm, +cp: U32, +w: U32) -> Tm:
  match zero:
    case True{}:
      t
    case False{}:
      Tm.put(Tm.pre(t, w), cp, w)

def Tm.print.w(+t: Tm, +cp: U32) -> Tm:
  +w = Vt.width(cp)
  Tm.print.k(U32.is_eq(w, 0), t, cp, w)

def Tm.print(+t: Tm, +cp: U32) -> Tm:
  Tm.print.w(t, Vt.dmap(Cur.dec(Tm.cur(t)), cp))

# SGR
# ---

def Pen.or(p: Pen, +bits: U32) -> Pen:
  match p:
    case Pen{f, b, a}:
      Pen{f, b, (a .|. bits : U32)}

def Pen.clr(p: Pen, +bits: U32) -> Pen:
  match p:
    case Pen{f, b, a}:
      Pen{f, b, (a .&. U32.not(bits) : U32)}

# the foreground (fg True) or background set to c
def Pen.color(fg: Bool, c: U32, p: Pen) -> Pen:
  match fg p:
    case True{} Pen{_, b, a}:
      Pen{c, b, a}
    case False{} Pen{f, _, a}:
      Pen{f, c, a}

def Pen.range.k(a: Bool, b: Bool, c: Bool, d: Bool, +n: U32, p: Pen) -> Pen:
  match a b c d:
    case True{} _ _ _:
      Pen.color(True{}, (n - 30 : U32), p)
    case False{} True{} _ _:
      Pen.color(False{}, (n - 40 : U32), p)
    case False{} False{} True{} _:
      Pen.color(True{}, (n - 82 : U32), p)
    case False{} False{} False{} True{}:
      Pen.color(False{}, (n - 92 : U32), p)
    case False{} False{} False{} False{}:
      p

# 30-37, 40-47, 90-97, 100-107
def Pen.range(+n: U32, p: Pen) -> Pen:
  Pen.range.k(Vt.in(n, 30, 37), Vt.in(n, 40, 47), Vt.in(n, 90, 97), Vt.in(n, 100, 107), n, p)

# SGR reads its parameters as a little machine: m 0 plain, 1 after 38/48,
# 2 expecting a palette index, 3/4/5 expecting red/green/blue
type Sg is Data:
  Sg{m: U32, fg: Bool, r: U32, g: U32, pen: Pen}

def Sg.plain(k: Nat, +n: U32, p: Pen) -> Sg:
  match k:
    case 0n:
      Sg{0, True{}, 0, 0, Pen.new()}
    case 1n:
      Sg{0, True{}, 0, 0, Pen.or(p, 1)}
    case 2n:
      Sg{0, True{}, 0, 0, Pen.or(p, 8)}
    case 4n:
      Sg{0, True{}, 0, 0, Pen.or(p, 2)}
    case 7n:
      Sg{0, True{}, 0, 0, Pen.or(p, 4)}
    case 8n:
      Sg{0, True{}, 0, 0, Pen.or(p, 16)}
    case 21n:
      Sg{0, True{}, 0, 0, Pen.or(p, 2)}
    case 22n:
      Sg{0, True{}, 0, 0, Pen.clr(p, 9)}
    case 24n:
      Sg{0, True{}, 0, 0, Pen.clr(p, 2)}
    case 27n:
      Sg{0, True{}, 0, 0, Pen.clr(p, 4)}
    case 28n:
      Sg{0, True{}, 0, 0, Pen.clr(p, 16)}
    case 38n:
      Sg{1, True{}, 0, 0, p}
    case 39n:
      Sg{0, True{}, 0, 0, Pen.color(True{}, 256, p)}
    case 48n:
      Sg{1, False{}, 0, 0, p}
    case 49n:
      Sg{0, True{}, 0, 0, Pen.color(False{}, 256, p)}
    case _:
      Sg{0, True{}, 0, 0, Pen.range(n, p)}

def Sg.k(m: Nat, +fg: Bool, +r: U32, +g: U32, p: Pen, +n: U32) -> Sg:
  match m:
    case 0n:
      Sg.plain(Vt.n(n), n, p)
    case 1n:
      Sg{Bool.pick(U32, U32.is_eq(n, 5), 2, Bool.pick(U32, U32.is_eq(n, 2), 3, 0)), fg, 0, 0, p}
    case 2n:
      Sg{0, fg, 0, 0, Pen.color(fg, (n .&. 255 : U32), p)}
    case 3n:
      Sg{4, fg, n, 0, p}
    case 4n:
      Sg{5, fg, r, n, p}
    case _:
      Sg{0, fg, 0, 0, Pen.color(fg, (16777216 .|. U32.shln((r .&. 255 : U32), 16n) .|. U32.shln((g .&. 255 : U32), 8n) .|. (n .&. 255 : U32) : U32), p)}

def Sg.step(s: Sg, +n: U32) -> Sg:
  match s:
    case Sg{m, fg, r, g, p}:
      Sg.k(Vt.n(m), fg, r, g, p, n)

def Sg.go(ps: List<&2, U32>, s: Sg) -> Sg:
  match ps:
    case Nil{}:
      s
    case n <> t:
      Sg.go(t, Sg.step(s, n))

def Sg.pen(s: Sg) -> Pen:
  match s:
    case Sg{_, _, _, _, p}:
      p

def Tm.sgr(+t: Tm, ps: List<&2, U32>) -> Tm:
  +c = Tm.cur(t)
  Tm.set_cur(t, Cur.with_pen(c, Sg.pen(Sg.go(ps, Sg{0, True{}, 0, 0, Cur.pen(c)}))))

# Modes, screens, replies
# -----------------------

def Tm.save(+t: Tm) -> Tm:
  match t:
    case Tm{g, s, +c, m, a, b, Ex{_, ti, out}}:
      Tm{g, s, c, m, a, b, Ex{c, ti, out}}

def Tm.restore(+t: Tm) -> Tm:
  match t:
    case Tm{+g, s, _, m, a, b, Ex{+sv, ti, out}}:
      Tm{g, s, Cur.clamp(sv, g), m, a, b, Ex{sv, ti, out}}

# to the alternate screen (blank); the main one is kept aside
def Tm.alt_on.k(a: Alt, +t: Tm) -> Tm:
  match a:
    case NoAlt{}:
      Tm.set_alt(Tm.set_scr(t, Scr.blank(Tm.g(t), 256)), InAlt{Tm.scr(t)})
    case InAlt{_}:
      t

def Tm.alt_on(+t: Tm) -> Tm:
  Tm.alt_on.k(Tm.alt(t), t)

def Tm.alt_off.k(a: Alt, +t: Tm) -> Tm:
  match a:
    case NoAlt{}:
      t
    case InAlt{s}:
      Tm.set_alt(Tm.set_scr(t, s), NoAlt{})

def Tm.alt_off(+t: Tm) -> Tm:
  Tm.alt_off.k(Tm.alt(t), t)

def Tm.set_mode(+t: Tm, k: Nat, on: Bool) -> Tm:
  Tm.set_md(t, Md.set(Tm.md(t), k, on))

def Tm.origin(+t: Tm, on: Bool) -> Tm:
  Tm.home(Tm.set_mode(t, 4n, on))

# 1049: save the cursor and switch; back: switch and restore
def Tm.m1049(on: Bool, +t: Tm) -> Tm:
  match on:
    case True{}:
      Tm.alt_on(Tm.save(t))
    case False{}:
      Tm.restore(Tm.alt_off(t))

def Tm.m47(on: Bool, +t: Tm) -> Tm:
  match on:
    case True{}:
      Tm.alt_on(t)
    case False{}:
      Tm.alt_off(t)

def Tm.m1048(on: Bool, +t: Tm) -> Tm:
  match on:
    case True{}:
      Tm.save(t)
    case False{}:
      Tm.restore(t)

def Tm.dec.small(k: Nat, +t: Tm, on: Bool) -> Tm:
  match k:
    case 1n:
      Tm.set_mode(t, 2n, on)
    case 6n:
      Tm.origin(t, on)
    case 7n:
      Tm.set_mode(t, 1n, on)
    case 25n:
      Tm.set_mode(t, 0n, on)
    case 47n:
      Tm.m47(on, t)
    case _:
      t

def Tm.dec.big(a: Bool, b: Bool, c: Bool, d: Bool, +t: Tm, on: Bool) -> Tm:
  match a b c d:
    case True{} _ _ _:
      Tm.m1049(on, t)
    case False{} True{} _ _:
      Tm.m47(on, t)
    case False{} False{} True{} _:
      Tm.m1048(on, t)
    case False{} False{} False{} True{}:
      Tm.set_mode(t, 3n, on)
    case False{} False{} False{} False{}:
      t

def Tm.dec1.k(small: Bool, +n: U32, +t: Tm, on: Bool) -> Tm:
  match small:
    case True{}:
      Tm.dec.small(Vt.n(n), t, on)
    case False{}:
      Tm.dec.big(U32.is_eq(n, 1049), U32.is_eq(n, 1047), U32.is_eq(n, 1048), U32.is_eq(n, 2004), t, on)

# one DEC private mode (CSI ? n h / l)
def Tm.dec1(+n: U32, +t: Tm, on: Bool) -> Tm:
  Tm.dec1.k(U32.is_lt(n, 100), n, t, on)

def Tm.decs(ps: List<&2, U32>, t: Tm, +on: Bool) -> Tm:
  match ps:
    case Nil{}:
      t
    case n <> r:
      Tm.decs(r, Tm.dec1(n, t, on), on)

def Tm.ansi1(hit: Bool, +t: Tm, on: Bool) -> Tm:
  match hit:
    case True{}:
      Tm.set_mode(t, 5n, on)
    case False{}:
      t

# ANSI modes (CSI n h / l): 4 insert
def Tm.ansi(ps: List<&2, U32>, t: Tm, +on: Bool) -> Tm:
  match ps:
    case Nil{}:
      t
    case n <> r:
      Tm.ansi(r, Tm.ansi1(U32.is_eq(n, 4), t, on), on)

def Vt.esc_seq(s: String) -> List<&2, U32>:
  27 <> U.Utf8.encode(s)

# DSR: 5 status, 6 cursor position
def Tm.dsr(k: Nat, +t: Tm) -> Tm:
  match k:
    case 5n:
      Tm.emit(t, Vt.esc_seq("[0n"))
    case 6n:
      Tm.emit(t, Vt.esc_seq("[" ++ U32.show((Tm.y(t) + 1 : U32)) ++ ";" ++ U32.show((Tm.x(t) + 1 : U32)) ++ "R"))
    case _:
      t

def Tm.stbm.k(ok: Bool, +t: Tm, top: U32, bot: U32) -> Tm:
  match ok:
    case True{}:
      Tm.home(Tm.set_g(t, Geo.region(Tm.g(t), top, bot)))
    case False{}:
      t

def Vt.arg.k(+v: U32, +d: U32) -> U32:
  Bool.pick(U32, U32.is_eq(v, 0), d, v)

# the n-th parameter; 0 or missing gives d
def Vt.arg(+ps: List<&2, U32>, i: Nat, +d: U32) -> U32:
  Vt.arg.k(Maybe.default(&2, U32, List.get(&2, U32, ps, i), 0), d)

def Vt.arg0(+ps: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ps, 0n), 0)

# DECSTBM: the scroll region (1-based, inclusive), then home
def Tm.stbm(+t: Tm, +ps: List<&2, U32>) -> Tm:
  +top = (Vt.arg(ps, 0n, 1) - 1 : U32)
  +bot = (U32.min(Vt.arg(ps, 1n, Tm.rows(t)), Tm.rows(t)) - 1 : U32)
  Tm.stbm.k(U32.is_lt(top, bot), t, top, bot)

# CSI with no private marker, by final byte
def Tm.csi0(f: Nat, +t: Tm, +ps: List<&2, U32>, +n: U32) -> Tm:
  match f:
    case 64n:
      Tm.ich(t, n)
    case 65n:
      Tm.up(t, n)
    case 66n:
      Tm.down(t, n)
    case 67n:
      Tm.goto(t, (Tm.x(t) + n : U32), Tm.y(t))
    case 68n:
      Tm.goto(t, Vt.sub0(Tm.x(t), n), Tm.y(t))
    case 69n:
      Tm.cr(Tm.down(t, n))
    case 70n:
      Tm.cr(Tm.up(t, n))
    case 71n:
      Tm.goto(t, (n - 1 : U32), Tm.y(t))
    case 72n:
      Tm.goto(t, (Vt.arg(ps, 1n, 1) - 1 : U32), Tm.orow(t, (n - 1 : U32)))
    case 73n:
      Tm.tab(t, n)
    case 74n:
      Tm.ed(Vt.n(Vt.arg0(ps)), t)
    case 75n:
      Tm.el(t, Vt.arg0(ps))
    case 76n:
      Tm.lines(t, n, False{})
    case 77n:
      Tm.lines(t, n, True{})
    case 80n:
      Tm.dch(t, n)
    case 83n:
      Tm.scroll_up(t, n)
    case 84n:
      Tm.scroll_down(t, n)
    case 88n:
      Tm.ech(t, n)
    case 90n:
      Tm.btab(t, n)
    case 96n:
      Tm.goto(t, (n - 1 : U32), Tm.y(t))
    case 97n:
      Tm.goto(t, (Tm.x(t) + n : U32), Tm.y(t))
    case 99n:
      Tm.emit(t, Vt.esc_seq("[?1;2c"))
    case 100n:
      Tm.goto(t, Tm.x(t), Tm.orow(t, (n - 1 : U32)))
    case 101n:
      Tm.goto(t, Tm.x(t), (Tm.y(t) + n : U32))
    case 102n:
      Tm.goto(t, (Vt.arg(ps, 1n, 1) - 1 : U32), Tm.orow(t, (n - 1 : U32)))
    case 104n:
      Tm.ansi(ps, t, True{})
    case 108n:
      Tm.ansi(ps, t, False{})
    case 109n:
      Tm.sgr(t, ps)
    case 110n:
      Tm.dsr(Vt.n(Vt.arg0(ps)), t)
    case 114n:
      Tm.stbm(t, ps)
    case 115n:
      Tm.save(t)
    case 117n:
      Tm.restore(t)
    case _:
      t

# CSI ? ...
def Tm.csiq(f: Nat, +t: Tm, +ps: List<&2, U32>) -> Tm:
  match f:
    case 74n:
      Tm.ed(Vt.n(Vt.arg0(ps)), t)
    case 75n:
      Tm.el(t, Vt.arg0(ps))
    case 104n:
      Tm.decs(ps, t, True{})
    case 108n:
      Tm.decs(ps, t, False{})
    case _:
      t

# CSI > c: secondary device attributes
def Tm.csigt(f: Nat, +t: Tm) -> Tm:
  match f:
    case 99n:
      Tm.emit(t, Vt.esc_seq("[>1;10;0c"))
    case _:
      t

def Tm.csi.k(plain: Bool, pv: Nat, +t: Tm, +ps: List<&2, U32>, +fin: U32) -> Tm:
  match plain pv:
    case True{} 0n:
      Tm.csi0(Vt.n(fin), t, ps, Vt.arg(ps, 0n, 1))
    case True{} 63n:
      Tm.csiq(Vt.n(fin), t, ps)
    case True{} 62n:
      Tm.csigt(Vt.n(fin), t)
    case _ _:
      t

def Tm.csi(+t: Tm, +pv: U32, +ps: List<&2, U32>, +inter: U32, +fin: U32) -> Tm:
  Tm.csi.k(U32.is_eq(inter, 0), Vt.n(pv), t, ps, fin)

# full reset (RIS): the scrollback stays
def Tm.reset(+t: Tm) -> Tm:
  +g = Tm.g(t)
  Tm.new(Geo.region(g, 0, (Geo.rows(g) - 1 : U32)), Tm.sb(t))

def Tm.esc0(f: Nat, +t: Tm) -> Tm:
  match f:
    case 55n:
      Tm.save(t)
    case 56n:
      Tm.restore(t)
    case 68n:
      Tm.nl(t)
    case 69n:
      Tm.nl(Tm.cr(t))
    case 77n:
      Tm.ri(t)
    case 99n:
      Tm.reset(t)
    case _:
      t

def Tm.esc.k(i: Nat, +t: Tm, +fin: U32) -> Tm:
  match i:
    case 0n:
      Tm.esc0(Vt.n(fin), t)
    case 40n:
      Tm.set_cur(t, Cur.with_dec(Tm.cur(t), U32.is_eq(fin, 48)))
    case _:
      t

def Tm.esc(+t: Tm, +inter: U32, +fin: U32) -> Tm:
  Tm.esc.k(Vt.n(inter), t, fin)

# C0 controls
def Tm.ctl(k: Nat, +t: Tm) -> Tm:
  match k:
    case 8n:
      Tm.bs(t)
    case 9n:
      Tm.tab(t, 1)
    case 10n:
      Tm.nl(t)
    case 11n:
      Tm.nl(t)
    case 12n:
      Tm.nl(t)
    case 13n:
      Tm.cr(t)
    case _:
      t

# OSC: "0;title" and "2;title" set the title. Read as number, ';', text.
type Os is Data:
  Os{n: U32, ph: U32, txt: List<&2, U32>}

def Os.num(digit: Bool, semi: Bool, +n: U32, +b: U32) -> Os:
  match digit semi:
    case True{} _:
      Os{U32.min(((n * 10 : U32) + (b - 48 : U32) : U32), 100000), 0, Nil{}}
    case False{} True{}:
      Os{n, 1, Nil{}}
    case False{} False{}:
      Os{n, 2, Nil{}}

def Os.k(ph: Nat, +n: U32, txt: List<&2, U32>, +b: U32) -> Os:
  match ph:
    case 0n:
      Os.num(Vt.in(b, 48, 57), U32.is_eq(b, 59), n, b)
    case 1n:
      Os{n, 1, b <> txt}
    case _:
      Os{n, 2, Nil{}}

def Os.step(o: Os, +b: U32) -> Os:
  match o:
    case Os{+n, ph, txt}:
      Os.k(Vt.n(ph), n, txt, b)

def Os.go(bs: List<&2, U32>, o: Os) -> Os:
  match bs:
    case Nil{}:
      o
    case b <> t:
      Os.go(t, Os.step(o, b))

def Tm.title.k(ok: Bool, t: Tm, txt: List<&2, U32>) -> Tm:
  match ok t:
    case True{} Tm{g, s, c, m, a, b, Ex{sv, _, out}}:
      Tm{g, s, c, m, a, b, Ex{sv, U.Utf8.decode(List.reverse(&2, U32, txt)), out}}
    case False{} t:
      t

def Tm.osc.k(o: Os, t: Tm) -> Tm:
  match o:
    case Os{+n, +ph, txt}:
      Tm.title.k(U32.is_eq(ph, 1) && (U32.is_eq(n, 0) || U32.is_eq(n, 2)), t, txt)

def Tm.osc(t: Tm, bs: List<&2, U32>) -> Tm:
  Tm.osc.k(Os.go(bs, Os{0, 0, Nil{}}), t)

# Parser
# ------

# ground, mid UTF-8 (code point so far, bytes owed), after ESC, ESC plus an
# intermediate, CSI (private marker, parameters newest first, the one being
# read, intermediate), OSC (bytes newest first, count, ESC seen), and a
# string to skip (DCS, SOS, PM, APC) until ST
type Par is Data:
  PG{}
  PU{cp: U32, owe: U32}
  PE{}
  PI{inter: U32}
  PC{pv: U32, ps: List<&2, U32>, cur: U32, inter: U32}
  PO{acc: List<&2, U32>, n: U32, esc: Bool}
  PS{esc: Bool}
  PT{run: List<&2, U32>, n: U32}

# what one byte asks of the screen
type Act is Data:
  ANone{}
  APr{cp: U32}
  ACtl{b: U32}
  AEsc{inter: U32, fin: U32}
  ACsi{pv: U32, ps: List<&2, U32>, inter: U32, fin: U32}
  AOsc{bs: List<&2, U32>}
  ABad{next: Act}

type Step is Data:
  Step{p: Par, a: Act}

def Vt.bc.lo(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool, f: Bool) -> Nat:
  match a b c d e f:
    case True{} _ _ _ _ _:
      0n
    case False{} True{} _ _ _ _:
      1n
    case False{} False{} True{} _ _ _:
      2n
    case False{} False{} False{} True{} _ _:
      3n
    case False{} False{} False{} False{} True{} _:
      4n
    case False{} False{} False{} False{} False{} True{}:
      5n
    case False{} False{} False{} False{} False{} False{}:
      6n

def Vt.bc.hi(a: Bool, b: Bool, c: Bool, d: Bool) -> Nat:
  match a b c d:
    case True{} _ _ _:
      7n
    case False{} True{} _ _:
      8n
    case False{} False{} True{} _:
      9n
    case False{} False{} False{} True{}:
      10n
    case False{} False{} False{} False{}:
      11n

def Vt.bc.k(lo: Bool, +b: U32) -> Nat:
  match lo:
    case True{}:
      Vt.bc.lo(U32.is_lt(b, 32), U32.is_lt(b, 48), U32.is_lt(b, 58), U32.is_lt(b, 60), U32.is_lt(b, 64), U32.is_lt(b, 127))
    case False{}:
      Vt.bc.hi(U32.is_lt(b, 192), U32.is_lt(b, 224), U32.is_lt(b, 240), U32.is_lt(b, 248))

# byte classes: 0 C0, 1 intermediate, 2 digit, 3 : ;, 4 < = > ?, 5 final
# (64-126), 6 DEL, 7 UTF-8 continuation, 8/9/10 UTF-8 lead of 2/3/4, 11 bad
def Vt.bc(+b: U32) -> Nat:
  Vt.bc.k(U32.is_lt(b, 128), b)

def Par.ctl(k: Nat, +b: U32, stay: Par) -> Step:
  match k:
    case 27n:
      Step{PE{}, ANone{}}
    case 24n:
      Step{PG{}, ANone{}}
    case 26n:
      Step{PG{}, ANone{}}
    case _:
      Step{stay, ACtl{b}}

def Par.ground(c: Nat, +b: U32) -> Step:
  match c:
    case 0n:
      Par.ctl(Vt.n(b), b, PG{})
    case 6n:
      Step{PG{}, ANone{}}
    case 7n:
      Step{PG{}, ABad{ANone{}}}
    case 8n:
      Step{PU{(b .&. 31 : U32), 1}, ANone{}}
    case 9n:
      Step{PU{(b .&. 15 : U32), 2}, ANone{}}
    case 10n:
      Step{PU{(b .&. 7 : U32), 3}, ANone{}}
    case 11n:
      Step{PG{}, ABad{ANone{}}}
    case _:
      Step{PG{}, APr{b}}

def Step.bad(s: Step) -> Step:
  match s:
    case Step{p, a}:
      Step{p, ABad{a}}

def Par.utf.fin(done: Bool, +cp: U32, +owe: U32) -> Step:
  match done:
    case True{}:
      Step{PG{}, APr{cp}}
    case False{}:
      Step{PU{cp, (owe - 1 : U32)}, ANone{}}

def Par.utf(c: Nat, +cp: U32, +owe: U32, +b: U32) -> Step:
  match c:
    case 7n:
      Par.utf.fin(U32.is_eq(owe, 1), (U32.shln(cp, 6n) .|. (b .&. 63 : U32) : U32), owe)
    case _:
      Step.bad(Par.ground(c, b))

def Par.esc.g(c: Nat, +b: U32) -> Step:
  match c:
    case 2n:
      Step{PG{}, AEsc{0, b}}
    case 3n:
      Step{PG{}, AEsc{0, b}}
    case 4n:
      Step{PG{}, AEsc{0, b}}
    case 5n:
      Step{PG{}, AEsc{0, b}}
    case _:
      Step{PG{}, ANone{}}

def Par.esc.f(k: Nat, c: Nat, +b: U32) -> Step:
  match k:
    case 91n:
      Step{PC{0, Nil{}, 0, 0}, ANone{}}
    case 93n:
      Step{PO{Nil{}, 0, False{}}, ANone{}}
    case 80n:
      Step{PS{False{}}, ANone{}}
    case 88n:
      Step{PS{False{}}, ANone{}}
    case 94n:
      Step{PS{False{}}, ANone{}}
    case 95n:
      Step{PS{False{}}, ANone{}}
    case _:
      Par.esc.g(c, b)

# the byte after ESC
def Par.esc(c: Nat, +b: U32) -> Step:
  match c:
    case 0n:
      Par.ctl(Vt.n(b), b, PE{})
    case 1n:
      Step{PI{b}, ANone{}}
    case _:
      Par.esc.f(Vt.n(b), c, b)

def Par.inter(c: Nat, +i: U32, +b: U32) -> Step:
  match c:
    case 0n:
      Par.ctl(Vt.n(b), b, PI{i})
    case 1n:
      Step{PI{b}, ANone{}}
    case 2n:
      Step{PG{}, AEsc{i, b}}
    case 3n:
      Step{PG{}, AEsc{i, b}}
    case 4n:
      Step{PG{}, AEsc{i, b}}
    case 5n:
      Step{PG{}, AEsc{i, b}}
    case _:
      Step{PG{}, ANone{}}

def Par.csi(c: Nat, +pv: U32, ps: List<&2, U32>, +cur: U32, +inter: U32, +b: U32) -> Step:
  match c:
    case 0n:
      Par.ctl(Vt.n(b), b, PC{pv, ps, cur, inter})
    case 1n:
      Step{PC{pv, ps, cur, b}, ANone{}}
    case 2n:
      Step{PC{pv, ps, U32.min(((cur * 10 : U32) + (b - 48 : U32) : U32), 65535), inter}, ANone{}}
    case 3n:
      Step{PC{pv, cur <> ps, 0, inter}, ANone{}}
    case 4n:
      Step{PC{b, ps, cur, inter}, ANone{}}
    case 5n:
      Step{PG{}, ACsi{pv, List.reverse(&2, U32, cur <> ps), inter, b}}
    case _:
      Step{PC{pv, ps, cur, inter}, ANone{}}

def Par.osc.add(room: Bool, +b: U32, acc: List<&2, U32>, +n: U32) -> Step:
  match room:
    case True{}:
      Step{PO{b <> acc, (n + 1 : U32), False{}}, ANone{}}
    case False{}:
      Step{PO{acc, n, False{}}, ANone{}}

def Par.osc.k(k: Nat, +b: U32, acc: List<&2, U32>, +n: U32) -> Step:
  match k:
    case 7n:
      Step{PG{}, AOsc{List.reverse(&2, U32, acc)}}
    case 27n:
      Step{PO{acc, n, True{}}, ANone{}}
    case 24n:
      Step{PG{}, ANone{}}
    case 26n:
      Step{PG{}, ANone{}}
    case _:
      Par.osc.add(U32.is_lt(n, 4096), b, acc, n)

def Par.osc.st(st: Bool, +b: U32, acc: List<&2, U32>) -> Step:
  match st:
    case True{}:
      Step{PG{}, AOsc{List.reverse(&2, U32, acc)}}
    case False{}:
      Par.esc(Vt.bc(b), b)

# OSC text ends with BEL or ESC \
def Par.osc(esc: Bool, +b: U32, acc: List<&2, U32>, +n: U32) -> Step:
  match esc:
    case True{}:
      Par.osc.st(U32.is_eq(b, 92), b, acc)
    case False{}:
      Par.osc.k(Vt.n(b), b, acc, n)

def Par.str(esc: Bool, k: Nat) -> Step:
  match esc k:
    case True{} 92n:
      Step{PG{}, ANone{}}
    case _ 27n:
      Step{PS{True{}}, ANone{}}
    case _ 24n:
      Step{PG{}, ANone{}}
    case _ 26n:
      Step{PG{}, ANone{}}
    case _ _:
      Step{PS{False{}}, ANone{}}

def Par.step(p: Par, +b: U32) -> Step:
  match p:
    case PG{}:
      Par.ground(Vt.bc(b), b)
    case PU{cp, owe}:
      Par.utf(Vt.bc(b), cp, owe, b)
    case PE{}:
      Par.esc(Vt.bc(b), b)
    case PI{i}:
      Par.inter(Vt.bc(b), i, b)
    case PC{pv, ps, cur, i}:
      Par.csi(Vt.bc(b), pv, ps, cur, i, b)
    case PO{acc, n, esc}:
      Par.osc(esc, b, acc, n)
    case PS{esc}:
      Par.str(esc, Vt.n(b))
    case PT{_, _}:
      Par.ground(Vt.bc(b), b)

def Tm.act(a: Act, +t: Tm) -> Tm:
  match a:
    case ANone{}:
      t
    case APr{cp}:
      Tm.print(t, cp)
    case ACtl{b}:
      Tm.ctl(Vt.n(b), t)
    case AEsc{i, f}:
      Tm.esc(t, i, f)
    case ACsi{pv, ps, i, f}:
      Tm.csi(t, pv, ps, i, f)
    case AOsc{bs}:
      Tm.osc(t, bs)
    case ABad{n}:
      Tm.act(n, Tm.print(t, 65533))

# Resize
# ------

def Rows.refit(xs: List<&2, Tr<Cell>>, +g: Geo, +g2: Geo) -> List<&2, Tr<Cell>>:
  match xs:
    case Nil{}:
      Nil{}
    case r <> t:
      Row.of(Row.cells(r, g), g2, Cell.blank(256)) <> Rows.refit(t, g, g2)

# a screen for new geometry, less its top k rows
def Scr.refit(s: Scr, +g: Geo, +g2: Geo, k: Nat) -> Scr:
  Scr.of(Rows.refit(List.drop(&2, Tr<Cell>, Scr.list(s, g), k), g, g2), g2, Row.blank(g2, 256))

def Alt.refit(a: Alt, +g: Geo, +g2: Geo) -> Alt:
  match a:
    case NoAlt{}:
      NoAlt{}
    case InAlt{s}:
      InAlt{Scr.refit(s, g, g2, 0n)}

# rows are cut or padded on the right (no reflow); when the screen gets
# shorter than the cursor's row, rows leave from the top into the scrollback
def Tm.resize(t: Tm, +c: U32, +r: U32) -> Tm:
  match t:
    case Tm{+g, +s, +cur, m, +a, b, Ex{sv, ti, out}}:
      +g2 = Geo.new(c, r)
      +y = Cur.y(cur)
      +k = Vt.sub0((y + 1 : U32), r)
      +gone = List.take(&2, Tr<Cell>, Scr.list(s, g), Vt.n(k))
      Tm{g2, Scr.refit(s, g, g2, Vt.n(k)), Cur.clamp(Cur.at(cur, Cur.x(cur), (y - k : U32)), g2), m, Alt.refit(a, g, g2), Sb.keeps(Alt.main(a), gone, b), Ex{Cur.clamp(sv, g2), ti, out}}

# Rendering
# ---------

def Vt.pal16(k: Nat) -> U32:
  match k:
    case 0n:
      1908774
    case 1n:
      14707829
    case 2n:
      10011513
    case 3n:
      15057019
    case 4n:
      6402031
    case 5n:
      13007069
    case 6n:
      5682882
    case 7n:
      11252415
    case 8n:
      6054768
    case 9n:
      16743302
    case 10n:
      11921552
    case 11n:
      16766602
    case 12n:
      8570111
    case 13n:
      14392560
    case 14n:
      8378080
    case _:
      15790837

def Vt.lvl(v: Nat) -> U32:
  match v:
    case 0n:
      0
    case 1n:
      95
    case 2n:
      135
    case 3n:
      175
    case 4n:
      215
    case _:
      255

# the 6x6x6 color cube (palette 16-231)
def Vt.cube(+j: Nat) -> U32:
  (U32.shln(Vt.lvl(Nat.div(j, 36n)), 16n) .|. U32.shln(Vt.lvl(Nat.mod(Nat.div(j, 6n), 6n)), 8n) .|. Vt.lvl(Nat.mod(j, 6n)) : U32)

def Vt.pal.k(a: Bool, b: Bool, +i: U32) -> U32:
  match a b:
    case True{} _:
      Vt.pal16(Vt.n(i))
    case False{} True{}:
      Vt.cube(Vt.n((i - 16 : U32)))
    case False{} False{}:
      ((8 + ((i - 232 : U32) * 10 : U32) : U32) * 65793 : U32)

# palette entry i as 0xRRGGBB
def Vt.pal(+i: U32) -> U32:
  Vt.pal.k(U32.is_lt(i, 16), U32.is_lt(i, 232), i)

def Vt.rgb.k(a: Bool, b: Bool, +c: U32, +d: U32) -> U32:
  match a b:
    case True{} _:
      d
    case False{} True{}:
      (c .&. 16777215 : U32)
    case False{} False{}:
      Vt.pal((c .&. 255 : U32))

# a cell color as 0xRRGGBB; d stands for the default
def Vt.rgb(+c: U32, +d: U32) -> U32:
  Vt.rgb.k(U32.is_eq(c, 256), U32.is_ge(c, 16777216), c, d)

# default text and background
def Vt.fg() -> U32:
  14277092

def Vt.bg() -> U32:
  855826

# halfway from f to b (dim text)
def Vt.blend(+f: U32, +b: U32) -> U32:
  ((U32.shrn(f, 1n) .&. 8355711 : U32) + (U32.shrn(b, 1n) .&. 8355711 : U32) : U32)

def Vt.bit(+a: U32, +m: U32) -> Bool:
  U32.is_ne((a .&. m : U32), 0)

# a cell with colors resolved
type RC is Data:
  RC{ch: U32, fg: U32, bg: U32, bold: Bool, ul: Bool}

def Cell.rc.k(+ch: U32, +f0: U32, +b0: U32, +at: U32) -> RC:
  +inv = Vt.bit(at, 4)
  +f1 = Bool.pick(U32, inv, b0, f0)
  +b1 = Bool.pick(U32, inv, f0, b0)
  +f2 = Bool.pick(U32, Vt.bit(at, 8), Vt.blend(f1, b1), f1)
  RC{ch, Bool.pick(U32, Vt.bit(at, 16), b1, f2), b1, Vt.bit(at, 1), Vt.bit(at, 2)}

def Cell.rc(c: Cell) -> RC:
  match c:
    case Cell{ch, fg, bg, at}:
      Cell.rc.k(ch, Vt.rgb(fg, Vt.fg()), Vt.rgb(bg, Vt.bg()), at)

# a styled run of text; a wide character in text covers two cells
type VRun is Data:
  VRun{text: String, fg: U32, bg: U32, bold: Bool, underline: Bool}

type VLine is Data:
  VLine{runs: List<&2, VRun>}

type VCur is Data:
  VCur{x: U32, y: U32, visible: Bool}

def Vt.beq(a: Bool, b: Bool) -> Bool:
  Bool.not(Bool.xor(a, b))

# runs being built: the open one (text reversed) and the closed ones
type Rb is Data:
  Rb{txt: String, fg: U32, bg: U32, bold: Bool, ul: Bool, open: Bool, wide: Bool, runs: List<&2, VRun>}

def Rb.close(open: Bool, txt: String, fg: U32, bg: U32, bold: Bool, ul: Bool, runs: List<&2, VRun>) -> List<&2, VRun>:
  match open:
    case True{}:
      VRun{String.reverse(txt), fg, bg, bold, ul} <> runs
    case False{}:
      runs

def Rb.k(skip: Bool, same: Bool, txt: String, f: U32, b: U32, bo: Bool, u: Bool, op: Bool, wi: Bool, runs: List<&2, VRun>, +ch: U32, xf: U32, xb: U32, xbo: Bool, xu: Bool) -> Rb:
  match skip same:
    case True{} _:
      Rb{txt, f, b, bo, u, op, False{}, runs}
    case False{} True{}:
      Rb{SCon{Chr{ch}, txt}, f, b, bo, u, True{}, U32.is_eq(Vt.width(ch), 2), runs}
    case False{} False{}:
      Rb{SCon{Chr{ch}, SNil{}}, xf, xb, xbo, xu, True{}, U32.is_eq(Vt.width(ch), 2), Rb.close(op, txt, f, b, bo, u, runs)}

def Rb.push(r: Rb, x: RC) -> Rb:
  match r x:
    case Rb{txt, +f, +b, +bo, +u, +op, +wi, runs} RC{+ch, +xf, +xb, +xbo, +xu}:
      Rb.k(U32.is_eq(ch, 0) && wi, op && U32.is_eq(f, xf) && U32.is_eq(b, xb) && Vt.beq(bo, xbo) && Vt.beq(u, xu), txt, f, b, bo, u, op, wi, runs, Bool.pick(U32, U32.is_eq(ch, 0), 32, ch), xf, xb, xbo, xu)

def Rb.go(xs: List<&2, Cell>, r: Rb) -> Rb:
  match xs:
    case Nil{}:
      r
    case c <> t:
      Rb.go(t, Rb.push(r, Cell.rc(c)))

def Rb.fin(r: Rb) -> VLine:
  match r:
    case Rb{txt, f, b, bo, u, op, _, runs}:
      VLine{List.reverse(&2, VRun, Rb.close(op, txt, f, b, bo, u, runs))}

# a blank that needs no drawing: space on the default background
def Cell.plain(c: Cell) -> Bool:
  match c:
    case Cell{+ch, _, +bg, +at}:
      (U32.is_eq(ch, 32) || U32.is_eq(ch, 0)) && U32.is_eq(bg, 256) && U32.is_eq((at .&. 6 : U32), 0)

def Cells.plainh(xs: List<&2, Cell>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> _:
      Cell.plain(h)

# drop plain cells from the front of a reversed row
def Cells.trim(xs: List<&2, Cell>, p: Bool) -> List<&2, Cell>:
  match xs p:
    case Nil{} _:
      Nil{}
    case _ <> +t True{}:
      Cells.trim(t, Cells.plainh(t))
    case h <> t False{}:
      h <> t

def Vt.vline(row: Tr<Cell>, +g: Geo) -> VLine:
  +rev = List.reverse(&2, Cell, Vt.fit(Cell, Vt.n(Geo.cols(g)), Tr.list(Cell, row, Nil{}), Cell.blank(256)))
  Rb.fin(Rb.go(List.reverse(&2, Cell, Cells.trim(rev, Cells.plainh(rev))), Rb{SNil{}, 0, 0, False{}, False{}, False{}, False{}, Nil{}}))

def Vt.vlines(xs: List<&2, Tr<Cell>>, +g: Geo) -> List<&2, VLine>:
  match xs:
    case Nil{}:
      Nil{}
    case r <> t:
      Vt.vline(r, g) <> Vt.vlines(t, g)

def Sb.head(+sb: Sb) -> U32:
  match sb:
    case Sb{_, h, _}:
      h

def Tm.view(+t: Tm, +scroll: Nat) -> List<&2, VLine>:
  +g = Tm.g(t)
  +sb = Tm.sb(t)
  +n = Vt.n(Sb.len(sb))
  +s = Bool.pick(Nat, Nat.is_le(scroll, n), scroll, n)
  +r = Vt.n(Geo.rows(g))
  +k = Bool.pick(Nat, Nat.is_le(s, r), s, r)
  Vt.vlines(List.append(&2, Tr<Cell>, Sb.rows(k, sb, (Sb.head(sb) - U32.from_nat(s) : U32)), List.take(&2, Tr<Cell>, Scr.list(Tm.scr(t), g), Nat.sub(r, k))), g)

# The terminal
# ------------

type Vt is Data:
  Vt{t: Tm, p: Par}

def Vt.clamp(+n: U32) -> U32:
  U32.max(1, U32.min(n, 1000))

# a blank cols x rows terminal
def Vt.new(cols: U32, rows: U32) -> Vt:
  Vt{Tm.new(Geo.new(Vt.clamp(cols), Vt.clamp(rows)), Sb.new()), PG{}}

def Vt.byte.k(s: Step, +t: Tm) -> Vt:
  match s:
    case Step{p, a}:
      Vt{Tm.act(a, t), p}

def Tm.ascii.put(+g: Geo, +s: Scr, +x: U32, +y: U32, +p: Pen, d: Bool, +m: Md, a: Alt, b: Sb, e: Ex, +ch: U32) -> Tm:
  Tm{g, Scr.put(s, g, y, Tr.put(Cell, Scr.row(s, g, y), x, Geo.cc(g), Cell.of(ch, p))), Cur.adv(Cur{x, y, False{}, p, d}, Geo.cols(g), Md.awm(m), 1), m, a, b, e}

def Tm.ascii.k(slow: Bool, g: Geo, s: Scr, +x: U32, +y: U32, w: Bool, +p: Pen, d: Bool, m: Md, a: Alt, b: Sb, e: Ex, +ch: U32) -> Tm:
  match slow:
    case True{}:
      Tm.print(Tm{g, s, Cur{x, y, w, p, d}, m, a, b, e}, ch)
    case False{}:
      Tm.ascii.put(g, s, x, y, p, d, m, a, b, e, ch)

# an ASCII character with no wrap pending, no line drawing, no insert mode:
# the common case, written without the general path's checks
def Tm.ascii(t: Tm, +ch: U32) -> Tm:
  match t:
    case Tm{g, s, Cur{x, y, +w, p, +d}, +m, a, b, e}:
      Tm.ascii.k(w || d || Md.ins(m), g, s, x, y, w, p, d, m, a, b, e, ch)

# Text runs
# ---------

# row cells x.. replaced by the characters ys (k of them) in pen p
def Cells.text(ys: List<&2, U32>, +p: Pen, rest: List<&2, Cell>) -> List<&2, Cell>:
  match ys:
    case Nil{}:
      rest
    case y <> t:
      Cell.of(y, p) <> Cells.text(t, p, rest)

def Row.text(row: Tr<Cell>, +g: Geo, +x: U32, ys: List<&2, U32>, +k: U32, +p: Pen) -> Tr<Cell>:
  +xs = Row.cells(row, g)
  Row.of(List.append(&2, Cell, List.take(&2, Cell, xs, Vt.n(x)), Cells.text(ys, p, List.drop(&2, Cell, xs, Vt.n((x + k : U32))))), g, Cell.blank(256))

def Tm.bulk.k(+g: Geo, +s: Scr, +x: U32, +y: U32, +p: Pen, d: Bool, +m: Md, a: Alt, b: Sb, e: Ex, ys: List<&2, U32>, +k: U32) -> Tm:
  Tm{g, Scr.put(s, g, y, Row.text(Scr.row(s, g, y), g, x, ys, k, p)), Cur.adv(Cur{x, y, False{}, p, d}, Geo.cols(g), Md.awm(m), k), m, a, b, e}

# k characters that fit before the margin, written in one pass over the row
def Tm.bulk(t: Tm, ys: List<&2, U32>, +k: U32) -> Tm:
  match t:
    case Tm{+g, +s, Cur{x, y, _, p, d}, +m, a, b, e}:
      Tm.bulk.k(g, s, x, y, p, d, m, a, b, e, ys, k)

def Tm.chars(ys: List<&2, U32>, t: Tm) -> Tm:
  match ys:
    case Nil{}:
      t
    case y <> r:
      Tm.chars(r, Tm.ascii(t, y))

def Tm.seg(big: Bool, t: Tm, ys: List<&2, U32>, +k: U32) -> Tm:
  match big:
    case True{}:
      Tm.bulk(t, ys, k)
    case False{}:
      Tm.chars(ys, t)

# the rest of a text run: characters, how many, the terminal
type Tx is Data:
  Tx{ys: List<&2, U32>, n: U32, t: Tm}

# one segment: up to the margin (after a pending wrap)
def Tx.seg(+ys: List<&2, U32>, +n: U32, +t: Tm) -> Tx:
  +k = U32.min(n, (Tm.cols(t) - Tm.x(t) : U32))
  Tx{List.drop(&2, U32, ys, Vt.n(k)), (n - k : U32), Tm.seg(U32.is_ge(k, 32), t, List.take(&2, U32, ys, Vt.n(k)), k)}

def Tx.step.k(done: Bool, ys: List<&2, U32>, +n: U32, +t: Tm) -> Tx:
  match done:
    case True{}:
      Tx{ys, n, t}
    case False{}:
      Tx.seg(ys, n, Tm.pre(t, 1))

def Tx.step(x: Tx) -> Tx:
  match x:
    case Tx{ys, +n, t}:
      Tx.step.k(U32.is_eq(n, 0), ys, n, t)

def Tx.go(fuel: Nat, x: Tx) -> Tx:
  match fuel:
    case 0n:
      x
    case 1n+f:
      Tx.go(f, Tx.step(x))

def Tx.tm(x: Tx) -> Tm:
  match x:
    case Tx{_, _, t}:
      t

def Tm.text.k(short: Bool, ys: List<&2, U32>, +n: U32, +t: Tm) -> Tm:
  match short:
    case True{}:
      Tm.chars(ys, t)
    case False{}:
      Tx.tm(Tx.go(Vt.n((n + 1 : U32)), Tx{ys, n, t}))

# n printable ASCII characters: short runs (and line drawing, insert mode)
# one by one, long ones a row segment at a time
def Tm.text(+t: Tm, ys: List<&2, U32>, +n: U32) -> Tm:
  +m = Tm.md(t)
  Tm.text.k(U32.is_lt(n, 32) || Cur.dec(Tm.cur(t)) || Md.ins(m), ys, n, t)

# printable ASCII in the ground state collects into a run, written at the
# next other byte or at the end of the chunk
def Vt.ground(pr: Bool, +t: Tm, +b: U32) -> Vt:
  match pr:
    case True{}:
      Vt{t, PT{[b], 1}}
    case False{}:
      Vt.byte.k(Par.ground(Vt.bc(b), b), t)

def Vt.run(pr: Bool, +t: Tm, run: List<&2, U32>, +n: U32, +b: U32) -> Vt:
  match pr:
    case True{}:
      Vt{t, PT{b <> run, (n + 1 : U32)}}
    case False{}:
      Vt.byte.k(Par.ground(Vt.bc(b), b), Tm.text(t, List.reverse(&2, U32, run), n))

def Vt.byte.p(p: Par, +t: Tm, +b: U32) -> Vt:
  match p:
    case PG{}:
      Vt.ground(U32.is_lt((b - 32 : U32), 95), t, b)
    case PT{run, n}:
      Vt.run(U32.is_lt((b - 32 : U32), 95), t, run, n, b)
    case p:
      Vt.byte.k(Par.step(p, b), t)

def Vt.byte(v: Vt, +b: U32) -> Vt:
  match v:
    case Vt{t, p}:
      Vt.byte.p(p, t, b)

def Vt.go(bs: List<&2, U32>, v: Vt) -> Vt:
  match bs:
    case Nil{}:
      v
    case b <> t:
      Vt.go(t, Vt.byte(v, b))

# a pending text run written out
def Vt.flush(v: Vt) -> Vt:
  match v:
    case Vt{t, PT{run, n}}:
      Vt{Tm.text(t, List.reverse(&2, U32, run), n), PG{}}
    case v:
      v

# bytes from the pty, in any chunks (a sequence or a character may be split)
def Vt.feed(v: Vt, bytes: List<&2, U32>) -> Vt:
  Vt.flush(Vt.go(bytes, v))

def Vt.resize(v: Vt, cols: U32, rows: U32) -> Vt:
  match v:
    case Vt{t, p}:
      Vt{Tm.resize(t, Vt.clamp(cols), Vt.clamp(rows)), p}

def Vt.tm(+v: Vt) -> Tm:
  match v:
    case Vt{t, _}:
      t

# bytes the host must write back to the pty (cursor reports, attributes)
def Vt.replies(+v: Vt) -> List<&2, U32>:
  match v:
    case Vt{Tm{_, _, _, _, _, _, Ex{_, _, out}}, _}:
      List.reverse(&2, U32, out)

# the terminal with its replies taken
def Vt.drain(v: Vt) -> Vt:
  match v:
    case Vt{Tm{g, s, c, m, a, b, Ex{sv, ti, _}}, p}:
      Vt{Tm{g, s, c, m, a, b, Ex{sv, ti, Nil{}}}, p}

# the window title (OSC 0 / 2)
def Vt.title(+v: Vt) -> String:
  match v:
    case Vt{Tm{_, _, _, _, _, _, Ex{_, ti, _}}, _}:
      ti

def Vt.cursor(+v: Vt) -> VCur:
  +t = Vt.tm(v)
  VCur{Tm.x(t), Tm.y(t), Md.show(Tm.md(t))}

def Vt.cols(+v: Vt) -> U32:
  Tm.cols(Vt.tm(v))

def Vt.rows(+v: Vt) -> U32:
  Tm.rows(Vt.tm(v))

# rows kept in the scrollback (the most Vt.lines can scroll back)
def Vt.history(+v: Vt) -> U32:
  Sb.len(Tm.sb(Vt.tm(v)))

# the alternate screen is up (full-screen programs: vim, less)
def Vt.alt(+v: Vt) -> Bool:
  Bool.not(Alt.main(Tm.alt(Vt.tm(v))))

# application cursor keys (?1) and bracketed paste (?2004) are on
def Vt.appk(+v: Vt) -> Bool:
  Md.appk(Tm.md(Vt.tm(v)))

def Vt.bpaste(+v: Vt) -> Bool:
  Md.paste(Tm.md(Vt.tm(v)))

# the visible rows, scrolled back by scroll lines into the scrollback;
# trailing blank cells are left out
def Vt.lines(+v: Vt, +scroll: Nat) -> List<&2, VLine>:
  Tm.view(Vt.tm(v), scroll)

# Keys
# ----

def Vt.meta(alt: Bool, bs: List<&2, U32>) -> List<&2, U32>:
  match alt:
    case True{}:
      27 <> bs
    case False{}:
      bs

# ESC [ 1 ; m L, or ESC [ L / ESC O L without modifiers
def Vt.csik.k(plain: Bool, appk: Bool, +l: U32, +m: U32) -> List<&2, U32>:
  match plain appk:
    case True{} True{}:
      [27, 79, l]
    case True{} False{}:
      [27, 91, l]
    case False{} _:
      Vt.esc_seq("[1;" ++ U32.show(m) ++ SCon{Chr{l}, SNil{}})

def Vt.csik(+l: U32, appk: Bool, +m: U32) -> List<&2, U32>:
  Vt.csik.k(U32.is_eq(m, 1), appk, l, m)

def Vt.tilde(+n: U32, +m: U32) -> List<&2, U32>:
  Vt.esc_seq("[" ++ U32.show(n) ++ Bool.pick(String, U32.is_eq(m, 1), "", ";" ++ U32.show(m)) ++ "~")

# a control character for ctrl + cp
def Vt.ctrl.k(k: Nat, +cp: U32) -> U32:
  match k:
    case 32n:
      0
    case 64n:
      0
    case 50n:
      0
    case 91n:
      27
    case 51n:
      27
    case 92n:
      28
    case 52n:
      28
    case 93n:
      29
    case 53n:
      29
    case 94n:
      30
    case 54n:
      30
    case 95n:
      31
    case 55n:
      31
    case 47n:
      31
    case 63n:
      127
    case 56n:
      127
    case _:
      cp

def Vt.ctrl.l(lower: Bool, upper: Bool, small: Bool, +cp: U32) -> U32:
  match lower upper small:
    case True{} _ _:
      (cp - 96 : U32)
    case False{} True{} _:
      (cp - 64 : U32)
    case False{} False{} True{}:
      Vt.ctrl.k(Vt.n(cp), cp)
    case False{} False{} False{}:
      cp

def Vt.ctrl(ctrl: Bool, +cp: U32) -> U32:
  match ctrl:
    case True{}:
      Vt.ctrl.l(Vt.in(cp, 97, 122), Vt.in(cp, 65, 90), U32.is_lt(cp, 128), cp)
    case False{}:
      cp

def Vt.key.text.k(none: Bool, +cp: U32, +mods: U32) -> List<&2, U32>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      Vt.meta(Vt.bit(mods, 8), U.Utf8.put(Vt.ctrl(Vt.bit(mods, 4), cp), Nil{}))

def Vt.key.text(+cp: U32, +mods: U32) -> List<&2, U32>:
  Vt.key.text.k(U32.is_eq(cp, 0), cp, mods)

# the character a key types: its text, else a Latin-1 or Unicode keysym
def Vt.key.cp(+keysym: U32, +text: U32) -> U32:
  Bool.pick(U32, U32.is_ne(text, 0), text, Bool.pick(U32, Vt.in(keysym, 32, 255), keysym, Bool.pick(U32, U32.is_ge(keysym, 16777216), (keysym - 16777216 : U32), 0)))

def Vt.fkey(k: Nat, +keysym: U32, +text: U32, +mods: U32, appk: Bool, +m: U32) -> List<&2, U32>:
  match k:
    case 8n:
      Vt.meta(Vt.bit(mods, 8), [Bool.pick(U32, Vt.bit(mods, 4), 8, 127)])
    case 9n:
      Bool.pick(List<&2, U32>, Vt.bit(mods, 1), [27, 91, 90], Vt.meta(Vt.bit(mods, 8), [9]))
    case 13n:
      Vt.meta(Vt.bit(mods, 8), [13])
    case 27n:
      [27]
    case 80n:
      Vt.csik(72, appk, m)
    case 81n:
      Vt.csik(68, appk, m)
    case 82n:
      Vt.csik(65, appk, m)
    case 83n:
      Vt.csik(67, appk, m)
    case 84n:
      Vt.csik(66, appk, m)
    case 85n:
      Vt.tilde(5, m)
    case 86n:
      Vt.tilde(6, m)
    case 87n:
      Vt.csik(70, appk, m)
    case 99n:
      Vt.tilde(2, m)
    case 141n:
      [13]
    case 149n:
      Vt.csik(72, appk, m)
    case 150n:
      Vt.csik(68, appk, m)
    case 151n:
      Vt.csik(65, appk, m)
    case 152n:
      Vt.csik(67, appk, m)
    case 153n:
      Vt.csik(66, appk, m)
    case 154n:
      Vt.tilde(5, m)
    case 155n:
      Vt.tilde(6, m)
    case 156n:
      Vt.csik(70, appk, m)
    case 158n:
      Vt.tilde(2, m)
    case 159n:
      Vt.tilde(3, m)
    case 190n:
      Vt.csik(80, True{}, m)
    case 191n:
      Vt.csik(81, True{}, m)
    case 192n:
      Vt.csik(82, True{}, m)
    case 193n:
      Vt.csik(83, True{}, m)
    case 194n:
      Vt.tilde(15, m)
    case 195n:
      Vt.tilde(17, m)
    case 196n:
      Vt.tilde(18, m)
    case 197n:
      Vt.tilde(19, m)
    case 198n:
      Vt.tilde(20, m)
    case 199n:
      Vt.tilde(21, m)
    case 200n:
      Vt.tilde(23, m)
    case 201n:
      Vt.tilde(24, m)
    case 255n:
      Vt.tilde(3, m)
    case _:
      Vt.key.text(Vt.key.cp(keysym, text), mods)

def Vt.key.k(fn: Bool, back: Bool, +keysym: U32, +text: U32, +mods: U32, appk: Bool) -> List<&2, U32>:
  match fn back:
    case True{} _:
      Vt.fkey(Vt.n((keysym - 65280 : U32)), keysym, text, mods, appk, (1 + (mods .&. 1 : U32) + U32.shrn((mods .&. 8 : U32), 2n) + (mods .&. 4 : U32) : U32))
    case False{} True{}:
      [27, 91, 90]
    case False{} False{}:
      Vt.key.text(Vt.key.cp(keysym, text), mods)

# the bytes for a key press: an X11 keysym, the text it typed (a code point,
# 0 for none), and modifiers (bit 0 shift, bit 2 ctrl, bit 3 alt)
def Vt.key(+v: Vt, +keysym: U32, +text: U32, +mods: U32) -> List<&2, U32>:
  Vt.key.k(U32.is_ge(keysym, 65280), U32.is_eq(keysym, 65056), keysym, text, mods, Md.appk(Tm.md(Vt.tm(v))))

# Paste
# -----

def Vt.onto(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      Vt.onto(t, h <> acc)

# the UTF-8 of s, reversed
def Vt.enc_rev(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, t}:
      Vt.enc_rev(t, Vt.onto(U.Utf8.put(c, Nil{}), acc))

def Paste.k(crlf: Bool, lf: Bool, esc: Bool, +b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match crlf lf esc:
    case True{} _ _:
      acc
    case False{} True{} _:
      13 <> acc
    case False{} False{} True{}:
      acc
    case False{} False{} False{}:
      b <> acc

# walks the reversed bytes (next is the byte that followed b), building the
# result forward: CR LF and LF become CR; ESC is dropped inside brackets
def Paste.go(rev: List<&2, U32>, acc: List<&2, U32>, +next: U32, +br: Bool) -> List<&2, U32>:
  match rev:
    case Nil{}:
      acc
    case +b <> t:
      Paste.go(t, Paste.k(U32.is_eq(b, 13) && U32.is_eq(next, 10), U32.is_eq(b, 10), U32.is_eq(b, 27) && br, b, acc), b, br)

def Paste.wrap(br: Bool, bs: List<&2, U32>) -> List<&2, U32>:
  match br:
    case True{}:
      List.append(&2, U32, [27, 91, 50, 48, 48, 126], List.append(&2, U32, bs, [27, 91, 50, 48, 49, 126]))
    case False{}:
      bs

# the bytes for pasted text, bracketed when the program asked (?2004)
def Vt.paste(+v: Vt, text: String) -> List<&2, U32>:
  +br = Md.paste(Tm.md(Vt.tm(v)))
  Paste.wrap(br, Paste.go(Vt.enc_rev(text, Nil{}), Nil{}, 0, br))
