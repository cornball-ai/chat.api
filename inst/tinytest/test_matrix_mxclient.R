# The half of the Matrix adapter that needs mx.client installed: drift
# detection against its real signatures, the mapping run through the
# real extractor rather than a seam, and the typing and resolve paths
# that call into it directly. Splitting these out means the skip is
# announced. Folded into test_matrix.R behind a bare `if`, roughly 60%
# of the Matrix suite used to evaporate on a runner built with
# _R_CHECK_FORCE_SUGGESTS_=false and the badge stayed green.

if (!requireNamespace("mx.client", quietly = TRUE)) {
    exit_file("mx.client not installed")
}

# ---- API drift ----
# Membership is not enough: the adapter passes the first one or two
# arguments positionally, so an upstream reorder would keep every name
# present while the message body went out as the room id.

sync_formals <- names(formals(mx.client::mx_sync_update))
expect_true(all(c("client", "timeout", "save", "app", "filter") %in%
                sync_formals))
expect_identical(sync_formals[1L], "client")

# mx_sync_update's return is what carries first_run, and a silent
# removal is invisible at the call site: isTRUE(NULL) is FALSE, so every
# restart would replay its backfill as new mail with nothing erroring.
sync_body <- paste(deparse(body(mx.client::mx_sync_update)), collapse = " ")
expect_true(grepl("first_run", sync_body, fixed = TRUE))

extract_formals <- names(formals(mx.client::mx_extract_text_events))
expect_true(all(c("sync_resp", "self_id") %in% extract_formals))
expect_identical(extract_formals[1L], "sync_resp")

send_formals <- names(formals(mx.client::mx_send_text))
expect_true(all(c("room", "msgtype", "markdown", "mentions") %in%
                send_formals))
expect_identical(send_formals[1:2], c("client", "text"))

# chat_send passes room by name to mx_send_media; a rename upstream
# would silently fall back to the client's default room.
media_formals <- names(formals(mx.client::mx_send_media))
expect_identical(media_formals[1:2], c("client", "path"))
expect_true("room" %in% media_formals)

# chat_typing goes through a session, not the client config
expect_true("mx_client_session" %in% getNamespaceExports("mx.client"))
# chat_poll's token self-heal
expect_true("mx_with_relogin" %in% getNamespaceExports("mx.client"))

if (requireNamespace("mx.api", quietly = TRUE)) {
    # chat_typing passes room, typing state, and timeout by name
    typing_formals <- names(formals(mx.api::mx_typing))
    expect_true(all(c("room_id", "typing", "timeout") %in% typing_formals))
    expect_identical(typing_formals[1L], "session")
}

# ---- Markdown table route ----

# Matrix is the chat.api adapter where Markdown tables need a transport
# conversion: chat.api keeps the source as markdown, mx.client renders it to
# Matrix custom HTML, and mx.api receives the final event. Stub only the final
# mx.api network call so this exercises the real chat.api -> mx.client path.
if (requireNamespace("mx.api", quietly = TRUE)) {
    sent <- new.env()
    sent$args <- list()
    orig_mx_send <- mx.api::mx_send
    assignInNamespace("mx_send", function(session, room_id, body,
                                          msgtype = "m.text", extra = NULL) {
        sent$args[[length(sent$args) + 1L]] <<- list(
            session = session, room_id = room_id, body = body,
            msgtype = msgtype, extra = extra)
        "$table:ex"
    }, ns = "mx.api")
    on.exit(assignInNamespace("mx_send", orig_mx_send, ns = "mx.api"),
            add = TRUE)

    table_md <- paste(c(
        "| package | days per submission | latest |",
        "|---|---:|---:|",
        "| `llm.api` | 20.8 | 2026-06-26 |",
        "| `tinyrox` | 52.5 | 2026-06-24 |"
    ), collapse = "\n")
    p_table <- chat_matrix(mx = list(user_id = "@bot:ex",
                                     server = "https://ex.invalid",
                                     token = "tok", device_id = "DEV",
                                     room_id = "!default:ex"),
                           .sync = function(...) NULL,
                           .extract = function(...) list(),
                           .media = function(...) NULL)
    expect_identical(chat_send(p_table, "!room:ex", table_md,
                               markup = "markdown"), "$table:ex")
    routed <- sent$args[[1L]]
    expect_identical(routed$room_id, "!room:ex")
    expect_identical(routed$body, table_md)
    expect_identical(routed$msgtype, "m.text")
    expect_identical(routed$extra$format, "org.matrix.custom.html")
    expect_true(grepl("<table>", routed$extra$formatted_body, fixed = TRUE))
    expect_true(grepl("<td><code>llm.api</code></td>",
                      routed$extra$formatted_body, fixed = TRUE))
    expect_true(grepl("<td align=\"right\">20.8</td>",
                      routed$extra$formatted_body, fixed = TRUE))
}

