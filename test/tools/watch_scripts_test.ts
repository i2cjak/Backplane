// The watched-work shell scripts (server.bend's Watch.launch.sh / check.sh /
// stop.sh) run for real: Stop signals only the process it was told about,
// and a launch marker with no sign of a launch does not suppress it.
// bun test/tools/watch_scripts_test.ts
import { readFileSync, mkdtempSync, writeFileSync, existsSync, readFileSync as rd } from "fs"
import { spawn, spawnSync } from "child_process"
import { tmpdir } from "os"

const src = readFileSync(new URL("../../src/server/server.bend", import.meta.url), "utf8")
const script = (n: string): string => {
  const m = src.match(new RegExp(`def Watch\\.${n}\\.sh\\(\\) -> String:\\n  "(.*)"\\n`))
  if (!m) throw new Error("no " + n)
  return JSON.parse('"' + m[1] + '"')
}
const sh = (n: string, args: string[], env: Record<string, string> = {}) =>
  spawnSync("sh", ["-c", script(n), "sh", ...args], { encoding: "utf8", env: { ...process.env, ...env } })
const alive = (p: number) => { try { process.kill(p, 0); return true } catch { return false } }
let bad = 0
const ok = (c: boolean, what: string) => { console.log((c ? "ok   " : "FAIL ") + what); if (!c) bad++ }

// a PATH with no systemd-run, so launch takes the setsid fallback
const bin = mkdtempSync(tmpdir() + "/wsb-")
for (const t of ["sh", "sleep", "cat", "sed", "cut", "tr", "ps", "setsid", "nohup", "mkdir", "printf", "echo", "mv", "kill", "head", "true"]) {
  const w = spawnSync("sh", ["-c", `command -v ${t}`], { encoding: "utf8" }).stdout.trim()
  if (w) spawnSync("ln", ["-s", w, bin + "/" + t])
}
const env = { PATH: bin }

// 1. launch, then Stop with the right identity ends it
let d = mkdtempSync(tmpdir() + "/wsd-")
let r = sh("launch", [d, "/tmp", "sleep 30", "bp-x"], env)
ok(r.stdout.trim() === "running", "launch runs")
let pid = Number(rd(d + "/pid", "utf8").trim())
ok(alive(pid), "launched process alive")
const ident = rd(d + "/pidid", "utf8").trim()
ok(ident.length > 0, "launch records the process identity")

// 2. a recycled pid (identity differs) is not signalled
writeFileSync(d + "/pidid", "other:1\n")
sh("stop", ["run", "", "-", d, "bp-x"], env)
await Bun.sleep(300)
ok(alive(pid), "Stop does not signal a pid whose identity changed")
writeFileSync(d + "/pidid", ident + "\n")
sh("stop", ["run", "", "-", d, "bp-x"], env)
await Bun.sleep(500)
ok(!alive(pid), "Stop ends the process it launched")

// 3. a pid watch: wrong identity survives, right one ends
const sl = spawn("sleep", ["30"], { stdio: "ignore" })
const w = sl.pid!
d = mkdtempSync(tmpdir() + "/wsd-")
sh("stop", ["pid", String(w), "boot:1", d, "bp-y"], env)
await Bun.sleep(300)
ok(alive(w), "a pid watch with another identity is not signalled")
sh("stop", ["pid", String(w), "-", d, "bp-y"], env)
await Bun.sleep(300)
ok(alive(w), "a pid watch whose identity was never learned is not signalled")
const id2 = sh("check", ["pid", String(w), "-", d, "bp-y"], env).stdout.split("\n").find(l => l.startsWith("ident "))!.slice(6)
sh("stop", ["pid", String(w), id2, d, "bp-y"], env)
await Bun.sleep(500)
ok(!alive(w), "a pid watch with its identity is ended")

// 4. started with no sign of a launch: launch again
d = mkdtempSync(tmpdir() + "/wsd-")
writeFileSync(d + "/started", "")
r = sh("launch", [d, "/tmp", "echo hi", "bp-z"], env)
await Bun.sleep(700)
ok(existsSync(d + "/code") && rd(d + "/out", "utf8").trim() === "hi", "a marker with no launch behind it does not suppress the command")

// 5. started and launched: not run twice
d = mkdtempSync(tmpdir() + "/wsd-")
sh("launch", [d, "/tmp", "echo once >> " + d + "/log; sleep 1", "bp-w"], env)
await Bun.sleep(300)
sh("launch", [d, "/tmp", "echo once >> " + d + "/log; sleep 1", "bp-w"], env)
await Bun.sleep(1500)
ok(rd(d + "/log", "utf8") === "once\n", "a launched command is not launched again")

// 6. a multi-line command is run whole
d = mkdtempSync(tmpdir() + "/wsd-")
sh("launch", [d, "/tmp", "echo A\necho B", "bp-v"], env)
await Bun.sleep(700)
ok(rd(d + "/out", "utf8") === "A\nB\n", "a multi-line command runs as written")
process.exit(bad ? 1 : 0)
