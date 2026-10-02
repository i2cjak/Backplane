#!/usr/bin/env python3
"""Give the phones' bundle native string comparisons.

Bend's JS target compares strings as Base defines them: a char at a time,
each step a slice of both strings, a Char.cmp and a tuple built on the way
back. On a phone's JavaScriptCore or QuickJS (no JIT) that was over half of
every screen (a list of 126 threads: 150 ms, 60 ms with these). The
replacements answer exactly what Base's String.cmp and String.eq do (the
strings back unchanged, the order by code point), found by the shape Bend
emits them in; a bundle where they are not found stops the build rather
than ship without them.

  scripts/bridge-native.py mobile/build/assets/bridge.js
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

I = r"[A-Za-z0-9_$]+"

# the trampoline's tail-call maker (the minifier names it: J in one build, E
# in another), which String.eq's shape goes through
jmp = re.findall(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return\{\$:"\$JMP",f:\2,x:\3\}\}', src)
if len(jmp) != 1:
    sys.exit(f"bridge-native: the tail-call maker found {len(jmp)} times, not once")
T = re.escape(jmp[0][0])

# String.cmp: (a, b) -> ((a, b), Cmp)
cmp_head = re.compile(
    r'function (' + I + r')\(([A-Z]),([A-Z])\)\{if\(\2===""\)if\(\3===""\)return\{\$:"Tuple",\["fst"\]:\{\$:"Tuple",\["fst"\]:"",\["snd"\]:""\},\["snd"\]:\{\$:"EQ"\}\};'
)
ms = list(cmp_head.finditer(src))
if len(ms) != 1:
    sys.exit(f"bridge-native: String.cmp found {len(ms)} times, not once")
m = ms[0]
cmp = m.group(1)
# the old body ends where the next top-level function starts
end = src.index("}function ", m.end()) + 1
while src[m.start():end].count("{") != src[m.start():end].count("}"):
    end = src.index("}function ", end) + 1
native_cmp = (
    f"function {cmp}(a,b){{let r;if(a===b)r=\"EQ\";else{{let i=0;const n=a.length<b.length?a.length:b.length;"
    "while(i<n&&a.charCodeAt(i)===b.charCodeAt(i))i++;"
    "r=i===n?(a.length<b.length?\"LT\":\"GT\"):(a.codePointAt(i)<b.codePointAt(i)?\"LT\":\"GT\")}"
    "return{$:\"Tuple\",[\"fst\"]:{$:\"Tuple\",[\"fst\"]:a,[\"snd\"]:b},[\"snd\"]:{$:r}}}"
)
src = src[: m.start()] + native_cmp + src[end:]

# Cmp.is_eq: LT false, EQ true, GT false
is_eq = re.findall(
    r'function (' + I + r')\(([A-Z])\)\{if\(\2\.\$==="LT"\)return!1;else if\(\2\.\$==="EQ"\)return!0;else return!1\}', src
)
names = {n for n, _ in is_eq}
# String.eq: its result's Cmp through Cmp.is_eq (the call that forces
# String.cmp's result is minifier-named too: Q in one build, another later)
fins = {
    f
    for f, x, y, g in re.findall(
        r'function (' + I + r')\(([A-Z])\)\{let [A-Z]=\2\.fst,[A-Z]=[A-Z]\.fst,[A-Z]=[A-Z]\.snd,([A-Z])=\2\.snd;return ' + T + r'\((' + I + r'),\[\3\]\)\}', src
    )
    if g in names
}
eq_re = re.compile(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return ' + T + r'\((' + I + r'),\[' + I + r'\(' + re.escape(cmp) + r'\(\2,\3\)\)\]\)\}')
eqs = [e for e in eq_re.finditer(src) if e.group(4) in fins]
if len(eqs) != 1:
    sys.exit(f"bridge-native: String.eq found {len(eqs)} times, not once")
e = eqs[0]
src = src[: e.start()] + f"function {e.group(1)}(a,b){{return a===b}}" + src[e.end():]

open(path, "w", encoding="utf-8").write(src)
print(f"bridge-native: String.cmp ({cmp}) and String.eq ({e.group(1)}) native")
