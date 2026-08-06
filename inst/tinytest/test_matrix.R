# Matrix adapter verification that needs nothing installed. Every client
# here supplies mx plus all four seams, which is the configuration
# chat_matrix() documents as running without mx.client, so these
# assertions are the ones that must not disappear on a bare CI runner.
# The half that pins the adapter to mx.client's real signatures lives in
# test_matrix_mxclient.R, which announces its skip.

# device_id is here because an Olm account belongs to a device: an e2ee
# client refuses a config that cannot name one.
fake_mx <- function(sync_token = NULL, user_id = "@bot:ex",
                    device_id = "DEV1") {
    list(user_id = user_id, server = "https://ex.invalid",
         device_id = device_id, sync_token = sync_token)
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
#
# save is seamed too. An e2ee client defers the cursor write out of the
# sync, and the real writer is mx.client::mx_client_save -- correct in
# production, and the one thing that would make this file need mx.client
# after all.
seam_client <- function(recs = list(), sync = wrap_sync(list()),
                        first_run = FALSE, token = "s1", mx = fake_mx(),
                        record = NULL, send = function(...) "$id",
                        media = function(...) NULL,
                        save = function(client, ...) client, ...) {
    chat_matrix(mx = mx, .save = save,
        .sync = function(client, ...) {
            if (!is.null(record)) {
                record$sync[[length(record$sync) + 1L]] <- c(
                    list(client = client), list(...))
            }
            # The post-sync config keeps the identity it went in with. A
            # real sync (or relogin) rotates the token, never the
            # user_id/device_id, and crypto is keyed on those.
            list(sync = sync,
                 client = fake_mx(token, user_id = client$user_id,
                                  device_id = client$device_id),
                 first_run = first_run)
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
# reactions is TRUE and there is a verb behind it, which is the whole
# rule: a flag without its implementation is what this suite exists to
# catch. reaction_events tracks the installed mx.client, since an older
# one has no reaction extractor and would report an empty list forever.
expect_true(caps$reactions)
expect_true("chat_react" %in% getNamespaceExports("chat.api"))
expect_true(is.function(getS3method("chat_react", "chat_matrix")))
expect_true(is.logical(caps$reaction_events))
expect_identical(caps$reaction_events, chat.api:::matrix_reactions_available())
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
# adapter's routing: which path a send takes, when crypto state is built
# and persisted, and whether decrypted events reach the caller as
# ordinary chat_message records in the order the homeserver sent them.

# A fake crypto context plus ops that record what the adapter asked for.
# Contexts are interned per identity, so a fresh fake starts by dropping
# whatever the previous one interned; otherwise every case after the first
# would silently reuse an earlier fake's context.
fake_crypto <- function(encrypted_rooms = "!enc:ex", decrypted = list(),
                        event_id = "$enc1", decrypt_error = FALSE,
                        lookup_error = FALSE, init_error = FALSE) {
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
            if (isTRUE(init_error)) {
                stop("keys could not be published")
            }
            ctx
        },
        encrypted = function(crypto, mx, room_id) {
            log$asked <- c(log$asked, room_id)
            if (isTRUE(lookup_error)) {
                stop("cannot determine the encryption state of ", room_id)
            }
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
expect_true(chat_capabilities(plain)$files)

# init is not called either: an unused crypto module must not touch the
# store or publish keys.
f <- fake_crypto()
off <- seam_client(e2ee = FALSE, .crypto = f$ops)
chat_poll(off)
chat_send(off, "!enc:ex", "hi")
expect_identical(length(f$log$init), 0L)
expect_null(off$env$crypto)

# ---- Crypto is built on first use, not at construction ----
# Initialization publishes keys, which is an authenticated request. The
# stored token may already be rejected at process start -- that is what
# mx_with_relogin() is for -- so building here put the upload ahead of
# any relogin. chat_matrix() threw, the poll loop never ran, and every
# restart repeated with the same dead token.

f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops)
expect_identical(length(f$log$init), 0L)
expect_null(enc$env$crypto)
# The capability answers from the setting, not the context, so it does not
# flip after the first poll.
expect_true(chat_capabilities(enc)$e2ee)
# ... and files is FALSE, because mx_send_media posts a cleartext m.file
# event whatever the room's encryption state says.
expect_false(chat_capabilities(enc)$files)

# A construction that would have died now survives to the first poll,
# which is where relogin gets its chance.
expect_silent(seam_client(e2ee = TRUE, .crypto = fake_crypto(init_error = TRUE)$ops))
expect_error(chat_poll(seam_client(e2ee = TRUE,
                                   .crypto = fake_crypto(init_error = TRUE)$ops)),
             "keys could not be published")

# The first poll builds it off the post-sync credentials rather than the
# ones the client was constructed with -- that is the whole point of
# waiting, since a relogin during the sync is what replaces a rejected
# token. Asserted on the access token, not the cursor: the cursor is
# deliberately still the pre-sync one at this point, held back until the
# crypto state is safe.
f <- fake_crypto()
enc <- chat_matrix(mx = fake_mx(), e2ee = TRUE, .crypto = f$ops,
                   .sync = function(client, ...) {
                       c2 <- fake_mx("advanced")
                       c2$token <- "after-relogin"
                       list(sync = wrap_sync(list()), client = c2,
                            first_run = FALSE)
                   },
                   .extract = function(...) list(),
                   .send = function(...) "$id", .media = function(...) NULL,
                   .save = function(client, ...) client)
chat_poll(enc)
expect_identical(length(f$log$init), 1L)
expect_identical(f$log$init[[1L]]$mx$token, "after-relogin")
expect_true(is.environment(enc$env$crypto))
# Later polls reuse it.
chat_poll(enc)
expect_identical(length(f$log$init), 1L)

# A send builds it too, for a client that sends before it polls.
f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops)
chat_send(enc, "!enc:ex", "secret")
expect_identical(length(f$log$init), 1L)

# ---- The store is bound to a device identity ----
# An Olm account belongs to a device, not a user. A config that cannot
# name one cannot key a store, and the check runs at construction so the
# caller hears about it there.
expect_error(chat_matrix(mx = list(user_id = "@bot:ex"), e2ee = TRUE,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL,
                         .crypto = fake_crypto()$ops),
             "user_id and device_id")
expect_error(chat_matrix(mx = list(device_id = "DEV1"), e2ee = TRUE,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL,
                         .crypto = fake_crypto()$ops),
             "user_id and device_id")
# e2ee off does not need one: a cleartext client has no account to key.
expect_silent(seam_client(mx = list(user_id = "@bot:ex")))

# The cache key is the device identity and nothing else. Matrix gives a
# device one ed25519 and one curve25519 key for the life of that
# device_id, so a key that also carried the store let two stores mint two
# Olm accounts -- two identity keys for one device.
k <- chat.api:::matrix_crypto_cache_key
expect_false(identical(k(fake_mx(user_id = "@a:ex")),
                       k(fake_mx(user_id = "@b:ex"))))
expect_false(identical(k(fake_mx(device_id = "D1")),
                       k(fake_mx(device_id = "D2"))))
expect_identical(k(fake_mx()), k(fake_mx()))
# Same device, different token or cursor: still one key.
expect_identical(k(fake_mx(sync_token = "s1")), k(fake_mx()))

# Store requests normalize, so two spellings of one directory are one
# request rather than two contexts writing over each other's pickles.
spec <- chat.api:::matrix_crypto_store_spec
expect_identical(spec("/tmp/store-a"), spec("/tmp/store-a/"))
expect_identical(spec("/tmp/store-a"), spec("/tmp/store-a///"))
expect_false(identical(spec("/tmp/store-a"), spec("/tmp/store-b")))

# Dot segments fold whether or not the directory exists. normalizePath()
# only folds them for a path that does, and a store's first use is
# exactly when it does not -- so two calls for one directory would have
# disagreed depending on whether it had been created in between.
n <- chat.api:::matrix_normalize_path
expect_identical(n("/missing/a/../b"), n("/missing/b"))
expect_identical(n("/missing/./b"), n("/missing/b"))
expect_identical(n("/missing/a/b/../.."), n("/missing"))
# Roots survive, including a Windows drive root -- the trailing-slash
# strip this replaced turned "C:/" into "C:".
expect_identical(n("/"), "/")
expect_identical(n("C:/"), "C:/")
expect_identical(n("C:/x/../y"), "C:/y")
expect_identical(n("C:\\x\\y"), "C:/x/y")
# There is nothing above a root to climb to.
expect_identical(n("/../x"), "/x")

# A UNC share is not the local path that happens to spell the same. On
# Windows //server/share/x is a remote mount and /server/share/x is a
# local directory; collapsing every leading slash run made them one spec,
# so a request for one store would have been handed the other's context.
expect_identical(n("//server/share/x"), "//server/share/x")
expect_identical(n("\\\\server\\share\\x"), "//server/share/x")
expect_false(identical(n("//server/share/x"), n("/server/share/x")))
# Three or more leading slashes are POSIX, not UNC, and collapse.
expect_identical(n("///server/share/x"), "/server/share/x")
# Dot segments fold inside a UNC path, and not past the share.
expect_identical(n("//server/share/a/../x"), "//server/share/x")
expect_identical(n("//server/share/../../x"), "//server/share/x")
# Two shares on one host are two roots.
expect_false(identical(n("//server/one/x"), n("//server/two/x")))

# A drive-relative path is refused rather than folded. Windows resolves
# "C:store" against the current directory of drive C, which R cannot
# read, so "C:../x", "C:x" and "C:a/../../x" are three directories that
# no amount of folding here can tell apart -- and two of them sharing a
# spec is two stores sharing a context.
expect_error(n("C:relative"), "drive-relative")
expect_error(n("C:../x"), "drive-relative")
expect_error(n("C:a/../../x"), "drive-relative")
expect_error(n("C:"), "drive-relative")
expect_error(n("c:store"), "drive-relative")
expect_error(spec("C:relative"), "drive-relative")
# An absolute drive path is fine, and is what the error asks for.
expect_identical(n("C:/relative"), "C:/relative")
# ~ expands, and a relative path resolves against the caller's directory
# rather than merging with an unrelated one of the same name.
expect_true(startsWith(n("~/x"), "/"))
expect_identical(n("rel/x"), n(file.path(getwd(), "rel/x")))
expect_true(startsWith(n("rel/x"), "/"))
# Directories that do exist still fold, which is the common case.
local({
    d <- file.path(tempfile("specdir"), "s")
    dir.create(d, recursive = TRUE)
    on.exit(unlink(dirname(d), recursive = TRUE))
    expect_identical(spec(d), spec(file.path(dirname(d), "..",
                                             basename(dirname(d)), "s")))
    # ... and the same path gives the same spec before and after it
    # exists, which is the property the whole comparison rests on.
    gone <- file.path(tempfile("specgone"), "s")
    before <- spec(gone)
    dir.create(gone, recursive = TRUE)
    on.exit(unlink(dirname(gone), recursive = TRUE), add = TRUE)
    expect_identical(before, spec(gone))
})
# A deferred store is a stable request too: two clients that both defer
# resolve the same way, and the app is what distinguishes them.
expect_identical(spec(NULL), spec(NULL))
expect_false(identical(spec(NULL, "a"), spec(NULL, "b")))

# Two default clients for different bots get two contexts.
f <- fake_crypto()
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops,
                      mx = fake_mx(user_id = "@one:ex")))
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops,
                      mx = fake_mx(user_id = "@two:ex")))
