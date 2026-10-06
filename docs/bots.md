# Bots

Persistent agents with a name, a face (an animated kitty cat), memory,
routines, webhooks, a browser page of their own, and a space: a UI they
write for themselves. Bots talk to each other directly or in rooms, on one
machine or across machines, including other people's Backplanes.

## Shape

- A bot is backed by one thread (`Bot.thread`). Its turns, model, provider,
  approvals, tools and timeline are the thread's. The thread belongs to no
  project (project `""`), so it never shows on a project shelf; it works in
  `<home>/bots/<id>/`, its home folder (set by a `WorktreeSet` once the hub
  has made the folder).
- Everything else lives in `M.State.bots : BT.World` (`src/core/bot.bend`),
  folded from additive `Change` variants (`Bot*`, `Room*`, `Hook*`,
  `Routine*`, `Memory*`, `Space*`, `Peer*`).
- Secrets never enter the event log or reach a client: webhook and peer
  secrets are files under `<home>/secrets/` (0700 dir, 0600 files); the
  Google refresh token too.

## Projects and sub-bots

A bot works for the person across all their projects. Its thread belongs
to none, so the thread tools reach every project for it: `thread_list`
lists every project's threads, `thread_read`, `thread_send`, `thread_wait`
and `thread_interrupt` take any of them, and `thread_launch` needs a
`project` (a name or id from `project_list`). The new thread shows in that
project like the person's own, its first message naming the bot.

New work gets a visible thread. A bot starts it with `thread_launch` and
its `project`, and `delegate_task` from a bot needs a `project` too (law
`bot_delegate_needs_project`): the child runs in that project's folder,
its first message names the bot, and unlike a thread's delegated child it
is not hidden under its parent (`Kids.set` in client.bend skips children
of bot threads, law `kids_bot_child_shown`), so the person sees it in that
project's sidebar. Its result still comes back to the bot as a message,
and the delegation depth limit applies as before.

`project_create(path, name?)` adds a project for the person, but only
once they say yes: every call opens an approval card ("New project ...,
Folder: ...") unless they allowed it for the session (law
`bot_newproj_asks`; a single yes never covers the next call,
`bot_newproj_once`). On accept the server makes the folder when missing
(`~/x`, or a bare name under the home folder), resolves it, and the hub
adds it (`Bots.newproj.made`); a folder that is a project already answers
that project. Declining makes nothing.

`bot_create` makes a sub-bot for a lasting role. Its maker is kept as the
setting `bot.parent.<id>`. Sub-bots go at most two levels below a bot a
person made (law `bot_spawn_bounded`), and a bot keeps at most eight.

## Conversation depth

A message a bot sends carries a hop count: a human, a routine, a webhook or
a space button starts at 0, and a bot's message to another bot is one more
than the hop of the turn that sent it (`Hop.send` in `src/core/bot.bend`).

A turn's hop is the lowest hop of the messages it answers (`Hops`,
`Hop.woke`, `Hop.taken`). A message that reaches a bot at rest starts a
turn at its hop. One that reaches a busy bot (its thread running, so the
hub queues the message) leaves the running turn's hop alone and waits;
the next turn (`QueueTaken`) runs at the lowest hop waiting. So when a
post at hop h asks five bots to answer once, each answer goes out at h+1
even though every answer wakes the others (law `bot_hop_fanout`), while a
back-and-forth between bots goes one hop deeper per message
(`bot_hop_queue_takes`) and stops at `Hop.max()`, 6 (`bot_hop_bounded`,
`bot_loop_bounded`, `bot_loop_stops`). A person, a routine or a webhook
starts a new exchange at hop 0.

A message past the bound is held, not dropped: it is posted where it was
going with a `[held: ...]` line, for the person to read, and heard by no
bot (`Bots.hop.gate`, law `bot_held_wakes_none`). In a shared room it goes
to the members' machines too, which log it and wake no one there. The
sending bot gets an answer saying so (`held: true` and a note telling it
not to send it again or anywhere else), not an error. A hop from a linked
machine is capped at the held hop (`Bots.hop.cap`). `test/depth_test.bend`
runs #staff: five bots here and one on a linked machine answering one post.

## Cats

`src/core/cat.bend`. A look (fur, pattern, eyes) comes from the bot's
`look` seed. A mood comes from the bot's status:

| mood | when | moves |
|---|---|---|
| sleep | idle for 15 min | still (breathing only on web/phone) |
| idle | ready | tail sway, blinks |
| work | turn running | kneading/typing paws, tail |
| think | queued | head tilt, tail flick |
| wait | needs you (approval, question) | ears up, bounce, "!" |
| talk | sent a bot message in the last minute | mouth, bubble |
| error | last turn failed | ears flat, still tail |
| away | remote, unreachable | greyed, still |

