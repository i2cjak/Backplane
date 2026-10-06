import Base
import ./json.bend as J
import ./sha1.bend as S
import ./utf8.bend as U

# Gmail and Google Calendar for bots, through Google's REST APIs (no
# browser). Pure: OAuth 2.0 for installed apps (PKCE, RFC 7636, with a
# loopback redirect), the request paths and bodies, and the summaries an
# agent reads. src/server/google.bend does the IO.

# URLs (RFC 3986)
# ---------------

# unreserved: A-Z a-z 0-9 - . _ ~
def Url.keep(+b: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(b, 65), U32.is_le(b, 90)), Bool.and(U32.is_ge(b, 97), U32.is_le(b, 122))),
    Bool.or(Bool.and(U32.is_ge(b, 48), U32.is_le(b, 57)),
      Bool.or(Bool.or(U32.is_eq(b, 45), U32.is_eq(b, 46)), Bool.or(U32.is_eq(b, 95), U32.is_eq(b, 126)))))

def Url.hexoff(lt: Bool) -> U32:
  match lt:
    case True{}:
      48
    case False{}:
      55

def Url.hexd(+n: U32) -> Char:
  Chr{(n + Url.hexoff(U32.is_lt(n, 10)) : U32)}

def Url.enc.put(keep: Bool, +b: U32, acc: String) -> String:
  match keep:
    case True{}:
      SCon{Chr{b}, acc}
    case False{}:
      SCon{Url.hexd(U32.and(b, 15)), SCon{Url.hexd(U32.and(U32.shrn(b, 4n), 15)), SCon{'%', acc}}}

def Url.enc.go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case +b <> t:
      Url.enc.go(t, Url.enc.put(Url.keep(b), b, acc))

# every byte of the UTF-8 text outside the unreserved set as %XX
def Url.encode(s: String) -> String:
  Url.enc.go(U.Utf8.encode(s), "")

# a hex digit's value, 16 when it is not one
def Hex.val.k(d: Bool, up: Bool, lo: Bool, +x: U32) -> U32:
  match d up lo:
    case True{} _ _:
      (x - 48 : U32)
    case False{} True{} _:
      (x - 55 : U32)
    case False{} False{} True{}:
      (x - 87 : U32)
    case False{} False{} False{}:
      16

def Hex.val(+x: U32) -> U32:
  Hex.val.k(Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)), Bool.and(U32.is_ge(x, 65), U32.is_le(x, 70)),
    Bool.and(U32.is_ge(x, 97), U32.is_le(x, 102)), x)

# percent-decoding as a walk over bytes: plain, after '%', after '%' and a digit
type Pd is Data:
  PdN{acc: List<&2, U32>}
  PdP{acc: List<&2, U32>}
  PdH{hi: U32, acc: List<&2, U32>}

def Pd.n(pct: Bool, plus: Bool, +x: U32, acc: List<&2, U32>) -> Pd:
  match pct plus:
    case True{} _:
      PdP{acc}
    case False{} True{}:
      PdN{32 <> acc}
    case False{} False{}:
      PdN{x <> acc}

def Pd.p(ok: Bool, +x: U32, acc: List<&2, U32>) -> Pd:
  match ok:
    case True{}:
      PdH{x, acc}
    case False{}:
      PdN{x <> 37 <> acc}

def Pd.h(ok: Bool, +hi: U32, +x: U32, acc: List<&2, U32>) -> Pd:
  match ok:
    case True{}:
      PdN{U32.or(U32.shln(Hex.val(hi), 4n), Hex.val(x)) <> acc}
    case False{}:
      PdN{x <> hi <> 37 <> acc}

def Pd.step(d: Pd, +x: U32) -> Pd:
  match d:
    case PdN{acc}:
      Pd.n(U32.is_eq(x, 37), U32.is_eq(x, 43), x, acc)
    case PdP{acc}:
      Pd.p(U32.is_lt(Hex.val(x), 16), x, acc)
    case PdH{+hi, acc}:
      Pd.h(U32.is_lt(Hex.val(x), 16), hi, x, acc)

def Pd.fin(d: Pd) -> List<&2, U32>:
  match d:
    case PdN{acc}:
      List.reverse(&2, U32, acc)
    case PdP{acc}:
      List.reverse(&2, U32, 37 <> acc)
    case PdH{hi, acc}:
      List.reverse(&2, U32, hi <> 37 <> acc)

def Pd.go(bs: List<&2, U32>, d: Pd) -> Pd:
  match bs:
    case Nil{}:
      d
    case +x <> t:
      Pd.go(t, Pd.step(d, x))

# %XX and '+' (a space, as forms write it) decoded; bytes read as UTF-8
def Url.decode(s: String) -> String:
  U.Utf8.decode(Pd.fin(Pd.go(U.Utf8.encode(s), PdN{Nil{}})))

def Url.after_q.k(t: List<&2, String>, h: String) -> String:
  match t:
    case Nil{}:
      h
    case a <> r:
      String.join(a <> r, "?")

def Url.after_q(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case h <> t:
      Url.after_q.k(t, h)

# the query of a URL (after the first '?', before '#'); the text itself
# when it has no '?'
def Url.query(s: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(Url.after_q(String.split(s, '?')), '#')), "")

def Url.param.take(+acc: String, +kv: String, +name: String) -> String:
  Bool.pick(String, Bool.and(String.is_empty(acc), String.starts_with(kv, name ++ "=")),
    Url.decode(String.drop(kv, 1n+String.length(name))), acc)

def Url.param.go(kvs: List<&2, String>, +name: String, +acc: String) -> String:
  match kvs:
    case Nil{}:
      acc
    case +kv <> t:
      Url.param.go(t, name, Url.param.take(acc, kv, name))

# a parameter of a query string, decoded ("" when absent)
def Url.param(q: String, +name: String) -> String:
  Url.param.go(String.split(q, '&'), name, "")

def Url.pair(+k: String, v: String) -> String:
  k ++ "=" ++ Url.encode(v)

# Base64 and base64url (RFC 4648)
# -------------------------------

def Gb64.url.k(plus: Bool, slash: Bool, pad: Bool, +c: U32, acc: String) -> String:
  match plus slash pad:
    case True{} _ _:
      SCon{'-', acc}
    case False{} True{} _:
      SCon{'_', acc}
    case False{} False{} True{}:
      acc
    case False{} False{} False{}:
      SCon{Chr{c}, acc}

def Gb64.url.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      Gb64.url.go(t, Gb64.url.k(U32.is_eq(c, 43), U32.is_eq(c, 47), U32.is_eq(c, 61), c, acc))

# base64url without padding: '-' and '_' for '+' and '/', no '='
def Gb64.encode_url(bs: List<&2, U32>) -> String:
  Gb64.url.go(S.B64.encode(bs), "")

# a character's six bits, either alphabet; 64 for anything else ('=',
# whitespace, junk), which the decoder skips
def Gb64.val.k(up: Bool, lo: Bool, dg: Bool, p: Bool, sl: Bool, +c: U32) -> U32:
  match up lo dg p sl:
    case True{} _ _ _ _:
      (c - 65 : U32)
    case False{} True{} _ _ _:
      (c - 71 : U32)
    case False{} False{} True{} _ _:
      (c + 4 : U32)
    case False{} False{} False{} True{} _:
      62
    case False{} False{} False{} False{} True{}:
      63
    case False{} False{} False{} False{} False{}:
      64

def Gb64.val(+c: U32) -> U32:
  Gb64.val.k(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)),
    Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.or(U32.is_eq(c, 43), U32.is_eq(c, 45)),
    Bool.or(U32.is_eq(c, 47), U32.is_eq(c, 95)), c)

