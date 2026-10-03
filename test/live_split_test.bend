import Base
import ./check.bend as C
import ../src/core/client.bend as U

# A streamed reply's settled prefix (client.bend's Live.at/head/rest): the
# text up to the last blank line outside a fence, which renders alone as it
# does inside the whole.

def para(+i: Nat) -> String:
  "Paragraph " ++ Nat.show(i) ++ " of *streamed* text with `code` and more words.\nA second line.\n\n"

def paras(+n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      para(n) ++ paras(k)

def main() -> IO(Unit):
  do IO<Unit>:
    +long : String = paras(300n) ++ "tail not settled"
    C.Check.str("a long reply keeps its tail", U.Live.rest(long), "tail not settled")
    C.Check.str("head and rest are the text", Nat.show(Nat.add(String.length(U.Live.head(long)), String.length(U.Live.rest(long)))), Nat.show(String.length(long)))
    C.Check.str("the head is every paragraph", Nat.show(String.length(U.Live.head(long))), Nat.show(String.length(paras(300n))))
    C.Check.str("no blank line, no head", U.Live.head("one\nline"), "")
    C.Check.str("a blank line inside a fence settles nothing", U.Live.head("a\n\n```\nx\n\ny"), "a\n\n")
    C.Check.str("closed fence settles", U.Live.rest("a\n\n```\nx\n\ny\n```\nz\n\nw"), "w")
    C.Check.str("an open fence at the end keeps it in the tail", U.Live.rest("p\n\n```\ncode\n\nmore"), "```\ncode\n\nmore")
    C.Check.str("indented fences count", U.Live.rest("p\n\n  ```\nx\n\n  ```\nq\n\nr"), "r")