# ---- Fixtures ----

fake_mx <- function(sync_token = NULL, room_id = NULL) {
    list(user_id = "@bot:ex", server = "https://ex.invalid",
         sync_token = sync_token, room_id = room_id)
}

# One human message, one from the bot itself, one m.notice. The bot's
# own event is tagged is_self by the extractor; the notice is dropped
# by its default msgtypes filter (see the asymmetry note below).
fake_sync <- list(rooms = list(join = list("!room:ex" = list(timeline = list(
    events = list(
        list(type = "m.room.message", event_id = "$1", sender = "@alice:ex",
             origin_server_ts = 1700000000000,
             content = list(msgtype = "m.text", body = "hello",
                            "m.mentions" = list(user_ids = list("@bot:ex")))),
        list(type = "m.room.message", event_id = "$2", sender = "@bot:ex",
             origin_server_ts = 1700000001000,
             content = list(msgtype = "m.text", body = "my own echo")),
        list(type = "m.room.message", event_id = "$3", sender = "@carol:ex",
             origin_server_ts = 1700000002000,
             content = list(msgtype = "m.notice", body = "a notice"))
    )
)))))

# ---- Poll through the real extractor ----
# Worth exercising for real rather than faking the record shape it
# produces: this is where the adapter's assumptions about that shape are
# either true of the installed build or not.

p <- chat_matrix(mx = fake_mx(), save_cursor = FALSE,
                 .sync = function(client, ...) {
                     list(sync = fake_sync, client = fake_mx("s_next"),
                          first_run = FALSE)
                 },
                 .send = function(...) "$id", .media = function(...) NULL)
got <- chat_poll(p)

expect_identical(got$cursor, "s_next")
expect_identical(p$env$mx$sync_token, "s_next")
expect_identical(got$raw, fake_sync)
expect_false(got$first_run)

# Self events are retained and flagged
expect_identical(length(got$messages), 2L)
expect_identical(vapply(got$messages, `[[`, "", "body"),
                 c("hello", "my own echo"))
expect_identical(vapply(got$messages, `[[`, logical(1), "self"),
                 c(FALSE, TRUE))

m <- got$messages[[1L]]
expect_identical(m$id, "$1")
expect_identical(m$channel, "!room:ex")
expect_identical(m$sender, "@alice:ex")
expect_identical(m$kind, "message")
expect_identical(m$mentions, "@bot:ex")

# The event's own time, by value. mx_extract_text_events only started
# carrying ts partway through mx.client 0.1.1.1's development, and
# builds either side of that share a version string, so this passes only
# if the adapter also reads origin_server_ts off the sync. A class-only
# assertion would have been satisfied by Sys.time().
expect_inherits(m$ts, "POSIXct")
expect_equal(as.numeric(m$ts), 1700000000, tolerance = 1e-6)
expect_equal(as.numeric(got$messages[[2L]]$ts), 1700000001, tolerance = 1e-6)

# Known asymmetry: chat_send can emit m.notice and m.emote, but
# mx_extract_text_events filters to m.text, so the adapter never
# receives what it can send. The notice above does not come back.
expect_false("a notice" %in% vapply(got$messages, `[[`, "", "body"))

# The extractor drops content$m.relates_to, so a threaded reply arrives
# with $thread empty and the relation unreachable from the message-level
# raw. thread_replies reports FALSE for exactly this reason.
expect_true(all(c("room_id", "event_id", "sender", "is_self", "body",
                  "msgtype", "mentions") %in% names(m$raw)))