expect_identical(length(f$log$init), 2L)

# ---- One Olm account per identity ----
# A consumer that derives a fresh client per use -- corteza does, so the
# rotating access token is never cached -- must not mint a second Olm
# account each time. Interning is what reconciles a short-lived client
# with a long-lived crypto identity.

f <- fake_crypto()
a <- seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
b <- seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops)
chat_poll(a)
chat_poll(b)
expect_identical(length(f$log$init), 1L)
expect_true(identical(a$env$crypto, b$env$crypto))

# One explicit store, asked for twice, is one context -- including when
# the second spelling of it differs.
f <- fake_crypto()
chat_send(seam_client(e2ee = TRUE, crypto_store = "/tmp/store-a",
                      .crypto = f$ops), "!enc:ex", "x")
chat_send(seam_client(e2ee = TRUE, crypto_store = "/tmp/store-a/",
                      .crypto = f$ops), "!enc:ex", "x")
expect_identical(length(f$log$init), 1L)

# A second store for a device that already has one is refused. Two stores
# would be two Olm accounts, and the spec gives a device_id one identity.
# It is not silently ignored either: the caller asked for a store and
# would otherwise have got a different one without being told.
expect_error(chat_send(seam_client(e2ee = TRUE, crypto_store = "/tmp/store-b",
                                   .crypto = f$ops), "!enc:ex", "x"),
             "already has a crypto store")
