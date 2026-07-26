# Matrix adapter verification. No homeserver in CI, so this pins the
# adapter to mx.client's installed signatures (API-drift detection) and
# drives every code path through the injection seams. Live sends need a
# real homeserver and credentials.

if (requireNamespace("mx.client", quietly = TRUE)) {
    # Every argument chat_poll passes must exist in mx_sync_update
    sync_formals <- names(formals(mx.client::mx_sync_update))
    expect_true(all(c("client", "timeout", "save", "app") %in% sync_formals))

    # ... and in the event extractor it hands the response to
    extract_formals <- names(formals(mx.client::mx_extract_text_events))
    expect_true(all(c("sync_resp", "self_id") %in% extract_formals))

    # Every argument chat_send passes must exist in mx_send_text
    send_formals <- names(formals(mx.client::mx_send_text))
    expect_true(all(c("room", "msgtype", "markdown") %in% send_formals))

    # chat_typing goes through a session, not the client config
    expect_true("mx_client_session" %in% getNamespaceExports("mx.client"))
}

# ---- Fixtures: a fake mx client config and a scripted sync ----

fake_mx <- function(sync_token = NULL) {
    list(user_id = "@bot:ex", server = "https://ex.invalid",
         sync_token = sync_token)
}

# One human message, one from the bot itself, one m.notice. The bot's
# own event is tagged is_self by the extractor; the notice is dropped
# by its default msgtypes filter (see the asymmetry note below).
fake_sync <- list(rooms = list(join = list("!room:ex" = list(timeline = list(
    events = list(
        list(type = "m.room.message", event_id = "$1", sender = "@alice:ex",
             origin_server_ts = 1700000000000,
             content = list(msgtype = "m.text", body = "hello")),
        list(type = "m.room.message", event_id = "$2", sender = "@bot:ex",
             origin_server_ts = 1700000001000,
             content = list(msgtype = "m.text", body = "my own echo")),
        list(type = "m.room.message", event_id = "$3", sender = "@carol:ex",
             origin_server_ts = 1700000002000,
             content = list(msgtype = "m.notice", body = "a notice"))
    )
)))))

# ---- Constructor ----

cl <- chat_matrix(mx = fake_mx(), .sync = function(...) NULL,
                  .extract = function(...) list(),
                  .send = function(...) "$id", .media = function(...) NULL)
expect_inherits(cl, "chat_matrix")
expect_inherits(cl, "chat_client")
expect_identical(cl$env$mx$user_id, "@bot:ex")
expect_true(cl$save_cursor)

# save_cursor is coerced, not passed through raw
expect_false(chat_matrix(mx = fake_mx(), save_cursor = NULL,
                         .sync = function(...) NULL,
                         .extract = function(...) list(),
                         .send = function(...) "$id",
                         .media = function(...) NULL)$save_cursor)

# ---- Poll: cursor handling ----
# The cursor is the piece a restarted consumer depends on, and the one
# that replays history when it goes wrong.

sync_calls <- new.env()
sync_calls$args <- list()
scripted_sync <- function(client, ...) {
    sync_calls$args[[length(sync_calls$args) + 1L]] <- c(list(client = client),
                                                         list(...))
    list(sync = fake_sync, client = fake_mx(sync_token = "s_next"),
         first_run = FALSE)
}

