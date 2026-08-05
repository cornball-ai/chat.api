# Matrix adapter verification that needs nothing installed. Every client
# here supplies mx plus all four seams, which is the configuration
# chat_matrix() documents as running without mx.client, so these
# assertions are the ones that must not disappear on a bare CI runner.
# The half that pins the adapter to mx.client's real signatures lives in
# test_matrix_mxclient.R, which announces its skip.

fake_mx <- function(sync_token = NULL) {
    list(user_id = "@bot:ex", server = "https://ex.invalid",
         sync_token = sync_token)
}

# An extractor-shaped record: the seven fields mx_extract_text_events
# has always returned, plus ts, which only newer builds carry.
rec <- function(event_id, sender = "@alice:ex", body = "hello",
                msgtype = "m.text", is_self = FALSE, mentions = NULL,
                ts = NULL, room_id = "!room:ex") {
    list(room_id = room_id, event_id = event_id, sender = sender,
         is_self = is_self, body = body, msgtype = msgtype, ts = ts,
         mentions = mentions)
}

# A timeline event carrying the origin_server_ts the extractor may or
# may not pass through.
ev <- function(event_id, ts = 1700000000000, sender = "@alice:ex",
               body = "hello", msgtype = "m.text", content = list()) {
    list(type = "m.room.message", event_id = event_id, sender = sender,
         origin_server_ts = ts,
         content = c(list(msgtype = msgtype, body = body), content))
}

wrap_sync <- function(events, room = "!room:ex") {
    join <- list(list(timeline = list(events = events)))
    names(join) <- room
    list(rooms = list(join = join))
}

# A fully seamed client. recs is what the .extract seam hands back, so
# the mapping under test never depends on which mx.client is installed.
# send and media are named parameters rather than `...` pass-throughs so
# a test can watch the cleartext path without colliding with the defaults
# this helper already supplies.
seam_client <- function(recs = list(), sync = wrap_sync(list()),
                        first_run = FALSE, token = "s1", mx = fake_mx(),
                        record = NULL, send = function(...) "$id",
                        media = function(...) NULL, ...) {
    chat_matrix(mx = mx,
        .sync = function(client, ...) {
            if (!is.null(record)) {
                record$sync[[length(record$sync) + 1L]] <- c(
                    list(client = client), list(...))
            }
            list(sync = sync, client = fake_mx(token), first_run = first_run)
        },
        .extract = function(sync_resp, self_id, ...) {
            if (!is.null(record)) {
                record$extract[[length(record$extract) + 1L]] <- list(
                    sync_resp = sync_resp, self_id = self_id)
            }
            recs
        },
        .send = send, .media = media, ...)
}

# ---- Constructor ----

cl <- seam_client()
expect_inherits(cl, "chat_matrix")
expect_inherits(cl, "chat_client")
expect_identical(cl$env$mx$user_id, "@bot:ex")
expect_true(cl$save_cursor)
expect_true(cl$relogin)

# save_cursor and relogin are coerced, not passed through raw
expect_false(chat_matrix(mx = fake_mx(), save_cursor = NULL,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL)$save_cursor)
expect_false(chat_matrix(mx = fake_mx(), relogin = NULL,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL)$relogin)

# app defaults to NULL so a wrapped config's own app/path attributes
# decide where mx.client persists the cursor. Naming an app here is an
# override, and an override aimed at the wrong namespace writes the
# bot's credentials into a second file and never advances the real one.
expect_null(cl$app)
expect_identical(seam_client(mx = fake_mx(), app = "myapp")$app, "myapp")

# ---- Poll: the .extract seam is load-bearing ----
# Without this, extract_fn could be replaced by a hardcoded
# mx.client::mx_extract_text_events and nothing would notice -- which
# would quietly break the documented seams-only configuration.

trace <- new.env()
trace$sync <- list()
trace$extract <- list()
sync_one <- wrap_sync(list(ev("$1")))
p <- seam_client(recs = list(rec("$1")), sync = sync_one, record = trace)
got <- chat_poll(p, timeout = 30)

expect_identical(length(got$messages), 1L)
expect_identical(got$messages[[1L]]$id, "$1")
# The seam is handed the sync response and the post-sync user id
expect_identical(length(trace$extract), 1L)
expect_identical(trace$extract[[1L]]$sync_resp, sync_one)
expect_identical(trace$extract[[1L]]$self_id, "@bot:ex")

# ---- Poll: cursor, timeout, and forwarded arguments ----