- Web: `Cat.svg(look, mood, px)` is one self-contained animated SVG (SMIL),
  shown as an `<img>` data URI; the browser animates it off the main thread.
- Native window: `Cat.pose(look, mood, ms)` gives polygons per colour for
  a time; flattened once per (look, mood), moved by an affine per frame.
  The window asks for frames at ~30 fps only while a visible cat moves and
  the window is focused (sleeping cats never ask).
- Phones: `Cat.rig(look, mood)` as JSON: parts with SVG path data (only
  `M L C Q Z`, absolute), fill colour, and one animation each (`rot`, `tx`,
  `ty`, `sx`, `sy`, `op` with from/to, pivot, period ms, delay ms, eased
  in-out, ping-pong). SwiftUI `Canvas` + `TimelineView`, Compose `Canvas` +
  `rememberInfiniteTransition`.

## Rooms and messages

- `bot_send(to, text, topic)`: `to` is a bot name here, or `name@peer`
  elsewhere. A request between bots goes in a room, not a private
  message, so the person and other bots can follow it: the live room whose
  members are exactly the two bots and whose name is the topic (any case;
  with no topic, the two names sorted, `miso + tofu`), else a new one
  (`RoomSet`, then the post). Asking again, or answering, with the same
  topic lands in the same room, whichever bot sends and on either machine
  (members compare as a bot's id here, or its lower-case name and the
  peer id). A bot on another machine is a member like any other
  (`name@machine`), so the post travels as a shared room post (below).
  `Req.*` in bothub.bend; law `bot_request_in_room` (a request is never
  posted to a `dm:` room) with `bot_request_fresh_id`.
- `bot_send` with `direct: true` is a private message, for when the person
  asks for one: room `dm:<a>:<b>`, names sorted, as before.
- `room_post(room, text)`: every other member gets it in their inbox.
- All are logged as `RoomPosted`, so people can read every conversation.
- The hop bound covers all of them alike.
- Delivery to a local bot goes through the thread inbox (`Hub.inbox`): it
  queues behind a running turn, never interrupts.

A person may write to a bot on a linked machine (`bots.tell`, `name@machine`):
the post goes in their direct room there (`dm:<name>@<machine>:you`) and the
bot hears `[message from person@<machine>]`. It answers in its own thread,
which that person cannot see, so when such a turn completes the hub sends
its newest answer back (`Reply.back`, run by the `bots.answered` request the
server sends itself on `TurnEnded`): logged here in the room the message
came in, and posted in the person's direct room there, waking no one (laws
`reply_*`).

### Shared rooms

A room's members can be on other machines (`name@machine`). A post goes to
each linked machine once (`Bots.remotes`), with the room's id, name, the
bots there it is for (`tos`), and its members as that machine names them:
a bare name is a bot there, `name@` a bot on the sender, `name@machine` a
bot on a third machine. The receiving machine keeps the room under the
same id (a `RoomSet` when it is new or its members changed), logs the post
once, and wakes the bots it is for (`Bots.shared`), so its bots and person
see the room and can post back. A machine sends its own posts to every
other and never passes on one it received, so nothing loops; a member on a
machine the poster is not linked to does not hear that post.

A linked machine may post in a room here only when the room is new here or
has a member on that machine (law `bot_room_no_takeover`), and never opens
a room the person deleted (law `bot_room_deleted_stays`). The other
machine learns of a room at its first post.

Every room list names a room by its id, so a shared room shows once: in
a hub's own list (the window, the web) and in a phone's list over several
paired hubs, which both report it (`BU.once.of`, `Hubs.rooms`; laws
`rooms_listed_once`, `hubs_rooms_listed_once`). Rooms are never merged by
name: two rooms with one name both show, each named with its id, and on a
phone with several hubs each row also carries its machine.

## Notifications

One item, one alert (`src/core/notice.bend`, laws `notice_*`). A turn's end
alerts the person unless it is part of a room exchange they read in the
room:

- A failed turn always alerts.
- A thread that is not a bot's alerts when it finishes.
- A bot with an open ask (waiting on the person) alerts.
- A bot turn that posted in a room, or sent to a bot, alerts only if its
  post opened the room's exchange: no other bot posted in the room since the
  person's last post there, or in the last 5 minutes. Its key is
  `room-<room id>`, the same on every linked machine, so apps and APNs
  replace one alert with the next instead of stacking them.
