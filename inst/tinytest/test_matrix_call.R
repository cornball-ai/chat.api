# MatrixRTC calls on the Matrix adapter (R/matrix-call.R), with the
# protocol (mx.client's mx_call_*) and the crypto faked through the
# constructor's seams. What is under test is the adapter's part: the
# live credentials and Olm sessions handed to each call operation, the
# decrypted to-device events of a poll reaching the call, and what a
# consumer is told afterwards.

library(tinytest)

fake_mx <- function(token = "tok", user_id = "@bot:ex", device_id = "DEV1") {
    list(user_id = user_id, server = "https://ex.invalid", token = token,
         device_id = device_id, sync_token = NULL)
}

wrap_sync <- function(events = list(), room = "!room:ex", to_device = list()) {
    join <- list(list(timeline = list(events = events)))
    names(join) <- room
    list(rooms = list(join = join), to_device = list(events = to_device))
}

key_event <- function(identity, key_b64, index) {
    list(type = "io.element.call.encryption_keys", sender = sub(":[^:]+$", "", identity),
         content = list(keys = list(list(index = index, key = key_b64)),
                        member = list(id = sub(":[^:]+$", "", identity),
                                      claimed_device_id = sub("^.*:", "", identity)),
                        room_id = "!room:ex"))
}

# A crypto context the fake decrypt fills with this poll's to-device
# events, the way the real one does.
fake_crypto <- function() {
    chat.api:::matrix_crypto_forget()
    ctx <- new.env(parent = emptyenv())
    ctx$account <- "ACCOUNT"
    ctx$sessions <- list(olm = list(), generation = 0L)
    ctx$store <- "/tmp/fake-store"
    ctx$encrypted <- "!room:ex"
    ctx$next_to_device <- list()
    ops <- list(init = function(mx, store = NULL, app = NULL) ctx,
                encrypted = function(crypto, mx, room_id) room_id %in% crypto$encrypted,
                send = function(crypto, mx, room_id, text, ...) "$sent",
                decrypt = function(crypto, sync, mx) {
                    crypto$to_device <- sync$to_device$events %||% list()
                    list()
                })
    list(ops = ops, ctx = ctx)
}

# The protocol, faked: a join mints a token and a key; a handle applies
# the key events it is given, rotates the key on a membership change,
# and records what it was handed; each operation touches the sessions
# so the adapter's adoption of them can be seen.
fake_calls <- function(handle_error = FALSE) {
    log <- new.env(parent = emptyenv())
    log$join <- list()
    log$handle <- list()
    log$leave <- list()
    ops <- list(
        join = function(client, account, sessions, room_id, intent = "voice",
                        store_dir = NULL, connect = TRUE, service_url = NULL) {
            log$join[[length(log$join) + 1L]] <- list(
                client = client, account = account, sessions = sessions,
                room_id = room_id, intent = intent, store_dir = store_dir,
                connect = connect, service_url = service_url)
            call <- new.env(parent = emptyenv())
            call$client <- client
            call$account <- account
            call$sessions <- modifyList(sessions, list(generation = sessions$generation + 1L))
            call$room_id <- room_id
            call$identity <- paste0(client$user_id, ":", client$device_id)
            call$token <- list(url = "wss://sfu.ex", jwt = "jwt-1")
            call$keys <- list(key = as.raw(1:16), index = 0L, peers = list())
            call
        },
        handle = function(call, sync, processed = NULL) {
            log$handle[[length(log$handle) + 1L]] <- list(
                client = call$client, sessions = call$sessions, processed = processed)
            if (isTRUE(handle_error)) {
                stop("room state unreachable")
            }
            call$sessions <- modifyList(call$sessions,
                                        list(generation = call$sessions$generation + 1L))
            received <- character()
            for (ev in processed$to_device %||% list()) {
                if (identical(ev$type, "io.element.call.encryption_keys")) {
                    id <- paste0(ev$content$member$id, ":",
                                 ev$content$member$claimed_device_id)
                    k <- ev$content$keys[[1L]]
                    call$keys$peers[[id]] <- list(key = jsonlite::base64_dec(k$key),
                                                  index = k$index)
                    received <- c(received, id)
                }
            }
            members <- NULL
            room <- sync$rooms$join[[call$room_id]]
            if (any(vapply(room$timeline$events %||% list(), function(e) {
                identical(e$type, "org.matrix.msc3401.call.member")
            }, logical(1)))) {
                members <- list(list(identity = call$identity),
                                list(identity = "@ann:ex:PHONE"))
                call$keys$key <- as.raw(17:32)
                call$keys$index <- call$keys$index + 1L
            }
            list(keys = received, members = members)
        },
        leave = function(call) {
            log$leave[[length(log$leave) + 1L]] <- list(client = call$client)
            invisible(NULL)
        })
    list(ops = ops, log = log)
}