expect_identical(length(f$log$init), 1L)
# The default store and an explicit one conflict the same way.
expect_error(chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops)),
             "already has a crypto store")

# A different app is a different store, so on the same device it
# conflicts too. In production it does not arise: cornelius and tiny are
# different user_ids, hence different devices.
f <- fake_crypto()
chat_poll(seam_client(e2ee = TRUE, app = "cornelius", .crypto = f$ops))
expect_error(chat_poll(seam_client(e2ee = TRUE, app = "tiny",
                                   .crypto = f$ops)),
             "already has a crypto store")

# Forgetting an identity is how to re-home one deliberately, and it
# leaves the other identities interned.
f <- fake_crypto()
one <- fake_mx(user_id = "@one:ex")
two <- fake_mx(user_id = "@two:ex")
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops, mx = one))
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops, mx = two))
chat.api:::matrix_crypto_forget(chat.api:::matrix_crypto_cache_key(two))
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops, mx = one))
chat_poll(seam_client(e2ee = TRUE, .crypto = f$ops, mx = two))
expect_identical(length(f$log$init), 3L)
expect_identical(f$log$init[[3L]]$mx$user_id, "@two:ex")
# ... and after forgetting, a new store for that device is allowed.
chat.api:::matrix_crypto_forget(chat.api:::matrix_crypto_cache_key(one))
chat_send(seam_client(e2ee = TRUE, crypto_store = "/tmp/rehomed",
                      .crypto = f$ops, mx = one), "!enc:ex", "x")
