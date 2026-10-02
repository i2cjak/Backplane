import Base
import ../core/json.bend as J
import ./dom.bend as D
import ../core/client.bend as U
import ./view.bend as V
import ../core/cbor.bend as C
import ../core/attach.bend as AT
import ../core/lightbox.bend as LB
import ./cat.bend as WC
import ../core/onboard.bend as OB

# What host.js calls. Everything the page decides happens behind these.

def init(now: Nat, cid: String) -> U.Ui:
  U.Ui.set_cid(U.Ui.init(now), cid)

# a draft this browser kept (Keep commands), read back at start
def restore(u: U.Ui, id: String, text: String) -> U.Ui:
  U.Ui.restore(u, id, text)

# a bot's browser has a new frame ({"t":"shot","bot":...,"n":...}): the
# Browser tab loads /bots/<bot>/screen.jpg?n=<n>
def recv.k(shot: Bool, u: U.Ui, +o: J.Json) -> U.Act:
  match shot:
    case True{}:
      U.Act{U.Ui.info_set(u, "shot." ++ J.Json.get_str(o, "bot", ""), J.Json.as_raw(J.Json.get(o, "n"), "")), Nil{}}
    case False{}:
      U.Ui.recv_act(u, o)

# a 3D model's note ({"t":"plotnote", key, text}: parts with no model),
# kept under its source's key for the 3D pane
# a schematic's sheets ({"t":"sheets", root, rows}: core/hier.bend's rows),
# kept under the project root for the Schematic tab's sheet chips
def recv.sheets(hit: Bool, u: U.Ui, +o: J.Json) -> U.Act:
  match hit:
    case True{}:
      U.Act{U.Ui.info_set(u, "sheets:" ++ J.Json.get_str(o, "root", ""), J.Json.get_str(o, "rows", "")), Nil{}}
    case False{}:
      recv.k(String.eq(J.Json.get_str(o, "t", ""), "shot"), u, o)

def recv.note(note: Bool, u: U.Ui, +o: J.Json) -> U.Act:
  match note:
    case True{}:
      U.Act{U.Ui.info_set(u, "plotnote:" ++ J.Json.get_str(o, "key", ""), J.Json.get_str(o, "text", "")), Nil{}}
    case False{}:
      recv.sheets(String.eq(J.Json.get_str(o, "t", ""), "sheets"), u, o)

# (the viewer asks the hub for its board, schematic or model when the
# source on screen changes)
def recv(u: U.Ui, +o: J.Json) -> U.Act:
  U.Solid.sync(recv.note(String.eq(J.Json.get_str(o, "t", ""), "plotnote"), u, o))

# a bot's cat for an <img data-cat="<look>:<mood>:<px>"> (host.js keeps
# each answer)
def cat(name: String) -> String:
  WC.WCat.uri(name)

# the page's own address (a webhook's URL starts with it)
def page(u: U.Ui, origin: String) -> U.Ui:
  U.Ui.scratch_set(u, "@page", origin)

# where a Connect goes: the other hub's page, carrying the bot to open
# there (U.Far.opened's "@bot.want") in the address's fragment
def visit(+u: U.Ui, +url: String) -> String:
  Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@bot.want")), url ++ "/", url ++ "/#bot=" ++ U.Ui.scratch(u, "@bot.want"))

# the page opened with "#bot=<name>" (decoded): that bot is shown once the
# log has it
def wanted(+u: U.Ui, +hash: String) -> U.Ui:
  Bool.pick(U.Ui, String.starts_with(hash, "#bot="), U.Want.bot(u, String.drop(hash, 5n)), u)

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Solid.sync(U.Ui.act(u, action, value))

def view(u: U.Ui) -> D.Node:
  V.View.page(u)

# this page is a desk (core/desk.bend): host.js calls this after input,
# focus and visibility changes; it answers the desk.look to send, when due
def desk(u: U.Ui, focused: Bool, now: Nat) -> U.Act:
  U.Ui.desk(u, focused, now)

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)