# bits waiting (buf holds n of them, n < 8) and the bytes so far, reversed
type Bd is Data:
  Bd{buf: U32, n: U32, acc: List<&2, U32>}

def Gb64.mask(+k: U32) -> U32:
  (U32.shln(1, U32.to_nat(k)) - 1 : U32)

def Gb64.add(full: Bool, +buf: U32, +n: U32, acc: List<&2, U32>) -> Bd:
  match full:
    case True{}:
      Bd{U32.and(buf, Gb64.mask((n - 8 : U32))), (n - 8 : U32), U32.and(U32.shrn(buf, U32.to_nat((n - 8 : U32))), 255) <> acc}
    case False{}:
      Bd{buf, n, acc}

def Gb64.push(+v: U32, d: Bd) -> Bd:
  match d:
    case Bd{buf, +n, acc}:
      Gb64.add(U32.is_ge((n + 6 : U32), 8), U32.or(U32.shln(buf, 6n), v), (n + 6 : U32), acc)

def Gb64.put(skip: Bool, +v: U32, d: Bd) -> Bd:
  match skip:
    case True{}:
      d
    case False{}:
      Gb64.push(v, d)

def Gb64.step(+v: U32, d: Bd) -> Bd:
  Gb64.put(U32.is_ge(v, 64), v, d)

def Gb64.go(s: String, d: Bd) -> Bd:
  match s:
    case SNil{}:
      d
    case SCon{Chr{+c}, t}:
      Gb64.go(t, Gb64.step(Gb64.val(c), d))

def Gb64.fin(d: Bd) -> List<&2, U32>:
  match d:
    case Bd{_, _, acc}:
      List.reverse(&2, U32, acc)

# the bytes of base64 or base64url text, padded or not
def Gb64.decode(s: String) -> List<&2, U32>:
  Gb64.fin(Gb64.go(s, Bd{0, 0, Nil{}}))

# Text helpers
# ------------

def Str.lat.go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case b <> t:
      Str.lat.go(t, SCon{Chr{b}, acc})

# bytes as ISO-8859-1 (each byte its own code point)
def Str.latin1(bs: List<&2, U32>) -> String:
  Str.lat.go(bs, "")