if (requireNamespace("mx.client", quietly = TRUE)) {
    # Real extractor: the mapping is worth exercising for real rather
    # than faking the record shape it produces.
    p <- chat_matrix(mx = fake_mx("s_prev"), save_cursor = FALSE,
                     .sync = scripted_sync, .send = function(...) "$id",
                     .media = function(...) NULL)

    got <- chat_poll(p, timeout = 30)

    # Timeout converts seconds to the milliseconds mx.client wants
    expect_identical(sync_calls$args[[1L]]$timeout, 30000L)
    # save_cursor rides through to the persistence decision
    expect_false(sync_calls$args[[1L]]$save)
    # The stored token is what gets synced from when `since` is absent
    expect_identical(sync_calls$args[[1L]]$client$sync_token, "s_prev")

    # The returned cursor comes from the post-sync client
    expect_identical(got$cursor, "s_next")
    # ... and the client env advances, so the next poll resumes from it
    expect_identical(p$env$mx$sync_token, "s_next")

    # raw carries the whole sync for Matrix-specific consumers
    # (invites, reactions, E2EE) the generic contract does not model
    expect_identical(got$raw, fake_sync)

    # An explicit `since` overrides the stored token
    chat_poll(p, since = "s_forced")
    expect_identical(sync_calls$args[[2L]]$client$sync_token, "s_forced")

    # Absent timeout is 0, not an error
    chat_poll(p)
    expect_identical(sync_calls$args[[3L]]$timeout, 0L)
}

# ---- Poll: message mapping ----

if (requireNamespace("mx.client", quietly = TRUE)) {
    p2 <- chat_matrix(mx = fake_mx(), .sync = scripted_sync,
                      .send = function(...) "$id",
                      .media = function(...) NULL)
    got2 <- chat_poll(p2)

    # Self events are retained: the adapter reports what the room saw,
    # and dropping the bot's own echo is the consumer's decision.
    expect_identical(length(got2$messages), 2L)
    expect_identical(vapply(got2$messages, `[[`, "", "body"),
                     c("hello", "my own echo"))

    m <- got2$messages[[1L]]
    expect_inherits(m, "chat_message")
    expect_identical(m$id, "$1")
    expect_identical(m$channel, "!room:ex")
    expect_identical(m$sender, "@alice:ex")
    expect_identical(m$markup, "plain")
    expect_identical(m$kind, "m.text")
    expect_inherits(m$ts, "POSIXct")

    # Known asymmetry: chat_send can emit m.notice and m.emote, but
    # mx_extract_text_events filters to m.text, so the adapter never
    # receives what it can send. The notice above does not come back.
    expect_false("a notice" %in% vapply(got2$messages, `[[`, "", "body"))

    # An empty sync polls to empty without error
    quiet <- chat_matrix(mx = fake_mx(),
                         .sync = function(client, ...) {
                             list(sync = list(rooms = list(join = list())),
                                  client = fake_mx("s0"), first_run = TRUE)
                         },
                         .send = function(...) "$id",
                         .media = function(...) NULL)
    empty <- chat_poll(quiet)
    expect_identical(length(empty$messages), 0L)
    expect_identical(empty$cursor, "s0")
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
    invisible(NULL)
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

# Files upload one call per file, into the same room, before the text
chat_send(s, "!room:ex", "see attached", files = c("/tmp/a.png",
                                                   "/tmp/b.png"))
expect_identical(length(media_calls$args), 2L)
expect_identical(media_calls$args[[1L]]$file, "/tmp/a.png")
expect_identical(media_calls$args[[2L]]$room, "!room:ex")
# ... and the text still goes, returning its own id
expect_identical(send_calls$args[[6L]]$text, "see attached")

# ---- Capabilities ----

caps <- chat_capabilities(s)
# Matrix threads are replies, not first-class channels
expect_false(caps$threads)
expect_true(caps$thread_replies)
expect_true(caps$reactions)
expect_true(caps$files)
expect_true(caps$typing)
# Matrix has no per-message identity override
expect_false(caps$identity_override)
expect_identical(caps$markup_dialects, c("plain", "markdown"))
# e2ee is reported from what is actually installed, not assumed
expect_identical(caps$e2ee, requireNamespace("mx.crypto", quietly = TRUE))

# ---- Typing ----

# Typing is best-effort: a client that cannot produce a session
# reports FALSE rather than propagating the error into a chat loop.
if (requireNamespace("mx.client", quietly = TRUE)) {
    broken <- chat_matrix(mx = list(), .sync = function(...) NULL,
                          .extract = function(...) list(),
                          .send = fake_send, .media = fake_media)
    expect_false(chat_typing(broken, "!room:ex", on = TRUE))
}