# how many changes this page holds and which log they came from (a
# reconnect asks the server for the rest)
def seq(u: U.Ui) -> String:
  Nat.show(U.Ui.seq(u))

def origin(u: U.Ui) -> String:
  U.Ui.info(u, "origin")

# The wire: CBOR bytes in and out (the host only moves them)
def wire_in(bs: List<&2, U32>) -> J.Json:
  Maybe.default(&2, J.Json, C.Cbor.decode(bs), J.Null{})

def wire_out(text: String) -> List<&2, U32>:
  C.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def show(j: J.Json) -> String:
  J.Json.show(j)

# whether a message can change the page (another thread's streamed text
# cannot: U.Ui.shows), and its kind ("log", "changes", "delta"...): the
# host renders and keeps the log only when these say so
def shows(+u: U.Ui, +o: J.Json) -> Bool:
  U.Ui.shows(u, o)

def kind(+j: J.Json) -> String:
  J.Json.get_str(j, "t", "")

# how many bytes of a file go in one upload piece
def chunk() -> String:
  Nat.show(AT.Att.chunk())

# the thread a file goes to (POST /attach), and what it is uploading
# ("attach-up" refused a file over the cap when it is not that file)
def sel(u: U.Ui) -> String:
  U.Ui.sel(u)

def uploading(u: U.Ui, thread: String) -> String:
  U.Ui.uploading(u, thread)

# the shortcuts the page takes for itself, comma-separated (in the
# terminal, and elsewhere)
def keys_term() -> String:
  String.join(U.Ui.keys(True{}), ",")

def keys_page() -> String:
  String.join(U.Ui.keys(False{}), ",")

# The image lightbox (core/lightbox.bend decides the zoom, the pan, the
# easing and what closes it; host.js feeds it pointer events and sets the
# style it answers on the picture)

def lb_node(url: String) -> D.Node:
  D.El{"div", "", [D.At{"class", "lightbox"}], [
    D.El{"img", "", [D.At{"class", "lb-img"}, D.At{"src", url}, D.At{"alt", ""}, D.At{"draggable", "false"}], Nil{}},
    D.El{"button", "", [D.At{"class", "lb-close"}, D.At{"title", "Close"}, D.At{"data-lb-close", "1"}], [D.Txt{"×"}]}]}

def lb_open() -> LB.Lb:
  LB.Lb.open()

def lb_box(iw: Nat, ih: Nat, vw: Nat, vh: Nat) -> LB.LbBox:
  LB.LbBox{iw, ih, vw, vh}

# a wheel turn (dy > 0 zooms out); a trackpad pinch comes as a ctrl wheel
# with small steps, applied at once and made larger
def lb_wheel(lb: LB.Lb, down: Bool, +mag: Nat, +pinch: Bool, cx: Nat, cy: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.wheel(lb, Bool.not(down), Bool.pick(Nat, pinch, Nat.mul(mag, 4n), mag), Bool.not(pinch), cx, cy, b, now)

def lb_pinch(lb: LB.Lb, d0: Nat, d1: Nat, cx: Nat, cy: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.pinch(lb, d0, d1, cx, cy, b, now)

def lb_press(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.press(lb, x, y, b, now)

def lb_move(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.move(lb, x, y, b, now)

def lb_release(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.release(lb, x, y, b, now)

def lb_closes(lb: LB.Lb, x: Nat, y: Nat) -> Bool:
  LB.Lb.closes(lb, x, y)

def lb_key(k: String) -> Bool:
  String.eq(k, "Escape")

def lb_stamp(lb: LB.Lb, now: Nat) -> LB.Lb:
  LB.Lb.stamp(lb, now)

def lb_busy(lb: LB.Lb, now: Nat) -> Bool:
  LB.Lb.busy(lb, now)

def lb_css(lb: LB.Lb, b: LB.LbBox, now: Nat) -> String:
  LB.Lb.css(lb, b, now)

# the tour's action for a key while its dialog is up ("" for any other)
def tour_key(key: String) -> String:
  OB.Ob.dom(key)