expect_false("content" %in% names(m$raw))
expect_null(m$raw[["m.relates_to"]])
expect_false(chat_capabilities(p)$thread_replies)

# ---- Resolve ----
# Offline: mx_resolve_room short-circuits on a !-prefixed id and on an
# empty name, so both paths run without a homeserver.

r <- chat_matrix(mx = fake_mx(room_id = "!default:ex"),
                 .sync = function(...) NULL,
                 .extract = function(...) list(),
                 .send = function(...) "$id", .media = function(...) NULL)
# A literal room id passes through untouched
expect_identical(chat_resolve(r, "!real:ex"), "!real:ex")
# An empty name falls back to the client's default room rather than
# erroring. That is mx_resolve_room's fallback = TRUE default, and the
# adapter does not override it, so a caller that resolves an empty name
# posts into the default room. Pinned so the behaviour stays deliberate.
expect_identical(chat_resolve(r, ""), "!default:ex")
# With no default room there is nothing to fall back to, and it errors
# instead of returning NULL
no_default <- chat_matrix(mx = fake_mx(), .sync = function(...) NULL,
                          .extract = function(...) list(),
                          .send = function(...) "$id",
                          .media = function(...) NULL)
expect_error(chat_resolve(no_default, ""))

# ---- Typing ----

fake_send <- function(...) "$sent"
fake_media <- function(...) NULL

# Typing is best-effort: a client that cannot produce a session
# reports FALSE rather than propagating the error into a chat loop.
broken <- chat_matrix(mx = list(), .sync = function(...) NULL,
                      .extract = function(...) list(),
                      .send = fake_send, .media = fake_media)
expect_false(chat_typing(broken, "!room:ex", on = TRUE))

# The success path needs a config complete enough for
# mx_client_session(), so the real config -> session mapping runs;
# .typing stands in for the homeserver call.
typing_calls <- new.env()
typing_calls$args <- list()
fake_typing <- function(session, room_id, ...) {
    typing_calls$args[[length(typing_calls$args) + 1L]] <- c(
        list(session = session, room_id = room_id), list(...))
    invisible(NULL)
}
ty <- chat_matrix(mx = list(user_id = "@bot:ex",
                            server = "https://ex.invalid",
                            token = "tok", device_id = "DEV"),
                  .sync = function(...) NULL,
                  .extract = function(...) list(),
                  .send = fake_send, .media = fake_media,
                  .typing = fake_typing)

expect_true(chat_typing(ty, "!room:ex"))
t1 <- typing_calls$args[[1L]]
expect_inherits(t1$session, "mx_session")
expect_identical(t1$room_id, "!room:ex")
expect_true(t1$typing)
# Default is 30 seconds, converted to the milliseconds mx.api wants
expect_identical(t1$timeout, 30000L)

# A caller working through a slow model turn picks its own window
expect_true(chat_typing(ty, "!room:ex", on = TRUE, timeout = 120))
expect_identical(typing_calls$args[[2L]]$timeout, 120000L)

# ... and clears it afterwards: the off path goes out as
# typing = FALSE rather than being dropped or inverted
expect_true(chat_typing(ty, "!room:ex", on = FALSE))
expect_false(typing_calls$args[[3L]]$typing)

# A NULL timeout falls back to the default instead of erroring
chat_typing(ty, "!room:ex", timeout = NULL)
expect_identical(typing_calls$args[[4L]]$timeout, 30000L)

# A failing homeserver call is still swallowed, seam or not
boom <- chat_matrix(mx = list(user_id = "@bot:ex",
                              server = "https://ex.invalid",
                              token = "tok", device_id = "DEV"),
                    .sync = function(...) NULL,
                    .extract = function(...) list(),
                    .send = fake_send, .media = fake_media,
                    .typing = function(...) stop("homeserver down"))
expect_false(chat_typing(boom, "!room:ex"))

# ---- The real crypto boundary functions ----
# These sit behind chat_matrix()'s .crypto seam, so the adapter-routing
# tests in test_matrix.R never reach them. Their failure modes are the
# two that leak, so they are driven directly here against stubbed
# mx.client / mx.api entry points.

