import Base
import ../core/board.bend as B
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ../core/schematic.bend as SC
import ../core/glb.bend as G
import ../gfx/mesh.bend as MS
import ../gfx/face.bend as FA
import ../gfx/bitmap.bend as BM
import ../core/look.bend as LO
import ../core/layers.bend as LY

# The board viewer. A scene is the board's items, each with the time it
# appeared, kept in paint order: by layer, then key. A new file merges into
# the scene by that order: an item whose layer, key and signature are
# unchanged keeps its birth time (law scene_merge_self: an unchanged board
# never re-fades); anything new or changed is born now and fades in.
# Geometry always comes from the newest file. Because the scene is already
# in paint order, a frame draws it in one pass.

type Seen is Data:
  Seen{item: B.Item, born: Nat}

# Keys
# ----

def Key.of(i: B.Item) -> String:
  match i:
    case B.Item{k, _, _, _, _}:
      k

def Key.sig(i: B.Item) -> U32:
  match i:
    case B.Item{_, s, _, _, _}:
      s

def Key.cmp.fin(r: (String & String) & Cmp) -> Cmp:
  (_, c) = r
  c

# string order of two keys
def Key.cmp(a: String, b: String) -> Cmp:
  Key.cmp.fin(String.cmp(a, b))

def Scene.cmp.k(c: Cmp, +a: String, +b: String) -> Cmp:
  match c:
    case EQ{}:
      Key.cmp(a, b)
    case LT{}:
      LT{}
    case GT{}:
      GT{}

# paint order: layer, then key
def Scene.cmp(a: B.Item, b: B.Item) -> Cmp:
  match a b:
    case B.Item{+ka, _, +la, _, _} B.Item{+kb, _, +lb, _, _}:
      Scene.cmp.k(U32.cmp(la, lb), ka, kb)

def Key.le(a: B.Item, b: B.Item) -> Bool:
  Cmp.is_le(Scene.cmp(a, b))

# items in paint order (merge needs both sides sorted)
def Scene.sort(+xs: List<&2, B.Item>) -> List<&2, B.Item>:
  List.sort(~B.Item, ~Key.le, xs)

# Merging
# -------

# the order of the two heads (EQ when either list is empty; unused then)
def Scene.heads(os: List<&2, Seen>, ns: List<&2, B.Item>) -> Cmp:
  match os ns:
    case Seen{+o, _} <> _ +n <> _:
      Scene.cmp(o, n)
    case _ _:
      EQ{}

def Scene.keep(same: Bool, n: B.Item, +born: Nat, +now: Nat) -> Seen:
  match same:
    case True{}:
      Seen{n, born}
    case False{}:
      Seen{n, now}

def Scene.born(ns: List<&2, B.Item>, +now: Nat) -> List<&2, Seen>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> t:
      Seen{n, now} <> Scene.born(t, now)

# the new items (sorted), each born now unless the old scene (sorted) had it
# unchanged; `c` is the order of the two lists' heads
def Scene.merge(+os: List<&2, Seen>, ns: List<&2, B.Item>, c: Cmp, +now: Nat) -> List<&2, Seen>:
  match os ns c:
    case Nil{} _ _:
      Scene.born(ns, now)
    case _ Nil{} _:
      Nil{}
    case _ <> +ot +n <> nt GT{}:
      Seen{n, now} <> Scene.merge(os, nt, Scene.heads(os, nt), now)
    case _ <> +ot +n <> +nt LT{}:
      Scene.merge(ot, n <> nt, Scene.heads(ot, n <> nt), now)
    case Seen{+o, +b} <> +ot +n <> nt EQ{}:
      Scene.keep(U32.is_eq(Key.sig(o), Key.sig(n)), n, b, now) <> Scene.merge(ot, nt, Scene.heads(ot, nt), now)

def Scene.update(+os: List<&2, Seen>, +ns: List<&2, B.Item>, +now: Nat) -> List<&2, Seen>:
  Scene.merge(os, ns, Scene.heads(os, ns), now)