def Str.chunks(fuel: Nat, +s: String, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+f:
      Str.chunks(f, String.drop(s, n), n, String.take(s, n) <> acc)

# s cut into pieces of n characters (the last may be shorter)
def Str.split_every(+s: String, +n: Nat) -> List<&2, String>:
  Str.chunks(Nat.div(Nat.add(String.length(s), Nat.sub(n, 1n)), n), s, n, Nil{})

def Str.nocr(+l: String) -> String:
  Bool.pick(String, String.ends_with(l, "\r"), String.take(l, Nat.sub(String.length(l), 1n)), l)

def Str.nocrs(ls: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +l <> t:
      Str.nocrs(t, Str.nocr(l) <> acc)

# the lines of a text, CRLF or LF, without their breaks
def Str.lines(s: String) -> List<&2, String>:
  Str.nocrs(String.split(s, '\n'), Nil{})

# at most n characters, with a note when cut
def Str.cap(+s: String, +n: Nat) -> String:
  Bool.pick(String, Nat.is_gt(String.length(s), n), String.take(s, n) ++ "\n[... truncated]", s)

def Str.or(+s: String, d: String) -> String:
  Bool.pick(String, String.is_empty(s), d, s)

# HTML to text
# ------------

# inside a tag, inside <style>/<script>, the tag so far (reversed), the text (reversed)
type Hs is Data:
  Hs{tag: Bool, skip: Bool, name: String, acc: String}

def Html.opens(+n: String) -> Bool:
  Bool.or(String.starts_with(n, "style"), String.starts_with(n, "script"))

def Html.closes(+n: String) -> Bool:
  Bool.or(String.starts_with(n, "/style"), String.starts_with(n, "/script"))

def Html.breaks(+n: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(n, "br"), String.starts_with(n, "/p")),
    Bool.or(Bool.or(String.starts_with(n, "/div"), String.starts_with(n, "/tr")),
      Bool.or(String.starts_with(n, "li"), Bool.or(String.starts_with(n, "/h"), String.starts_with(n, "p ")))))

def Html.nl(b: Bool, acc: String) -> String:
  match b:
    case True{}:
      SCon{'\n', acc}
    case False{}:
      acc

def Html.skip(o: Bool, c: Bool, skip: Bool) -> Bool:
  match o c:
    case True{} _:
      True{}
    case False{} True{}:
      False{}
    case False{} False{}:
      skip

def Html.close(+n: String, skip: Bool, acc: String) -> Hs:
  Hs{False{}, Html.skip(Html.opens(n), Html.closes(n), skip), "", Html.nl(Html.breaks(n), acc)}

def Html.text(lt: Bool, skip: Bool, c: Char, acc: String) -> Hs:
  match lt skip:
    case True{} _:
      Hs{True{}, skip, "", acc}
    case False{} True{}:
      Hs{False{}, True{}, "", acc}
    case False{} False{}:
      Hs{False{}, False{}, "", SCon{c, acc}}

def Html.intag(gt: Bool, skip: Bool, c: Char, name: String, acc: String) -> Hs:
  match gt:
    case True{}:
      Html.close(String.to_lower(String.trim(String.reverse(name))), skip, acc)
    case False{}:
      Hs{True{}, skip, SCon{c, name}, acc}

def Html.step(h: Hs, +c: U32) -> Hs:
  match h:
    case Hs{True{}, skip, name, acc}:
      Html.intag(U32.is_eq(c, 62), skip, Chr{c}, name, acc)
    case Hs{False{}, skip, _, acc}:
      Html.text(U32.is_eq(c, 60), skip, Chr{c}, acc)

def Html.go(s: String, h: Hs) -> Hs:
  match s:
    case SNil{}:
      h
    case SCon{Chr{+c}, t}:
      Html.go(t, Html.step(h, c))

def Html.fin(h: Hs) -> String:
  match h:
    case Hs{_, _, _, acc}:
      String.reverse(acc)

# entities: outside one, or inside with its name so far (reversed)
type Es is Data:
  Es{inside: Bool, name: String, acc: String}

def Ent.num(m: Maybe<&2, U32>, +raw: String) -> String:
  match m:
    case Some{n}:
      SCon{Chr{n}, SNil{}}
    case None{}:
      "&" ++ raw ++ ";"

def Ent.named(+n: String) -> String:
  Bool.pick(String, String.eq(n, "nbsp"), " ",
    Bool.pick(String, String.eq(n, "amp"), "&",
      Bool.pick(String, String.eq(n, "lt"), "<",
        Bool.pick(String, String.eq(n, "gt"), ">",
          Bool.pick(String, String.eq(n, "quot"), "\"",
            Bool.pick(String, Bool.or(String.eq(n, "apos"), String.eq(String.to_lower(n), "#x27")), "'",
              Bool.pick(String, String.starts_with(n, "#"), Ent.num(U32.read(String.drop(n, 1n)), n), "&" ++ n ++ ";")))))))

def Ent.close(+n: String, acc: String) -> Es:
  Es{False{}, "", String.reverse.go(Ent.named(n), acc)}

def Ent.in(semi: Bool, amp: Bool, long: Bool, c: Char, name: String, acc: String) -> Es:
  match semi amp long:
    case True{} _ _:
      Ent.close(String.reverse(name), acc)
    case False{} True{} _:
      Es{True{}, "", String.reverse.go(String.reverse(name), SCon{'&', acc})}
    case False{} False{} True{}:
      Es{False{}, "", SCon{c, String.reverse.go(String.reverse(name), SCon{'&', acc})}}
    case False{} False{} False{}:
      Es{True{}, SCon{c, name}, acc}

def Ent.out(amp: Bool, c: Char, acc: String) -> Es:
  match amp:
    case True{}:
      Es{True{}, "", acc}
    case False{}:
      Es{False{}, "", SCon{c, acc}}

def Ent.step(e: Es, +c: U32) -> Es:
  match e:
    case Es{True{}, +name, acc}:
      Ent.in(U32.is_eq(c, 59), U32.is_eq(c, 38), Nat.is_gt(String.length(name), 8n), Chr{c}, name, acc)
    case Es{False{}, _, acc}:
      Ent.out(U32.is_eq(c, 38), Chr{c}, acc)

def Ent.go(s: String, e: Es) -> Es:
  match s:
    case SNil{}:
      e
    case SCon{Chr{+c}, t}:
      Ent.go(t, Ent.step(e, c))

def Ent.fin(e: Es) -> String:
  match e:
    case Es{True{}, name, acc}:
      String.reverse(String.reverse.go(String.reverse(name), SCon{'&', acc}))
    case Es{False{}, _, acc}:
      String.reverse(acc)

# &amp; &lt; &gt; &quot; &nbsp; &#39; ... decoded; unknown ones kept
def Html.entities(s: String) -> String:
  Ent.fin(Ent.go(s, Es{False{}, "", ""}))

def Squeeze.put(blank: Bool, prev: Bool, +l: String, acc: List<&2, String>) -> List<&2, String>:
  match blank prev:
    case True{} True{}:
      acc
    case True{} False{}:
      "" <> acc
    case False{} _:
      l <> acc

def Squeeze.go(ls: List<&2, String>, prev: Bool, acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +l <> t:
      Squeeze.go(t, String.is_empty(String.trim(l)), Squeeze.put(String.is_empty(String.trim(l)), prev, String.trim(l), acc))

# lines trimmed, runs of blank lines as one
def Str.squeeze(s: String) -> String:
  String.trim(String.join(Squeeze.go(Str.lines(s), True{}, Nil{}), "\n"))

# the readable text of an HTML body
def Html.to_text(s: String) -> String:
  Str.squeeze(Html.entities(Html.fin(Html.go(s, Hs{False{}, False{}, "", ""}))))

# Dates (UTC, proleptic Gregorian; days from civil, H. Hinnant)
# -------------------------------------------------------------

type Ymd is Data:
  Ymd{y: Nat, m: Nat, d: Nat}

def Date.civil.e(+y: Nat, +doy: Nat, +mp: Nat) -> Ymd:
  +m = Bool.pick(Nat, Nat.is_lt(mp, 10n), Nat.add(mp, 3n), Nat.sub(mp, 9n))
  Ymd{Nat.add(y, Bool.pick(Nat, Nat.is_le(m, 2n), 1n, 0n)), m,
    Nat.add(Nat.sub(doy, Nat.div(Nat.add(Nat.mul(153n, mp), 2n), 5n)), 1n)}

def Date.civil.d(+y: Nat, +doy: Nat) -> Ymd:
  Date.civil.e(y, doy, Nat.div(Nat.add(Nat.mul(5n, doy), 2n), 153n))

def Date.civil.c(+era: Nat, +doe: Nat, +yoe: Nat) -> Ymd:
  Date.civil.d(Nat.add(yoe, Nat.mul(era, 400n)),
    Nat.sub(doe, Nat.sub(Nat.add(Nat.mul(365n, yoe), Nat.div(yoe, 4n)), Nat.div(yoe, 100n))))

def Date.civil.b(+era: Nat, +doe: Nat) -> Ymd:
  Date.civil.c(era, doe,
    Nat.div(Nat.sub(Nat.sub(Nat.add(doe, Nat.div(doe, 36524n)), Nat.div(doe, 1460n)), Nat.div(doe, 146096n)), 365n))

def Date.civil.a(+z: Nat) -> Ymd:
  Date.civil.b(Nat.div(z, 146097n), Nat.mod(z, 146097n))

# the date of a day count since 1970-01-01
def Date.civil(+days: Nat) -> Ymd:
  Date.civil.a(Nat.add(days, 719468n))

def Date.days.b(+y: Nat, +m: Nat, +d: Nat) -> Nat:
  +era = Nat.div(y, 400n)
  +yoe = Nat.sub(y, Nat.mul(era, 400n))
  +doy = Nat.sub(Nat.add(Nat.div(Nat.add(Nat.mul(153n, Bool.pick(Nat, Nat.is_gt(m, 2n), Nat.sub(m, 3n), Nat.add(m, 9n))), 2n), 5n), d), 1n)
  +doe = Nat.add(Nat.sub(Nat.add(Nat.mul(yoe, 365n), Nat.div(yoe, 4n)), Nat.div(yoe, 100n)), doy)
  Nat.sub(Nat.add(Nat.mul(era, 146097n), doe), 719468n)

# days since 1970-01-01 of a date
def Date.days(+y: Nat, +m: Nat, +d: Nat) -> Nat:
  Date.days.b(Nat.sub(y, Bool.pick(Nat, Nat.is_le(m, 2n), 1n, 0n)), m, d)

def Date.pad2(+n: Nat) -> String:
  Bool.pick(String, Nat.is_lt(n, 10n), "0" ++ Nat.show(n), Nat.show(n))

def Date.ymd(d: Ymd) -> String:
  match d:
    case Ymd{y, m, d}:
      Nat.show(y) ++ "-" ++ Date.pad2(m) ++ "-" ++ Date.pad2(d)

# epoch seconds as RFC 3339 UTC: 2026-09-24T13:05:00Z
def Date.iso(+t: Nat) -> String:
  +s = Nat.mod(t, 86400n)
  Date.ymd(Date.civil(Nat.div(t, 86400n))) ++ "T" ++ Date.pad2(Nat.div(s, 3600n)) ++ ":"
    ++ Date.pad2(Nat.div(Nat.mod(s, 3600n), 60n)) ++ ":" ++ Date.pad2(Nat.mod(s, 60n)) ++ "Z"

def Date.num(+s: String, +at: Nat, +n: Nat) -> Nat:
  Maybe.default(&2, Nat, Nat.read(String.take(String.drop(s, at), n)), 0n)

# n days after a YYYY-MM-DD date (only its first 10 characters are read)
def Date.plus_days(+s: String, +n: Nat) -> String:
  Date.ymd(Date.civil(Nat.add(Date.days(Date.num(s, 0n, 4n), Date.num(s, 5n, 2n), Date.num(s, 8n, 2n)), n)))

# the day after a YYYY-MM-DD date
def Date.next_day(+s: String) -> String:
  Date.plus_days(s, 1n)

# a bare date as the start of that day (UTC); anything else as given
def Date.time(+s: String) -> String:
  Bool.pick(String, Nat.is_eq(String.length(s), 10n), s ++ "T00:00:00Z", s)

# OAuth 2.0 for installed apps (RFC 6749, RFC 7636, RFC 8252)
# -----------------------------------------------------------

# read, send and label mail; read and write calendar events; who signed in
def Google.scopes() -> List<&2, String>:
  ["openid", "email", "https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendar.events"]

def Google.auth_base() -> String:
  "https://accounts.google.com/o/oauth2/v2/auth"

# the consent page's URL at an authorization endpoint
def Google.auth_url.at(+base: String, +client_id: String, +redirect: String, +challenge: String, +state: String, scopes: List<&2, String>) -> String:
  base ++ "?" ++ String.join([Url.pair("client_id", client_id), Url.pair("redirect_uri", redirect),
    "response_type=code", Url.pair("scope", String.join(scopes, " ")),
    Url.pair("code_challenge", challenge), "code_challenge_method=S256", Url.pair("state", state),
    "access_type=offline", "prompt=select_account%20consent"], "&")

# the URL the user opens to allow access (a refresh token comes back
# because of access_type=offline and prompt=consent)
def Google.auth_url(+client_id: String, +redirect: String, +challenge: String, +state: String, scopes: List<&2, String>) -> String:
  Google.auth_url.at(Google.auth_base(), client_id, redirect, challenge, state, scopes)

# The shared client
# -----------------
# One Google Cloud "Desktop app" client that every install ships, so
# connecting is one button (sign in, allow). An installed app's secret is
# not a secret (RFC 8252 8.5); PKCE is what protects the code. Empty until
# one is registered; BACKPLANE_GOOGLE_CLIENT_ID and _SECRET replace it.
# It links Gmail and Calendar. Gmail's scopes are restricted: until Google
# verifies the client (a yearly security assessment), people click past an
# unverified-app warning and at most 100 accounts can sign in. A client of
# the user's own (pasted in Settings) always wins over it.

type Client is Data:
  Client{id: String, secret: String}

def Google.shared() -> Client:
  Client{"", ""}

def Client.has(c: Client) -> Bool:
  match c:
    case Client{id, secret}:
      Bool.not(Bool.or(String.is_empty(id), String.is_empty(secret)))

def Client.id(c: Client) -> String:
  match c:
    case Client{id, _}:
      id

def Client.secret(c: Client) -> String:
  match c:
    case Client{_, secret}:
      secret

def Google.client.k(own: Bool, mine: Client, shared: Client) -> Client:
  match own:
    case True{}:
      mine
    case False{}:
      shared

# the client a sign-in uses: the user's own when set, else the shared one
def Google.client(+mine: Client, shared: Client) -> Client:
  Google.client.k(Client.has(mine), mine, shared)

# the scopes a sign-in asks for: every one, through either client
def Google.scopes_for(own: Bool) -> List<&2, String>:
  match own:
    case True{}:
      Google.scopes()
    case False{}:
      Google.scopes()

# the client is the shared one
def Google.is_shared(+id: String, +shared: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(id)), String.eq(id, shared))

def Google.gmail(+tool: String) -> Bool:
  String.starts_with(tool, "gmail_")

# a tool the link can do: every one, through either client
def Google.covers(shared: Bool, +tool: String) -> Bool:
  True{}

def Google.note.who(+email: String, shared: Bool) -> String:
  Bool.pick(String, String.is_empty(email), "Connected", "Connected as " ++ email)
    ++ " (Gmail and Calendar)."

def Google.note.k(connected: Bool, pending: Bool, ready: Bool, +email: String, shared: Bool) -> String:
  match connected pending ready:
    case True{} _ _:
      Google.note.who(email, shared)
    case False{} True{} _:
      "Waiting for Google: allow access in the tab that opened, or paste where it landed."
    case False{} False{} True{}:
      "Not connected."
    case False{} False{} False{}:
      "Not connected. This build has no shared Google client: add your own OAuth client (Desktop app) below."

# the connection in one line for the Settings screens. ready: a client
# (own or shared) is there to sign in with
def Google.note(connected: Bool, pending: Bool, ready: Bool, +email: String, shared: Bool) -> String:
  Google.note.k(connected, pending, ready, email, shared)

# Accounts
# --------
# Every Google account a hub signed in to, in the order they were added
# (secrets/google.json's "accounts"). A sign-in to an address already
# there replaces it; the first is the one a tool uses when it names none.

type Acct is Data:
  Acct{email: String, refresh: String, access: String, expiry: Nat}

def Acct.email(a: Acct) -> String:
  match a:
    case Acct{e, _, _, _}:
      e

# an account as the secrets file keeps it (a file from before accounts
# kept its one account's fields at its top, under the same names)
def Acct.of(+j: J.Json) -> Acct:
  Acct{J.Json.get_str(j, "email", ""), J.Json.get_str(j, "refresh_token", ""), J.Json.get_str(j, "access_token", ""), J.Json.get_nat(j, "expiry", 0n)}

def Acct.json(a: Acct) -> J.Json:
  match a:
    case Acct{e, r, x, t}:
      J.Json.obj([J.KV{"email", J.Str{e}}, J.KV{"refresh_token", J.Str{r}}, J.KV{"access_token", J.Str{x}}, J.KV{"expiry", J.Json.nat(t)}])

def Accts.of.go(xs: List<&2, J.Json>) -> List<&2, Acct>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Acct.of(x) <> Accts.of.go(t)

def Accts.legacy(none: Bool, +j: J.Json) -> List<&2, Acct>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [Acct.of(j)]

def Accts.or_legacy(xs: List<&2, Acct>, +j: J.Json) -> List<&2, Acct>:
  match xs:
    case Nil{}:
      Accts.legacy(String.is_empty(J.Json.get_str(j, "refresh_token", "")), j)
    case x <> t:
      x <> t

# the accounts a secrets file holds
def Accts.of(+j: J.Json) -> List<&2, Acct>:
  Accts.or_legacy(Accts.of.go(J.Json.elems(J.Json.get_obj(j, "accounts"))), j)

def Accts.json.go(xs: List<&2, Acct>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Acct.json(x) <> Accts.json.go(t)

def Accts.json(xs: List<&2, Acct>) -> J.Json:
  J.Json.arr(Accts.json.go(xs))

def Accts.emails(xs: List<&2, Acct>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Acct.email(x) <> Accts.emails(t)

# the head has address e
def Accts.hit(xs: List<&2, Acct>, +e: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case x <> _:
      String.eq(Acct.email(x), e)

def Accts.put.go(xs: List<&2, Acct>, hit: Bool, a: Acct, +e: String) -> List<&2, Acct>:
  match xs hit:
    case Nil{} _:
      [a]
    case +x <> +t True{}:
      a <> t
    case +x <> +t False{}:
      x <> Accts.put.go(t, Accts.hit(t, e), a, e)

# an account signed in: it replaces the one with its address, else goes last
def Accts.put(+xs: List<&2, Acct>, +a: Acct) -> List<&2, Acct>:
  Accts.put.go(xs, Accts.hit(xs, Acct.email(a)), a, Acct.email(a))

def Accts.drop.go(xs: List<&2, Acct>, hit: Bool, +e: String) -> List<&2, Acct>:
  match xs hit:
    case Nil{} _:
      Nil{}
    case +x <> +t True{}:
      Accts.drop.go(t, Accts.hit(t, e), e)
    case +x <> +t False{}:
      x <> Accts.drop.go(t, Accts.hit(t, e), e)

# every account but the one with address e
def Accts.drop(+xs: List<&2, Acct>, +e: String) -> List<&2, Acct>:
  Accts.drop.go(xs, Accts.hit(xs, e), e)

def Accts.first(xs: List<&2, Acct>) -> Maybe<&2, Acct>:
  match xs:
    case Nil{}:
      None{}
    case x <> _:
      Some{x}

def Accts.pick.go(xs: List<&2, Acct>, hit: Bool, +e: String) -> Maybe<&2, Acct>:
  match xs hit:
    case Nil{} _:
      None{}
    case +x <> +t True{}:
      Some{x}
    case +x <> +t False{}:
      Accts.pick.go(t, Accts.hit(t, e), e)

def Accts.pick.k(empty: Bool, +xs: List<&2, Acct>, +e: String) -> Maybe<&2, Acct>:
  match empty:
    case True{}:
      Accts.first(xs)
    case False{}:
      Accts.pick.go(xs, Accts.hit(xs, e), e)

# the account a tool names by address; "" names the first
def Accts.pick(+xs: List<&2, Acct>, +e: String) -> Maybe<&2, Acct>:
  Accts.pick.k(String.is_empty(e), xs, e)

def Accts.strs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{s} <> t:
      s <> Accts.strs(t)
    case _ <> t:
      Accts.strs(t)

# a status answer's addresses, one a line, for the Settings screens
def Accts.line(+status: String) -> String:
  String.join(Accts.strs(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(status), J.Null{}), "accounts"))), "\n")

# google_accounts' answer
def Accts.text(+emails: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, emails), "No Google account is connected (Settings, Google).",
    "Connected Google accounts (the first is the default):\n" ++ String.join(emails, "\n"))