seam_client <- function(syncs, crypto, calls, e2ee = TRUE) {
    i <- 0L
    chat_matrix(mx = fake_mx(), e2ee = e2ee, .crypto = crypto$ops, .call = calls$ops,
                .save = function(client, ...) client,
                .sync = function(client, ...) {
                    i <<- i + 1L
                    s <- if (i <= length(syncs)) syncs[[i]] else wrap_sync()
                    # Each poll rotates the token, as a relogin would.
                    list(sync = s, client = fake_mx(sprintf("tok-%d", i)),
                         first_run = FALSE)
                },
                .extract = function(sync, self_id) list(),
                .send = function(...) "$id", .media = function(...) NULL)
}

# ---- capabilities ----
local({
    cr <- fake_crypto()
    expect_true(chat_capabilities(seam_client(list(), cr, fake_calls()))$calls)
    expect_false(chat_capabilities(seam_client(list(), cr, fake_calls(), e2ee = FALSE))$calls)
    expect_false(chat_capabilities(chat_loopback())$calls)
    for (adapter in c("chat_loopback", "chat_irc", "chat_slack", "chat_matrix",
                      "chat_telegram")) {
        m <- getS3method("chat_capabilities", adapter)
        caps <- m(structure(list(env = new.env()), class = adapter))
        expect_true(is.logical(caps$calls) && length(caps$calls) == 1L,
                    info = adapter)
    }
})

# Other adapters refuse by name.
expect_error(chat_call_join(chat_loopback(), "general"), "not supported")
expect_error(chat_call_leave(chat_loopback(), structure(new.env(), class = "chat_call")),
             "not supported")

# ---- joining ----
local({
    cr <- fake_crypto()
    fc <- fake_calls()
    # Not without e2ee: the keys travel over Olm.
    expect_error(chat_call_join(seam_client(list(), cr, fc, e2ee = FALSE), "!room:ex"),
                 "e2ee = TRUE")
    cl <- seam_client(list(), cr, fc)
    call <- chat_call_join(cl, "!room:ex", service_url = "https://jwt.ex")
    expect_true(inherits(call, "chat_call"))
    expect_identical(call$channel, "!room:ex")
    expect_identical(call$identity, "@bot:ex:DEV1")
    # The protocol got the live credentials, the adapter's crypto
    # state, its store, and no media connection of its own.
    j <- fc$log$join[[1L]]
    expect_identical(j$client$token, "tok")
    expect_identical(j$account, "ACCOUNT")
    expect_identical(j$store_dir, "/tmp/fake-store")
    expect_false(j$connect)
    expect_identical(j$intent, "voice")
    expect_identical(j$service_url, "https://jwt.ex")
    # The sessions the join touched are the adapter's now.
    expect_identical(cr$ctx$sessions$generation, 1L)
    # What a media side needs.
    media <- chat_call_media(call)
    expect_identical(media$url, "wss://sfu.ex")
    expect_identical(media$jwt, "jwt-1")
    expect_identical(media$identity, "@bot:ex:DEV1")
    expect_identical(media$key, list(key = as.raw(1:16), index = 0L))
    expect_identical(media$peers, list())
    # Nothing has changed yet.
    upd <- chat_call_updates(call)
    expect_identical(upd$keys, list())
    expect_null(upd$own)
    expect_null(upd$members)
    expect_false(upd$ended)
    # One call per room at a time.
    expect_error(chat_call_join(cl, "!room:ex"), "already in the call")
    expect_stdout(print(call), "<chat_call> !room:ex as @bot:ex:DEV1")
})