expect_identical(trace$sync[[1L]]$timeout, 30000L)
expect_true(trace$sync[[1L]]$save)
# app rides through as NULL by default, leaving the wrapped config's
# own namespace in charge. It is passed, not omitted: mx_sync_update
# reads it as `app %||% attr(client, "app")`, so NULL is the value that
# defers and a stray "chat.api" is the value that hijacks.
expect_true("app" %in% names(trace$sync[[1L]]))
expect_null(trace$sync[[1L]]$app)
expect_identical(got$cursor, "s1")
expect_identical(p$env$mx$sync_token, "s1")
expect_identical(got$raw, sync_one)

# An explicit app is forwarded verbatim
trace2 <- new.env()
trace2$sync <- list()
trace2$extract <- list()
chat_poll(seam_client(record = trace2, app = "myapp"))
expect_identical(trace2$sync[[1L]]$app, "myapp")
# Absent timeout is 0, not an error
expect_identical(trace2$sync[[1L]]$timeout, 0L)

# `...` reaches mx_sync_update. filter is a real parameter of it, and
# the only way to ask the homeserver for a narrower sync.
trace3 <- new.env()
trace3$sync <- list()
trace3$extract <- list()
chat_poll(seam_client(record = trace3), filter = "{\"room\":{}}")
expect_identical(trace3$sync[[1L]]$filter, "{\"room\":{}}")

# An explicit `since` overrides the stored token
trace4 <- new.env()
trace4$sync <- list()
trace4$extract <- list()
p4 <- seam_client(record = trace4, mx = fake_mx("s_prev"))
chat_poll(p4)
expect_identical(trace4$sync[[1L]]$client$sync_token, "s_prev")
chat_poll(p4, since = "s_forced")
expect_identical(trace4$sync[[2L]]$client$sync_token, "s_forced")

# save_cursor rides through to the persistence decision
trace5 <- new.env()
trace5$sync <- list()
trace5$extract <- list()
chat_poll(seam_client(record = trace5, save_cursor = FALSE))
expect_false(trace5$sync[[1L]]$save)

# ---- Poll: the post-sync client comes back out ----
# A relogin can swap the token mid-poll. A consumer that keeps driving
# mx.api off its own pre-poll copy spends the rest of the cycle
# authenticating with the token the homeserver just rejected.

expect_true("client" %in% names(got))
expect_identical(got$client$sync_token, "s1")
expect_identical(got$client$user_id, "@bot:ex")

# ---- Poll: timestamps ----
# The one field that is silently wrong rather than loudly missing when
# it breaks, so it is asserted by value, never by class.

# From the record, when the extractor carries ts
tsm <- chat_poll(seam_client(recs = list(rec("$1", ts = 1700000000000)),
                             sync = wrap_sync(list(ev("$1")))))$messages[[1L]]
expect_inherits(tsm$ts, "POSIXct")
expect_equal(as.numeric(tsm$ts), 1700000000, tolerance = 1e-6)

# From the sync, when it does not. Builds of mx.client on either side of
# the change that added ts share a version string, so the adapter cannot
# tell them apart and has to work on both.
fallback <- chat_poll(seam_client(recs = list(rec("$1", ts = NULL)),
    sync = wrap_sync(list(ev("$1", ts = 1700000000000)))))$messages[[1L]]
expect_equal(as.numeric(fallback$ts), 1700000000, tolerance = 1e-6)

# The record wins when both are present
both <- chat_poll(seam_client(recs = list(rec("$1", ts = 1700000000000)),
    sync = wrap_sync(list(ev("$1", ts = 1600000000000)))))$messages[[1L]]
expect_equal(as.numeric(both$ts), 1700000000, tolerance = 1e-6)

# Events are matched by id, not by position
pair <- chat_poll(seam_client(
    recs = list(rec("$2", body = "second"), rec("$1", body = "first")),
    sync = wrap_sync(list(ev("$1", ts = 1700000000000),
                          ev("$2", ts = 1700000086400)))))$messages
expect_equal(as.numeric(pair[[1L]]$ts), 1700000086.4, tolerance = 1e-6)
expect_equal(as.numeric(pair[[2L]]$ts), 1700000000, tolerance = 1e-6)

# Neither source has one: NA, not the poll's wall clock. Stamping
# Sys.time() would make a restart's whole backfill look like it arrived
# at once, and no consumer ordering or windowing by ts could tell.
unknown <- chat_poll(seam_client(recs = list(rec("$9", ts = NULL)),
    sync = wrap_sync(list())))$messages[[1L]]
expect_inherits(unknown$ts, "POSIXct")
expect_true(is.na(unknown$ts))

# ---- Poll: message mapping ----

mapped <- chat_poll(seam_client(
    recs = list(rec("$1", sender = "@alice:ex", body = "hello",
                    mentions = list("@bot:ex")),
                rec("$2", sender = "@bot:ex", body = "my own echo",
                    is_self = TRUE)),
    sync = wrap_sync(list(ev("$1"), ev("$2")))))