# what the redirect carried; bare when the user pasted only the code
type CodeState is Data:
  CodeState{code: String, state: String, bare: Bool}

def Google.code_of.q(+code: String, +state: String) -> Maybe<&2, CodeState>:
  Bool.pick(Maybe<&2, CodeState>, String.is_empty(code), None{}, Some{CodeState{code, state, False{}}})

def Google.code_of.k(isq: Bool, +s: String) -> Maybe<&2, CodeState>:
  match isq:
    case True{}:
      Google.code_of.q(Url.param(Url.query(s), "code"), Url.param(Url.query(s), "state"))
    case False{}:
      Bool.pick(Maybe<&2, CodeState>, String.is_empty(s), None{}, Some{CodeState{Url.decode(s), "", True{}}})

# the code and state from a pasted redirect: the whole URL, its query, or
# only the code (text without '?', '=' or '&')
def Google.code_of(s: String) -> Maybe<&2, CodeState>:
  +t = String.trim(s)
  Google.code_of.k(Bool.or(String.contains(t, "?"), Bool.or(String.contains(t, "="), String.contains(t, "&"))), t)

# the error a redirect carried (access_denied when the user said no), or ""
def Google.error_of(s: String) -> String:
  Url.param(Url.query(String.trim(s)), "error")

# the token request for an authorization code (form-encoded)
def Google.code_body(+client_id: String, +secret: String, +code: String, +verifier: String, +redirect: String) -> String:
  String.join(["grant_type=authorization_code", Url.pair("code", code), Url.pair("client_id", client_id),
    Url.pair("client_secret", secret), Url.pair("redirect_uri", redirect), Url.pair("code_verifier", verifier)], "&")