- A bot turn woken by a room or bot message that posted nothing is quiet.
- A bot turn the person started in the bot's own thread, or a routine's,
  alerts as before (`turn-<thread>`).

A hub counts only its own bots' posts (it pushes only for its own threads). A
phone paired with several hubs counts every bot, so only the hub whose bot
answered first raises the alert. A held push is logged as
`backplane: push alert held for <thread>`.

### Desks

The window and the web page are desks (`src/core/desk.bend`). Each tells
the hub which thread it shows and whether it has the focus, when either
changes and at most once a minute while in use. A thread a focused desk
shows, used in the last 3 minutes, is being watched: its turn's end raises
no phone alert (neither the APNs push nor the phone's own), and no desktop
notification. Any other alert also shows as a desktop notification on the
desk used last: the browser's notifications (the page asks for permission
on the first click or key; macOS, Windows, Linux) or `notify-send` from the
Linux window. Clicking it opens the thread.
## Mentions in threads

In any thread's composer (web, window, phones) a word that starts with a
sigil names something, and a menu offers matches with their summaries as
you type:

| sigil | names | when sent |
|---|---|---|
| `@name`, `@name@machine` | a bot, here or on a linked machine | the bot is woken (hop 0) with the message and the thread it came from; it can `thread_read` it and answer with `thread_send` |
| `>slug` | a thread | the agent is told the thread's id, project and summary |
| `>machine:slug` | a thread on another of the owner's machines | the agent is told what it is and where; `thread_read` reads it |
| `%slug` | a project | the agent is told the project's id, folder and summary |
| `#slug` | a group chat | the message is posted in the room |