expect_identical(length(mapped$messages), 2L)
m <- mapped$messages[[1L]]
expect_inherits(m, "chat_message")
expect_identical(m$id, "$1")
expect_identical(m$channel, "!room:ex")
expect_identical(m$sender, "@alice:ex")
expect_identical(m$body, "hello")
expect_identical(m$markup, "plain")
expect_null(m$thread)

# kind is the contract's vocabulary, not Matrix's. Leaving m.text on the
# record makes every Matrix message fail a cross-adapter
# `kind == "message"` filter that Slack, IRC, and loopback traffic pass.
expect_identical(m$kind, "message")
expect_identical(chat_poll(seam_client(
    recs = list(rec("$1", msgtype = "m.notice"))))$messages[[1L]]$kind,
    "notice")
expect_identical(chat_poll(seam_client(
    recs = list(rec("$1", msgtype = "m.emote"))))$messages[[1L]]$kind,
    "emote")
# An unmapped msgtype degrades to "message" rather than leaking through
expect_identical(chat_poll(seam_client(
    recs = list(rec("$1", msgtype = "m.image"))))$messages[[1L]]$kind,
    "message")
expect_identical(chat_poll(seam_client(
    recs = list(rec("$1", msgtype = NULL))))$messages[[1L]]$kind, "message")

# Self events are retained, and flagged. A consumer that cannot tell its
# own traffic apart answers itself, and the reply comes back on the next
# sync as fresh mail.
expect_identical(vapply(mapped$messages, `[[`, logical(1), "self"),
                 c(FALSE, TRUE))
expect_identical(vapply(mapped$messages, `[[`, "", "body"),
                 c("hello", "my own echo"))

# mentions survive as a character vector. A bot in a multi-human room
# gates its replies on this; body substring matching misses a rich
# mention whose plain text is just a display name.
expect_identical(m$mentions, "@bot:ex")
expect_null(mapped$messages[[2L]]$mentions)

# raw is the record the transport handed over, which for Matrix is
# mx_extract_text_events' output, not the timeline event. The relation
# on a threaded message is reachable through the poll's raw and nowhere
# else, so a consumer reaching for msg$raw$m.relates_to gets NULL.
threaded_sync <- wrap_sync(list(ev("$4", body = "in a thread",
    content = list("m.relates_to" = list(rel_type = "m.thread",
                                         event_id = "$root")))))
tp <- seam_client(recs = list(rec("$4", body = "in a thread")),
                  sync = threaded_sync)
tres <- chat_poll(tp)
tmsg <- tres$messages[[1L]]
expect_identical(tmsg$body, "in a thread")
expect_null(tmsg$thread)
expect_false(chat_capabilities(tp)$thread_replies)
expect_null(tmsg$raw[["m.relates_to"]])
expect_identical(
    tres$raw$rooms$join[["!room:ex"]]$timeline$events[[1L]]$content[["m.relates_to"]]$rel_type,
    "m.thread")

# ---- Poll: first_run ----
# The headline of the poll contract, and the field a consumer needs on a
# bare runner as much as anywhere else, so none of it sits behind a
# Suggests gate.

empty <- chat_poll(seam_client(first_run = TRUE, token = "s0"))
expect_identical(length(empty$messages), 0L)
expect_identical(empty$cursor, "s0")
expect_true(empty$first_run)
expect_false(got$first_run)

# A sync response that omits first_run reports FALSE, not NULL: the
# field is always present and always a single logical
silent <- chat_matrix(mx = fake_mx(),
                      .sync = function(client, ...) {
                          list(sync = wrap_sync(list()),
                               client = fake_mx("s0"))
                      },
                      .extract = function(...) list(),
                      .send = function(...) "$id",
                      .media = function(...) NULL)
expect_identical(chat_poll(silent)$first_run, FALSE)

# ---- Poll: relogin wiring ----
# mx_with_relogin hands the retry a re-authenticated config. The sync
# has to run off whatever config it is given: wiring it to reach back
# into the client's env instead retries with the token the homeserver
# just rejected, and the second rejection escapes the handler.

token_error <- function(client, ...) {
    # mx_with_relogin builds the retry's client inside the call
    # expression, so a fake that never touches its argument leaves the
    # re-login unevaluated and the retry indistinguishable from the
    # first attempt. The real mx_sync_update reads client$sync_token on
    # its first line; this forces the same way.
    force(client)
    stop(structure(class = c("mx_error_M_UNKNOWN_TOKEN", "error", "condition"),
                   list(message = "M_UNKNOWN_TOKEN", call = NULL)))
}
expired <- function(relogin) {
    chat_matrix(mx = fake_mx(), relogin = relogin, .sync = token_error,
                .extract = function(...) list(),
                .send = function(...) "$id", .media = function(...) NULL)
}
# relogin = FALSE lets the condition through untouched
expect_error(chat_poll(expired(FALSE)), "M_UNKNOWN_TOKEN")