expect_identical(f$log$init[[length(f$log$init)]]$store, "/tmp/rehomed")

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

# ---- An unanswerable encryption state is not a plaintext room ----
# The lookup used to turn every failure -- expired token, timeout, 500 --
# into FALSE, and the send went out in the clear. On an e2ee client that
# is a leak, so it aborts instead.
f <- fake_crypto(lookup_error = TRUE)
cleartext <- new.env(parent = emptyenv()); cleartext$n <- 0L
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   send = function(...) { cleartext$n <- cleartext$n + 1L
                                          "$clear1" })
expect_error(chat_send(enc, "!unknown:ex", "secret"),
             "cannot determine the encryption state")
expect_identical(cleartext$n, 0L)
expect_identical(length(f$log$sent), 0L)
# A cleartext client is untouched: with no crypto context there is no
# lookup to fail, and the send goes out as it always did.
plain <- seam_client(.crypto = f$ops,
                     send = function(...) { cleartext$n <- cleartext$n + 1L
                                            "$clear1" })
expect_identical(chat_send(plain, "!unknown:ex", "hi"), "$clear1")
expect_identical(cleartext$n, 1L)

# ---- Attachments are refused in encrypted rooms ----
# mx_send_media() posts an ordinary cleartext m.file event. The check used
# to run after the upload loop, so the files reached the homeserver in the
# clear and only the text took the Megolm path -- and an attachment-only
# send never asked at all.
f <- fake_crypto()
uploads <- new.env(parent = emptyenv()); uploads$n <- 0L
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   media = function(mx, file, ...) {
                       uploads$n <- uploads$n + 1L
                       paste0("$m", basename(file))
                   })
expect_error(chat_send(enc, "!enc:ex", "see these", files = "/a.png"),
             "cannot send attachments to the encrypted room")
# Nothing was uploaded: the refusal comes before the loop, not after it.
expect_identical(uploads$n, 0L)
expect_identical(length(f$log$sent), 0L)
# Attachment-only sends are refused on the same terms.
expect_error(chat_send(enc, "!enc:ex", "", files = "/a.png"),
             "cannot send attachments")
expect_identical(uploads$n, 0L)
# A plaintext room on the same client still takes attachments.
ids <- chat_send(enc, "!plain:ex", "see these", files = c("/a.png", "/b.png"))
expect_identical(ids, c("$ma.png", "$mb.png", "$id"))
expect_identical(uploads$n, 2L)

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

# A failed encrypted send propagates, the same way the cleartext path's
# failures do. Reporting no event id would have a caller record the
# message as sent-but-unacknowledged rather than as failed.
f <- fake_crypto()
enc <- seam_client(e2ee = TRUE, .crypto = f$ops,
                   send = function(...) stop("must not be reached"))
enc$crypto_ops$send <- function(...) stop("olm session could not be opened")
expect_error(chat_send(enc, "!enc:ex", "secret"),
             "olm session could not be opened")

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
# beside the cleartext ones. corteza used to run its own decrypt off $raw
# and concatenate the results itself.
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

