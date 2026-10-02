// A stand-in `claude` for end-to-end tests: Claude Code 2.1.286's
// stream-json, shaped like the recordings in test/fixtures/claude/
// (bg-wake.jsonl, stop-steer.jsonl), keyed to the uuids the hub sends. No
// model runs. Each user line's uuid gets command_lifecycle queued, started
// and completed (or cancelled), its result before its completion; commands
// queue and run one at a time; an interrupt answers {still_queued: []} and
// cancels the running command and the queued ones.
//
// The mode is BP_STANDIN_MODE, or "mode:<name>" in the first message:
//   wake         the first command starts a background shell that ends
//                BP_BG_MS later (2500); Claude then wakes by itself
//                (bg-wake.jsonl l.17-23)
//   bg           the same; messages after the first take BP_WORK_MS
//   stale-first  the live repro: on the first message, a whole stale
//                notification turn runs before the command starts
//   stop         a command works until it is interrupted (20 s at most)
//   pair         each command works BP_WORK_MS (1500), so a second sent
//                at once waits queued (stop-steer.jsonl l.20-33)
//   noLC         an old CLI: no lifecycles, init says 2.0.0
//   exit-held    a child holds stdout open, the process exits 3
//   result-exit  a result, then exit with a child holding stdout
//   plain        each command: init, an answer, its result
//   delegate     the first command calls the hub's delegate_task (its MCP
//                URL from --mcp-config) for a child "mode:plain child
//                work", then ends; later commands as plain
// Every line read is appended to $FAKE_LOG ("IN <line>"), and "START pid".
//
//   test/tools/claude_standin.ts is run through a `claude` wrapper:
//   #!/bin/sh
//   exec bun /path/to/claude_standin.ts "$@"
import { appendFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const args = process.argv.slice(2);
const at = args.indexOf("--resume");
const session = at >= 0 ? args[at + 1] : `sess-${process.pid}-${Date.now()}`;
const logf = process.env.FAKE_LOG ?? "";
const log = (s: string) => {
  if (logf) appendFileSync(logf, s + "\n");
};
log(`START ${process.pid} ${args.join(" ").slice(0, 200).replace(/\n/g, " ")}`);
const workMs = Number(process.env.BP_WORK_MS ?? 1500);
const bgMs = Number(process.env.BP_BG_MS ?? 2500);
let mode = process.env.BP_STANDIN_MODE ?? "";
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const rnd = () => crypto.randomUUID();
const mcpAt = args.indexOf("--mcp-config");
const mcpUrl = (() => {
  try { return JSON.parse(args[mcpAt + 1]).mcpServers.backplane.url as string; } catch { return ""; }
})();
if (mcpUrl) log(`MCP ${process.pid} ${mcpUrl}`);

const emit = (o: object) => process.stdout.write(JSON.stringify(o) + "\n");
const lc = (u: string, state: string) => {
  if (mode !== "noLC") emit({ type: "command_lifecycle", command_uuid: u, state, uuid: rnd(), session_id: session });
};
const init = () =>
  emit({ type: "system", subtype: "init", cwd: process.cwd(), session_id: session, tools: ["Bash"], mcp_servers: [], model: "claude-haiku-4-5-20251001",
    permissionMode: "bypassPermissions", apiKeySource: "none", claude_code_version: mode === "noLC" ? "2.0.0" : "2.1.286",
    capabilities: mode === "noLC" ? [] : ["interrupt_receipt_v1", "interrupt_cancel_queued_v1", "msg_lifecycle_v1"], uuid: rnd() });
let msgN = 0;
const say = (text: string) => {
  const id = `msg_${process.pid}_${++msgN}`;
  emit({ type: "assistant", message: { id, type: "message", role: "assistant", model: "claude-haiku-4-5-20251001", content: [{ type: "thinking", thinking: "", signature: "x" }], usage: { input_tokens: 10, output_tokens: 1 } }, parent_tool_use_id: null, session_id: session, uuid: rnd() });
  emit({ type: "assistant", message: { id, type: "message", role: "assistant", model: "claude-haiku-4-5-20251001", content: [{ type: "text", text }], usage: { input_tokens: 10, output_tokens: 5 } }, parent_tool_use_id: null, session_id: session, uuid: rnd() });
};
const result = (text: string, err = false) =>
  emit(err
    ? { type: "result", subtype: "error_during_execution", duration_ms: 10, is_error: true, num_turns: 1, session_id: session, total_cost_usd: 0, usage: {}, modelUsage: {}, uuid: rnd() }
    : { type: "result", subtype: "success", is_error: false, duration_ms: 10, num_turns: 1, result: text, session_id: session, total_cost_usd: 0, usage: {},
        modelUsage: { "claude-haiku-4-5-20251001": { inputTokens: 10, outputTokens: 5, contextWindow: 200000 } }, uuid: rnd() });

// background tasks (Bash run_in_background)
let bgN = 0;
const bgStart = () => {
  const task = `b${process.pid}x${++bgN}`;
  const tool = `toolu_${task}`;
  emit({ type: "assistant", message: { id: `msg_bg_${task}`, role: "assistant", content: [{ type: "tool_use", id: tool, name: "Bash", input: { command: "sleep 8; echo done-bg", run_in_background: true } }], usage: { input_tokens: 1 } }, parent_tool_use_id: null, session_id: session });
  emit({ type: "system", subtype: "background_tasks_changed", tasks: [{ task_id: task, task_type: "local_bash", description: "sleep 8; echo done-bg" }], session_id: session });
  emit({ type: "system", subtype: "task_started", task_id: task, tool_use_id: tool, description: "sleep 8; echo done-bg", is_backgrounded: true, task_type: "local_bash", session_id: session });
  emit({ type: "user", message: { role: "user", content: [{ tool_use_id: tool, type: "tool_result", content: `Command running in background with ID: ${task}.` }] }, parent_tool_use_id: null, session_id: session });
  return { task, tool };
};

type Cmd = { uuid: string; text: string };
const queue: Cmd[] = [];
let busy = false;
let interrupted = false;
let wake: { task: string; tool: string } | null = null;
let wakeDue = false;
let first = true;

const waitOrInterrupt = async (ms: number) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (interrupted) return true;
    await sleep(20);
  }
  return interrupted;
};