if (requireNamespace("mx.client", quietly = TRUE)) {
    # relogin = TRUE catches it and attempts a re-login, handing the
    # retry the config that re-login produced. This config has no stored
    # password, so mx.client refuses before any network call -- a
    # different error, which is the evidence the wrapper ran and that
    # the sync closure takes its client as an argument instead of
    # reaching back into the client's env. The successful-retry half
    # needs a homeserver and is not covered here.
    expect_error(suppressMessages(chat_poll(expired(TRUE))),
                 "no stored password")
}

# ---- Send: msgtype and markup mapping ----

send_calls <- new.env()
send_calls$args <- list()
fake_send <- function(mx, text, ...) {
    send_calls$args[[length(send_calls$args) + 1L]] <- c(list(text = text),
                                                          list(...))
    "$sent"
}
media_calls <- new.env()
media_calls$args <- list()
fake_media <- function(mx, file, ...) {
    media_calls$args[[length(media_calls$args) + 1L]] <- c(list(file = file),
                                                            list(...))
    sprintf("$media%d", length(media_calls$args))
}

s <- chat_matrix(mx = fake_mx(), .sync = function(...) NULL,
                 .extract = function(...) list(),
                 .send = fake_send, .media = fake_media)

# Default send is plain m.text, and the id comes back as a character
id <- chat_send(s, "!room:ex", "plain words")
expect_identical(id, "$sent")
a1 <- send_calls$args[[1L]]
expect_identical(a1$text, "plain words")
expect_identical(a1$room, "!room:ex")
expect_identical(a1$msgtype, "m.text")
expect_false(a1$markdown)

# markup = "markdown" flips the render flag, msgtype is unchanged
chat_send(s, "!room:ex", "**bold**", markup = "markdown")
a2 <- send_calls$args[[2L]]
expect_true(a2$markdown)
expect_identical(a2$msgtype, "m.text")

# kind maps onto Matrix msgtypes
chat_send(s, "!room:ex", "quietly", kind = "notice")
expect_identical(send_calls$args[[3L]]$msgtype, "m.notice")
chat_send(s, "!room:ex", "waves", kind = "emote")
expect_identical(send_calls$args[[4L]]$msgtype, "m.emote")
# an unrecognized kind degrades to m.text rather than erroring
chat_send(s, "!room:ex", "whatever", kind = "sparkle")
expect_identical(send_calls$args[[5L]]$msgtype, "m.text")

# An unknown markup is rejected by match.arg, not silently sent
expect_error(chat_send(s, "!room:ex", "x", markup = "html"))

# `...` reaches mx_send_text. Its mentions argument is the only way to
# emit an m.mentions user_ids list, which is what modern clients key
# their push rules off -- without it an addressed reply never notifies.
chat_send(s, "!room:ex", "hi there", mentions = "@carol:ex")
expect_identical(send_calls$args[[6L]]$mentions, "@carol:ex")

# ---- Send: files ----

media_calls$args <- list()
chat_send(s, "!room:ex", "see attached", files = c("/tmp/a.png",
                                                   "/tmp/b.png"))
# One call per file, in order, into the same room. Uploading the first
# file twice or dropping the second is a silent data loss, so both the
# order and every room have to be pinned.
expect_identical(vapply(media_calls$args, `[[`, "", "file"),
                 c("/tmp/a.png", "/tmp/b.png"))
expect_identical(vapply(media_calls$args, `[[`, "", "room"),
                 c("!room:ex", "!room:ex"))
# ... and the text still goes, returning its own id
expect_identical(send_calls$args[[7L]]$text, "see attached")

# An attachment-only send is the uploads and nothing else: Matrix
# accepts an empty body and clients render it as a blank bubble, so
# posting one after every file leaves visible litter in the room. The
# media event ids come back so the caller can redact or react to them.
media_calls$args <- list()
before <- length(send_calls$args)
only <- chat_send(s, "!room:ex", "", files = c("/tmp/a.png", "/tmp/b.png"))
expect_identical(length(media_calls$args), 2L)
expect_identical(length(send_calls$args), before)
expect_identical(only, c("$media1", "$media2"))

# ---- Capabilities ----