`@Miso look at >fix-perf-lag` points a bot at a thread. A slug is the
title in lower case with every other run of characters one `-`; a thread
whose slug another shares is `slug-<n>`, the number its id ends with. The
thread's own agent gets the message as typed plus a `<references>` block
naming each (`Refs.agent`); the timeline keeps it as typed. A bot is never
woken by a mention in its own thread (law `refs_own_bot_never`), and a
message resent after a dropped connection wakes nothing twice
(`bot_mention_once`). Bots on linked machines are offered too, from the
list every client gets (info `bots.remote`), as `@name@machine` (the
machine's link id when its name could mean another, `Refs.fars`); sent,
the bot hears the message as the person's, with the thread's title, which
it cannot read, and answers in the person's conversation with it
(`Bots.mention.far`, the same room `bots.tell` writes in).

Threads synced from the owner's other machines (below, "Threads
elsewhere") are offered as `>machine:slug`, the machine by its name as a
slug (`Refs.x.*`); their rows start with the machine's name, which a query
matches too, and `>machine:` alone offers only that machine's threads. A
`>machine:slug` never names a thread here (`>fix: it fails` still names
`fix`: a slug must follow the colon, laws `refs_machine_word`,
`refs_colon_after_stays_here`). The hub has no read model of other
machines' threads, only its mirror of each, so `src/core/xref.bend` folds
the one mirror a word names when it must: for the agent's
`<references>` block (server.bend's `Far.turn`, around `Bots.turn`), and
for `thread_read` on a `<link>~<id>` (`Xref.read`, answered from the
mirror, before the MCP call reaches the hub).

The menu (`Refs.offer` in `src/core/refs.bend`) ranks by how well the
query matches the slug or name (fuzzy), a query of three or more letters
found in the summary, then nearness: the same project, recent work, pinned
or running threads. It is worked out once per edit of the draft and kept
in the client's info map, so frames and phone screens only read it.

Summaries come from the text generation model (the one that titles
threads): a thread's when a turn ends, at most every ten minutes
(`summary.<thread>`), and its project's after it, from the project's
newest threads (`summary.<project>`). A bot's is its thread's; before its
first turn the menu shows its persona's first line.

## Scratch and giving a thread away

Not every conversation belongs to a project. Scratch (a project every hub
makes for itself, at `<home>/scratch`) holds throwaway threads: the `+` on
its sidebar row starts one, and each works in a folder of its own
(`<home>/scratch/<thread>`). They are ephemeral: one left alone for the
`scratch.days` setting (default 7) is deleted with its folder at the next
tick. Pin one to keep it.

To take a conversation somewhere, type `/give` in its composer with the
references it goes to and, if you like, a note (the send button reads
"Give"):

| names | what happens |
|---|---|
| `>slug` | the conversation is queued into that thread, ahead of its next message (like a fork brought back) |
| `%slug` | a new thread in that project starts with it queued (like a fork) |
| `@name` | the bot is woken with it |

`/give >pcb-rev-b %enclosure keep the connector choice` hands one scratch
conversation to a thread and to a new thread in another project at once;
several scratch threads given to one thread gather there. The thread it came
from logs where it went and stays where it is. `/give` works in every
thread, not only scratch ones (bothub.bend's `Give`, laws `give_*`).

## Machines and people

A peer is another hub, linked by an invite: the inviting hub makes
`bp1:<url>:<peer id>:<secret hex>`; the other pastes it, and both keep the
32-byte secret. Every hub-to-hub request is signed like a webhook (below),
so the same verification guards both. Linked hubs exchange their bot
directory (name, look, mood) every minute and deliver messages with
`POST /bots/deliver`.

## Webhooks

`POST /hook/<hook id>` with

    X-Backplane-Timestamp: <unix seconds>
    X-Backplane-Signature: sha256=<hex HMAC-SHA256(secret, ts + "." + body)>

- The timestamp must be within 300 s of the hub's clock.
- A signature is accepted once (replay cache for the window).
- The comparison is constant time; the body is capped at 256 KB.
- GitHub's `X-Hub-Signature-256` is accepted with `X-GitHub-Delivery` as
  the replay key.
- The secret (32 random bytes, hex) is shown once, when the hook is made.
- The payload reaches the bot marked as untrusted data, never as
  instructions.

### Bearer tokens

A sender that cannot sign (the Pebble Index ring's app sends only fixed
headers) can use the hook's bearer token instead: `Authorization: Bearer
<token>`. A hook has none until someone asks for it (the Token button,
`bots.hook_token` with `op` "show", "new" or "off"). The token is 16
random bytes as 32 hex digits, kept by the server in
`<home>/secrets/hooks/<id>.token` (0600, gone when the hook is revoked),
never in the log; it is compared in constant time. A signature, when
there is one, is checked instead of the token. Each call with the token is
new to the replay cache (a static token proves nothing about freshness).
Refusals say why: no credentials, no token on this hook, wrong token, or
a bad or stale signature.

A `multipart/form-data` body under a token becomes a JSON object for the
bot: `source` ("pebble-index-01" when `client` is "ring", else
"form-data"), `transcription`, `recordedAt` (a number), `client`, and
`audio` as `"omitted, <X-Audio-Size> bytes"`: a bot cannot hear M4A, and
keeping untrusted binaries in its folder buys nothing. When Backplane
transcribed the recording itself, `transcription` is its words, with
`heardBy` and `unsure` (the words to ask the person about). Other bodies go as
they came. Either way the bot reads it as untrusted data, like any
webhook's.

The URL shown with the token is where a phone reaches the hub:
`BACKPLANE_HOOK_URL` when set (a funnel, a relay), else the HTTPS address
`tailscale serve` gives the hub's port, else its tailnet address over
plain HTTP (the Pebble app wants HTTPS; the panel says so). To give a hub
an HTTPS address on the tailnet without taking port 443 from another
service: `tailscale serve --bg --https=3788 http://127.0.0.1:3787`.

### A Pebble Index ring

Make a webhook for the bot, press Token, then in the Pebble app (Index 01
Settings, Webhook, a gesture):

- URL: the one shown with the token (`https://<machine>.<tailnet>.ts.net[:port]/hook/<hook id>`;
  the phone must be on the tailnet)
- Header: `Authorization` = `Bearer <token>`
- Send: Transcription, or Recording (or both) to have Backplane transcribe it
  with GPT-Live-Transcribe and your dictionary (docs/voice.md; needs the
  OpenAI key in Settings, Voice; forms may be 2 MB)

What arrives is untrusted data for the bot (above).

The hub also takes the Index webhook protocol's HMAC signature
(`X-Index-Signature`, version 1) where an app sends it: then configure:

- URL: `https://<this machine>.<tailnet>.ts.net/hook/<hook id>` (the hub
  started with `--tailscale-https`; the phone must be on the tailnet)
- Sign requests: on, with the webhook's secret pasted as it is shown
- Send: as above (a signed form with a recording is checked over its bytes)

A signed voice note reaches the bot as the person's own words, `[voice note
from your Pebble ring]` and the transcription, starting a conversation
at hop 0: only the phone holding the secret can sign it. The app's
"Send test event" is logged and wakes no one. Each gesture has its own
URL, so Hold & talk and Double click & hold can go to different bots.

## Routines

A routine is a cron line (5 fields, the hub's time zone, `*`, lists,
ranges, steps, and `@hourly`/`@daily`/`@weekly`) and a prompt. The hub's
minute tick fires a due routine once (`RoutineFired` records it), even
after being off for a while (one catch-up run, never a burst).

## Memory

Keyed, typed items, not a notebook:

- kinds: `user` (about the people it works for), `pref` (how they want
  things done), `fact` (about the world, projects, contacts), `howto`
  (procedures it learned), `note` (what happened; short-lived).
- `memory_save(key, kind, text, tags)` replaces the item with that key, so
  a bot updates what it knows instead of piling it up.
- `memory_recall(query)` ranks by words in key, tags and text, then kind,
  then recency. `memory_forget(key)`.
- Each turn a bot starts gets a short `<memory>` block: all `user` and
  `pref` items, then the few items that match the turn's text, within a
  fixed budget (law `mem_block_budget`). Notes older than 30 days leave the
  block but stay recallable.

## Space

A bot's own UI, in its Space tab. The bot writes it with `space_set(spec)`,
a JSON document of blocks:

    {"title": "...", "blocks": [
      {"type": "heading", "text": "..."},
      {"type": "text", "text": "..."},             (markdown-ish, plain)
      {"type": "stat", "label": "...", "value": "...", "hint": "..."},
      {"type": "progress", "label": "...", "value": 0.4},
      {"type": "list", "items": ["...", ...]},
      {"type": "kv", "rows": [["k", "v"], ...]},
      {"type": "table", "head": ["a","b"], "rows": [["1","2"], ...]},
      {"type": "button", "label": "...", "action": "..."},
      {"type": "input", "label": "...", "action": "...", "placeholder": "..."},
      {"type": "divider"},
      {"type": "row", "blocks": [ ...stats/buttons... ]}
    ]}

`Space.parse` keeps what it understands and caps sizes. A button or input
sends the bot `[space] <action> <value>` as a human turn (hop 0). The spec
is data, never code a client runs, so a bot cannot script a client.

A bot can also write its space as a web page with `space_page(html)` (HTML
and CSS, at most 256 KB; `""` removes it; event `SpacePageSet`). The phone
apps show it full screen in the Space tab in place of the blocks; desktop
and web keep the blocks, or say the space is a page when there are none.
The hub serves it at `GET /bots/<id>/space.html` behind `Space.page.head`,
whose policy (also sent as a header) runs no script and loads nothing from
the network: images and fonts are `data:` URLs (law `space_page_locked`).
The apps turn scripts off too (Android also blocks network loads) and load
it with no origin. A link to `space:<action>`, or a form with
`action="space:<action>"` and a field named `value`, works as a button or
an input: the app hands the URL to the `space-link` action and
`Space.link` reads it; any other URL sends nothing (law
`space_link_only_ours`), and web links open in the phone's browser. Only a
tap or a submit counts, never a navigation the page makes by itself.

## Browser

Each bot has its own page (a tab in the shared Chrome, one persistent
profile, so logins last). The page's frames are JPEG files the hub serves at
`GET /bots/<id>/screen.jpg`; a `{"t":"shot","bot":...,"n":...}` message says
when a new one is ready, and only clients showing that tab fetch it.

## Google

Gmail and Calendar through Google's APIs, not the browser: OAuth 2.0 for
installed apps with PKCE and a loopback redirect to the hub
(`/oauth/google`), or paste the redirected URL when the browser is on
another device. Tools: `gmail_search`, `gmail_read`, `gmail_send`
(asks you first), `calendar_events`, `calendar_create` (asks you first),
`google_accounts`.

Google always sends the browser back to `127.0.0.1:<port>`, so a sign-in
started on another machine's hub (a phone, or a window linked to that
hub) lands on the hub of the machine the browser runs on. The sign-in's
state names the hub that started it (its tailnet address,
`Google.state`), and a hub whose sign-in it is not answers with a
redirect there (`Google.hop`: only to a `*.ts.net` address, only once;
laws `google_state_*`, `google_hop_*`). With no hub on the browser's
machine, paste the address the browser ended on instead.

Several accounts: each sign-in adds one (Google shows its account
chooser; signing in to an address already there replaces it). They live
in `<home>/secrets/google.json` under `accounts`, the default first (a
file from before keeps its one account at its top and is read as the
first). Every tool takes an optional `account` address; without it, the
first. Settings lists the accounts, each with its own Sign out (the
`google` action `signout:<address>`; `disconnect` with no address signs
out all). Pure half: `Acct`/`Accts.*` in `src/core/google.bend`, laws
`google_accts_*`.

Connect Google in Settings signs in with Backplane's shared OAuth client,
so nobody pastes anything. The client is baked in at build time:
`scripts/build-app.sh` reads `BACKPLANE_GOOGLE_CLIENT_ID` and
`BACKPLANE_GOOGLE_CLIENT_SECRET` from its environment (release builds get
them from the repository's Actions secrets) or from a git-ignored `.env` in
the checkout or the main checkout, and `src/server/effects/google.c` hands
them to `Gs.shared`. The same variables at run time win over the baked
ones; with neither, `Google.shared` in `src/core/google.bend` is used.
The shared client asks for Gmail and Calendar (laws `google_shared_*`).
Gmail's scopes are restricted: until Google verifies the client (a yearly
security assessment), people click past an unverified-app warning and at
most 100 accounts can sign in. Own client takes a Google Cloud OAuth client
(Desktop app) of your own; it always wins over the shared one (law
`google_own_client_wins`).

Registering the shared client: a Google Cloud project with the Gmail and
Calendar APIs on, an OAuth consent screen (External, In production, scopes
`gmail.modify` and `calendar.events`), and an OAuth client of type Desktop
app. Its id and secret go in `.env` and the repository's Actions secrets
(`BACKPLANE_GOOGLE_CLIENT_ID`, `_SECRET`); an installed
app's secret is not secret (RFC 8252 8.5), PKCE protects the code. Until
Google verifies it, people see an unverified-app warning and at most 100
can sign in; while the consent screen is in Testing, sign-ins expire
after 7 days.

## Server

`src/server/botnet.bend` (secrets, signing, verifying, the directory) and
the Bots section of `src/server/server.bend` (effects, routes, Google's
tools). Routes:

| route | who | auth |
|---|---|---|
| `POST /hook/<id>` | anyone with the hook's secret or token | our signature, GitHub's or the ring's, replay cache; or the hook's bearer token; 256 KB |
| `POST /bots/deliver` | a linked machine | `X-Backplane-Peer` + signature with its secret, replay cache |
| `POST /bots/link` | the holder of an invite | the same; once per peer id |
| `GET /bots/dir` | a linked machine | the same, over the empty body |
| `POST /far/push`, `/far/log`, `/far/rpc` | one of the owner's linked machines | the same |
| `GET /bots/<id>/screen.jpg` | clients | loopback, or the pairing token |
| `GET /oauth/google` | the user's browser | loopback, or the pairing token; Google's state |

The signature is checked off the hub (the secret read from its file);
the hub then accepts the replay key once and only then changes anything.
Peer ids and hook ids name files only when they are plain ids
(`[A-Za-z0-9_-]`, at most 80). Hub-to-hub requests go through `curl` with
the signed headers on stdin and the body in a 0600 file under
`<home>/secrets/tmp`, http(s) only, no redirects. This machine's name for
others is `BACKPLANE_NAME`, else its host name; its address is its
MagicDNS name on the tailnet (same port), else its listen address.

Every minute the hub runs due routines (`date +%z` for the time zone)
and asks each linked machine for its bots; the merged list is the info
key `bots.remote` (a machine that does not answer keeps its bots, away).
`test/tools/bots_e2e.ts` runs two hubs against each other; `test/tools/newproj_e2e.ts` runs project_create on one.

Each bot is listed once (`src/core/once.bend`; laws `bot_rows_once`,
`bot_picks_once`, `hubs_bots_once`). A bot here is keyed by its id, a bot
elsewhere by its name (any case) at its machine's link id, so one bot
reported twice, or named `Kit@box` in one room and `Kit@<box's id>` in
another, is one entry, and bots with one name on two machines stay two.
`name@machine` finds a machine by its id first, then the first by name;
when a name could mean two machines (two called `laptop`, any case), the
bot is `name@<id>` and shown as `laptop (<id>)`. Two bots here with one
name show their ids. A phone paired with two linked hubs shows a bot once,
as its own hub's.

A bot elsewhere that lives on one of the owner's own machines (the
machine switcher's list: the same address, or, when the link's address is
on the owner's tailnet domain, the peer's name or MagicDNS label on the
same port, `Far.machine` in client.bend) is mirrored here (below) and
opens here, at once, as a bot like any other. A bot on anyone else's
machine, or one not mirrored yet, is a conversation (`bots.tell`). The
window no longer switches hubs to show a bot: that fetched the other hub's
whole log over the link (11 to 20 s for a 13 MB log, `test/native/link_bench.bend`).

## Threads elsewhere

`src/core/far.bend`. A hub shares its projects, ordinary project threads and bots (turns,
messages, tool calls, asks, delegated tasks, bot space, memory and routines) with the owner's other machines it is
linked to. It shares no settings, devices, links, webhooks or rooms (rooms
travel on their own, above), and nothing with a machine that is not the
owner's (`Far.own` in server.bend: the machines list; laws `far_*_stay_home`).

- Names. A thing on the machine behind link `L` is `L~<its id>` here
  (`Fr.id`; local ids never hold a `~`). So nothing from elsewhere can take
  the place of anything here, a bot shows once (its mirror and the
  directory's report of it share `BU.key`, name@link; law `bot_rows_once`),
  and a phone paired with both machines keeps the owner's own.
- Push. The owning hub is the authority. Each commit's shared changes go,
  numbered by its log, to each such peer: `POST /far/push`
  `{"name", "epoch", "since", "head", "items": [{"n", "c"}]}`, one push out per link
  at a time, later batches merged behind it (`Out.*`). A batch says it
  follows the last push that got through only while every push since did;
  after a failure or a restart it says it follows only its own start.
- Pull. A mirror takes a batch only when it follows what it has
  (`since <= head`) and only the items it lacks (`n > head`); a batch past a
  gap takes nothing and the rest is pulled: `POST /far/log {"since", "epoch"}`
  answers a page of about 400 KB `{"since", "epoch", "head", "items", "more"}` from the
  owning hub's feed (its shared lines, made from the log off the hub at
  start, then grown by each commit). A batch that comes twice, late or out
  of order changes nothing (laws `far_gap_takes_nothing`,
  `far_old_takes_nothing`, `far_overlap_takes_new`, `far_batch_again`).
- History identity. The epoch is a cached hash of the first durable wire
  change. It stays the same through restart; replacing that first change
  changes it. A pull with another epoch starts at zero. A push naming
  another epoch triggers a pull from the authority (a delayed push cannot
  revert history). Clients remove only that link's old projection, preserving
  their local sequence and other mirrors. Old mirror files and epoch-free
  messages remain readable. An exact copy of the original history prefix
  has the same epoch; reset history must replace its first change.
- Mirrors. The receiving hub keeps one per link, in memory and in
  `<home>/far/<link>.jsonl` (an epoch header, each batch's items, then `{"head"}`), and
  sends it to each client that joins (`{"t":"far","link","name","away",
  "epoch","since","head","items"}`, `since` 0) and each batch as it comes. A
  client folds it into its read model under the far ids, never counting it
  in its own log's sequence (a reconnect still asks its hub for exactly what
  it missed), and keeps how far it has each link beside the read model, so
  a fresh log forgets both at once (`Fr.fold`, `Ui.far`).
- Freshness and partitions. No polling of its own: pushes as changes
  happen; a pull at start (after the mirror is read back from disk), on a
  gap, and when the minute's directory exchange finds a link that was away
  answering again. When discovery recognizes a linked owner machine, it
  both offers the current head and pulls that peer's authoritative history
  (`Far.returned`): an earlier hint may have arrived before this side
  recognized ownership and been refused. This also checks a healthy cached
  mirror after a quick restart. These are one-time discovery actions; the
  existing minute directory and two-minute machine discovery remain the
  only periodic checks. A link that does not answer the directory, or a pull,
  is away: its bots and threads stay listed and readable, marked away
  (`far.away.<link>`, mood "away", "Kit · box (away)").
- Requests. What a client does to a thread elsewhere (write, stop, answer
  an ask, its queue, settle, a side question, its modes, a bot's space and
  routines: `Fr.methods`) goes to its hub in that hub's ids (`Fr.route`,
  `POST /far/rpc`), signed like every hub-to-hub request; the owning hub
  takes it only for what it shares (`Fr.allowed`). The client's answer
  keeps the owner's success, error and payload, with the caller's request id;
  while it is away the answer says so. Anything
  else about a far thread is refused here (law `far_route_here_stays`,
  `far_allowed_only_methods`).