# the items of a scene (what a re-read of the same file yields)
def Scene.items(ss: List<&2, Seen>) -> List<&2, B.Item>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{i, _} <> t:
      i <> Scene.items(t)

# Fading
# ------

def Fade.ms() -> Nat:
  220n

def Fade.alpha.k(done: Bool, +age: Nat) -> U32:
  match done:
    case True{}:
      255
    case False{}:
      U32.from_nat(Nat.div(Nat.mul(age, 255n), Fade.ms()))

# opacity of something born at `born`, now: 0 at birth, 255 once FADE ms
# have passed (law fade_done), in between a straight ramp
def Fade.alpha(+now: Nat, +born: Nat) -> U32:
  Fade.alpha.k(Nat.is_ge(now, Nat.add(born, Fade.ms())), Nat.sub(now, born))

# whether anything is still fading (the window keeps drawing only then)
def Fade.busy(ss: List<&2, Seen>, +now: Nat) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{_, +b} <> t:
      Bool.or(Nat.is_lt(now, Nat.add(b, Fade.ms())), Fade.busy(t, now))

# Layers
# ------

# colour and opacity per layer index (B.Layer.names); 0 opacity hides it
def Layer.look(i: Nat) -> U32 & U32:
  LO.Look.board(i)

# View
# ----

# pixels per mm, and where the board's origin lands on screen
type View is Data:
  View{zoom: F32, ox: F32, oy: F32}

def View.x(v: View, +x: F32) -> F32:
  match v:
    case View{z, ox, _}:
      F32.add(ox, F32.mul(x, z))

def View.y(v: View, +y: F32) -> F32:
  match v:
    case View{z, _, oy}:
      F32.add(oy, F32.mul(y, z))

def View.p(+v: View, p: B.Pt) -> D.P2:
  match p:
    case B.Pt{x, y}:
      D.P2{View.x(v, x), View.y(v, y)}

def View.ps(ps: List<&2, B.Pt>, +v: View) -> List<&2, D.P2>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      View.p(v, p) <> View.ps(t, v)

def View.w(v: View, +w: F32) -> F32:
  match v:
    case View{z, _, _}:
      F32.max(F32.mul(w, z), 1.0)

def View.box.pt(p: B.Pt, b: D.Box) -> D.Box:
  match p b:
    case B.Pt{+x, +y} D.Box{+x0, +y0, +x1, +y1}:
      D.Box{F32.min(x0, x), F32.min(y0, y), F32.max(x1, x), F32.max(y1, y)}

def View.box.pts(ps: List<&2, B.Pt>, b: D.Box) -> D.Box:
  match ps:
    case Nil{}:
      b
    case p <> t:
      View.box.pts(t, View.box.pt(p, b))

def View.box.prim(p: B.Prim, b: D.Box) -> D.Box:
  match p:
    case B.PSeg{a, e, _}:
      View.box.pt(e, View.box.pt(a, b))
    case B.PLine{ps, _}:
      View.box.pts(ps, b)
    case B.PCirc{c, _, _, _}:
      View.box.pt(c, b)
    case B.PPoly{ps, _, _}:
      View.box.pts(ps, b)
    case B.PTint{ps, _, _}:
      View.box.pts(ps, b)

# the scene's extent in mm
def View.box(ss: List<&2, Seen>, b: D.Box) -> D.Box:
  match ss:
    case Nil{}:
      b
    case Seen{B.Item{_, _, _, p, _}, _} <> t:
      View.box(t, View.box.prim(p, b))