caps <- chat_capabilities(s)
# Every flag answers "can this adapter do it", not "can Matrix do it".
# Matrix threads are replies, not first-class channels
expect_false(caps$threads)
# thread_replies stays FALSE while chat_poll cannot fill in $thread:
# mx_extract_text_events drops content$m.relates_to, so the relation
# never reaches the adapter. The flag and the mapping move together.
expect_false(caps$thread_replies)
# reactions: chat.api has no reaction verb, and the extractor's m.text
# filter means an m.reaction can be neither sent nor received here
expect_false(caps$reactions)
expect_false("chat_react" %in% getNamespaceExports("chat.api"))
# e2ee answers for this client. `s` was built without e2ee = TRUE, so it
# holds no crypto context and chat_send goes through mx_send_text, which
# PUTs a cleartext m.room.message whatever the room's encryption state
# says. Reporting TRUE off an installed mx.crypto would invite a consumer
# to hand this client a secret and have it land on the homeserver in the
# clear. The e2ee = TRUE half is asserted in the E2EE block below.
expect_false(caps$e2ee)
expect_true(is.logical(caps$e2ee) && length(caps$e2ee) == 1L)
expect_true(caps$files)
expect_true(caps$typing)
# Matrix has no per-message identity override
expect_false(caps$identity_override)
expect_identical(caps$markup_dialects, c("plain", "markdown"))

# chat_send() returns every event it created, in send order. A caller
# that tracks its own traffic by id has to see the attachment events too,
# or each attachment's echo reads as somebody else's message.
local({
    sent <- new.env(); sent$media <- character(); sent$text <- 0L
    cl <- chat_matrix(mx = fake_mx(),
        .sync = function(...) NULL, .extract = function(...) list(),
        .send = function(...) { sent$text <- sent$text + 1L; "$text1" },
        .media = function(mx, file, ...) {
            id <- paste0("$media", length(sent$media) + 1L)
            sent$media <- c(sent$media, id)
            id
        })

    # Text only: one id, as every other adapter returns.
    expect_identical(chat_send(cl, "!r:ex", "hello"), "$text1")

    # Files plus text: media first, text last, so the conversational
    # event is always the final element.
    ids <- chat_send(cl, "!r:ex", "see these", files = c("/a.png", "/b.png"))
    expect_identical(ids, c("$media1", "$media2", "$text1"))
    expect_identical(ids[[length(ids)]], "$text1")

    # Attachment-only: the media ids and no empty text event.
    before <- sent$text
    only <- chat_send(cl, "!r:ex", "", files = "/c.png")
    expect_identical(only, "$media3")
    expect_identical(sent$text, before)
})

# ---- E2EE ----
# The .crypto seam stands in for the whole crypto module, so these run
# with neither mx.crypto nor a Rust toolchain. What is under test is the
# adapter's routing: which path a send takes, and whether decrypted
# events reach the caller as ordinary chat_message records.

# A fake crypto context plus ops that record what the adapter asked for.
# Contexts are interned per identity, so a fresh fake starts by dropping
# whatever the previous one interned; otherwise every case after the first
# would silently reuse an earlier fake's context.
fake_crypto <- function(encrypted_rooms = "!enc:ex", decrypted = list(),
                        event_id = "$enc1", decrypt_error = FALSE) {
    chat.api:::matrix_crypto_forget()
    log <- new.env(parent = emptyenv())
    log$init <- list()
    log$asked <- character()
    log$sent <- list()
    log$decrypted <- 0L
    ctx <- new.env(parent = emptyenv())
    ctx$encrypted <- encrypted_rooms
    ops <- list(
        init = function(mx, store = NULL, app = NULL) {
            log$init[[length(log$init) + 1L]] <- list(mx = mx, store = store,
                                                      app = app)
            ctx
        },
        encrypted = function(crypto, mx, room_id) {
            log$asked <- c(log$asked, room_id)
            room_id %in% crypto$encrypted
        },
        send = function(crypto, mx, room_id, text, msgtype = "m.text",
                        markdown = FALSE, mentions = NULL) {
            log$sent[[length(log$sent) + 1L]] <- list(
                room_id = room_id, text = text, msgtype = msgtype,
                markdown = markdown, mentions = mentions, mx = mx)
            event_id
        },
        decrypt = function(crypto, sync, mx) {
            log$decrypted <- log$decrypted + 1L
            if (isTRUE(decrypt_error)) {
                stop("no session for that megolm stream")
            }
            decrypted
        })
    list(ops = ops, log = log, ctx = ctx)
}

# e2ee is opt-in. Without it there is no crypto context, so nothing the
# adapter does can consult one -- this is the pre-E2EE behaviour exactly.
plain <- seam_client()
expect_null(plain$env$crypto)
expect_false(plain$e2ee)
expect_false(chat_capabilities(plain)$e2ee)

# init is not called either: an unused crypto module must not touch the
# store or publish keys.
f <- fake_crypto()
off <- seam_client(e2ee = FALSE, .crypto = f$ops)
expect_identical(length(f$log$init), 0L)
expect_null(off$env$crypto)

