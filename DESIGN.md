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