- Creating anywhere. `thread.create` (its `project` a `<link>~<id>`),
  `thread.fork`, `thread.pin`/`unpin`, `thread.archive`/`unarchive` and
  `project.remove` go to the owning hub like the rest, which makes the thread
  in its own project; its answer names the new thread by its id here
  (`Fr.reply.on`: `<link>~<thread>`, the id the mirror will give it). The
  asking client keeps "making" (`Made.waiting`, `Made.coming`) until the
  mirrored thread is here, then opens it (`@thread.want`, `Bots.wanted`),
  whichever of the answer and the push comes first. The project picker can
  work on another of the owner's machines: a row at its end ("On box
  (change)", action `proj-on`, `Proj.machine`) cycles this hub and each
  machine that has answered; its requests (`fs.list`, `fs.mkdir`, `fs.find`,
  `project.add`, `project.new`) then carry `on: <link>`, which `Fr.params.link`
  routes. The owning hub runs those from a job (`Far.fs.job`: the same
  `FsJob` as for its own clients, then `FarDo` for `project.create`) and
  answers the open request. `Fr.allowed`: a create needs one of its own
  projects (not a mirror, not one it lacks); pin, archive, fork a thread it
  shares; folders and adding need nothing but an owner's link. `thread.delete`
  is not one of them (law `far_no_delete`): a thread elsewhere is deleted on
  its own machine. Laws `far_create_*`, `made_far_*`, `proj_machine_*`; tests
  `test/far_test.bend`, `bun test/tools/create_far_e2e.ts`.