# the token request for a fresh access token (form-encoded)
def Google.refresh_body(+client_id: String, +secret: String, +refresh: String) -> String:
  String.join(["grant_type=refresh_token", Url.pair("refresh_token", refresh), Url.pair("client_id", client_id),
    Url.pair("client_secret", secret)], "&")

# tokens from the token endpoint; expiry in epoch seconds; refresh and
# email "" when absent (a refresh answers no refresh token)
type Tok is Data:
  Tok{access: String, expiry: Nat, refresh: String, email: String}

def Google.jwt_claims(ps: List<&2, String>) -> J.Json:
  match ps:
    case _ <> p <> _:
      Maybe.default(&2, J.Json, J.Json.parse(U.Utf8.decode(Gb64.decode(p))), J.Null{})
    case _:
      J.Null{}

# the email claim of an id_token (no signature check: it came straight
# from Google over TLS)
def Google.jwt_email(s: String) -> String:
  J.Json.get_str(Google.jwt_claims(String.split(s, '.')), "email", "")

def Google.tokens.m(empty: Bool, +j: J.Json, +now: Nat) -> Maybe<&2, Tok>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{Tok{J.Json.get_str(j, "access_token", ""), Nat.add(now, J.Json.get_nat(j, "expires_in", 3600n)),
        J.Json.get_str(j, "refresh_token", ""), Google.jwt_email(J.Json.get_str(j, "id_token", ""))}}

def Google.tokens.j(m: Maybe<&2, J.Json>, +now: Nat) -> Maybe<&2, Tok>:
  match m:
    case Some{+j}:
      Google.tokens.m(String.is_empty(J.Json.get_str(j, "access_token", "")), j, now)
    case None{}:
      None{}

# the tokens of a token endpoint's answer, or None
def Google.tokens(text: String, +now: Nat) -> Maybe<&2, Tok>:
  Google.tokens.j(J.Json.parse(text), now)

# an access token is good for a request when it lives a minute more
def Google.fresh(+now: Nat, +expiry: Nat) -> Bool:
  Nat.is_lt(Nat.add(now, 60n), expiry)

def Google.err.k(e: J.Json, +desc: String, +msg: String, +raw: String) -> String:
  match e:
    case J.Str{+s}:
      Bool.pick(String, String.is_empty(desc), s, s ++ ": " ++ desc)
    case J.Obj{_}:
      Str.or(msg, raw)
    case _:
      raw

def Google.err.j(m: Maybe<&2, J.Json>, +raw: String) -> String:
  match m:
    case Some{+j}:
      Google.err.k(J.Json.get_obj(j, "error"), J.Json.get_str(j, "error_description", ""),
        J.Json.get_str(J.Json.get_obj(j, "error"), "message", ""), raw)
    case None{}:
      raw

# the message of an OAuth or API error answer (its first 300 characters
# when it is not one)
def Google.api_error(+text: String) -> String:
  Google.err.j(J.Json.parse(text), String.take(String.trim(text), 300n))

# Gmail (v1)
# ----------

def Gmail.path.go() -> String:
  "/gmail/v1/users/me"

def Google.gmail_search_path(q: String, +max: Nat) -> String:
  Gmail.path.go() ++ "/messages?" ++ Url.pair("q", q) ++ "&maxResults=" ++ Nat.show(max)

def Google.gmail_fmt(full: Bool) -> String:
  match full:
    case True{}:
      "?format=full"
    case False{}:
      "?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date"

# one message; full, or only the headers a list shows
def Google.gmail_get_path(id: String, full: Bool) -> String:
  Gmail.path.go() ++ "/messages/" ++ Url.encode(id) ++ Google.gmail_fmt(full)

def Google.gmail_send_path() -> String:
  Gmail.path.go() ++ "/messages/send"

def Google.gmail_profile_path() -> String:
  Gmail.path.go() ++ "/profile"

# the ids of a messages.list answer
def Google.msg_ids.go(ms: List<&2, J.Json>, acc: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}:
      List.reverse(&2, String, acc)
    case m <> t:
      Google.msg_ids.go(t, J.Json.get_str(m, "id", "") <> acc)

def Google.msg_ids(j: J.Json) -> List<&2, String>:
  Google.msg_ids.go(J.Json.elems(J.Json.get_obj(j, "messages")), Nil{})

# Mail headers: no line breaks or controls (a To or Subject cannot add
# headers), non-ASCII subjects as RFC 2047 encoded words

def Mail.clean.k(ctl: Bool, +c: U32, acc: String) -> String:
  match ctl:
    case True{}:
      SCon{' ', acc}
    case False{}:
      SCon{Chr{c}, acc}

def Mail.clean.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      Mail.clean.go(t, Mail.clean.k(Bool.or(U32.is_lt(c, 32), U32.is_eq(c, 127)), c, acc))

# a header value: every control character (CR, LF, tab...) a space
def Mail.clean(s: String) -> String:
  Mail.clean.go(s, "")

def Mail.ascii.go(s: String, ok: Bool) -> Bool:
  match s:
    case SNil{}:
      ok
    case SCon{Chr{+c}, t}:
      Mail.ascii.go(t, Bool.and(ok, U32.is_lt(c, 127)))

def Mail.ascii(s: String) -> Bool:
  Mail.ascii.go(s, True{})