crypto_ctx <- function(encrypted = character(), store = tempfile("cs")) {
    ctx <- new.env(parent = emptyenv())
    ctx$encrypted <- encrypted
    ctx$store <- store
    ctx$account <- NULL
    ctx$sessions <- list()
    ctx
}

stub <- function(name, value, ns) {
    orig <- get(name, envir = asNamespace(ns))
    assignInNamespace(name, value, ns = ns)
    orig
}

mx_cfg <- list(user_id = "@bot:ex", device_id = "DEV",
               server = "https://ex.invalid", token = "tok")

# An unanswerable encryption state aborts rather than answering FALSE.
# Turning an expired token, a timeout, or a 500 into "not encrypted" sent
# the message in the clear.
local({
    orig <- stub("mx_room_encrypted",
                 function(...) stop("Matrix error [M_UNKNOWN_TOKEN]"),
                 "mx.client")
    on.exit(assignInNamespace("mx_room_encrypted", orig, ns = "mx.client"))
    expect_error(
        chat.api:::matrix_room_is_encrypted(crypto_ctx(), mx_cfg, "!r:ex"),
        "cannot determine the encryption state")
})

# A room that answers TRUE is remembered, so the next send skips the
# lookup -- which is also what keeps a transient failure from blocking a
# room already known to be encrypted.
local({
    ctx <- crypto_ctx()
    orig <- stub("mx_room_encrypted", function(...) TRUE, "mx.client")
    on.exit(assignInNamespace("mx_room_encrypted", orig, ns = "mx.client"))
    expect_true(chat.api:::matrix_room_is_encrypted(ctx, mx_cfg, "!r:ex"))
    expect_true("!r:ex" %in% ctx$encrypted)
})
local({
    ctx <- crypto_ctx(encrypted = "!r:ex")
    orig <- stub("mx_room_encrypted", function(...) stop("down"), "mx.client")
    on.exit(assignInNamespace("mx_room_encrypted", orig, ns = "mx.client"))
    expect_true(chat.api:::matrix_room_is_encrypted(ctx, mx_cfg, "!r:ex"))
})

# A room that answers FALSE is a plaintext room, and is not cached: the
# next send asks again, so a room that turns encryption on is caught.
local({
    asked <- 0L
    ctx <- crypto_ctx()
    orig <- stub("mx_room_encrypted",
                 function(...) { asked <<- asked + 1L; FALSE }, "mx.client")
    on.exit(assignInNamespace("mx_room_encrypted", orig, ns = "mx.client"))
    expect_false(chat.api:::matrix_room_is_encrypted(ctx, mx_cfg, "!r:ex"))
    expect_false(chat.api:::matrix_room_is_encrypted(ctx, mx_cfg, "!r:ex"))
    expect_identical(asked, 2L)
    expect_identical(ctx$encrypted, character())
})

# No crypto context is not an encrypted room, and asks nobody.
local({
    orig <- stub("mx_room_encrypted", function(...) stop("must not be asked"),
                 "mx.client")
    on.exit(assignInNamespace("mx_room_encrypted", orig, ns = "mx.client"))
    expect_false(chat.api:::matrix_room_is_encrypted(NULL, mx_cfg, "!r:ex"))
})

# Membership discovery is not best-effort. mx_send_encrypted() derives
# the recipient devices from member_ids: an empty list shares the room key
# with nobody, posts the event anyway, and returns an event id, so the
# room cannot read the message while the caller records a successful send.
local({
    sent <- 0L
    o1 <- stub("mx_client_session", function(...) list(server = "s"),
               "mx.client")
    o2 <- stub("mx_room_members", function(...) stop("500 from homeserver"),
               "mx.api")
    o3 <- stub("mx_send_encrypted",
               function(...) { sent <<- sent + 1L
                               list(event_id = "$e", sessions = list()) },
               "mx.client")
    on.exit({
        assignInNamespace("mx_client_session", o1, ns = "mx.client")
        assignInNamespace("mx_room_members", o2, ns = "mx.api")
        assignInNamespace("mx_send_encrypted", o3, ns = "mx.client")
    })
    expect_error(chat.api:::matrix_crypto_send(crypto_ctx(), mx_cfg, "!r:ex",
                                               "secret"),
                 "500 from homeserver")
    expect_identical(sent, 0L)
})

