import Base
import ./utf8.bend as U8

# QR codes (ISO/IEC 18004), for pairing a phone: the hub's pairing link as
# a code the phone's camera reads. Byte mode, error correction level M,
# the smallest of versions 1-40 that holds the text; the mask with the
# least penalty. A code is its rows, '1' dark and '0' light, joined by
# newlines (no quiet zone: whoever draws it leaves four modules around).

# Versions
# --------

# one version's blocks at level M: error correction codewords per block,
# blocks of d data codewords, blocks of d + 1
type QrV is Data:
  QrV{ec: U32, n1: U32, d: U32, n2: U32}

def Qr.table() -> List<&2, QrV>:
  [QrV{10, 1, 16, 0}, QrV{16, 1, 28, 0}, QrV{26, 1, 44, 0}, QrV{18, 2, 32, 0}, QrV{24, 2, 43, 0},
   QrV{16, 4, 27, 0}, QrV{18, 4, 31, 0}, QrV{22, 2, 38, 2}, QrV{22, 3, 36, 2}, QrV{26, 4, 43, 1},
   QrV{30, 1, 50, 4}, QrV{22, 6, 36, 2}, QrV{22, 8, 37, 1}, QrV{24, 4, 40, 5}, QrV{24, 5, 41, 5},
   QrV{28, 7, 45, 3}, QrV{28, 10, 46, 1}, QrV{26, 9, 43, 4}, QrV{26, 3, 44, 11}, QrV{26, 3, 41, 13},
   QrV{26, 17, 42, 0}, QrV{28, 17, 46, 0}, QrV{28, 4, 47, 14}, QrV{28, 6, 45, 14}, QrV{28, 8, 47, 13},
   QrV{28, 19, 46, 4}, QrV{28, 22, 45, 3}, QrV{28, 3, 45, 23}, QrV{28, 21, 45, 7}, QrV{28, 19, 47, 10},
   QrV{28, 2, 46, 29}, QrV{28, 10, 46, 23}, QrV{28, 14, 46, 21}, QrV{28, 14, 46, 23}, QrV{28, 12, 47, 26},
   QrV{28, 6, 47, 34}, QrV{28, 29, 46, 14}, QrV{28, 13, 46, 32}, QrV{28, 40, 47, 7}, QrV{28, 18, 47, 31}]

def Qr.row(+v: U32) -> QrV:
  Maybe.default(&2, QrV, List.get(&2, QrV, Qr.table(), U32.to_nat((v - 1 : U32))), QrV{10, 1, 16, 0})

# data codewords a version holds
def Qr.cap.of(r: QrV) -> U32:
  match r:
    case QrV{_, +n1, +d, +n2}:
      ((n1 * d : U32) + (n2 * (d + 1 : U32) : U32) : U32)

def Qr.cap(+v: U32) -> U32:
  Qr.cap.of(Qr.row(v))

# bits of the byte count: 8 up to version 9, then 16
def Qr.cc(+v: U32) -> U32:
  Bool.pick(U32, U32.is_le(v, 9), 8, 16)

def Qr.fits(+v: U32, +len: U32) -> Bool:
  U32.is_le(((4 + Qr.cc(v) : U32) + (len * 8 : U32) : U32), (Qr.cap(v) * 8 : U32))

def Qr.fit.k(k: Nat, ok: Bool, +v: U32, +len: U32) -> U32:
  match k ok:
    case _ True{}:
      v
    case 0n False{}:
      0
    case 1n+r False{}:
      Qr.fit.k(r, Qr.fits((v + 1 : U32), len), (v + 1 : U32), len)

# the smallest version that holds len bytes, 0 for none
def Qr.version(+len: U32) -> U32:
  Qr.fit.k(40n, Qr.fits(1, len), 1, len)

def Qr.size(+v: U32) -> U32:
  (17 + (v * 4 : U32) : U32)

# Bits
# ----

def Qr.bit(+x: U32, +i: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(x, U32.to_nat(i)), 1), 1)

# x's low n bits, the highest first, onto rest
def Qr.bits(n: Nat, +x: U32, rest: List<&2, Bool>) -> List<&2, Bool>:
  match n:
    case 0n:
      rest
    case 1n+k:
      Qr.bits(k, U32.shr(x), U32.is_eq(U32.and(x, 1), 1) <> rest)