def Mail.words(ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case w <> t:
      ("=?UTF-8?B?" ++ S.B64.encode(U.Utf8.encode(w)) ++ "?=") <> Mail.words(t)

def Mail.subject.k(plain: Bool, +s: String) -> String:
  match plain:
    case True{}:
      s
    case False{}:
      String.join(Mail.words(Str.split_every(s, 11n)), "\r\n ")

# a Subject value: as is when ASCII, else encoded words of at most 11
# characters (44 bytes, under the 75-character limit), folded
def Mail.subject(s: String) -> String:
  +c = Mail.clean(s)
  Mail.subject.k(Mail.ascii(c), c)

def Mail.cc(+cc: String) -> String:
  Bool.pick(String, String.is_empty(String.trim(cc)), "", "Cc: " ++ Mail.clean(cc) ++ "\r\n")

# a plain-text message (RFC 5322, MIME): body as UTF-8 in base64 with CRLF
# line breaks, in lines of 76
def Google.mime(to: String, +cc: String, subject: String, body: String) -> String:
  "To: " ++ Mail.clean(to) ++ "\r\n" ++ Mail.cc(cc) ++ "Subject: " ++ Mail.subject(subject) ++ "\r\n"
    ++ "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
    ++ String.join(Str.split_every(S.B64.encode(U.Utf8.encode(String.join(Str.lines(body), "\r\n"))), 76n), "\r\n") ++ "\r\n"

# messages.send's body: the message base64url-encoded
def Google.send_body(to: String, +cc: String, subject: String, body: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"raw", J.Str{Gb64.encode_url(U.Utf8.encode(Google.mime(to, cc, subject, body)))}}]))

# Reading messages

def Mail.hdr.take(+acc: String, +h: J.Json, +name: String) -> String:
  Bool.pick(String, Bool.and(String.is_empty(acc), String.eq(String.to_lower(J.Json.get_str(h, "name", "")), name)),
    J.Json.get_str(h, "value", ""), acc)

def Mail.hdr.go(hs: List<&2, J.Json>, +name: String, +acc: String) -> String:
  match hs:
    case Nil{}:
      acc
    case +h <> t:
      Mail.hdr.go(t, name, Mail.hdr.take(acc, h, name))

# a header of a message part (name in lower case), or ""
def Mail.hdr(+part: J.Json, +name: String) -> String:
  Mail.hdr.go(J.Json.elems(J.Json.get_obj(part, "headers")), name, "")

def Mail.has.go(xs: List<&2, J.Json>, +s: String, ok: Bool) -> Bool:
  match xs:
    case Nil{}:
      ok
    case x <> t:
      Mail.has.go(t, s, Bool.or(ok, String.eq(J.Json.as_str(Some{x}, ""), s)))

def Mail.unread(+m: J.Json) -> String:
  Bool.pick(String, Mail.has.go(J.Json.elems(J.Json.get_obj(m, "labelIds")), "UNREAD", False{}), " [unread]", "")

# one message of a list: id, date, from, subject, snippet
def Google.msg_line(+m: J.Json) -> String:
  +p = J.Json.get_obj(m, "payload")
  "- id " ++ J.Json.get_str(m, "id", "") ++ Mail.unread(m) ++ "  " ++ Mail.hdr(p, "date")
    ++ "\n  From: " ++ Mail.hdr(p, "from")
    ++ "\n  Subject: " ++ Mail.hdr(p, "subject")
    ++ "\n  " ++ Html.entities(J.Json.get_str(m, "snippet", ""))