# e2ee = TRUE builds the context, and the capability follows the context
# rather than the installed packages.
f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops)
expect_identical(length(f$log$init), 1L)
expect_true(is.environment(enc$env$crypto))
expect_true(chat_capabilities(enc)$e2ee)

# The store is derived inside init, not by the constructor, so mx.client
# is only needed on the path that does crypto. app and an explicit
# crypto_store both reach it.
f <- fake_crypto()
seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
expect_identical(f$log$init[[1L]]$app, "cornelius")
expect_null(f$log$init[[1L]]$store)
f <- fake_crypto()
seam_client(e2ee = TRUE, crypto_store = "/tmp/store", .crypto = f$ops)
expect_identical(f$log$init[[1L]]$store, "/tmp/store")

# An explicit config path with no app and no crypto_store cannot name a
# unique store: the default is keyed on the app namespace alone, so two
# bots built that way would share one Olm account and the second would
# come up wearing the first's device keys. That is an error, not a guess.
expect_error(chat_matrix(mx = fake_mx(), path = "/tmp/bot.json", e2ee = TRUE,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL,
                         .crypto = fake_crypto()$ops),
             "unique to this identity")
# The same path with an app names one, so it is allowed.
f <- fake_crypto()
ok <- chat_matrix(mx = fake_mx(), path = "/tmp/bot.json", app = "tiny",
                  e2ee = TRUE, .sync = function(...) NULL,
                  .extract = function(...) list(),
                  .send = function(...) "$id", .media = function(...) NULL,
                  .crypto = f$ops)
expect_true(is.environment(ok$env$crypto))
# ... and so does crypto_store on its own.
expect_true(is.environment(
    chat_matrix(mx = fake_mx(), path = "/tmp/bot.json", e2ee = TRUE,
                crypto_store = "/tmp/store", .sync = function(...) NULL,
                .extract = function(...) list(),
                .send = function(...) "$id", .media = function(...) NULL,
                .crypto = fake_crypto()$ops)$env$crypto))

# ---- One Olm account per identity ----
# A consumer that derives a fresh client per use -- corteza does, so the
# rotating access token is never cached -- must not mint a second Olm
# account each time. Interning is what reconciles a short-lived client
# with a long-lived crypto identity.

f <- fake_crypto()
a <- seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
b <- seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
expect_identical(length(f$log$init), 1L)
expect_true(identical(a$env$crypto, b$env$crypto))

# Two identities are two contexts. Sharing one would have the second bot
# come up wearing the first's device keys.
f <- fake_crypto()
one <- seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
two <- seam_client(e2ee = TRUE, app = "tiny", .crypto = f$ops)
expect_identical(length(f$log$init), 2L)
expect_identical(f$log$init[[1L]]$app, "cornelius")
expect_identical(f$log$init[[2L]]$app, "tiny")
# The fake returns one shared environment, so identity of the context
# cannot be the assertion here; that init ran twice is.
expect_identical(sort(names(f$log$init[[1L]])), c("app", "mx", "store"))

# An explicit crypto_store keys on the store, and the app default keys on
# the app, so the two never collide.
f <- fake_crypto()
seam_client(e2ee = TRUE, crypto_store = "/tmp/store-a", .crypto = f$ops)
seam_client(e2ee = TRUE, crypto_store = "/tmp/store-a", .crypto = f$ops)
seam_client(e2ee = TRUE, crypto_store = "/tmp/store-b", .crypto = f$ops)
expect_identical(length(f$log$init), 2L)

# The cache key is a plain identity string, not a resolved directory:
# resolving one calls into mx.client, and the seam exists so the e2ee
# paths run without it.
expect_identical(chat.api:::matrix_crypto_cache_key(NULL, NULL), "app:chat.api")
expect_identical(chat.api:::matrix_crypto_cache_key(NULL, "tiny"), "app:tiny")
expect_identical(chat.api:::matrix_crypto_cache_key("/s", "tiny"), "/s")

# Forgetting one identity leaves the others interned.
f <- fake_crypto()
seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
seam_client(e2ee = TRUE, app = "tiny", .crypto = f$ops)
chat.api:::matrix_crypto_forget("app:tiny")
seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
seam_client(e2ee = TRUE, app = "tiny", .crypto = f$ops)
expect_identical(length(f$log$init), 3L)
expect_identical(f$log$init[[3L]]$app, "tiny")

# ---- Encrypted sends ----

# An encrypted room takes the Megolm path and the cleartext send never
# runs. This is the assertion that matters most: a regression here PUTs
# plaintext into a room the user believes is encrypted.
f <- fake_crypto()
cleartext <- new.env(parent = emptyenv()); cleartext$n <- 0L
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   send = function(...) { cleartext$n <- cleartext$n + 1L
                                          "$clear1" })
