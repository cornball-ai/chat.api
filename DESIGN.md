# chat.api design

Extracted from corteza's Matrix layer (R/matrix.R, 1549 lines as of
corteza main 2026-07-20). Design method: survey the R chat-client
ecosystem, take the union of their parameters, build the contract to
that spec. Adapters implement the contract; capability flags keep them
honest about what their platform can't do.

## Candidate survey (CRAN downloads, last month, 2026-07-20)

| Package | Platform | Downloads | Send | Receive | Model |
|---|---|---:|---|---|---|
| slackr | Slack | 4,992 | yes (chat.postMessage, files, blocks) | Web API polling (conversations.history) | HTTP poll or Socket Mode (websocket) |
| telegram | Telegram | 2,447 | yes | getUpdates | HTTP long-poll |
| telegram.bot | Telegram | 484 | yes (keyboards, parse modes) | getUpdates(offset, timeout) | HTTP long-poll |
| mx.client / mx.api | Matrix | 316 / 189 | yes (markdown, E2EE via mx.crypto) | /sync(since, timeout) | HTTP long-poll |
| telegramR | Telegram | 288 | yes | yes | MTProto |
| teamr | MS Teams | 36 | webhook cards only | none | send-only webhook |
| (none on CRAN) | IRC | — | trivial over socketConnection | PRIVMSG stream | persistent socket |
| (none on CRAN) | Discord | — | — | — | websocket gateway |

rwhatsapp excluded: chat-log analysis, not a client.

## Reference transports (the 3)

1. **Matrix** — the incumbent; extraction source; dogfooded daily by the
   resident bot fleet. HTTP long-poll, E2EE, HTML markup.