def Google.msg_lines(ms: List<&2, J.Json>, acc: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +m <> t:
      Google.msg_lines(t, Google.msg_line(m) <> acc)

# messages (metadata) as the list an agent reads
def Google.msg_list(+ms: List<&2, J.Json>) -> String:
  Bool.pick(String, List.is_empty(&2, J.Json, ms), "No messages.",
    Nat.show(List.length(&2, J.Json, ms)) ++ " messages:\n" ++ String.join(Google.msg_lines(ms, Nil{}), "\n"))

# MIME parts: every object of a message's payload tree, in document order
def Mime.parts.go(j: J.Json, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match j:
    case J.Obj{+fs}:
      Mime.parts.go(fs, J.Obj{fs} <> acc)
    case J.Arr{xs}:
      Mime.parts.go(xs, acc)
    case J.Item{h, t}:
      Mime.parts.go(t, Mime.parts.go(h, acc))
    case J.Field{_, v, t}:
      Mime.parts.go(t, Mime.parts.go(v, acc))
    case _:
      acc

def Mime.parts(j: J.Json) -> List<&2, J.Json>:
  List.reverse(&2, J.Json, Mime.parts.go(j, Nil{}))

def Mime.data(+p: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(p, "body"), "data", "")

def Mime.is(+p: J.Json, +want: String) -> Bool:
  Bool.and(String.eq(J.Json.get_str(p, "mimeType", ""), want),
    Bool.and(Bool.not(String.is_empty(Mime.data(p))), String.is_empty(J.Json.get_str(p, "filename", ""))))

def Mime.pick.s(acc: Maybe<&2, J.Json>, hit: Bool, p: J.Json) -> Maybe<&2, J.Json>:
  match acc hit:
    case Some{a} _:
      Some{a}
    case None{} True{}:
      Some{p}
    case None{} False{}:
      None{}

def Mime.pick(ps: List<&2, J.Json>, +want: String, acc: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match ps:
    case Nil{}:
      acc
    case +p <> t:
      Mime.pick(t, want, Mime.pick.s(acc, Mime.is(p, want), p))

def Mime.latin(+p: J.Json) -> Bool:
  Bool.or(String.contains(String.to_lower(Mail.hdr(p, "content-type")), "8859-1"),
    String.contains(String.to_lower(Mail.hdr(p, "content-type")), "1252"))

def Mime.decode(latin: Bool, bs: List<&2, U32>) -> String:
  match latin:
    case True{}:
      Str.latin1(bs)
    case False{}:
      U.Utf8.decode(bs)

# a part's text, its transfer encoding undone and its charset read
def Mime.text(+p: J.Json) -> String:
  Mime.decode(Mime.latin(p), Gb64.decode(Mime.data(p)))

def Mime.body.h(m: Maybe<&2, J.Json>, +snippet: String) -> String:
  match m:
    case Some{+p}:
      Html.to_text(Mime.text(p))
    case None{}:
      Html.entities(snippet)

def Mime.body.k(m: Maybe<&2, J.Json>, +ps: List<&2, J.Json>, +snippet: String) -> String:
  match m:
    case Some{+p}:
      String.join(Str.lines(Mime.text(p)), "\n")
    case None{}:
      Mime.body.h(Mime.pick(ps, "text/html", None{}), snippet)

# the text of a message: its text/plain part, else its HTML as text, else
# the snippet
def Mime.body(+ps: List<&2, J.Json>, +snippet: String) -> String:
  Mime.body.k(Mime.pick(ps, "text/plain", None{}), ps, snippet)

def Mime.att(none: Bool, +p: J.Json, acc: List<&2, String>) -> List<&2, String>:
  match none:
    case True{}:
      acc
    case False{}:
      (J.Json.get_str(p, "filename", "") ++ " (" ++ J.Json.get_str(p, "mimeType", "") ++ ", "
        ++ J.Json.as_raw(J.Json.get(J.Json.get_obj(p, "body"), "size"), "?") ++ " bytes)") <> acc

def Mime.atts(ps: List<&2, J.Json>, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +p <> t:
      Mime.atts(t, Mime.att(String.is_empty(J.Json.get_str(p, "filename", "")), p, acc))

def Mail.line(+name: String, +v: String) -> String:
  Bool.pick(String, String.is_empty(v), "", name ++ ": " ++ v ++ "\n")

def Mail.labels(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Json.as_str(Some{x}, "") <> Mail.labels(t)

# the most a message's text may be for an agent
def Google.body_cap() -> Nat:
  20000n

# a whole message (format=full) as text: headers, attachments, body
def Google.msg_full(+m: J.Json) -> String:
  +p = J.Json.get_obj(m, "payload")
  +ps = Mime.parts(p)
  "id: " ++ J.Json.get_str(m, "id", "") ++ "\nthread: " ++ J.Json.get_str(m, "threadId", "") ++ "\n"
    ++ Mail.line("From", Mail.hdr(p, "from")) ++ Mail.line("To", Mail.hdr(p, "to")) ++ Mail.line("Cc", Mail.hdr(p, "cc"))
    ++ Mail.line("Date", Mail.hdr(p, "date")) ++ Mail.line("Subject", Mail.hdr(p, "subject"))
    ++ Mail.line("Labels", String.join(Mail.labels(J.Json.elems(J.Json.get_obj(m, "labelIds"))), ", "))
    ++ Mail.line("Attachments", String.join(Mime.atts(ps, Nil{}), "; "))
    ++ "\n" ++ Str.cap(Mime.body(ps, J.Json.get_str(m, "snippet", "")), Google.body_cap())

# Calendar (v3)
# -------------

def Cal.q(+q: String) -> String:
  Bool.pick(String, String.is_empty(q), "", "&" ++ Url.pair("q", q))

# the primary calendar's events in [from, to), recurring ones expanded
def Google.cal_list_path(+from: String, +to: String, +max: Nat, +q: String) -> String:
  "/calendar/v3/calendars/primary/events?" ++ Url.pair("timeMin", Date.time(from)) ++ "&" ++ Url.pair("timeMax", Date.time(to))
    ++ "&singleEvents=true&orderBy=startTime&maxResults=" ++ Nat.show(max) ++ Cal.q(q)

# a new event; invitations go out when it has attendees
def Google.cal_insert_path(any: Bool) -> String:
  match any:
    case True{}:
      "/calendar/v3/calendars/primary/events?sendUpdates=all"
    case False{}:
      "/calendar/v3/calendars/primary/events"

def Cal.tz(+tz: String) -> List<&2, J.KV>:
  Bool.pick(List<&2, J.KV>, String.is_empty(tz), Nil{}, [J.KV{"timeZone", J.Str{tz}}])

def Cal.at(all_day: Bool, +s: String, +tz: String) -> J.Json:
  match all_day:
    case True{}:
      J.Json.obj([J.KV{"date", J.Str{String.take(s, 10n)}}])
    case False{}:
      J.Json.obj(J.KV{"dateTime", J.Str{s}} <> Cal.tz(tz))

# an all-day event ends (exclusively) after its start: the next day when
# the end given is not later
def Cal.end(all_day: Bool, +start: String, +end: String) -> String:
  match all_day:
    case True{}:
      Bool.pick(String, String.is_le(String.take(end, 10n), String.take(start, 10n)), Date.next_day(String.take(start, 10n)), end)
    case False{}:
      end

def Cal.who(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case a <> t:
      J.Json.obj([J.KV{"email", J.Str{String.trim(a)}}]) <> Cal.who(t)

def Cal.opt(+k: String, +v: String) -> List<&2, J.KV>:
  Bool.pick(List<&2, J.KV>, String.is_empty(v), Nil{}, [J.KV{k, J.Str{v}}])

def Cal.attendees(+xs: List<&2, String>) -> List<&2, J.KV>:
  Bool.pick(List<&2, J.KV>, List.is_empty(&2, String, xs), Nil{}, [J.KV{"attendees", J.Json.arr(Cal.who(xs))}])

# events.insert's body
def Google.event_body(summary: String, +description: String, +start: String, +end: String, +attendees: List<&2, String>, +all_day: Bool, +tz: String) -> String:
  J.Json.show(J.Json.obj(List.concat(&2, J.KV, [[J.KV{"summary", J.Str{summary}}], Cal.opt("description", description),
    [J.KV{"start", Cal.at(all_day, start, tz)}, J.KV{"end", Cal.at(all_day, Cal.end(all_day, start, end), tz)}],
    Cal.attendees(attendees)])))

def Cal.when(+o: J.Json) -> String:
  Str.or(J.Json.get_str(o, "dateTime", ""), J.Json.get_str(o, "date", ""))

def Cal.where(+l: String) -> String:
  Bool.pick(String, String.is_empty(l), "", "\n  at " ++ l)

def Cal.people(+n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "", ", " ++ Nat.show(n) ++ " attendees")

# one event: when, what, where, its id
def Google.event_line(+e: J.Json) -> String:
  "- " ++ Cal.when(J.Json.get_obj(e, "start")) ++ " -> " ++ Cal.when(J.Json.get_obj(e, "end")) ++ "  "
    ++ Str.or(J.Json.get_str(e, "summary", ""), "(no title)") ++ Cal.where(J.Json.get_str(e, "location", ""))
    ++ "\n  id " ++ J.Json.get_str(e, "id", "") ++ Cal.people(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(e, "attendees"))))

def Google.event_lines(es: List<&2, J.Json>, acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +e <> t:
      Google.event_lines(t, Google.event_line(e) <> acc)

def Google.events.k(+es: List<&2, J.Json>, +tz: String) -> String:
  Bool.pick(String, List.is_empty(&2, J.Json, es), "No events.",
    Nat.show(List.length(&2, J.Json, es)) ++ " events" ++ Bool.pick(String, String.is_empty(tz), "", " (calendar time zone " ++ tz ++ ")")
      ++ ":\n" ++ String.join(Google.event_lines(es, Nil{}), "\n"))

# an events.list answer as the list an agent reads
def Google.events(+j: J.Json) -> String:
  Google.events.k(J.Json.elems(J.Json.get_obj(j, "items")), J.Json.get_str(j, "timeZone", ""))

# events.insert's answer, what was made
def Google.created(+e: J.Json) -> String:
  "Created:\n" ++ Google.event_line(e) ++ Bool.pick(String, String.is_empty(J.Json.get_str(e, "htmlLink", "")), "", "\n  " ++ J.Json.get_str(e, "htmlLink", ""))

# MCP tools
# ---------

def Tool.prop(+name: String, +ty: String, desc: String) -> J.KV:
  J.KV{name, J.Json.obj([J.KV{"type", J.Str{ty}}, J.KV{"description", J.Str{desc}}])}

def Tool.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Str{x} <> Tool.strs(t)

# the shape of src/core/mcp.bend's Tool.def
def Tool.def(name: String, desc: String, props: List<&2, J.KV>, req: List<&2, String>) -> J.Json:
  J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"description", J.Str{desc}},
    J.KV{"inputSchema", J.Json.obj([J.KV{"type", J.Str{"object"}}, J.KV{"properties", J.Json.obj(props)}, J.KV{"required", J.Json.arr(Tool.strs(req))}])}])

def Google.tool_names() -> List<&2, String>:
  ["gmail_search", "gmail_read", "gmail_send", "calendar_events", "calendar_create", "google_accounts"]

def Tool.account() -> J.KV:
  Tool.prop("account", "string", "Which connected Google account, by address (see google_accounts); default the first.")

# the tools that act for the user; the hub asks the user before each call
def Google.asks(+tool: String) -> Bool:
  Bool.or(String.eq(tool, "gmail_send"), String.eq(tool, "calendar_create"))

def Google.tool_defs() -> List<&2, J.Json>:
  [Tool.def("gmail_search", "Search the user's Gmail (Gmail search syntax, e.g. 'from:alice is:unread newer_than:7d'). Lists id, date, from, subject and snippet; read one with gmail_read.",
     [Tool.prop("query", "string", "Gmail search query; empty lists the newest mail."), Tool.prop("max", "number", "How many (default 10, at most 25)."), Tool.account()], Nil{}),
   Tool.def("gmail_read", "Read one Gmail message by id: headers, attachment names and its text (at most 20 KB).",
     [Tool.prop("id", "string", "A message id from gmail_search."), Tool.account()], ["id"]),
   Tool.def("gmail_send", "Send a plain-text email from the user's Gmail. The user is asked to approve every send first.",
     [Tool.prop("to", "string", "Recipients, comma-separated."), Tool.prop("subject", "string", "Subject."),
      Tool.prop("body", "string", "Plain-text body."), Tool.prop("cc", "string", "Cc recipients, comma-separated (optional)."), Tool.account()], ["to", "subject", "body"]),
   Tool.def("calendar_events", "List events on the user's primary Google Calendar, recurring ones expanded, soonest first.",
     [Tool.prop("from", "string", "Start, RFC 3339 (e.g. 2026-09-24T09:00:00-07:00) or a date; default now."),
      Tool.prop("to", "string", "End, RFC 3339 or a date; default a week after from."),
      Tool.prop("max", "number", "How many (default 20, at most 50)."), Tool.prop("query", "string", "Free-text filter (optional)."), Tool.account()], Nil{}),
   Tool.def("calendar_create", "Create an event on the user's primary Google Calendar; attendees get invitations. The user is asked to approve it first.",
     [Tool.prop("summary", "string", "Title."),
      Tool.prop("start", "string", "Start, RFC 3339 with an offset (e.g. 2026-09-24T09:00:00-07:00), or YYYY-MM-DD when all_day."),
      Tool.prop("end", "string", "End, same form as start. For all_day, the day after the last day (defaults to one day)."),
      Tool.prop("description", "string", "Details (optional)."),
      J.KV{"attendees", J.Json.obj([J.KV{"type", J.Str{"array"}}, J.KV{"items", J.Json.obj([J.KV{"type", J.Str{"string"}}])}, J.KV{"description", J.Str{"Attendee emails (optional)."}}])},
      Tool.prop("all_day", "boolean", "An all-day event (optional)."),
      Tool.prop("timeZone", "string", "IANA time zone, e.g. America/Los_Angeles, for times without an offset (optional)."), Tool.account()],
     ["summary", "start", "end"]),
   Tool.def("google_accounts", "List the Google accounts connected in Settings, by address; the first is the default the other tools use.", Nil{}, Nil{})]

# The loopback page
# -----------------

def Html.esc.k(lt: Bool, gt: Bool, amp: Bool, q: Bool, +c: U32, acc: String) -> String:
  match lt gt amp q:
    case True{} _ _ _:
      String.reverse.go("&lt;", acc)
    case False{} True{} _ _:
      String.reverse.go("&gt;", acc)
    case False{} False{} True{} _:
      String.reverse.go("&amp;", acc)
    case False{} False{} False{} True{}:
      String.reverse.go("&quot;", acc)
    case False{} False{} False{} False{}:
      SCon{Chr{c}, acc}

def Html.esc.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      Html.esc.go(t, Html.esc.k(U32.is_eq(c, 60), U32.is_eq(c, 62), U32.is_eq(c, 38), U32.is_eq(c, 34), c, acc))

# text safe inside HTML
def Html.esc(s: String) -> String:
  Html.esc.go(s, "")

# what the browser shows after Google redirects to the hub
def Google.page(msg: String) -> String:
  "<!doctype html><meta charset=\"utf-8\"><title>Backplane</title><body style=\"font:14px system-ui,sans-serif;margin:40px\"><p>"
    ++ Html.esc(msg) ++ "</p></body>"

# Which hub started a sign-in
# ---------------------------
# Google always sends the browser back to http://127.0.0.1:<port>, so a
# sign-in started on another machine's hub lands on the hub of the machine
# the browser runs on. The state names the hub that started it (its
# tailnet address, base64url, after a '.'; the nonce is base64url, which
# has no '.'), and a hub whose sign-in it is not sends the browser there.

# the state for a sign-in: the nonce, and the hub's address when it has one
def Google.state(+nonce: String, +home: String) -> String:
  Bool.pick(String, String.is_empty(home), nonce, nonce ++ "." ++ Gb64.encode_url(U.Utf8.encode(home)))

def Google.state.home.k(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case b <> _:
      U.Utf8.decode(Gb64.decode(b))

# the hub a state names ("" for none)
def Google.state.home(s: String) -> String:
  Google.state.home.k(List.drop(&2, String, String.split(s, '.'), 1n))

def Google.hop.rest(+url: String) -> String:
  Bool.pick(String, String.starts_with(url, "https://"), String.drop(url, 8n),
    Bool.pick(String, String.starts_with(url, "http://"), String.drop(url, 7n), ""))

def Google.hop.host(+rest: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(rest, ':')), "")

def Google.hop.plain(+rest: String) -> Bool:
  Bool.not(Bool.or(String.contains(rest, "/"), Bool.or(String.contains(rest, "@"),
    Bool.or(String.contains(rest, "?"), Bool.or(String.contains(rest, "#"), String.contains(rest, "\\"))))))

# a hub the browser may be sent to: a machine on a tailnet
# (http(s)://<name>.ts.net[:port], nothing after)
def Google.hop.ok(+url: String) -> Bool:
  Bool.and(String.ends_with(Google.hop.host(Google.hop.rest(url)), ".ts.net"), Google.hop.plain(Google.hop.rest(url)))

def Google.hop.k(go: Bool, +home: String, +query: String) -> String:
  match go:
    case True{}:
      home ++ "/oauth/google?" ++ query ++ "&hop=1"
    case False{}:
      ""

# where to send the browser Google sent back (query: the redirect's) when
# the sign-in in flight here (mine: its state) is not the one it names:
# the hub its state names, on the tailnet, and only once (hop=1); "" to
# finish here
def Google.hop(+query: String, +mine: String) -> String:
  Google.hop.k(Bool.and(Bool.not(String.eq(Url.param(query, "state"), mine)),
      Bool.and(Bool.not(String.eq(Url.param(query, "hop"), "1")), Google.hop.ok(Google.state.home(Url.param(query, "state"))))),
    Google.state.home(Url.param(query, "state")), query)

# A phone's own sign-in (RFC 8252 7.3): the app listens on a loopback port
# of its own and asks the hub to begin with that redirect, so Google sends
# the phone's browser back to the app, which hands the address it caught
# to the hub to finish. The hub takes only exactly
# http://127.0.0.1:<1-5 digits>/oauth/google; anything else begins with its
# own redirect.
def Google.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Char.is_digit(c), Google.digits(t))

def Google.loopback.port(+p: String) -> Bool:
  Bool.and(Bool.and(Nat.is_gt(String.length(p), 0n), Nat.is_le(String.length(p), 5n)), Google.digits(p))

def Google.loopback.mid(+url: String) -> String:
  String.take(String.drop(url, 17n), Nat.sub(String.length(url), 30n))

def Google.loopback(+url: String) -> Bool:
  Bool.and(Bool.and(String.starts_with(url, "http://127.0.0.1:"), String.ends_with(url, "/oauth/google")),
    Bool.and(Nat.is_gt(String.length(url), 30n), Google.loopback.port(Google.loopback.mid(url))))

# the redirect a sign-in begins with: the one asked for when it is a
# loopback, else the hub's own
def Google.redirect.pick(+asked: String, +own: String) -> String:
  Bool.pick(String, Google.loopback(asked), asked, own)