id <- chat_send(enc, "!enc:ex", "secret")
expect_identical(id, "$enc1")
expect_identical(cleartext$n, 0L)
expect_identical(length(f$log$sent), 1L)
expect_identical(f$log$sent[[1L]]$text, "secret")
expect_identical(f$log$sent[[1L]]$room_id, "!enc:ex")

# A cleartext room on the same client still goes out in the clear: e2ee
# is a per-room property, not a per-client one.
id <- chat_send(enc, "!plain:ex", "public")
expect_identical(id, "$clear1")
expect_identical(cleartext$n, 1L)
expect_identical(length(f$log$sent), 1L)

# The room is asked about on every send rather than once at init, so a
# room that turns on encryption between polls does not get one cleartext
# message first.
expect_identical(f$log$asked, c("!enc:ex", "!plain:ex"))
f$ctx$encrypted <- c(f$ctx$encrypted, "!plain:ex")
expect_identical(chat_send(enc, "!plain:ex", "now secret"), "$enc1")
expect_identical(cleartext$n, 1L)

# markup, kind, and mentions carry into the encrypted branch. Dropping
# them would make an encrypted room silently lose formatting and pings
# that the same call gets in the clear.
f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops)
chat_send(enc, "!enc:ex", "**bold**", markup = "markdown",
          mentions = "@carol:ex", kind = "notice")
expect_true(f$log$sent[[1L]]$markdown)
expect_identical(f$log$sent[[1L]]$mentions, "@carol:ex")
expect_identical(f$log$sent[[1L]]$msgtype, "m.notice")
chat_send(enc, "!enc:ex", "plain words")
expect_false(f$log$sent[[2L]]$markdown)
expect_null(f$log$sent[[2L]]$mentions)
expect_identical(f$log$sent[[2L]]$msgtype, "m.text")

# The encrypted send takes the client's live mx, not a copy captured at
# init. A relogin replaces the token mid-poll, and a cached config would
# spend the rest of the run authenticating with the rejected one.
enc$env$mx <- fake_mx(sync_token = "rotated")
chat_send(enc, "!enc:ex", "after relogin")
expect_identical(f$log$sent[[3L]]$mx$sync_token, "rotated")

# Attachments plus encrypted text: media ids first, encrypted event last,
# same contract the cleartext path reports.
f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   media = function(mx, file, ...) paste0("$m", basename(file)))
ids <- chat_send(enc, "!enc:ex", "see these", files = c("/a.png", "/b.png"))
expect_identical(ids, c("$ma.png", "$mb.png", "$enc1"))

# A failed encrypted send reports no event id, the same way the cleartext
# path does, rather than inventing one or falling back to plaintext.
f <- fake_crypto(event_id = NULL)
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   send = function(...) stop("must not be reached"))
expect_identical(chat_send(enc, "!enc:ex", "secret"), character(0))

# ---- Decryption on poll ----

dec_rec <- function(event_id, body = "psst", sender = "@alice:ex",
                    room_id = "!enc:ex", msgtype = "m.text",
                    sender_verified = TRUE, is_self = FALSE, ts = NULL,
                    mentions = NULL) {
    list(room_id = room_id, event_id = event_id, sender = sender,
         body = body, msgtype = msgtype, sender_verified = sender_verified,
         is_self = is_self, ts = ts, mentions = mentions)
}

# Decrypted events come out as ordinary chat_message records, folded in
# beside the cleartext ones. corteza used to run its own decrypt off
# $raw and concatenate the results itself; that is what this replaces.
f <- fake_crypto(decrypted = list(dec_rec("$e1", ts = 1700000000000)))
enc <- seam_client(recs = list(rec("$c1", body = "in the clear")),
                   e2ee = TRUE, .crypto = f$ops)
res <- chat_poll(enc)
expect_identical(length(res$messages), 2L)
expect_identical(f$log$decrypted, 1L)
expect_identical(res$messages[[1L]]$body, "in the clear")
expect_false(res$messages[[1L]]$encrypted)
# sender_verified is NULL on cleartext: the transport asserts the sender
# and there is nothing to verify, which is not the same answer as FALSE.
expect_null(res$messages[[1L]]$sender_verified)
m <- res$messages[[2L]]
expect_inherits(m, "chat_message")
expect_identical(m$id, "$e1")
expect_identical(m$channel, "!enc:ex")
expect_identical(m$sender, "@alice:ex")
expect_identical(m$body, "psst")
expect_true(m$encrypted)
expect_true(m$sender_verified)
expect_identical(m$kind, "message")