2. **Slack** — largest R userbase by 2x (slackr ~5k/mo). Forces threads
   into the contract as first-class, plus the mrkdwn dialect and
   per-message identity override (username/icon per post — which is
   also the right home for corteza PR #155's model badge). Adapter
   Suggests slackr; receive via Web API polling, Socket Mode later.
3. **IRC** — no R package exists; implementable over base
   socketConnection() with zero deps. Earns the slot as the
   architectural diversifier: a persistent-socket transport that keeps
   the contract honest for Discord gateway / Slack Socket Mode later,
   plus 512-byte line limits and plain-text-only markup exercise the
   capability system.

Telegram is the obvious fourth: highest combined userbase after Slack
(~3.2k/mo across three packages) and its getUpdates long-poll is
shape-identical to Matrix /sync. Nearly free once the poll contract
exists.

## Contract sketch (union of parameters)

Client: `chat_connect(config) -> chat_client` (S3: c("chat_<adapter>", "chat_client"))

Receive: `chat_poll(client, since = NULL, timeout = NULL) -> list(messages, cursor)`
  - message: id, channel, thread, sender, body, markup, ts, kind, self,
    mentions, raw
  - self and mentions are what a bot needs to decide whether to answer:
    without self it replies to its own echo, and without mentions it
    misses a rich @-mention whose body carries no matching text
  - poll-shaped everywhere: long-poll transports map directly; socket
    transports buffer into the poll; cursor is opaque per adapter
    (Matrix since-token, Slack ts, Telegram offset, IRC position).

Send: `chat_send(client, channel, text, markup = c("plain", "markdown"),
                 thread = NULL, reply_to = NULL, identity = NULL,
                 files = NULL, kind = "message", notify = TRUE)`
  - adapters render markdown to their dialect (HTML for Matrix, mrkdwn
    for Slack, stripped for IRC); identity = per-message name/icon
    override where supported (Slack), silently ignored elsewhere unless
    required = TRUE.

Presence: `chat_typing(client, channel, on)` — capability-gated no-op default.

Rooms: `chat_resolve(client, name) -> channel id`; `chat_channels(client)`.

Capabilities: `chat_capabilities(client)` -> named logical/character:
  threads, edits, reactions, files, typing, e2ee, identity_override,
  buttons, markup_dialects, max_message_bytes.

## Extraction plan

1. Contract package (this repo): generics, message constructor,
   capability schema, a loopback adapter for tests. Zero deps.
2. Matrix adapter: move corteza's mx glue behind the contract
   (chat.matrix or in-package via Suggests mx.client/mx.api/mx.crypto —
   decide by dependency weight).
3. corteza rewires its loop (gating, sessions, commands, archiving stay
   in corteza) against chat_poll/chat_send. PR #155 lands here as the
   identity/decoration option.
4. Slack adapter (Suggests slackr), then IRC (base R), then Telegram.

---

# The two contracts still missing

Written 2026-08-07, after phases 1a-1e landed. corteza's `chat_poll()$raw`
is unread and its Matrix message plane is entirely on the contract. What
remains is 15 direct `mx.*` calls, and they are not stragglers of the
same job — they are two jobs the contract never had a shape for.

| what | calls | verb it needs |
|---|---:|---|
| current state (rooms, history, pending invites) | 3 `mx.api` | below, "state" |
| read receipts | 1 `mx.api` | `chat_mark_read()` |
| credentials and session lifecycle | 11 `mx.client` | below, "credentials" |

## Contract A: reading state, not deltas

`chat_poll()` answers "what changed since my cursor". Every remaining
`mx.api` call in corteza asks the opposite question — "what is true
now" — and there is no half of the contract that answers it.

The three sites:

- `mx_rooms(sess)` — which rooms am I in? Startup backfill iterates them.
- `mx_messages(sess, rid, dir = "b", limit = 30)` — the recent tail of a
  room, replayed into a fresh process's session history so a restart
  does not lose context.
- `mx_sync(sess, timeout = 0)` with no `since` — a full sync at startup,
  purely to see invitations. Conduit only reports invites that arrived
  after the `since` token, so a bot invited while it was down never
  learns about it from the poll loop. corteza then hands the raw
  response to `mx_extract_invite_records()`.

That third one is the tell. An invitation is standing state, which the
contract already conceded when `chat_invite` was given no `ts` ("an
invitation is a standing state rather than an event at a moment"). A
record with no timestamp cannot be a delta, so delivering it only
through a cursor-driven poll was always going to leave a hole — and the
hole is exactly the case where the bot was offline when it mattered.

Proposed surface:

```r
chat_channels(client)                                  # -> character
chat_history(client, channel, limit = 50, before = NULL)  # -> list(chat_message)
chat_pending(client)                                   # -> list(invites = list(chat_invite))
chat_mark_read(client, channel, message_id)            # -> TRUE, invisibly
```

Four decisions worth making deliberately:

1. **`chat_history()` returns chronological order**, oldest first, whatever
   the platform's native direction. Matrix `dir = "b"` and Slack
   `conversations.history` both hand back newest-first, and corteza
   already flips it (`chunk <- rev(msgs$chunk)`). One flip in the adapter
   beats one per consumer, and a consumer replaying history into a
   transcript needs the order to be right, not documented.
2. **History and poll overlap, and the contract says so.** The same
   message can arrive from both, so `chat_message$id` is the dedup key
   and adapters must return the same id from both paths. corteza already
   depends on this through `seen_event_ids`; today it is a coincidence of
   both paths reading `event_id`, not a promise.
3. **`chat_pending()` rather than a `since = NA` mode on `chat_poll()`.**
   Overloading the cursor makes "start from nothing" and "tell me what is
   standing" the same call, and they differ: the first consumes a cursor
   position, the second must not. A bot that asked for pending invites and
   thereby reset its read position would replay every room on startup.
4. **`chat_mark_read()` is write-only for now.** Reading other people's
   read state is a much larger surface (per-user receipts, per-device,
   Slack's absence of it) and nothing needs it. Ship the half with a
   consumer.

Capability flags: `channels`, `history`, `pending`, `mark_read`. Slack has
all four (`conversations.list`, `conversations.history`,
`conversations.mark`; `pending` is empty since Slack bots are added
rather than invited, which `invites = FALSE` already says). IRC has
`channels` and nothing else. Loopback gets `history` for free from its
in-memory log.

## Contract B: credentials and session lifecycle

The larger of the two, and a prerequisite for 1f rather than a follow-on.

### Why 1f is blocked

Phase 1f is "stop returning `$client` from `chat_poll()`". It cannot be
done yet, and the reason is specific: **corteza rotates its own access
token mid-loop, and disk is how that rotation propagates.**

A `/model` command renames the bot. The rename calls
`mx.client::mx_set_displayname()`, which wraps itself in
`mx_with_relogin()`, which persists a refreshed config and returns only
`TRUE` — discarding the client it just refreshed. So corteza re-reads
the config from disk (`R/matrix.R:974`, with a comment explaining that
disk is authoritative either way) and rebuilds every client from it.
That is what `chat_now()` and `matrix_reply_send(cfg, ...)` are for, and
there is a regression test driving the whole poll loop to prove the
rotated token reaches the acknowledgement send.

So the nine `chat_now()` / `matrix_reply_send(cfg, ...)` call sites are
not redundancy to be tidied away — collapsing them onto one long-lived
`chat` object would reintroduce exactly the bug that test guards. And
`chat_poll()$client` is how the loop seeds `cfg` in the first place.
Remove it without moving the rename, and corteza either loses the
rotation or reaches into `chat$env` for it.

Two rotation paths, two owners, one shared file. That is the actual
defect, and `$client` is a symptom.

### The eleven calls

| group | calls |
|---|---|
| where the file lives | `mx_client_config_path`, `mx_client_legacy_config_path` |
| read/write | `mx_client_load`, `mx_client_save`, `mx_client_from_config` |
| credentials to live client | `mx_client_session` |
| refresh | `mx_client_relogin` |
| first-time setup | `mx_client_configure` |
| profile | `mx_set_displayname` |
| msgtype escape hatch | `mx_send_text` |

The last is not a credential concern: `matrix_send()` falls back to a
direct send for msgtypes the contract's `kind` vocabulary cannot carry
(`m.image` and friends). It goes away by widening `kind`, or stays as an
honest documented hatch. Either way it is separate.

### Direction

**Make the client object the sole owner of its credentials**, so rotation
never needs a file to propagate.

1. **`chat_set_identity(client, display = NULL, avatar = NULL)`.** Moves
   the rename behind the contract. The relogin it triggers then happens
   inside the adapter and lands in `client$env$mx` like the poll's does.
   This single verb is what unblocks 1f: with it, nothing outside the
   adapter rotates a token, so `chat_now()` collapses to `chat`,
   `matrix_reply_send()` takes the client, and `$client` has no consumer
   left. Slack maps it to `users.profile.set`; IRC to `NICK`;
   `identity_override = TRUE` adapters already do the per-message form,
   and this is the persistent one.
2. **`chat_credentials()` / `chat_save()` — resist.** Where an
   application keeps its config is the application's business, and a
   contract that owns the file has to own its format, its migration, and
   its permissions. What corteza actually needs is narrower: to stop
   holding a plain list it indexes by `user_id`, `token`, `room_id`.
   Those are Matrix field names, and `chat_whoami()` already replaced the
   first. The rest are read at exactly two kinds of site: building a
   client (`chat_matrix(mx = cfg)`) and reading policy (`bots`,
   `operators`, `model_badge` — corteza's own fields, not Matrix's).
   Splitting corteza's config into "transport credentials, opaque" and
   "corteza policy, ours" is a corteza change that needs no new verb.
3. **`chat_connect(config)` as the one construction path.** DESIGN.md
   sketched it and it was never built; adapters are constructed by
   name (`chat_matrix()`, `chat_slack()`). That is fine for an
   application that knows its transport, and corteza does. The thing
   worth adding is not a generic constructor but a guarantee: **a
   `chat_client` is durable and self-healing.** Build it once per
   process, hold it, and every verb keeps it current. Document that,
   and `chat_now()` stops looking prudent and starts looking like a
   workaround.
4. **`mx_client_configure()` stays in corteza.** Interactive first-run
   setup is a terminal UI over transport-specific questions (homeserver,
   password, device name). A generic version would be a lowest common
   denominator that suits nobody.

### Order

`chat_set_identity()` first — it is one verb, it unblocks 1f, and 1f is
the last item of phase 1. The config split is a corteza-side change with
no contract dependency and can go in parallel. Contract A is independent
of both.