# ---- Mixed timelines keep the homeserver's order ----
# Appending the decrypted events put every one of them after every
# cleartext one, so an encrypted message followed by a plain reply came
# back the other way round -- which reorders a room's commands against
# the messages they act on.
f <- fake_crypto(decrypted = list(dec_rec("$first", body = "encrypted 1st")))
enc <- seam_client(recs = list(rec("$second", body = "clear 2nd")),
                   e2ee = TRUE, .crypto = f$ops,
                   sync = wrap_sync(list(ev("$first"), ev("$second"))))
res <- chat_poll(enc)
expect_identical(vapply(res$messages, function(m) m$id, character(1)),
                 c("$first", "$second"))
expect_true(res$messages[[1L]]$encrypted)
expect_false(res$messages[[2L]]$encrypted)

# Interleaved, three deep, to catch an ordering that only looks right
# when the encrypted event happens to come first.
f <- fake_crypto(decrypted = list(dec_rec("$b"), dec_rec("$d")))
enc <- seam_client(recs = list(rec("$a"), rec("$c"), rec("$e")),
                   e2ee = TRUE, .crypto = f$ops,
                   sync = wrap_sync(list(ev("$a"), ev("$b"), ev("$c"),
                                         ev("$d"), ev("$e"))))
expect_identical(vapply(chat_poll(enc)$messages, function(m) m$id,
                        character(1)),
                 c("$a", "$b", "$c", "$d", "$e"))

# An event the sync did not position keeps its arrival order at the end
# rather than being dropped.
f <- fake_crypto(decrypted = list(dec_rec("$nowhere")))
enc <- seam_client(recs = list(rec("$a")), e2ee = TRUE, .crypto = f$ops,
                   sync = wrap_sync(list(ev("$a"))))
expect_identical(vapply(chat_poll(enc)$messages, function(m) m$id,
                        character(1)),
                 c("$a", "$nowhere"))

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

# ---- A sync is not consumed until its crypto state is on disk ----
# mx_sync_update(save = TRUE) commits the advanced cursor before anything
# parses the response, which is what makes a malformed event survivable.
# But a sync carrying a room key is only consumed once that key is
# persisted: the homeserver never re-sends it, so a crash in between
# leaves every later message in that room undecryptable.

saves <- new.env(parent = emptyenv())
saves$order <- character()
saved_client <- function(f, ...) {
    seam_client(e2ee = TRUE, .crypto = f$ops,
                save = function(client, app = NULL, ...) {
                    saves$order <- c(saves$order, "cursor")
                    client
                }, ...)
}

# The sync does not write the cursor itself...
f <- fake_crypto()
f$ops$decrypt <- function(crypto, sync, mx) {
    saves$order <- c(saves$order, "crypto")
    list()
}
trace <- new.env(); trace$sync <- list(); trace$extract <- list()
saves$order <- character()
chat_poll(saved_client(f, record = trace))
expect_false(trace$sync[[1L]]$save)
# ... it is written afterwards, and after the crypto state.
expect_identical(saves$order, c("crypto", "cursor"))

# A crypto failure means the sync was not consumed: no cursor write, and
# the error is not swallowed. mx.client already skips an individual event
# it has no session for, so a throw here is to-device processing or the
# session save itself.
f <- fake_crypto(decrypt_error = TRUE)
saves$order <- character()
expect_error(chat_poll(saved_client(f)), "no session for that megolm stream")
expect_identical(saves$order, character())

# ... and "not consumed" has to hold in memory too, not just on disk.
# Leaving the advanced cursor on the client only moved the skip: a caller
# that catches the error and polls the same client again would resume
# past the sync whose room keys were lost, and the homeserver never
# re-sends them.
f <- fake_crypto(decrypt_error = TRUE)
retry <- seam_client(e2ee = TRUE, .crypto = f$ops, token = "advanced",
                     mx = fake_mx(sync_token = "before"),
                     save = function(client, ...) client)
expect_error(chat_poll(retry), "no session")
expect_identical(retry$env$mx$sync_token, "before")
# The next poll asks from where the failed one started.
trace6 <- new.env(); trace6$sync <- list(); trace6$extract <- list()
retry2 <- seam_client(e2ee = TRUE, .crypto = f$ops, token = "advanced",
                      mx = fake_mx(sync_token = "before"), record = trace6,
                      save = function(client, ...) client)