def Qr.bytes.go(bs: List<&2, U32>, acc: List<&2, Bool>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      acc
    case +b <> t:
      Qr.bytes.go(t, List.append(&2, Bool, List.reverse(&2, Bool, Qr.bits(8n, b, Nil{})), acc))

# bytes as bits, the highest of each first
def Qr.bytes(bs: List<&2, U32>) -> List<&2, Bool>:
  List.reverse(&2, Bool, Qr.bytes.go(bs, Nil{}))

# packing: bits in the byte so far, the byte, the bytes done (reversed)
type Pk is Data:
  Pk{n: U32, cur: U32, out: List<&2, U32>}

def Qr.pack.step(+b: Bool, p: Pk) -> Pk:
  match p:
    case Pk{+n, +cur, +out}:
      +c = {U32.or(U32.shln(cur, 1n), Bool.pick(U32, b, 1, 0)) : U32}
      Bool.pick(Pk, U32.is_eq(n, 7), Pk{0, 0, c <> out}, Pk{(n + 1 : U32), c, out})

def Qr.pack.end(p: Pk) -> List<&2, U32>:
  match p:
    case Pk{+n, +cur, +out}:
      Bool.pick(List<&2, U32>, U32.is_eq(n, 0), out, U32.and(U32.shln(cur, U32.to_nat((8 - n : U32))), 255) <> out)

def Qr.pack.go(bs: List<&2, Bool>, p: Pk) -> Pk:
  match bs:
    case Nil{}:
      p
    case +b <> t:
      Qr.pack.go(t, Qr.pack.step(b, p))

# bits to bytes, a short last byte filled with zeros
def Qr.pack(bs: List<&2, Bool>) -> List<&2, U32>:
  List.reverse(&2, U32, Qr.pack.end(Qr.pack.go(bs, Pk{0, 0, Nil{}})))

def Qr.pad.go(n: Nat, +odd: Bool, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+k:
      Qr.pad.go(k, Bool.not(odd), Bool.pick(U32, odd, 17, 236) <> acc)

# the data codewords: mode 0100, the count, the bytes, up to four zero
# bits, then 236 and 17 in turn up to the version's capacity
def Qr.data(+v: U32, +bs: List<&2, U32>) -> List<&2, U32>:
  +len = {U32.from_nat(List.length(&2, U32, bs)) : U32}
  +used = {((4 + Qr.cc(v) : U32) + (len * 8 : U32) : U32) : U32}
  +room = {((Qr.cap(v) * 8 : U32) - used : U32) : U32}
  +head = {Qr.bits(4n, 4, Qr.bits(U32.to_nat(Qr.cc(v)), len, Nil{})) : List<&2, Bool>}
  +all = {List.append(&2, Bool, head, List.append(&2, Bool, Qr.bytes(bs), List.replicate(Bool, U32.to_nat(U32.min(room, 4)), False{}))) : List<&2, Bool>}
  +cw = {Qr.pack(all) : List<&2, U32>}
  List.append(&2, U32, cw, List.reverse(&2, U32, Qr.pad.go(Nat.sub(U32.to_nat(Qr.cap(v)), List.length(&2, U32, cw)), False{}, Nil{})))

# Reed-Solomon
# ------------

def Qr.gmul.go(k: Nat, +a: U32, +b: U32, +r: U32) -> U32:
  match k:
    case 0n:
      r
    case 1n+n:
      +a2 = {U32.shln(a, 1n) : U32}
      Qr.gmul.go(n, Bool.pick(U32, U32.is_eq(U32.and(a2, 256), 256), U32.xor(a2, 285), a2), U32.shr(b), Bool.pick(U32, U32.is_eq(U32.and(b, 1), 1), U32.xor(r, a), r))

# a times b in GF(256) over x^8 + x^4 + x^3 + x^2 + 1
def Qr.gmul(+a: U32, +b: U32) -> U32:
  Qr.gmul.go(8n, a, b, 0)

def Qr.scale(xs: List<&2, U32>, +f: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Qr.gmul(x, f) <> Qr.scale(t, f)

def Qr.xors(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs ys:
    case +x <> t +y <> u:
      U32.xor(x, y) <> Qr.xors(t, u)
    case _ _:
      Nil{}

def Qr.gen.go(k: Nat, +root: U32, +p: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      p
    case 1n+n:
      Qr.gen.go(n, Qr.gmul(root, 2), Qr.xors(List.append(&2, U32, p, [0]), 0 <> Qr.scale(p, root)))

# the generator of degree e, (x - 1)(x - 2)...(x - 2^(e-1)), its
# coefficients highest first without the leading 1
def Qr.gen(e: Nat) -> List<&2, U32>:
  List.drop(&2, U32, Qr.gen.go(e, 1, [1]), 1n)

def Qr.rs.step(rem: List<&2, U32>, +g: List<&2, U32>, +d: U32) -> List<&2, U32>:
  match rem:
    case Nil{}:
      Nil{}
    case +h <> t:
      Qr.xors(List.append(&2, U32, t, [0]), Qr.scale(g, U32.xor(d, h)))

def Qr.rs.go(ds: List<&2, U32>, +g: List<&2, U32>, rem: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}:
      rem
    case +d <> t:
      Qr.rs.go(t, g, Qr.rs.step(rem, g, d))

# a block's error correction codewords: the remainder of the block over g
def Qr.rs(ds: List<&2, U32>, +g: List<&2, U32>) -> List<&2, U32>:
  Qr.rs.go(ds, g, List.replicate(U32, List.length(&2, U32, g), 0))

# Blocks
# ------

def Qr.split(n: Nat, +size: Nat, +xs: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      acc
    case 1n+k:
      Qr.split(k, size, List.drop(&2, U32, xs, size), List.take(&2, U32, xs, size) <> acc)

# the data codewords in blocks: n1 of d, then n2 of d + 1
def Qr.blocks.of(r: QrV, +cw: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match r:
    case QrV{_, +n1, +d, +n2}:
      +k1 = {Nat.mul(U32.to_nat(n1), U32.to_nat(d)) : Nat}
      List.reverse(&2, List<&2, U32>, Qr.split(U32.to_nat(n2), U32.to_nat((d + 1 : U32)), List.drop(&2, U32, cw, k1),
        Qr.split(U32.to_nat(n1), U32.to_nat(d), cw, Nil{})))

def Qr.blocks(+v: U32, +cw: List<&2, U32>) -> List<&2, List<&2, U32>>:
  Qr.blocks.of(Qr.row(v), cw)

def Qr.eccs(bs: List<&2, List<&2, U32>>, +g: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      Qr.rs(b, g) <> Qr.eccs(t, g)

def Qr.head1(b: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      rest
    case +x <> _:
      x <> rest

def Qr.tail1(b: List<&2, U32>, rest: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match b:
    case Nil{}:
      rest
    case _ <> r:
      r <> rest

def Qr.heads(bs: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Qr.head1(b, Qr.heads(t))

def Qr.tails(bs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Qr.tail1(b, Qr.tails(t))

def Qr.weave.go(k: Nat, +bs: List<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      acc
    case 1n+n:
      Qr.weave.go(n, Qr.tails(bs), List.append(&2, U32, List.reverse(&2, U32, Qr.heads(bs)), acc))

# the blocks' first codewords, then their second, and so on
def Qr.weave(+bs: List<&2, List<&2, U32>>, +most: Nat) -> List<&2, U32>:
  List.reverse(&2, U32, Qr.weave.go(most, bs, Nil{}))

# every codeword in the order it is placed: data then error correction,
# each interleaved across the blocks
def Qr.codewords.of(r: QrV, +v: U32, +bs: List<&2, U32>) -> List<&2, U32>:
  match r:
    case QrV{+ec, _, +d, _}:
      +blocks = {Qr.blocks(v, Qr.data(v, bs)) : List<&2, List<&2, U32>>}
      List.append(&2, U32, Qr.weave(blocks, U32.to_nat((d + 1 : U32))), Qr.weave(Qr.eccs(blocks, Qr.gen(U32.to_nat(ec))), U32.to_nat(ec)))

def Qr.codewords(+v: U32, +bs: List<&2, U32>) -> List<&2, U32>:
  Qr.codewords.of(Qr.row(v), v, bs)

# Function patterns
# -----------------

def Qr.bch.go(k: Nat, +top: Nat, +poly: U32, +rem: U32) -> U32:
  match k:
    case 0n:
      rem
    case 1n+n:
      Qr.bch.go(n, top, poly, U32.xor(U32.shln(rem, 1n), Bool.pick(U32, Qr.bit(rem, U32.from_nat(top)), poly, 0)))

# the 15 format bits for level M (00) and a mask
def Qr.format(+m: U32) -> U32:
  U32.xor(U32.or(U32.shln(m, 10n), Qr.bch.go(10n, 9n, 1335, m)), 21522)

# the 18 version bits (versions 7 and up)
def Qr.vbits(+v: U32) -> U32:
  U32.or(U32.shln(v, 12n), Qr.bch.go(12n, 11n, 7973, v))

def Qr.aligns.go(k: Nat, +p: U32, +step: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      acc
    case 1n+n:
      Qr.aligns.go(n, (p - step : U32), step, p <> acc)

# the alignment patterns' centres along each axis
def Qr.aligns(+v: U32) -> List<&2, U32>:
  +n = {((v / 7 : U32) + 2 : U32) : U32}
  +step = {Bool.pick(U32, U32.is_eq(v, 32), 26, (((((v * 4 : U32) + (n * 2 : U32) : U32) + 1 : U32) / ((n * 2 : U32) - 2 : U32) : U32) * 2 : U32)) : U32}
  Bool.pick(List<&2, U32>, U32.is_eq(v, 1), Nil{}, 6 <> Qr.aligns.go(U32.to_nat((n - 1 : U32)), (Qr.size(v) - 7 : U32), step, Nil{}))

def Qr.dist(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), (a - b : U32), (b - a : U32))

# the centre in ps within two of x, or 0 (no centre is 0)
def Qr.near(ps: List<&2, U32>, +x: U32) -> U32:
  match ps:
    case Nil{}:
      0
    case +p <> t:
      Bool.pick(U32, U32.is_le(Qr.dist(p, x), 2), p, Qr.near(t, x))

# a module: fixed by a function pattern, or one of the data's
type Md is Data:
  Fix{dark: Bool}
  Dat{}

# what the code is drawn with: version, size, alignment centres, format
# and version bits
type Qc is Data:
  Qc{v: U32, s: U32, al: List<&2, U32>, fb: U32, vb: U32}

def Qc.s(+q: Qc) -> U32:
  match q:
    case Qc{_, +s, _, _, _}:
      s

def Qc.fb(+q: Qc) -> U32:
  match q:
    case Qc{_, _, _, +fb, _}:
      fb

# a finder (or its separator) centred at (cr, cc), else the format bit i
def Qr.finder(+r: U32, +c: U32, +cr: U32, +cc: U32, +fb: U32, +i: U32) -> Md:
  +d = {U32.max(Qr.dist(r, cr), Qr.dist(c, cc)) : U32}
  Bool.pick(Md, U32.is_le(d, 4), Fix{Bool.and(Bool.not(U32.is_eq(d, 2)), Bool.not(U32.is_eq(d, 4)))},
    Bool.pick(Md, Bool.or(U32.is_eq(r, 6), U32.is_eq(c, 6)), Fix{True{}}, Fix{Qr.bit(fb, i)}))

def Qr.tl.i(+r: U32, +c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 8), Bool.pick(U32, U32.is_lt(r, 6), r, (r - 1 : U32)), Bool.pick(U32, U32.is_eq(c, 7), 8, (14 - c : U32)))

def Qr.align(+r: U32, +c: U32, +s: U32, +al: List<&2, U32>) -> Md:
  +ar = {Qr.near(al, r) : U32}
  +ac = {Qr.near(al, c) : U32}
  +corner = {Bool.or(Bool.and(U32.is_eq(ar, 6), Bool.or(U32.is_eq(ac, 6), U32.is_eq(ac, (s - 7 : U32)))), Bool.and(U32.is_eq(ar, (s - 7 : U32)), U32.is_eq(ac, 6))) : Bool}
  Bool.pick(Md, Bool.or(Bool.or(U32.is_eq(ar, 0), U32.is_eq(ac, 0)), corner), Dat{},
    Fix{Bool.not(U32.is_eq(U32.max(Qr.dist(r, ar), Qr.dist(c, ac)), 1))})

def Qr.rest.k(ver: Bool, +r: U32, +c: U32, +q: Qc) -> Md:
  match ver q:
    case True{} Qc{_, +s, _, _, +vb}:
      Bool.pick(Md, U32.is_le(r, 5), Fix{Qr.bit(vb, (((r * 3 : U32) + c : U32) - (s - 11 : U32) : U32))}, Fix{Qr.bit(vb, (((c * 3 : U32) + r : U32) - (s - 11 : U32) : U32))})
    case False{} Qc{_, +s, +al, _, _}:
      Bool.pick(Md, U32.is_eq(r, 6), Fix{U32.is_eq(U32.and(c, 1), 0)}, Bool.pick(Md, U32.is_eq(c, 6), Fix{U32.is_eq(U32.and(r, 1), 0)}, Qr.align(r, c, s, al)))

# timing, version information, alignment, else data
def Qr.rest(+r: U32, +c: U32, +q: Qc) -> Md:
  match q:
    case Qc{+v, +s, +al, +fb, +vb}:
      +a = {Bool.and(U32.is_le(r, 5), Bool.and(U32.is_ge(c, (s - 11 : U32)), U32.is_le(c, (s - 9 : U32)))) : Bool}
      +b = {Bool.and(U32.is_le(c, 5), Bool.and(U32.is_ge(r, (s - 11 : U32)), U32.is_le(r, (s - 9 : U32)))) : Bool}
      Qr.rest.k(Bool.and(U32.is_ge(v, 7), Bool.or(a, b)), r, c, Qc{v, s, al, fb, vb})

def Qr.cell.k(tl: Bool, tr: Bool, bl: Bool, +r: U32, +c: U32, +q: Qc) -> Md:
  match tl tr bl:
    case True{} _ _:
      Qr.finder(r, c, 3, 3, Qc.fb(q), Qr.tl.i(r, c))
    case False{} True{} _:
      Qr.finder(r, c, 3, (Qc.s(q) - 4 : U32), Qc.fb(q), ((Qc.s(q) - 1 : U32) - c : U32))
    case False{} False{} True{}:
      Bool.pick(Md, Bool.and(U32.is_eq(r, (Qc.s(q) - 8 : U32)), U32.is_eq(c, 8)), Fix{True{}}, Qr.finder(r, c, (Qc.s(q) - 4 : U32), 3, Qc.fb(q), ((r + 15 : U32) - Qc.s(q) : U32)))
    case False{} False{} False{}:
      Qr.rest(r, c, q)

# the module at row r, column c
def Qr.cell(+r: U32, +c: U32, +q: Qc) -> Md:
  +top = {U32.is_le(r, 8) : Bool}
  +left = {U32.is_le(c, 8) : Bool}
  Qr.cell.k(Bool.and(top, left), Bool.and(top, U32.is_ge(c, (Qc.s(q) - 8 : U32))), Bool.and(left, U32.is_ge(r, (Qc.s(q) - 8 : U32))), r, c, q)

# Masks
# -----

def Qr.mask(+m: U32, +r: U32, +c: U32) -> Bool:
  +p = {(r * c : U32) : U32}
  +a = {((r + c : U32) % 2 : U32) : U32}
  Maybe.default(&2, Bool, List.get(&2, Bool, [
    U32.is_eq(a, 0),
    U32.is_eq((r % 2 : U32), 0),
    U32.is_eq((c % 3 : U32), 0),
    U32.is_eq(((r + c : U32) % 3 : U32), 0),
    U32.is_eq((((r / 2 : U32) + (c / 3 : U32) : U32) % 2 : U32), 0),
    U32.is_eq(((p % 2 : U32) + (p % 3 : U32) : U32), 0),
    U32.is_eq((((p % 2 : U32) + (p % 3 : U32) : U32) % 2 : U32), 0),
    U32.is_eq(((a + (p % 3 : U32) : U32) % 2 : U32), 0)], U32.to_nat(m)), False{})

# Placement
# ---------

# a module's colour and the data bits left after it
type Tk is Data:
  Tk{dark: Bool, rest: List<&2, Bool>}

def Qr.take.d(bs: List<&2, Bool>, +mk: Bool) -> Tk:
  match bs:
    case Nil{}:
      Tk{mk, Nil{}}
    case +b <> t:
      Tk{Bool.xor(b, mk), t}

def Qr.take(md: Md, +mk: Bool, bs: List<&2, Bool>) -> Tk:
  match md:
    case Fix{+d}:
      Tk{d, bs}
    case Dat{}:
      Qr.take.d(bs, mk)

# a column pair's walk: the right column's colours, the left's, the data
# bits left
type Wk is Data:
  Wk{rs: List<&2, Bool>, ls: List<&2, Bool>, bits: List<&2, Bool>}

def Qr.step.l(b: Tk, +da: Bool, rs: List<&2, Bool>, ls: List<&2, Bool>) -> Wk:
  match b:
    case Tk{+db, rest}:
      Wk{da <> rs, db <> ls, rest}

def Qr.step.k(a: Tk, +r: U32, +cl: U32, +m: U32, +q: Qc, rs: List<&2, Bool>, ls: List<&2, Bool>) -> Wk:
  match a:
    case Tk{+da, rest}:
      Qr.step.l(Qr.take(Qr.cell(r, cl, q), Qr.mask(m, r, cl), rest), da, rs, ls)

def Qr.step(+r: U32, +cr: U32, +m: U32, +q: Qc, w: Wk) -> Wk:
  match w:
    case Wk{rs, ls, bits}:
      Qr.step.k(Qr.take(Qr.cell(r, cr, q), Qr.mask(m, r, cr), bits), r, (cr - 1 : U32), m, q, rs, ls)

def Qr.pair.go(+k: Nat, +up: Bool, +s: U32, +cr: U32, +m: U32, +q: Qc, w: Wk) -> Wk:
  match k:
    case 0n:
      w
    case 1n+n:
      +r = {Bool.pick(U32, up, U32.from_nat(n), (s - U32.from_nat(1n+n) : U32)) : U32}
      Qr.pair.go(n, up, s, cr, m, q, Qr.step(r, cr, m, q, w))

# the columns built so far (left to right) and the data bits left
type Cols is Data:
  Cols{cols: List<&2, List<&2, Bool>>, bits: List<&2, Bool>}

def Qr.take.dark(md: Md) -> Bool:
  match md:
    case Fix{d}:
      d
    case Dat{}:
      False{}

def Qr.col6(+k: Nat, +q: Qc, acc: List<&2, Bool>) -> List<&2, Bool>:
  match k:
    case 0n:
      acc
    case 1n+n:
      Qr.col6(n, q, Qr.take.dark(Qr.cell(U32.from_nat(n), 6, q)) <> acc)

def Qr.pair.k(w: Wk, +up: Bool, +s: U32, +cr: U32, +q: Qc, cols: List<&2, List<&2, Bool>>) -> Cols:
  match w:
    case Wk{+rs, +ls, rest}:
      +rcol = {Bool.pick(List<&2, Bool>, up, rs, List.reverse(&2, Bool, rs)) : List<&2, Bool>}
      +lcol = {Bool.pick(List<&2, Bool>, up, ls, List.reverse(&2, Bool, ls)) : List<&2, Bool>}
      +more = {lcol <> rcol <> cols : List<&2, List<&2, Bool>>}
      Cols{Bool.pick(List<&2, List<&2, Bool>>, U32.is_eq(cr, 8), Qr.col6(U32.to_nat(s), q, Nil{}) <> more, more), rest}

# one column pair, right column cr, walked up or down by its place;
# column 6 (timing) comes in just left of the pair at 7 and 8
def Qr.pair(+s: U32, +cr: U32, +m: U32, +q: Qc, cs: Cols) -> Cols:
  match cs:
    case Cols{cols, bits}:
      +up = {U32.is_eq(U32.and((cr + 1 : U32), 2), 0) : Bool}
      Qr.pair.k(Qr.pair.go(U32.to_nat(s), up, s, cr, m, q, Wk{Nil{}, Nil{}, bits}), up, s, cr, q, cols)

def Qr.pairs(+k: Nat, +s: U32, +m: U32, +q: Qc, cs: Cols) -> Cols:
  match k:
    case 0n:
      cs
    case 1n+n:
      +i = {U32.from_nat(n) : U32}
      +cr = {Bool.pick(U32, U32.is_ge(i, 3), (8 + ((i - 3 : U32) * 2 : U32) : U32), (1 + (i * 2 : U32) : U32)) : U32}
      Qr.pairs(n, s, m, q, Qr.pair(s, cr, m, q, cs))

# Matrices
# --------

def Qr.first1(b: List<&2, Bool>, rest: List<&2, Bool>) -> List<&2, Bool>:
  match b:
    case Nil{}:
      rest
    case +x <> _:
      x <> rest

def Qr.rest1(b: List<&2, Bool>, rest: List<&2, List<&2, Bool>>) -> List<&2, List<&2, Bool>>:
  match b:
    case Nil{}:
      rest
    case _ <> r:
      r <> rest

def Qr.firsts(cs: List<&2, List<&2, Bool>>) -> List<&2, Bool>:
  match cs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Qr.first1(b, Qr.firsts(t))

def Qr.rests(cs: List<&2, List<&2, Bool>>) -> List<&2, List<&2, Bool>>:
  match cs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Qr.rest1(b, Qr.rests(t))

def Qr.flip.go(k: Nat, +cs: List<&2, List<&2, Bool>>, acc: List<&2, List<&2, Bool>>) -> List<&2, List<&2, Bool>>:
  match k:
    case 0n:
      List.reverse(&2, List<&2, Bool>, acc)
    case 1n+n:
      Qr.flip.go(n, Qr.rests(cs), Qr.firsts(cs) <> acc)

# columns to rows
def Qr.flip(+n: Nat, +cs: List<&2, List<&2, Bool>>) -> List<&2, List<&2, Bool>>:
  Qr.flip.go(n, cs, Nil{})

def Qr.cols.of(c: Cols) -> List<&2, List<&2, Bool>>:
  match c:
    case Cols{cols, _}:
      cols

# the code's columns, left to right, with mask m
def Qr.columns(+v: U32, +m: U32, +bits: List<&2, Bool>) -> List<&2, List<&2, Bool>>:
  +s = {Qr.size(v) : U32}
  +q = {Qc{v, s, Qr.aligns(v), Qr.format(m), Qr.vbits(v)} : Qc}
  Qr.cols.of(Qr.pairs(U32.to_nat(((s - 1 : U32) / 2 : U32)), s, m, q, Cols{Nil{}, bits}))

# Penalty
# -------

def Qr.same(+a: Bool, +b: Bool) -> Bool:
  Bool.not(Bool.xor(a, b))

# runs of five or more alike: 3, and 1 for each beyond five
def Qr.run.end(+n: U32, +acc: U32) -> U32:
  Bool.pick(U32, U32.is_ge(n, 5), ((acc + n : U32) - 2 : U32), acc)

# a run walk: the colour, its length so far, the penalty so far
type Rn is Data:
  Rn{cur: Bool, n: U32, acc: U32}

def Qr.run.step(+x: Bool, r: Rn) -> Rn:
  match r:
    case Rn{+cur, +n, +acc}:
      Bool.pick(Rn, Qr.same(x, cur), Rn{cur, (n + 1 : U32), acc}, Rn{x, 1, Qr.run.end(n, acc)})

def Qr.run.fin(r: Rn) -> U32:
  match r:
    case Rn{_, +n, +acc}:
      Qr.run.end(n, acc)

def Qr.runs.go(xs: List<&2, Bool>, r: Rn) -> U32:
  match xs:
    case Nil{}:
      Qr.run.fin(r)
    case +x <> t:
      Qr.runs.go(t, Qr.run.step(x, r))

def Qr.runs(xs: List<&2, Bool>) -> U32:
  match xs:
    case Nil{}:
      0
    case +x <> t:
      Qr.runs.go(t, Rn{x, 1, 0})

# finder-like stretches, 1011101 with four light on either side: 40 each
def Qr.finds.go(xs: List<&2, Bool>, +h: U32, +n: U32, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case +x <> t:
      +h2 = {U32.and(U32.or(U32.shln(h, 1n), Bool.pick(U32, x, 1, 0)), 2047) : U32}
      +hit = {Bool.and(U32.is_ge(n, 10), Bool.or(U32.is_eq(h2, 1488), U32.is_eq(h2, 93))) : Bool}
      Qr.finds.go(t, h2, (n + 1 : U32), Bool.pick(U32, hit, (acc + 40 : U32), acc))

def Qr.darks(xs: List<&2, Bool>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case +x <> t:
      Qr.darks(t, Bool.pick(U32, x, (acc + 1 : U32), acc))

# 2x2 blocks alike: 3 each
def Qr.boxes.go(a: List<&2, Bool>, b: List<&2, Bool>, +pa: Bool, +pb: Bool, +acc: U32) -> U32:
  match a b:
    case +x <> t +y <> u:
      +hit = {Bool.and(Qr.same(x, y), Bool.and(Qr.same(x, pa), Qr.same(x, pb))) : Bool}
      Qr.boxes.go(t, u, x, y, Bool.pick(U32, hit, (acc + 3 : U32), acc))
    case _ _:
      acc

def Qr.boxes(a: List<&2, Bool>, b: List<&2, Bool>) -> U32:
  match a b:
    case +x <> t +y <> u:
      Qr.boxes.go(t, u, x, y, 0)
    case _ _:
      0

def Qr.lines(ls: List<&2, List<&2, Bool>>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Qr.lines(t, ((acc + Qr.runs(l) : U32) + Qr.finds.go(l, 0, 0, 0) : U32))

def Qr.pairs.box(ls: List<&2, List<&2, Bool>>, +prev: List<&2, Bool>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Qr.pairs.box(t, l, (acc + Qr.boxes(prev, l) : U32))

def Qr.dark.all(ls: List<&2, List<&2, Bool>>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Qr.dark.all(t, Qr.darks(l, acc))

# the four penalty rules over a code's columns and rows
def Qr.penalty(+cols: List<&2, List<&2, Bool>>, +rows: List<&2, List<&2, Bool>>, +s: U32) -> U32:
  +total = {(s * s : U32) : U32}
  +pct = {((Qr.dark.all(rows, 0) * 100 : U32) / total : U32) : U32}
  ((Qr.lines(rows, 0) + Qr.lines(cols, 0) : U32) + (Qr.pairs.box(rows, Nil{}, 0) + ((Qr.dist(pct, 50) / 5 : U32) * 10 : U32) : U32) : U32)

# Codes
# -----

# a candidate: its mask's rows and penalty
type Qm is Data:
  Qm{score: U32, rows: List<&2, List<&2, Bool>>}

def Qr.try(+v: U32, +m: U32, +bits: List<&2, Bool>) -> Qm:
  +cols = {Qr.columns(v, m, bits) : List<&2, List<&2, Bool>>}
  +rows = {Qr.flip(U32.to_nat(Qr.size(v)), cols) : List<&2, List<&2, Bool>>}
  Qm{Qr.penalty(cols, rows, Qr.size(v)), rows}

def Qr.better(a: Qm, b: Qm) -> Qm:
  match a b:
    case Qm{+sa, ra} Qm{+sb, rb}:
      Bool.pick(Qm, U32.is_le(sa, sb), Qm{sa, ra}, Qm{sb, rb})

def Qr.best(+k: Nat, +v: U32, +bits: List<&2, Bool>, best: Qm) -> Qm:
  match k:
    case 0n:
      best
    case 1n+n:
      Qr.best(n, v, bits, Qr.better(Qr.try(v, U32.from_nat(n), bits), best))

def Qr.line(xs: List<&2, Bool>) -> String:
  match xs:
    case Nil{}:
      ""
    case +x <> t:
      SCon{Bool.pick(Char, x, '1', '0'), Qr.line(t)}

def Qr.show(ls: List<&2, List<&2, Bool>>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Qr.line(l) <> Qr.show(t)

def Qr.shown(q: Qm) -> List<&2, String>:
  match q:
    case Qm{_, rows}:
      Qr.show(rows)

def Qr.code.m(+m: Maybe<&2, U32>, +v: U32, +bits: List<&2, Bool>) -> List<&2, String>:
  match m:
    case Some{+k}:
      Qr.shown(Qr.try(v, k, bits))
    case None{}:
      Qr.shown(Qr.best(7n, v, bits, Qr.try(v, 7, bits)))

def Qr.code.v(+v: U32, +bs: List<&2, U32>, +m: Maybe<&2, U32>) -> List<&2, String>:
  Qr.code.m(m, v, Qr.bytes(Qr.codewords(v, bs)))

def Qr.code.k(+v: U32, +bs: List<&2, U32>, +m: Maybe<&2, U32>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(v, 0), Nil{}, Qr.code.v(v, bs, m))

# the code for text with mask m (None: the best), its rows; none when the
# text is empty or too long for any version
def Qr.rows.with(+text: String, +m: Maybe<&2, U32>) -> List<&2, String>:
  +bs = {U8.Utf8.encode(text) : List<&2, U32>}
  Bool.pick(List<&2, String>, String.is_empty(text), Nil{}, Qr.code.k(Qr.version(U32.from_nat(List.length(&2, U32, bs))), bs, m))

def Qr.rows(+text: String) -> List<&2, String>:
  Qr.rows.with(text, None{})

# the code as one string, rows joined by newlines ("" for none)
def Qr.text(+text: String) -> String:
  String.join(Qr.rows(text), "\n")

# Pairing
# -------

def Qr.hex(+x: U32) -> Char:
  Bool.pick(Char, U32.is_lt(x, 10), Chr{(x + 48 : U32)}, Chr{(x + 55 : U32)})

def Qr.esc.c(+c: U32) -> String:
  +plain = {Bool.or(Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 47), U32.is_le(c, 58)), Bool.or(Bool.or(U32.is_eq(c, 45), U32.is_eq(c, 46)), Bool.or(U32.is_eq(c, 61), Bool.or(U32.is_eq(c, 95), U32.is_eq(c, 126)))))) : Bool}
  Bool.pick(String, plain, SCon{Chr{c}, ""}, SCon{'%', SCon{Qr.hex(U32.shrn(c, 4n)), SCon{Qr.hex(U32.and(c, 15)), ""}}})

def Qr.esc(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case +b <> t:
      Qr.esc.c(b) ++ Qr.esc(t)

# what the pairing code says: the app's own link (a phone's camera opens
# the app with it), carrying the hub's pairing link
def Qr.link(+link: String) -> String:
  Bool.pick(String, String.is_empty(link), "", "backplane://pair?url=" ++ Qr.esc(U8.Utf8.encode(link)))

# SVG
# ---

def Qr.path.run(+on: Bool, +start: U32, +x: U32, +y: U32) -> String:
  Bool.pick(String, Bool.and(on, U32.is_gt(x, start)), "M" ++ U32.show(start) ++ " " ++ U32.show(y) ++ "h" ++ U32.show((x - start : U32)) ++ "v1h-" ++ U32.show((x - start : U32)) ++ "z", "")

def Qr.path.row(s: String, +x: U32, +y: U32, +start: U32, +on: Bool) -> String:
  match s:
    case SNil{}:
      Qr.path.run(on, start, x, y)
    case SCon{Chr{+c}, t}:
      +d = {U32.is_eq(c, 49) : Bool}
      Bool.pick(String, Qr.same(d, on), "", Qr.path.run(on, start, x, y)) ++ Qr.path.row(t, (x + 1 : U32), y, Bool.pick(U32, Qr.same(d, on), start, x), d)

def Qr.path.go(rs: List<&2, String>, +y: U32) -> String:
  match rs:
    case Nil{}:
      ""
    case r <> t:
      Qr.path.row(r, 4, y, 4, False{}) ++ Qr.path.go(t, (y + 1 : U32))

# the dark modules as SVG path data, each row's runs one box, inside a
# four-module quiet zone (the view box is the size plus eight)
def Qr.path(rs: List<&2, String>) -> String:
  Qr.path.go(rs, 4)