# An unverified sender is FALSE, not NULL: the payload decrypted, but the
# claimed sender is the homeserver's word rather than a verified device.
f <- fake_crypto(decrypted = list(dec_rec("$e1", sender_verified = FALSE)))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops))
expect_false(res$messages[[1L]]$sender_verified)
# A missing flag is also FALSE. Absence of proof is not proof.
f <- fake_crypto(decrypted = list(dec_rec("$e1", sender_verified = NULL)))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops))
expect_false(res$messages[[1L]]$sender_verified)

# Decrypted msgtypes map into the contract's kind vocabulary, same as
# cleartext, so a cross-adapter kind filter treats both alike.
f <- fake_crypto(decrypted = list(dec_rec("$e1", msgtype = "m.notice"),
                                  dec_rec("$e2", msgtype = "m.emote")))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops))
expect_identical(res$messages[[1L]]$kind, "notice")
expect_identical(res$messages[[2L]]$kind, "emote")

# A decrypted record without its own ts takes the timestamp off the sync,
# and an unknown time stays NA rather than becoming the poll's clock.
f <- fake_crypto(decrypted = list(dec_rec("$e1")))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops,
                             sync = wrap_sync(list(ev("$e1", ts = 1700000000000)))))
expect_false(is.na(res$messages[[1L]]$ts))
f <- fake_crypto(decrypted = list(dec_rec("$nowhere")))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops))
expect_true(is.na(res$messages[[1L]]$ts))

# The bot's own encrypted echo is marked self, so a consumer replying to
# inbound mail does not answer itself.
f <- fake_crypto(decrypted = list(dec_rec("$e1", is_self = TRUE)))
res <- chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops))
expect_true(res$messages[[1L]]$self)

# A decrypt that throws warns and loses the encrypted traffic, but the
# poll still returns the cleartext messages and advances the cursor. One
# room with a missing Megolm session must not stall the whole loop.
f <- fake_crypto(decrypt_error = TRUE)
enc <- seam_client(recs = list(rec("$c1")), e2ee = TRUE, .crypto = f$ops,
                   token = "s2")
expect_warning(res <- chat_poll(enc), "decrypt failed")
expect_identical(length(res$messages), 1L)
expect_identical(res$cursor, "s2")

# Nothing consults crypto when e2ee is off, so an installed mx.crypto
# cannot change what a cleartext client does.
f <- fake_crypto(decrypted = list(dec_rec("$e1")))
res <- chat_poll(seam_client(recs = list(rec("$c1")), .crypto = f$ops))
expect_identical(f$log$decrypted, 0L)
expect_identical(length(res$messages), 1L)

# ---- Encrypted-room cache file ----
# One room id per line, not JSON: chat.api has no dependencies. A stale
# encrypted_rooms.json from corteza is ignored, and losing the cache
# costs nothing because init rescans the homeserver's own room state.
store <- file.path(tempfile("chatapi-store"))
dir.create(store)
expect_identical(chat.api:::matrix_crypto_load_encrypted(store), character())
ctx <- new.env(parent = emptyenv())
ctx$store <- store
ctx$encrypted <- c("!a:ex", "!b:ex")
chat.api:::matrix_crypto_save_encrypted(ctx)
expect_identical(chat.api:::matrix_crypto_load_encrypted(store),
                 c("!a:ex", "!b:ex"))
# An empty set round trips as an empty set, not as one blank room id.
ctx$encrypted <- character()
chat.api:::matrix_crypto_save_encrypted(ctx)
expect_identical(chat.api:::matrix_crypto_load_encrypted(store), character())
# A leftover JSON file is not read as room ids.
writeLines('["!json:ex"]', file.path(store, "encrypted_rooms.json"))
expect_identical(chat.api:::matrix_crypto_load_encrypted(store), character())
unlink(store, recursive = TRUE)
# Saving into a store that does not exist yet creates it.
store2 <- tempfile("chatapi-store2")
ctx$store <- store2
ctx$encrypted <- "!c:ex"
chat.api:::matrix_crypto_save_encrypted(ctx)
expect_true(dir.exists(store2))
expect_identical(chat.api:::matrix_crypto_load_encrypted(store2), "!c:ex")
unlink(store2, recursive = TRUE)

# The ops table defaults to the real implementations and overrides
# selectively, so a seam that names one operation does not blank the rest.
ops <- chat.api:::matrix_crypto_ops()
expect_identical(sort(names(ops)), c("decrypt", "encrypted", "init", "send"))
expect_identical(ops$send, chat.api:::matrix_crypto_send)
partial <- chat.api:::matrix_crypto_ops(list(send = function(...) "$x"))
expect_identical(partial$decrypt, chat.api:::matrix_crypto_decrypt)
expect_false(identical(partial$send, chat.api:::matrix_crypto_send))