expect_error(chat_poll(retry2), "no session")
expect_error(chat_poll(retry2), "no session")
expect_identical(trace6$sync[[2L]]$client$sync_token, "before")

# A relogin's refreshed credentials survive the rollback: a rotated token
# is not what makes a sync consumed, and dropping it would have the retry
# authenticate with the one the homeserver just rejected.
f <- fake_crypto(decrypt_error = TRUE)
rl <- chat_matrix(mx = fake_mx(sync_token = "before"), e2ee = TRUE,
                  .crypto = f$ops,
                  .sync = function(client, ...) {
                      c2 <- fake_mx("advanced")
                      c2$token <- "rotated"
                      list(sync = wrap_sync(list()), client = c2,
                           first_run = FALSE)
                  },
                  .extract = function(...) list(),
                  .send = function(...) "$id", .media = function(...) NULL,
                  .save = function(client, ...) client)
expect_error(chat_poll(rl), "no session")
expect_identical(rl$env$mx$token, "rotated")
expect_identical(rl$env$mx$sync_token, "before")

# A successful poll does advance it, or nothing would ever move.
f <- fake_crypto()
ok <- seam_client(e2ee = TRUE, .crypto = f$ops, token = "advanced",
                  mx = fake_mx(sync_token = "before"),
                  save = function(client, ...) client)
chat_poll(ok)
expect_identical(ok$env$mx$sync_token, "advanced")

# save_cursor = FALSE still means nothing is written, either way.
f <- fake_crypto()
saves$order <- character()
chat_poll(saved_client(f, save_cursor = FALSE))
expect_identical(saves$order, character())

# A cleartext client keeps the cursor inside the sync, where the
# poison-pill protection wants it. Only e2ee pays for durability.
trace2 <- new.env(); trace2$sync <- list(); trace2$extract <- list()
chat_poll(seam_client(record = trace2))
expect_true(trace2$sync[[1L]]$save)

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

# ---- The store is bound to the device that owns it ----
# The directory name is sanitized and therefore not injective: "@a/b:ex"
# and "@a_b:ex" land in the same place. The exact identity is written
# into the store and compared on every open, so a collision -- or a
# copied store, or a changed device_id -- is an error rather than one bot
# silently opening another's Olm account.
store <- tempfile("chatapi-id")
chat.api:::matrix_crypto_bind_identity(store, fake_mx(user_id = "@a:ex",
                                                     device_id = "D1"))
expect_true(file.exists(file.path(store, "identity.txt")))
expect_identical(readLines(file.path(store, "identity.txt")),
                 c("@a:ex", "D1"))
# Reopening with the same identity is fine, and does not rewrite it.
expect_silent(chat.api:::matrix_crypto_bind_identity(
    store, fake_mx(user_id = "@a:ex", device_id = "D1")))
# A different user, or the same user on a different device, is not.
expect_error(chat.api:::matrix_crypto_bind_identity(
    store, fake_mx(user_id = "@b:ex", device_id = "D1")),
    "belongs to")
expect_error(chat.api:::matrix_crypto_bind_identity(
    store, fake_mx(user_id = "@a:ex", device_id = "D2")),
    "belongs to")
# The collision the sanitization allows is caught by the same check.
# (That the two identities really do share a directory is asserted in
# test_matrix_mxclient.R: resolving the path calls into mx.client, and
# nothing in this file may.)
shared <- tempfile("chatapi-collide")
chat.api:::matrix_crypto_bind_identity(shared, fake_mx(user_id = "@a/b:ex",
                                                      device_id = "D"))
expect_error(chat.api:::matrix_crypto_bind_identity(
    shared, fake_mx(user_id = "@a_b:ex", device_id = "D")), "belongs to")
unlink(c(store, shared), recursive = TRUE)

# Both halves of the identity are required, wherever it is asked for.
expect_error(chat.api:::matrix_crypto_identity(list(user_id = "@a:ex")),
             "user_id and device_id")
expect_error(chat.api:::matrix_crypto_identity(list(device_id = "D")),
             "user_id and device_id")
expect_error(chat.api:::matrix_crypto_identity(
    list(user_id = "@a:ex", device_id = "")), "user_id and device_id")
expect_identical(
    chat.api:::matrix_crypto_identity(list(user_id = "@a:ex",
                                           device_id = "D"))[["device_id"]],
    "D")