- The same view. A mirrored bot is a bot in the read model, so the window,
  the web and the phones show it with the same header, tabs, space and
  chat, its thread with the same timeline and composer; only its name
  carries its machine ("Kit · box", `Label.title` and `Ui.far.title`). Its tabs are what
  its machine shares (chat, space, memory, routines; `BU.tabs.of`). A reported-only
  choice adopts the full thread when its mirror arrives, keeping an unfinished
  remote composer in place until it has been sent (`Far.arrived`). Ordinary
  thread rows, project sections and timeline headers use the same machine
  marker. On phones paired with both hubs, the paired owner's catalog
  replaces mirrored sections/rows once it has loaded (`Hubs.catalog.*`);
  its cached mirror stays visible until then. Direct paired-owner Active rows and focused thread/bot headers keep the machine name too; an offline owner is marked away, and an already-marked mirror keeps its original title. When the paired owner differs from
  the focused hub, its machine badge remains visible. Hidden Older and Settled
  counts also drop duplicates.
- Pairing. The owner's machines link by themselves; nobody pastes an
  invite (`Mate.*` in client.bend). Every two minutes a hub lists the
  tailnet's online machines of its owner that answer `GET /hello`
  (`Machines.*`), and each minute it asks those it is not linked to and
  whose address is above its own (so of two hubs exactly one asks) with
  `POST /bots/pair?name=<its name>&url=<its address>`. Only the owner's
  own devices may call it (the tailnet listener's `tailscale whois`, the
  same trust as the websocket); the answer is a fresh invite, joined like
  a pasted one (`BotJob.join`), unless the asker is none of the machines
  the hub found (403: its link could not reach back), sync with it is off
  (403) or a live link already reaches it (409). A hub started with
  `--no-tailscale` still lists the tailnet machines to switch to but pairs
  only with hubs `BACKPLANE_PEERS` names (`named`), so a throwaway hub
  never links itself to real ones. Laws `mate_*`; `test/tools/far_e2e.ts`
  pairs its two hubs this way.