# ---- polling advances the call ----
local({
    cr <- fake_crypto()
    fc <- fake_calls()
    peer_key <- jsonlite::base64_enc(as.raw(101:116))
    syncs <- list(
        wrap_sync(to_device = list(key_event("@ann:ex:PHONE", peer_key, 4L))),
        wrap_sync(events = list(list(type = "org.matrix.msc3401.call.member",
                                     sender = "@ann:ex", content = list()))),
        wrap_sync())
    cl <- seam_client(syncs, cr, fc)
    call <- chat_call_join(cl, "!room:ex")
    # Poll 1: a peer's key arrives in the to-device traffic the adapter
    # decrypted; the call is handed it, not the raw sync to decrypt again.
    chat_poll(cl)
    h <- fc$log$handle[[1L]]
    expect_identical(length(h$processed$to_device), 1L)
    expect_identical(h$processed$to_device[[1L]]$type, "io.element.call.encryption_keys")
    # With the credentials this poll rotated to, and the adapter's sessions.
    expect_identical(h$client$token, "tok-1")
    expect_identical(h$sessions$generation, 1L)
    expect_identical(cr$ctx$sessions$generation, 2L)
    upd <- chat_call_updates(call)
    expect_identical(upd$keys, list(list(identity = "@ann:ex:PHONE", key = as.raw(101:116),
                                         index = 4L)))
    expect_null(upd$own)
    expect_null(upd$members)
    # The peer's key is also in what a media side starting late gets.
    expect_identical(chat_call_media(call)$peers[[1L]]$identity, "@ann:ex:PHONE")
    # Poll 2: a membership change rotates our key; the consumer is told
    # the new key and the members.
    chat_poll(cl)
    expect_identical(fc$log$handle[[2L]]$client$token, "tok-2")
    upd <- chat_call_updates(call)
    expect_identical(upd$keys, list())
    expect_identical(upd$own, list(key = as.raw(17:32), index = 1L))
    expect_identical(upd$members, c("@bot:ex:DEV1", "@ann:ex:PHONE"))
    expect_identical(chat_call_media(call)$key$index, 1L)
    # Poll 3: nothing for the call; updates are empty and were cleared.
    chat_poll(cl)
    upd <- chat_call_updates(call)
    expect_identical(upd$keys, list())
    expect_null(upd$own)
    expect_null(upd$members)
    expect_identical(length(fc$log$handle), 3L)
    # The to-device events were not left on the context for a later poll.
    expect_null(cr$ctx$to_device)
})

# ---- a call that cannot be advanced costs the poll nothing ----
local({
    cr <- fake_crypto()
    fc <- fake_calls(handle_error = TRUE)
    cl <- seam_client(list(wrap_sync()), cr, fc)
    call <- chat_call_join(cl, "!room:ex")
    res <- NULL
    expect_warning(res <- chat_poll(cl), "could not be advanced: room state unreachable")
    expect_true(is.list(res) && !is.null(res$messages))
    expect_false(chat_call_updates(call)$ended)
    expect_identical(length(fc$log$handle), 1L)
})

# ---- the call outlives the client object ----
# corteza builds a chat client per poll. The calls live on the identity's
# interned crypto context, so a new client for the same identity polls
# them on.
local({
    cr <- fake_crypto()
    fc <- fake_calls()
    peer_key <- jsonlite::base64_enc(as.raw(1:16))
    first <- seam_client(list(), cr, fc)
    call <- chat_call_join(first, "!room:ex")
    second <- seam_client(list(wrap_sync(to_device = list(
        key_event("@bob:ex:LAPTOP", peer_key, 2L)))), cr, fc)
    chat_poll(second)
    expect_identical(length(fc$log$handle), 1L)
    expect_identical(chat_call_updates(call)$keys[[1L]]$identity, "@bob:ex:LAPTOP")
    # And a third client sees it as already joined.
    expect_error(chat_call_join(seam_client(list(), cr, fc), "!room:ex"),
                 "already in the call")
    chat_call_leave(seam_client(list(), cr, fc), call)
    expect_true(chat_call_updates(call)$ended)
})

# ---- leaving ----
local({
    cr <- fake_crypto()
    fc <- fake_calls()
    cl <- seam_client(list(wrap_sync(), wrap_sync()), cr, fc)
    call <- chat_call_join(cl, "!room:ex")
    chat_poll(cl)
    chat_call_leave(cl, call)
    expect_identical(fc$log$leave[[1L]]$client$token, "tok-1")
    expect_true(chat_call_updates(call)$ended)
    expect_stdout(print(call), "(left)")
    # No longer advanced by polls, and the room can be joined again.
    chat_poll(cl)
    expect_identical(length(fc$log$handle), 1L)
    again <- chat_call_join(cl, "!room:ex")
    expect_false(chat_call_updates(again)$ended)
    # Leaving twice is idempotent.
    chat_call_leave(cl, call)
    expect_identical(length(fc$log$leave), 1L)
})