# An empty member list is the same refusal, reached without an error to
# propagate.
local({
    sent <- 0L
    o1 <- stub("mx_client_session", function(...) list(server = "s"),
               "mx.client")
    o2 <- stub("mx_room_members", function(...) character(), "mx.api")
    o3 <- stub("mx_send_encrypted",
               function(...) { sent <<- sent + 1L
                               list(event_id = "$e", sessions = list()) },
               "mx.client")
    on.exit({
        assignInNamespace("mx_client_session", o1, ns = "mx.client")
        assignInNamespace("mx_room_members", o2, ns = "mx.api")
        assignInNamespace("mx_send_encrypted", o3, ns = "mx.client")
    })
    expect_error(chat.api:::matrix_crypto_send(crypto_ctx(), mx_cfg, "!r:ex",
                                               "secret"),
                 "reach nobody")
    expect_identical(sent, 0L)
})

# A session that cannot be built is the same: no send.
local({
    sent <- 0L
    o1 <- stub("mx_client_session", function(...) stop("no server in config"),
               "mx.client")
    o3 <- stub("mx_send_encrypted",
               function(...) { sent <<- sent + 1L
                               list(event_id = "$e", sessions = list()) },
               "mx.client")
    on.exit({
        assignInNamespace("mx_client_session", o1, ns = "mx.client")
        assignInNamespace("mx_send_encrypted", o3, ns = "mx.client")
    })
    expect_error(chat.api:::matrix_crypto_send(crypto_ctx(), mx_cfg, "!r:ex",
                                               "secret"),
                 "no server in config")
    expect_identical(sent, 0L)
})

# With members, the send goes through and carries them, plus the content
# the cleartext path would have PUT.
local({
    seen <- NULL
    o1 <- stub("mx_client_session", function(...) list(server = "s"),
               "mx.client")
    o2 <- stub("mx_room_members", function(...) c("@a:ex", "@b:ex"), "mx.api")
    o3 <- stub("mx_send_encrypted",
               function(client, account, sessions, room_id, content, store_dir,
                        recipients = NULL, member_ids = NULL) {
                   seen <<- list(content = content, member_ids = member_ids,
                                 room_id = room_id)
                   list(event_id = "$enc", sessions = "new")
               }, "mx.client")
    on.exit({
        assignInNamespace("mx_client_session", o1, ns = "mx.client")
        assignInNamespace("mx_room_members", o2, ns = "mx.api")
        assignInNamespace("mx_send_encrypted", o3, ns = "mx.client")
    })
    ctx <- crypto_ctx()
    expect_identical(chat.api:::matrix_crypto_send(ctx, mx_cfg, "!r:ex",
                                                   "**hi**",
                                                   markdown = TRUE), "$enc")
    expect_identical(seen$member_ids, c("@a:ex", "@b:ex"))
    expect_identical(seen$content$body, "**hi**")
    expect_identical(seen$content$format, "org.matrix.custom.html")
    expect_true(grepl("<strong>hi</strong>", seen$content$formatted_body))
    # The updated session set is kept, or the next send re-shares the key.
    expect_identical(ctx$sessions, "new")
})

# The content an encrypted send wraps is the one mx_send_text() PUTs in
# the clear, so a room's encryption state changes the envelope and
# nothing a reader sees.
content <- chat.api:::matrix_crypto_content
expect_identical(content("hi")$body, "hi")
expect_null(content("hi")$formatted_body)
expect_identical(content("hi", msgtype = "m.notice")$msgtype, "m.notice")
expect_true(grepl("<strong>hi</strong>",
                  content("**hi**", markdown = TRUE)$formatted_body))
m <- content("hi", mentions = "@c:ex")
expect_identical(m[["m.mentions"]]$user_ids, list("@c:ex"))
expect_identical(m$format, "org.matrix.custom.html")