def View.fit.z(+z: F32, +cx: F32, +cy: F32, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  View{z, F32.sub(F32.add(x0, F32.div(w, 2.0)), F32.mul(cx, z)), F32.sub(F32.add(y0, F32.div(h, 2.0)), F32.mul(cy, z))}

def View.fit.k(b: D.Box, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  match b:
    case D.Box{+bx0, +by0, +bx1, +by1}:
      View.fit.z(F32.mul(0.9, F32.min(F32.div(w, F32.max(F32.sub(bx1, bx0), 1.0)), F32.div(h, F32.max(F32.sub(by1, by0), 1.0)))),
        F32.div(F32.add(bx0, bx1), 2.0), F32.div(F32.add(by0, by1), 2.0), x0, y0, w, h)

# the view that shows the whole scene in the w x h panel at (x0, y0)
def View.fit(+ss: List<&2, Seen>, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  View.fit.k(View.box(ss, D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}), x0, y0, w, h)

# zoom by f around screen point (px, py)
def View.zoom(v: View, +f: F32, +px: F32, +py: F32) -> View:
  match v:
    case View{z, ox, oy}:
      View{F32.mul(z, f), F32.add(px, F32.mul(F32.sub(ox, px), f)), F32.add(py, F32.mul(F32.sub(oy, py), f))}

def View.pan(v: View, +dx: F32, +dy: F32) -> View:
  match v:
    case View{z, ox, oy}:
      View{z, F32.add(ox, dx), F32.add(oy, dy)}

# Ops
# ---

def Ops.line(ps: List<&2, D.P2>, +c: D.Clip, +w: F32, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  match ps:
    case D.P2{+ax, +ay} <> D.P2{+bx, +by} <> t:
      D.Draw.seg(c, ax, ay, bx, by, w, color, alpha) <> Ops.line(D.P2{bx, by} <> t, c, w, color, alpha)
    case _:
      Nil{}

def Ops.at(+i: Nat, +cx: F32, +cy: F32, +r: F32) -> D.P2:
  +a = F32.mul(F32.div(F32.from_nat(i), 32.0), F32.mul(2.0, F32.pi()))
  D.P2{F32.add(cx, F32.mul(r, F32.cos(a))), F32.add(cy, F32.mul(r, F32.sin(a)))}

def Ops.circle(n: Nat, +i: Nat, +cx: F32, +cy: F32, +r: F32) -> List<&2, D.P2>:
  match n:
    case 0n:
      [Ops.at(i, cx, cy, r)]
    case 1n+m:
      Ops.at(i, cx, cy, r) <> Ops.circle(m, 1n+i, cx, cy, r)

def Ops.ring(+c: D.Clip, +cx: F32, +cy: F32, +r: F32, +w: F32, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  Ops.line(Ops.circle(32n, 0n, cx, cy, r), c, w, color, alpha)

def Ops.z(v: View) -> F32:
  match v:
    case View{z, _, _}:
      z

def Ops.prim(p: B.Prim, +v: View, +c: D.Clip, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  match p:
    case B.PSeg{a, b, w}:
      Ops.line([View.p(v, a), View.p(v, b)], c, View.w(v, w), color, alpha)
    case B.PLine{ps, w}:
      Ops.line(View.ps(ps, v), c, View.w(v, w), color, alpha)
    case B.PCirc{B.Pt{+x, +y}, +r, +w, True{}}:
      [D.Draw.disc(c, View.x(v, x), View.y(v, y), F32.max(F32.mul(r, Ops.z(v)), 0.5), color, alpha)]
    case B.PCirc{B.Pt{+x, +y}, +r, +w, False{}}:
      Ops.ring(c, View.x(v, x), View.y(v, y), F32.mul(r, Ops.z(v)), View.w(v, w), color, alpha)
    case B.PPoly{+ps, w, True{}}:
      [D.Draw.poly(c, View.ps(ps, v), color, alpha)]
    case B.PPoly{+ps, +w, False{}}:
      Ops.line(List.append(&2, D.P2, View.ps(ps, v), [View.p(v, Maybe.default(&2, B.Pt, List.head(&2, B.Pt, ps), B.Pt{0.0, 0.0}))]), c, View.w(v, w), color, alpha)
    case B.PTint{+ps, _, _}:
      [D.Draw.poly(c, View.ps(ps, v), color, alpha)]

def Ops.item.show(hidden: Bool, p: B.Prim, +v: View, +c: D.Clip, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match hidden:
    case True{}:
      rest
    case False{}:
      List.append(&2, R.Op, Ops.prim(p, v, c, color, alpha), rest)

# a tint keeps its own colour and opacity; everything else takes its layer's
def Ops.item.own(p: B.Prim, hidden: Bool, +v: View, +c: D.Clip, +color: U32, +alpha: U32, +fade: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match p:
    case B.PTint{ps, +tc, +ta}:
      Ops.item.show(hidden, B.PTint{ps, tc, ta}, v, c, tc, ((ta * fade : U32) / 255 : U32), rest)
    case B.PSeg{a, b, w}:
      Ops.item.show(hidden, B.PSeg{a, b, w}, v, c, color, alpha, rest)
    case B.PLine{ps, w}:
      Ops.item.show(hidden, B.PLine{ps, w}, v, c, color, alpha, rest)
    case B.PCirc{m, r, w, f}:
      Ops.item.show(hidden, B.PCirc{m, r, w, f}, v, c, color, alpha, rest)
    case B.PPoly{ps, w, f}:
      Ops.item.show(hidden, B.PPoly{ps, w, f}, v, c, color, alpha, rest)

def Ops.item.k(look: U32 & U32, p: B.Prim, +v: View, +c: D.Clip, +fade: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  (color, +base) = look
  Ops.item.own(p, U32.is_eq(base, 0), v, c, color, ((base * fade : U32) / 255 : U32), fade, rest)

# a layer's colour and opacity in a board (kind 0) or a schematic (kind 1)
def Look.of(+kind: U32, +layer: U32) -> U32 & U32:
  LO.Look.of(LY.Lyr.kind.base(kind), layer)

# (a comparison's marks included: other scenes have nothing on them)
def Look.count(+kind: U32) -> Nat:
  LO.Look.count(U32.or(LY.Lyr.kind.base(kind), LO.Look.diff()))

# Layer visibility
# ----------------
# The user turns layers on and off one by one. `flip` holds a bit per
# layer index: a set bit shows a layer the viewer hides by default (at
# Look.dim) and hides one it shows. 0 is the default look (law
# look_flip_none); flipping a layer twice gives it back (law
# look_flip_twice).

def Look.dim() -> U32:
  170

def Look.bit(+layer: U32) -> U32:
  U32.shln(1, U32.to_nat(layer))

def Look.flipped.k(none: Bool, +flip: U32, +layer: U32) -> Bool:
  match none:
    case True{}:
      False{}
    case False{}:
      Bool.not(U32.is_eq(U32.and(flip, Look.bit(layer)), 0))

# whether a layer's bit is set in `flip` (no shifting when none is)
def Look.flipped(+flip: U32, +layer: U32) -> Bool:
  Look.flipped.k(U32.is_eq(flip, 0), flip, layer)

# `flip` with one layer toggled
def Look.toggle(+flip: U32, +layer: U32) -> U32:
  U32.xor(flip, Look.bit(layer))

def Look.flip.k(on: Bool, look: U32 & U32) -> U32 & U32:
  match on:
    case False{}:
      look
    case True{}:
      (c, +a) = look
      (c, Bool.pick(U32, U32.is_eq(a, 0), Look.dim(), 0))

# The look word: besides a bit per layer, bit 31 is the viewer's light
# ground (its own sun/moon button), bit 30 the window's light theme and
# bit 29 a comparison's look (Look.cmp);
# no layer reaches any of them (a board has 25 layers, a schematic 24,
# a comparison marks up to 28)
def Look.light.bit() -> U32:
  2147483648

def Look.ui.bit() -> U32:
  1073741824

# bit 29: the scene is a comparison (core/hist.bend), drawn in its look
def Look.cmp.bit() -> U32:
  536870912

def Look.cmp(+flip: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(flip, Look.cmp.bit()), 0))

def Look.light(+flip: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(flip, Look.light.bit()), 0))

def Look.ui(+flip: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(flip, Look.ui.bit()), 0))

# the viewer's ground under the scene
def Look.ground(+flip: U32) -> U32:
  LO.Look.ground(Look.light(flip))

def Look.on.k(+kind: U32, +layer: U32, +flip: U32) -> U32 & U32:
  Look.flip.k(Look.flipped(flip, layer), LO.Look.of.t(Look.light(flip), Bool.pick(U32, Look.cmp(flip), U32.or(kind, LO.Look.diff()), kind), layer))

# a layer's colour and opacity once the user's flips apply, then the
# focus the kind word carries (core/layers.bend: the active layer stands
# out, the rest dimmed or hidden)
def Look.on(+kind: U32, +layer: U32, +flip: U32) -> U32 & U32:
  LY.Lyr.shade(LY.Lyr.kind.base(kind), LY.Lyr.kind.focus(kind), layer, Look.on.k(LY.Lyr.kind.base(kind), layer, flip))

def Look.alpha.k(l: U32 & U32) -> U32:
  (_, a) = l
  a

def Look.alpha(+kind: U32, +layer: U32, +flip: U32) -> U32:
  Look.alpha.k(Look.on(kind, layer, flip))

# whether a layer shows
def Look.shows(+kind: U32, +layer: U32, +flip: U32) -> Bool:
  U32.is_gt(Look.alpha(kind, layer, flip), 0)

# the layers a scene has items on, as bits (for the layer list)
def Layers.present(ss: List<&2, Seen>, +acc: U32) -> U32:
  match ss:
    case Nil{}:
      acc
    case Seen{B.Item{_, _, +l, _, _}, _} <> t:
      Layers.present(t, U32.or(acc, Look.bit(l)))

# Culling
# -------
# An item wholly outside the panel makes no ops at all: when zoomed in,
# most of a board is skipped before any geometry is transformed.

def Cull.pt(p: B.Pt, +pad: F32, b: D.Box) -> D.Box:
  match p b:
    case B.Pt{+x, +y} D.Box{+x0, +y0, +x1, +y1}:
      D.Box{F32.min(x0, F32.sub(x, pad)), F32.min(y0, F32.sub(y, pad)), F32.max(x1, F32.add(x, pad)), F32.max(y1, F32.add(y, pad))}

def Cull.pts(ps: List<&2, B.Pt>, +pad: F32, b: D.Box) -> D.Box:
  match ps:
    case Nil{}:
      b
    case p <> t:
      Cull.pts(t, pad, Cull.pt(p, pad, b))

# whether a box in mm meets the clip on screen (a pixel of slack for the
# one-pixel minimum stroke)
def Cull.meets(b: D.Box, +v: View, c: D.Clip) -> Bool:
  match b c:
    case D.Box{+x0, +y0, +x1, +y1} D.Clip{+cx0, +cy0, +cx1, +cy1}:
      Bool.and(Bool.and(F32.is_ge(F32.add(View.x(v, x1), 1.0), U32.to_f32(cx0)), F32.is_le(F32.sub(View.x(v, x0), 1.0), U32.to_f32(cx1))),
        Bool.and(F32.is_ge(F32.add(View.y(v, y1), 1.0), U32.to_f32(cy0)), F32.is_le(F32.sub(View.y(v, y0), 1.0), U32.to_f32(cy1))))

def Ops.pick(keep: Bool, +p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, +kind: U32, +flip: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match keep:
    case True{}:
      Ops.item.k(Look.on(kind, layer, flip), p, v, c, fade, rest)
    case False{}:
      rest

# what the viewer shows: kind 0 board, 1 schematic, 2 3D, 3 the agents'
# browser (`bmp` its latest frame); `pick` is the
# selected item's key; `tris` and `cam` the 3D scene and camera; `shown`
# the source (Src.key) the scene belongs to; `busy` a status line; (px,
# py) where the pointer went down; `path` a file an agent asked to show
type Vx is Data:
  Vx{kind: U32, pick: String, tris: FA.Scene3, cam: MS.Cam, shown: String, busy: String, px: U32, py: U32, path: String, seen: String, bmp: BM.Bitmap}

# Viewer state (held by the window's state)
# ----------------------------------------

# the scene and its view; `root` is the project the scene belongs to;
# `base` caches the settled board drawn at `view` (valid while `fresh`)
# `cut` is when the base was drawn: the base holds exactly the items whose
# fade had ended by then; the rest are drawn over it every frame
type Vw is Data:
  Vw{scene: List<&2, Seen>, view: View, fitted: Bool, root: String, drag: Bool, lx: U32, ly: U32, base: Image, fresh: Bool, cut: Nat, x: Vx}

def Vx.init() -> Vx:
  Vx{0, "", FA.Scene3.none(), MS.Cam.at(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.8), "", "", 0, 0, "", "", BM.Bitmap{0, 0, 0n, Pix{0}, 0, 0, 0, 0}}

def Vw.init() -> Vw:
  Vw{Nil{}, View{1.0, 0.0, 0.0}, False{}, "", False{}, 0, 0, Pix{0}, False{}, 0n, Vx.init()}

# the source a scene comes from: kind, project root and an explicit path
def Src.key(+kind: U32, +root: String, +path: String) -> String:
  U32.show(kind) ++ "|" ++ root ++ "|" ++ path

# whether an item belongs in a base drawn at `cut`
def Vw.settled(+born: Nat, +cut: Nat) -> Bool:
  Nat.is_le(Nat.add(born, Fade.ms()), cut)

# Picking
# -------
# A click picks the smallest visible item under the pointer (a pad over
# the zone it sits in); tol is a few pixels in mm.

def Pick.d2(+ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  F32.add(F32.mul(F32.sub(ax, bx), F32.sub(ax, bx)), F32.mul(F32.sub(ay, by), F32.sub(ay, by)))

# distance from (x, y) to the segment a-b
def Pick.seg(a: B.Pt, b: B.Pt, +x: F32, +y: F32) -> F32:
  match a b:
    case B.Pt{+ax, +ay} B.Pt{+bx, +by}:
      +dx = F32.sub(bx, ax)
      +dy = F32.sub(by, ay)
      +l2 = F32.max(F32.add(F32.mul(dx, dx), F32.mul(dy, dy)), 0.000001)
      +t = F32.max(0.0, F32.min(1.0, F32.div(F32.add(F32.mul(F32.sub(x, ax), dx), F32.mul(F32.sub(y, ay), dy)), l2)))
      F32.sqrt(Pick.d2(x, y, F32.add(ax, F32.mul(t, dx)), F32.add(ay, F32.mul(t, dy))))

def Pick.path(ps: List<&2, B.Pt>, +x: F32, +y: F32, +acc: F32) -> F32:
  match ps:
    case +a <> +b <> t:
      Pick.path(b <> t, x, y, F32.min(acc, Pick.seg(a, b, x, y)))
    case _:
      acc

def Pick.inside(b: D.Box, +x: F32, +y: F32) -> Bool:
  match b:
    case D.Box{x0, y0, x1, y1}:
      Bool.and(Bool.and(F32.is_ge(x, x0), F32.is_le(x, x1)), Bool.and(F32.is_ge(y, y0), F32.is_le(y, y1)))

def Pick.area(b: D.Box) -> F32:
  match b:
    case D.Box{x0, y0, x1, y1}:
      F32.mul(F32.max(F32.sub(x1, x0), 0.01), F32.max(F32.sub(y1, y0), 0.01))

def Pick.big() -> D.Box:
  D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}

# a prim's extent in mm, strokes included
def Cull.box(p: B.Prim) -> D.Box:
  match p:
    case B.PSeg{a, e, +w}:
      Cull.pt(e, F32.mul(w, 0.5), Cull.pt(a, F32.mul(w, 0.5), Pick.big()))
    case B.PLine{ps, +w}:
      Cull.pts(ps, F32.mul(w, 0.5), Pick.big())
    case B.PCirc{c, +r, +w, _}:
      Cull.pt(c, F32.add(r, F32.mul(w, 0.5)), Pick.big())
    case B.PPoly{ps, +w, _}:
      Cull.pts(ps, F32.mul(w, 0.5), Pick.big())
    case B.PTint{ps, _, _}:
      Cull.pts(ps, 0.0, Pick.big())

def Cull.in(+p: B.Prim, +v: View, +c: D.Clip) -> Bool:
  Cull.meets(Cull.box(p), v, c)

def Ops.cull(on: Bool, +p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, +kind: U32, +flip: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      Ops.pick(Cull.in(p, v, c), p, layer, v, c, fade, kind, flip, rest)
    case False{}:
      rest

def Ops.gate(keep: Bool, +p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +now: Nat, +born: Nat, +kind: U32, +flip: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match keep:
    case True{}:
      Ops.cull(Bool.and(Look.shows(kind, layer, flip), Nat.is_lt(U32.to_nat(layer), Look.count(kind))), p, layer, v, c, Fade.alpha(now, born), kind, flip, rest)
    case False{}:
      rest

# the scene's ops in paint order (it is kept that way): those in a base
# drawn at `cut` when `base` is set, the others when it is not; layers
# past the kind's count, hidden layers and items off the panel make none.
# The cheap test (base or not) comes first, so a settled scene's overlay
# costs one comparison per item.
# (lift: the one layer drawn apart, LY.Lyr.lift: 255 none)
def Ops.scene.k(ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32, +flip: U32, +lift: U32) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{B.Item{_, _, +l, +p, _}, +b} <> t:
      Ops.gate(Bool.and(Bool.not(Bool.xor(base, Vw.settled(b, cut))), LY.Lyr.lift.ok(lift, l)), p, l, v, c, now, b, kind, flip,
        Ops.scene.k(t, v, c, now, cut, base, kind, flip, lift))

def Ops.scene.two(on: Bool, +ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32, +flip: U32) -> List<&2, R.Op>:
  match on:
    case True{}:
      List.append(&2, R.Op, Ops.scene.k(ss, v, c, now, cut, base, kind, flip, LY.Lyr.lift.under(LY.Lyr.kind.focus(kind))),
        Ops.scene.k(ss, v, c, now, cut, base, kind, flip, LY.Lyr.lift.over(LY.Lyr.kind.focus(kind))))
    case False{}:
      Ops.scene.k(ss, v, c, now, cut, base, kind, flip, LY.Lyr.lift.none())

# the scene's ops in paint order; under a focus (core/layers.bend) the
# active layer after all the others, as KiCad draws it on top
def Ops.scene(+ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32, +flip: U32) -> List<&2, R.Op>:
  Ops.scene.two(LY.Lyr.on(LY.Lyr.kind.focus(kind)), ss, v, c, now, cut, base, kind, flip)

def Pick.circ(c: B.Pt, +r: F32) -> D.Box:
  match c:
    case B.Pt{+x, +y}:
      D.Box{F32.sub(x, r), F32.sub(y, r), F32.add(x, r), F32.add(y, r)}

# whether the prim is under (x, y), and its size (for the smallest-wins rule)
def Pick.hit(p: B.Prim, +x: F32, +y: F32, +tol: F32) -> Bool & F32:
  match p:
    case B.PSeg{+a, +b, +w}:
      (F32.is_le(Pick.seg(a, b, x, y), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pt(b, View.box.pt(a, Pick.big()))))
    case B.PLine{+ps, +w}:
      (F32.is_le(Pick.path(ps, x, y, 1000000.0), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pts(ps, Pick.big())))
    case B.PCirc{B.Pt{+cx, +cy}, +r, +w, True{}}:
      (F32.is_le(F32.sqrt(Pick.d2(x, y, cx, cy)), F32.add(r, tol)), F32.mul(F32.mul(r, r), 4.0))
    case B.PCirc{B.Pt{+cx, +cy}, +r, +w, False{}}:
      (F32.is_le(F32.abs(F32.sub(F32.sqrt(Pick.d2(x, y, cx, cy)), r)), F32.add(F32.mul(w, 0.5), tol)), F32.mul(F32.mul(r, r), 4.0))
    case B.PPoly{+ps, _, True{}}:
      (Pick.inside(View.box.pts(ps, Pick.big()), x, y), Pick.area(View.box.pts(ps, Pick.big())))
    case B.PPoly{+ps, +w, False{}}:
      (F32.is_le(Pick.path(ps, x, y, 1000000.0), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pts(ps, Pick.big())))
    case B.PTint{+ps, _, _}:
      (Pick.inside(View.box.pts(ps, Pick.big()), x, y), Pick.area(View.box.pts(ps, Pick.big())))

def Pick.better.k(take: Bool, +key: String, +area: F32, bk: String, +ba: F32) -> String & F32:
  match take:
    case True{}:
      (key, area)
    case False{}:
      (bk, ba)

def Pick.better(r: Bool & F32, +shown: Bool, +key: String, best: String & F32) -> String & F32:
  (hit, +area) = r
  (bk, +ba) = best
  Pick.better.k(Bool.and(Bool.and(hit, shown), F32.is_lt(area, ba)), key, area, bk, ba)

def Pick.go(ss: List<&2, Seen>, +x: F32, +y: F32, +tol: F32, +kind: U32, +flip: U32, best: String & F32) -> String & F32:
  match ss:
    case Nil{}:
      best
    case Seen{B.Item{+k, _, +l, p, _}, _} <> t:
      Pick.go(t, x, y, tol, kind, flip, Pick.better(Pick.hit(p, x, y, tol), Look.shows(kind, l, flip), k, best))

def Pick.key(r: String & F32) -> String:
  (k, _) = r
  k

# the key of the item under screen point (sx, sy), "" for none
def Pick.at(+ss: List<&2, Seen>, v: View, +sx: F32, +sy: F32, +kind: U32, +flip: U32) -> String:
  match v:
    case View{+z, +ox, +oy}:
      Pick.key(Pick.go(ss, F32.div(F32.sub(sx, ox), z), F32.div(F32.sub(sy, oy), z), F32.div(4.0, z), kind, flip, ("", 1000000000000.0)))

# the picked item's info ("" when it is gone)
def Pick.info(ss: List<&2, Seen>, +key: String) -> String:
  match ss:
    case Nil{}:
      ""
    case Seen{B.Item{+k, _, _, _, info}, _} <> t:
      Bool.pick(String, String.eq(k, key), info, Pick.info(t, key))

# (a match: only the picked item's ops are made, not every item's)
def Ops.picked.k(hit: Bool, p: B.Prim, +v: View, +c: D.Clip, +flip: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match hit:
    case True{}:
      Ops.prim(p, v, c, Bool.pick(U32, Look.light(flip), 0, 16777215), 200)
    case False{}:
      rest

# the picked item drawn again on top, bright (dark on the light ground)
def Ops.picked(ss: List<&2, Seen>, +key: String, +v: View, +c: D.Clip, +flip: U32) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{B.Item{+k, _, _, p, _}, _} <> t:
      Ops.picked.k(String.eq(k, key), p, v, c, flip, Ops.picked(t, key, v, c, flip))

# some item's fade ended after the base was drawn: fold it into the base
def Vw.late(ss: List<&2, Seen>, +cut: Nat, +now: Nat) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{_, +b} <> t:
      Bool.or(Bool.and(Bool.not(Vw.settled(b, cut)), Vw.settled(b, now)), Vw.late(t, cut, now))