- Choosing. Settings, Your machines (all four clients, `Mate.rows`) lists
  each machine found, how its sync goes (linking, in sync, catching up N
  projects, away) and On/Off: the setting `sync.<name>`. Off, nothing is
  pushed to it or taken from it (`Far.own`), it is not asked to pair, it
  is refused if it asks, and its projects leave the sidebar
  (`Side.projs`, law `mate_off_hidden`).
- Catching up. A pull's answer carries the owner's catalog: every project
  it shares, with its title, latest activity and the number of its last
  shared change (`Fr.catalog`; the feed keeps each project's number as it
  grows, `Fh.lasts`). The mirroring hub tells clients and keeps it for
  those that join later (`Fh.cat`, the mirror's last chunk). A client
  lists every project at once, in its place (a project not arrived yet
  stands in with its title and activity), and marks each still catching
  up while the link's head is short of its number (`wait~<id>`,
  `Fr.syncing`): faded, titled "Board · desk (syncing)", on all four
  clients through `Label.title`/`Label.syncing` and the phones' `quiet`.
  Projects that have arrived work meanwhile, and nothing pops in or moves.
  Laws `far_catalog_*`, `far_scope_*`.
- Not mirrored: streamed text while a far turn runs (its messages arrive as
  they are posted), file viewers for far project threads, and a bot's browser.

`test/far_test.bend` (the client's fold, routing, sharing) and
`test/tools/far_e2e.ts` (two hubs: a bot made on one shows on the other,
a message from the other reaches it and its answer comes back, away when
it stops, from disk after a restart).