# matrix_crypto_init() binds the store before it opens the account, so a
# store belonging to another device is refused rather than unpickled.
# Every mx.client entry point below is stubbed: what is under test is the
# order of the adapter's own steps, not the cryptography.
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    local({
        opened <- 0L
        o1 <- stub("mx_crypto_account",
                   function(...) { opened <<- opened + 1L; "acct" },
                   "mx.client")
        o2 <- stub("mx_crypto_publish_keys", function(...) invisible(TRUE),
                   "mx.client")
        o3 <- stub("mx_crypto_sessions_load", function(...) list(),
                   "mx.client")
        o4 <- stub("mx_client_session", function(...) stop("offline"),
                   "mx.client")
        o5 <- stub("mxc_account_identity_keys",
                   function(...) list(curve25519 = "C", ed25519 = "E"),
                   "mx.crypto")
        # A homeserver that has never seen this device. The published-key
        # check is exercised on its own further down.
        o6 <- stub("mx_crypto_known_devices", function(...) list(),
                   "mx.client")
        on.exit({
            assignInNamespace("mx_crypto_account", o1, ns = "mx.client")
            assignInNamespace("mx_crypto_publish_keys", o2, ns = "mx.client")
            assignInNamespace("mx_crypto_sessions_load", o3, ns = "mx.client")
            assignInNamespace("mx_client_session", o4, ns = "mx.client")
            assignInNamespace("mxc_account_identity_keys", o5, ns = "mx.crypto")
            assignInNamespace("mx_crypto_known_devices", o6, ns = "mx.client")
        })

        store <- tempfile("initstore")
        a <- list(user_id = "@a:ex", device_id = "D1", token = "t",
                  server = "https://ex.invalid")
        ctx <- chat.api:::matrix_crypto_init(a, store = store)
        expect_identical(ctx$store, store)
        expect_identical(opened, 1L)
        expect_identical(readLines(file.path(store, "identity.txt")),
                         c("@a:ex", "D1"))

        # Another device pointed at the same store is refused, and the
        # account is never opened for it.
        b <- list(user_id = "@b:ex", device_id = "D2", token = "t",
                  server = "https://ex.invalid")
        expect_error(chat.api:::matrix_crypto_init(b, store = store),
                     "belongs to")
        expect_identical(opened, 1L)
        unlink(store, recursive = TRUE)
    })
}

# The store path is per device, and its sanitization is not injective:
# "@a/b:ex" and "@a_b:ex" resolve to the same directory. That is why the
# identity is written into the store and compared on open -- the
# collision is caught there, in test_matrix.R. Resolving the path calls
# mx_crypto_store_dir(), which is why this half lives here.
local({
    a <- list(user_id = "@a/b:ex", device_id = "D")
    b <- list(user_id = "@a_b:ex", device_id = "D")
    expect_identical(chat.api:::matrix_crypto_store(a, app = "t"),
                     chat.api:::matrix_crypto_store(b, app = "t"))
    # Two devices of one user are two stores, and two users are two too.
    one <- list(user_id = "@a:ex", device_id = "D1")
    two <- list(user_id = "@a:ex", device_id = "D2")
    expect_false(identical(chat.api:::matrix_crypto_store(one, app = "t"),
                           chat.api:::matrix_crypto_store(two, app = "t")))
    expect_false(identical(chat.api:::matrix_crypto_store(one, app = "t"),
                           chat.api:::matrix_crypto_store(
                               list(user_id = "@b:ex", device_id = "D1"),
                               app = "t")))
    # It sits under mx.client's own store convention for the app.
    expect_true(startsWith(chat.api:::matrix_crypto_store(one, app = "t"),
                           mx.client::mx_crypto_store_dir(app = "t")))
})