# ---- The device query covers to-device senders ----
# sender_bound is stamped once, when a room key arrives over to-device,
# and persisted with the Megolm session; a later sync carrying a timeline
# message from that sender does not rebind it. Room keys normally arrive
# before the message they are for, so asking only about timeline senders
# recorded them unverified forever.
senders <- chat.api:::matrix_encrypted_senders
td <- function(events) list(to_device = list(events = events))
expect_identical(
    senders(td(list(list(type = "m.room.encrypted", sender = "@a:ex")))),
    "@a:ex")
# Timeline and to-device are unioned, and each sender appears once.
sync <- c(td(list(list(type = "m.room.encrypted", sender = "@a:ex"),
                  list(type = "m.room.encrypted", sender = "@b:ex"))),
          list(rooms = list(join = list(`!r:ex` = list(timeline = list(
              events = list(list(type = "m.room.encrypted",
                                 sender = "@a:ex"))))))))
expect_identical(sort(senders(sync)), c("@a:ex", "@b:ex"))
# Other to-device types are not senders to ask about.
expect_identical(
    senders(td(list(list(type = "m.room_key_request", sender = "@a:ex")))),
    character())
expect_identical(senders(list()), character())

# ---- Timeline order ----
pos <- chat.api:::matrix_event_order
expect_identical(pos(wrap_sync(list(ev("$a"), ev("$b"))))[["$b"]], 2L)
expect_identical(length(pos(list())), 0L)
# Positions run across rooms, so the walk is the sync's own order rather
# than a per-room one that would interleave arbitrarily.
two <- list(rooms = list(join = list(
    `!r1:ex` = list(timeline = list(events = list(ev("$a")))),
    `!r2:ex` = list(timeline = list(events = list(ev("$b")))))))
expect_identical(pos(two)[["$a"]], 1L)
expect_identical(pos(two)[["$b"]], 2L)

# ---- The four seams still run without mx.client ----
# chat_matrix() documents mx plus .sync/.extract/.send/.media as enough
# to poll and send on a host with no mx.client. That works because `%||%`
# is lazy: the mx.client:: default on each of those four is never forced
# when a seam is supplied. Adding a fifth default that was resolved
# unconditionally broke it for every client, cleartext ones included, and
# turned both CI legs red with "there is no package called 'mx.client'".
#
# The proof has to be that no mx.client symbol is referenced eagerly, and
# an installed mx.client makes that invisible here -- so this reads the
# constructor's own body instead of relying on the environment.
ctor <- deparse(body(chat_matrix))
defaults <- grep("mx\\.client::", ctor, value = TRUE)
# Every remaining mx.client:: reference in the returned list is behind a
# `%||%` whose left side is a seam.
listed <- grep("_fn = ", defaults, value = TRUE)
expect_true(all(grepl("%\\|\\|%", listed)))
expect_false(any(grepl("save_fn = .*mx\\.client::", ctor)))

# And by construction: a client built the documented way never touches
# save_fn's default, because only the deferred-save path resolves one.
seamed <- chat_matrix(mx = fake_mx(), .sync = function(...) NULL,
                      .extract = function(...) list(),
                      .send = function(...) "$id",
                      .media = function(...) NULL)
expect_null(seamed$save_fn)
expect_false(seamed$e2ee)
# A supplied .save is kept verbatim rather than being wrapped.
mine <- function(client, ...) client
expect_identical(chat_matrix(mx = fake_mx(), .sync = function(...) NULL,
                             .extract = function(...) list(),
                             .send = function(...) "$id",
                             .media = function(...) NULL,
                             .save = mine)$save_fn, mine)

# ---- Reactions ----
# A reaction is not a message: it has a target and no body, where a
# message has a body and no target. chat_poll() reports them in their own
# list rather than folding them into $messages.

rx_ev <- function(event_id, target = "$msg", key = "y",
                  sender = "@alice:ex", ts = 1700000000000,
                  rel_type = "m.annotation", room = "!room:ex") {
    list(type = "m.reaction", event_id = event_id, sender = sender,
         origin_server_ts = ts,
         content = list(`m.relates_to` = list(rel_type = rel_type,
                                              event_id = target, key = key)))
}