async function wakeTurn() {
  const w = wake!;
  wake = null;
  wakeDue = false;
  busy = true;
  emit({ type: "system", subtype: "background_tasks_changed", tasks: [], session_id: session });
  emit({ type: "system", subtype: "task_updated", task_id: w.task, patch: { status: "completed", end_time: Date.now() }, session_id: session });
  emit({ type: "system", subtype: "task_notification", task_id: w.task, tool_use_id: w.tool, status: "completed", output_file: `/tmp/standin/${w.task}.output`,
    summary: 'Background command "sleep 8; echo done-bg" completed (exit code 0)', session_id: session });
  init();
  await sleep(300);
  say("FINISHED");
  result("FINISHED");
  log("WOKE");
  busy = false;
}

async function run(c: Cmd, firstOne: boolean) {
  interrupted = false;
  if (firstOne && mode === "stale-first") {
    emit({ type: "system", subtype: "task_notification", task_id: "old1", tool_use_id: "toolu_old1", status: "completed", summary: "An old background command completed", session_id: session });
    init();
    say("STALE");
    result("STALE");
    log("STALE");
    await sleep(2000);
  }
  lc(c.uuid, "started");
  init();
  if (firstOne && (mode === "exit-held" || mode === "result-exit")) {
    if (mode === "result-exit") {
      say("BYE");
      result("BYE");
      lc(c.uuid, "completed");
    }
    spawn("sleep", ["600"], { stdio: ["ignore", "inherit", "ignore"], detached: true }).unref();
    log(`EXIT ${process.pid}`);
    await sleep(100);
    process.exit(mode === "exit-held" ? 3 : 0);
  }
  if (firstOne && mode === "delegate") {
    let task = "";
    try {
      const r = await fetch(mcpUrl, { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delegate_task", arguments: { prompt: process.env.BP_CHILD_PROMPT ?? "mode:plain child work", provider: "claude" } } }) });
      task = await r.text();
    } catch (e) { task = String(e); }
    log(`DELEGATED ${task.slice(0, 300)}`);
    say("DELEGATED");
    result("DELEGATED");
    lc(c.uuid, "completed");
    return;
  }
  if (firstOne && (mode === "wake" || mode === "bg")) {
    const t = bgStart();
    say("STARTED");
    result("STARTED");
    lc(c.uuid, "completed");
    setTimeout(() => {
      wake = t;
      wakeDue = true;
      pump();
    }, bgMs);
    return;
  }
  const stopped = await waitOrInterrupt(mode === "stop" ? 20000 : mode === "plain" ? 200 : workMs);
  if (stopped) {
    say("1. One is the first number and the begin");
    emit({ type: "user", message: { role: "user", content: [{ type: "text", text: "[Request interrupted by user]" }] }, parent_tool_use_id: null, session_id: session });
    result("", true);
    lc(c.uuid, "cancelled");
    return;
  }
  const reply = c.text.includes("two") ? "TWO" : c.text.includes("one") ? "ONE" : `REPLY ${c.text.slice(0, 40)}`;
  say(reply);
  result(reply);
  lc(c.uuid, "completed");
}

async function pump() {
  if (busy) return;
  busy = true;
  for (;;) {
    const c = queue.shift();
    if (!c) break;
    const f = first;
    first = false;
    await run(c, f);
  }
  busy = false;
  if (wakeDue) await wakeTurn();
  if (queue.length) pump();
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  log(`IN ${line.slice(0, 400)}`);
  let o: any;
  try { o = JSON.parse(line); } catch { return; }
  if (o.type === "control_request" && o.request?.subtype === "interrupt") {
    emit({ type: "control_response", response: { subtype: "success", request_id: o.request_id, response: { still_queued: [] } } });
    interrupted = true;
    for (const c of queue.splice(0)) lc(c.uuid, "cancelled");
    log("INT");
    return;
  }
  if (o.type !== "user") return;
  const text = (o.message?.content ?? []).map((b: any) => (typeof b === "string" ? b : b.text ?? "")).join(" ");
  if (!mode) mode = /mode:([\w-]+)/.exec(text)?.[1] ?? "plain";
  const uuid = o.uuid ?? rnd();
  log(`USER ${uuid} ${text.slice(0, 80)}`);
  lc(uuid, "queued");
  queue.push({ uuid, text });
  pump();
});
rl.on("close", () => {
  log(`EOF ${process.pid}`);
  setTimeout(() => process.exit(0), 50);
});
process.on("SIGTERM", () => {
  log(`TERM ${process.pid}`);
  process.exit(0);
});