# ---- One identity per device, durably ----
# The in-process cache stops two contexts existing at once and nothing
# more: restart, or matrix_crypto_forget(), and a changed crypto_store
# would mint a fresh account and publish different long-lived keys under
# the old device_id. The homeserver is the authority on which keys a
# device has, so that is what init checks against.
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    init_stubs <- function(known, ...) {
        o <- list(
            mx_crypto_account = stub("mx_crypto_account", function(...) "acct",
                                     "mx.client"),
            mx_crypto_publish_keys = stub("mx_crypto_publish_keys",
                                          function(...) invisible(TRUE),
                                          "mx.client"),
            mx_crypto_sessions_load = stub("mx_crypto_sessions_load",
                                           function(...) list(), "mx.client"),
            mx_client_session = stub("mx_client_session",
                                     function(...) stop("offline"),
                                     "mx.client"),
            mx_crypto_known_devices = stub("mx_crypto_known_devices", known,
                                           "mx.client"),
            mxc_account_identity_keys = stub(
                "mxc_account_identity_keys",
                function(...) list(curve25519 = "CURVE-ours",
                                   ed25519 = "ED-ours"), "mx.crypto"))
        o
    }
    restore_stubs <- function(o) {
        for (nm in names(o)) {
            ns <- if (nm == "mxc_account_identity_keys") "mx.crypto" else
                "mx.client"
            assignInNamespace(nm, o[[nm]], ns = ns)
        }
    }
    me <- list(user_id = "@a:ex", device_id = "D1", token = "t",
               server = "https://ex.invalid")

    # A device the homeserver has never seen is the first run.
    local({
        published <- NULL
        o <- init_stubs(function(client, user_ids) {
            published <<- user_ids
            list()
        })
        on.exit(restore_stubs(o))
        store <- tempfile("pub1")
        expect_true(is.environment(chat.api:::matrix_crypto_init(me,
                                                                 store = store)))
        # It asks about its own user, not the room's members.
        expect_identical(published, "@a:ex")
        unlink(store, recursive = TRUE)
    })

    # Keys that match are this device's own account: proceed.
    local({
        o <- init_stubs(function(...) list(
            list(user_id = "@a:ex", device_id = "D1",
                 curve25519 = "CURVE-ours", ed25519 = "ED-ours")))
        on.exit(restore_stubs(o))
        store <- tempfile("pub2")
        expect_true(is.environment(chat.api:::matrix_crypto_init(me,
                                                                 store = store)))
        unlink(store, recursive = TRUE)
    })

    # Keys that differ mean this store is not this device's. This is the
    # case a restart plus a changed crypto_store produced, which nothing
    # in the process cache could have seen.
    local({
        o <- init_stubs(function(...) list(
            list(user_id = "@a:ex", device_id = "D1",
                 curve25519 = "CURVE-theirs", ed25519 = "ED-theirs")))
        on.exit(restore_stubs(o))
        store <- tempfile("pub3")
        expect_error(chat.api:::matrix_crypto_init(me, store = store),
                     "already has different device keys")
        unlink(store, recursive = TRUE)
    })

    # Another device of the same user is not this device, and does not
    # collide with it.
    local({
        o <- init_stubs(function(...) list(
            list(user_id = "@a:ex", device_id = "D2",
                 curve25519 = "CURVE-other", ed25519 = "ED-other")))
        on.exit(restore_stubs(o))
        store <- tempfile("pub4")
        expect_true(is.environment(chat.api:::matrix_crypto_init(me,
                                                                 store = store)))
        unlink(store, recursive = TRUE)
    })

    # A query that cannot be answered is an error, not a shrug. init is
    # about to publish keys to that same homeserver, so being unable to
    # ask it anything is not a state to publish from.
    local({
        o <- init_stubs(function(...) stop("504 from homeserver"))
        on.exit(restore_stubs(o))
        store <- tempfile("pub5")
        expect_error(chat.api:::matrix_crypto_init(me, store = store),
                     "cannot read this device's published keys")
        unlink(store, recursive = TRUE)
    })

    # The check runs before the upload, so a mismatch never publishes.
    local({
        uploads <- 0L
        o <- init_stubs(function(...) list(
            list(user_id = "@a:ex", device_id = "D1",
                 curve25519 = "CURVE-theirs", ed25519 = "ED-theirs")))
        assignInNamespace("mx_crypto_publish_keys",
                          function(...) { uploads <<- uploads + 1L
                                          invisible(TRUE) }, ns = "mx.client")
        on.exit(restore_stubs(o))
        store <- tempfile("pub6")
        expect_error(chat.api:::matrix_crypto_init(me, store = store))
        expect_identical(uploads, 0L)
        unlink(store, recursive = TRUE)
    })
}