# Sending goes through mx.api::mx_react, seamed here.
local({
    seen <- NULL
    cl <- seam_client(.react = function(session, room_id, event_id, key) {
        seen <<- list(room_id = room_id, event_id = event_id, key = key)
        "$reaction1"
    })
    expect_identical(chat_react(cl, "!room:ex", "$msg", "\U0001F44D"),
                     "$reaction1")
    expect_identical(seen$room_id, "!room:ex")
    # The message id is the target, not the reaction's own -- the one
    # confusion this argument order invites.
    expect_identical(seen$event_id, "$msg")
    expect_identical(seen$key, "\U0001F44D")
})

# A failing react propagates. Unlike a typing indicator, a dropped
# acknowledgement is one the sender believes it made.
expect_error(chat_react(seam_client(.react = function(...) stop("403")),
                        "!room:ex", "$msg", "y"), "403")

# An adapter with no reaction support says so rather than doing nothing
# quietly: a silent no-op has the caller believe it acknowledged.
expect_error(chat_react(structure(list(), class = c("chat_nothing",
                                                    "chat_client")),
                        "!r", "$m", "y"),
             "not supported by this adapter")

# ---- Reactions come back out of chat_poll ----
if (requireNamespace("mx.client", quietly = TRUE) &&
    "mx_extract_reactions" %in% getNamespaceExports("mx.client")) {

    res <- chat_poll(seam_client(
        recs = list(rec("$m1", body = "hello")),
        sync = wrap_sync(list(ev("$m1"), rx_ev("$r1", target = "$m1",
                                               key = "\U0001F44D")))))
    expect_identical(length(res$messages), 1L)
    expect_identical(length(res$reactions), 1L)
    r <- res$reactions[[1L]]
    expect_inherits(r, "chat_reaction")
    # id is the reaction's own event, target is what it annotates.
    expect_identical(r$id, "$r1")
    expect_identical(r$target, "$m1")
    expect_identical(r$channel, "!room:ex")
    expect_identical(r$sender, "@alice:ex")
    expect_identical(r$key, "\U0001F44D")
    expect_false(r$self)
    expect_equal(as.numeric(r$ts), 1700000000, tolerance = 1e-6)
    # A reaction is not in $messages, and a message is not in $reactions.
    expect_identical(res$messages[[1L]]$id, "$m1")
    expect_false(inherits(res$messages[[1L]], "chat_reaction"))

    # The bot's own reactions come back tagged, not dropped: a consumer
    # tracking which it has already placed needs them.
    res <- chat_poll(seam_client(
        sync = wrap_sync(list(rx_ev("$r1", sender = "@bot:ex")))))
    expect_true(res$reactions[[1L]]$self)

    # Reactions keep the homeserver's order, same as messages.
    res <- chat_poll(seam_client(
        sync = wrap_sync(list(rx_ev("$b"), rx_ev("$a"), rx_ev("$c")))))
    expect_identical(vapply(res$reactions, function(r) r$id, character(1)),
                     c("$b", "$a", "$c"))

    # A sync with no reactions gives an empty list, not NULL: a consumer
    # looping over it should not have to test for both.
    res <- chat_poll(seam_client(sync = wrap_sync(list(ev("$m1")))))
    expect_identical(res$reactions, list())
    expect_false(is.null(res$reactions))

    # A missing origin_server_ts is NA, never the poll's clock.
    res <- chat_poll(seam_client(sync = wrap_sync(list(rx_ev("$r1",
                                                             ts = NULL)))))
    expect_true(is.na(res$reactions[[1L]]$ts))
}

# ---- The record itself ----
rr <- chat_reaction(id = "$r", channel = "!c", sender = "@a", target = "$m",
                    key = "y", ts = as.POSIXct(NA))
expect_inherits(rr, "chat_reaction")
expect_identical(rr$target, "$m")
expect_null(rr$self)
# A platform that gives a reaction no identity of its own passes NULL,
# which is different from not knowing the target.
expect_null(chat_reaction(id = NULL, channel = "!c", sender = "@a",
                          target = "$m", key = "y", ts = as.POSIXct(NA))$id)
# The target is required and must be a string: a reaction to nothing is
# not a reaction.
expect_error(chat_reaction(id = "$r", channel = "!c", sender = "@a",
                           target = NULL, key = "y", ts = as.POSIXct(NA)))
expect_error(chat_reaction(id = "$r", channel = "!c", sender = "@a",
                           target = "$m", key = NULL, ts = as.POSIXct(NA)))
