# Matrix end-to-end encryption for the chat.api adapter.
#
# Olm/Megolm state owned by the adapter, so a consumer never handles
# crypto itself. All cryptography is delegated to mx.client and
# mx.crypto, both Suggests, both behind requireNamespace.
#
# Ported from corteza, which carried this in parallel to the contract and
# reached around chat_poll()$raw to do it. None of it is exported: the
# whole point is that E2EE is a property of the client a consumer already
# holds, not a second API it has to learn.

matrix_crypto_available <- function() {
    requireNamespace("mx.client", quietly = TRUE) &&
    requireNamespace("mx.crypto", quietly = TRUE)
}

# The Matrix device an Olm account belongs to: (user_id, device_id).
#
# Both are required. An Olm account is a device's identity, not a user's,
# so a store keyed on anything coarser is a store two identities can end
# up sharing -- and the second to open it comes up wearing the first's
# device keys.
matrix_crypto_identity <- function(mx) {
    uid <- mx$user_id %||% ""
    did <- mx$device_id %||% ""
    if (!nzchar(uid) || !nzchar(did)) {
        stop("chat.api: end-to-end encryption needs both user_id and ",
             "device_id on the Matrix config. An Olm account belongs to a ",
             "device, and a store that cannot name one is a store two ",
             "identities can share.", call. = FALSE)
    }
    c(user_id = uid, device_id = did)
}

# Where this identity's Olm account and sessions live.
#
# Under mx.client's own convention, R_user_dir(app, "data")/crypto, with a
# per-device subdirectory. Deliberately NOT derived from the config file's
# location: corteza computed dirname(config)/crypto, which ties the
# identity to wherever the config happens to sit, so a moved config
# silently minted a new device and lost every Megolm session it had.
#
# The directory name is sanitized and therefore not injective -- "@a/b:ex"
# and "@a_b:ex" land in the same place. That is why the exact identity is
# written into the store and checked on every open: a collision has to
# fail loudly rather than hand one bot another's account.
matrix_crypto_store <- function(mx, app = NULL) {
    id <- matrix_crypto_identity(mx)
    slug <- gsub("[^A-Za-z0-9._-]", "_",
                 paste(id[["user_id"]], id[["device_id"]], sep = "|"))
    file.path(mx.client::mx_crypto_store_dir(app = app %||% "chat.api"), slug)
}

# Bind a store to one device identity, and refuse to open one bound to
# another. Written on first use; compared exactly thereafter, so a
# sanitization collision, a copied store directory, or a device_id change
# is an error instead of a silent account swap.
matrix_crypto_bind_identity <- function(store, mx) {
    id <- matrix_crypto_identity(mx)
    f <- file.path(store, "identity.txt")
    if (file.exists(f)) {
        have <- readLines(f, warn = FALSE)
        want <- c(id[["user_id"]], id[["device_id"]])
        if (!identical(have[seq_along(want)], want)) {
            stop("chat.api: crypto store ", store, " belongs to ",
                 paste(have, collapse = "/"), ", not ",
                 paste(want, collapse = "/"),
                 ". Refusing to open another device's Olm account.",
                 call. = FALSE)
        }
        return(invisible(store))
    }
    dir.create(store, showWarnings = FALSE, recursive = TRUE)
    writeLines(c(id[["user_id"]], id[["device_id"]]), f)
    invisible(store)
}

# Crypto contexts already built in this session, keyed per identity.
#
# One identity is one Olm account, and building a second client for the
# same identity must not mint a second context: the account pickle, its
# published one-time keys, and the Megolm session set are all per-device
# state, and two contexts writing one store would overwrite each other's
# pickles.
#
# This is what lets a consumer rebuild its client as often as it likes.
# corteza builds one per use on purpose -- the access token rotates
# mid-loop, so anything holding a config from before a relogin keeps
# authenticating with the rejected one -- and interning means that costs
# an environment lookup rather than an account load and a 50-key upload.
.crypto_cache <- new.env(parent = emptyenv())

# The cache key: the device identity, plus wherever its store was asked
# for. Deliberately not the resolved directory -- resolving one calls into
# mx.client, and a .crypto seam exists precisely so the e2ee paths run
# without it.
#
# The identity has to be in the key. Keying on app or store alone had two
# clients built the documented way, chat_matrix(mx = ..., e2ee = TRUE),
# collapse onto one "app:chat.api" entry and share an Olm account.
matrix_crypto_cache_key <- function(store = NULL, app = NULL, mx = NULL) {
    id <- matrix_crypto_identity(mx)
    paste(store %||% paste0("app:", app %||% "chat.api"), id[["user_id"]],
          id[["device_id"]], sep = "\n")
}

matrix_crypto_context <- function(key, factory) {
    if (!is.null(.crypto_cache[[key]])) {
        return(.crypto_cache[[key]])
    }
    ctx <- factory()
    .crypto_cache[[key]] <- ctx
    ctx
}

# The client's crypto context, built on first use.
#
# Deliberately not built in chat_matrix(). Initialization publishes keys,
# which is an authenticated request, and the token on disk may already be
# rejected at process start -- that is the case mx_with_relogin() exists
# for. Building at construction put the upload before any relogin could
# happen, so chat_matrix() threw, corteza's poll loop never got to run,
# and every restart repeated with the same dead token. Now the context is
# built after a request has succeeded, off the config that succeeded.
#
# The result is stashed on the client's env, which is shared with every
# copy of the client, so this costs one lookup after the first call.
matrix_crypto_require <- function(client) {
    if (!isTRUE(client$e2ee)) {
        return(NULL)
    }
    if (!is.null(client$env$crypto)) {
        return(client$env$crypto)
    }
    mx <- client$env$mx
    ctx <- matrix_crypto_context(
                                 matrix_crypto_cache_key(client$crypto_store, client$app, mx),
                                 function() {
        client$crypto_ops$init(mx, store = client$crypto_store,
                               app = client$app)
    })
    client$env$crypto <- ctx
    ctx
}

# Drop interned contexts. Tests need it because they build many clients
# per identity on purpose; nothing in production calls it, since forgetting
# a context loses the Megolm sessions decrypted since the last save.
matrix_crypto_forget <- function(key = NULL) {
    if (is.null(key)) {
        rm(list = ls(.crypto_cache), envir = .crypto_cache)
    } else if (!is.null(.crypto_cache[[key]])) {
        rm(list = key, envir = .crypto_cache)
    }
    invisible(NULL)
}

# The crypto operations the adapter calls, as a replaceable set. Same
# reason chat_matrix() takes .sync and .extract: the Matrix methods have
# to be verifiable on a runner with neither mx.client nor a Rust
# toolchain, and E2EE is the one part of the adapter that cannot be
# exercised against a real homeserver in a test.
matrix_crypto_ops <- function(override = NULL) {
    ops <- list(init = matrix_crypto_init,
                encrypted = matrix_room_is_encrypted,
                send = matrix_crypto_send, decrypt = matrix_crypto_decrypt)
    for (nm in names(override)) {
        ops[[nm]] <- override[[nm]]
    }
    ops
}

# Load or create the account, publish keys, restore sessions and the
# known-encrypted-room set. Returns an environment: the poll loop mutates
# sessions in place, and callers hold the same object across polls.
#
# The store directory is derived here rather than by the caller so that
# mx.client is only needed on the path that actually does crypto: a
# .crypto seam replaces this whole function, and a test using one must
# not pay for mx_crypto_store_dir().
matrix_crypto_init <- function(mx, store = NULL, app = NULL) {
    if (!matrix_crypto_available()) {
        stop("Matrix end-to-end encryption requires the 'mx.client' and ",
             "'mx.crypto' packages.", call. = FALSE)
    }
    store <- store %||% matrix_crypto_store(mx, app = app)
    matrix_crypto_bind_identity(store, mx)
    acct <- mx.client::mx_crypto_account(store)
    mx.client::mx_crypto_publish_keys(mx, acct, store, n_otks = 50L)
    crypto <- new.env(parent = emptyenv())
    crypto$account <- acct
    crypto$store <- store
    # No cached client. The access token rotates -- chat_poll() relogins --
    # and a copy taken here goes stale the moment it does. Every send and
    # decrypt takes the adapter's live env$mx.
    crypto$sessions <- mx.client::mx_crypto_sessions_load(store)
    crypto$encrypted <- matrix_crypto_load_encrypted(store)
    crypto$self_curve <-
    mx.crypto::mxc_account_identity_keys(acct)$curve25519
    # Ask each joined room for its encryption state up front rather than
    # waiting for a sync to mention it. Best-effort per room; a transient
    # failure defers that room to sync-time detection.
    found <- matrix_crypto_scan_rooms(mx)
    fresh <- setdiff(found, crypto$encrypted)
    if (length(fresh)) {
        crypto$encrypted <- c(crypto$encrypted, fresh)
        matrix_crypto_save_encrypted(crypto)
    }
    crypto
}

# Joined rooms advertising m.room.encryption, by direct state query.
matrix_crypto_scan_rooms <- function(mx) {
    s <- tryCatch(mx.client::mx_client_session(mx), error = function(e) NULL)
    if (is.null(s)) {
        return(character())
    }
    rooms <- tryCatch(mx.api::mx_rooms(s), error = function(e) character())
    out <- character()
    for (rid in rooms) {
        if (isTRUE(tryCatch(mx.client::mx_room_encrypted(mx, rid),
                            error = function(e) FALSE))) {
            out <- c(out, rid)
        }
    }
    out
}

# One room id per line, not JSON: chat.api has no dependencies and a
# character vector does not need a parser. corteza wrote
# encrypted_rooms.json here; the name differs so a leftover file is
# ignored rather than read as room ids. Nothing is lost by ignoring it --
# the room set is a cache, and matrix_crypto_scan_rooms() rebuilds it at
# init from the homeserver's own state.
matrix_crypto_room_file <- function(store) {
    file.path(store, "encrypted_rooms.txt")
}

matrix_crypto_load_encrypted <- function(store) {
    f <- matrix_crypto_room_file(store)
    if (!file.exists(f)) {
        return(character())
    }
    rooms <- readLines(f, warn = FALSE)
    unique(rooms[nzchar(rooms)])
}

matrix_crypto_save_encrypted <- function(crypto) {
    dir.create(crypto$store, showWarnings = FALSE, recursive = TRUE)
    writeLines(crypto$encrypted, matrix_crypto_room_file(crypto$store))
}

# Rooms advertising m.room.encryption in this sync (state or timeline).
matrix_detect_encrypted_rooms <- function(sync) {
    out <- character()
    joined <- sync$rooms$join %||% list()
    for (rid in names(joined)) {
        evs <- c(joined[[rid]]$state$events %||% list(),
                 joined[[rid]]$timeline$events %||% list())
        for (ev in evs) {
            if (isTRUE(ev$type == "m.room.encryption")) {
                out <- c(out, rid)
                break
            }
        }
    }
    out
}

# Decrypt a sync: recover room keys from to-device, decrypt encrypted
# timeline events, refresh the encrypted-room set. Mutates `crypto`.
#
# `devices` is the verified device list for the senders in this sync.
# mx.client only reports sender_verified = TRUE when a payload's claimed
# (sender, ed25519, curve25519) binds to a device whose device_keys
# verified, so without this every decrypted message would come back
# unattributed. Fetching it is a /keys/query round trip, so it is skipped
# when the sync carries no encrypted traffic.
matrix_crypto_decrypt <- function(crypto, sync, mx) {
    fresh <- setdiff(matrix_detect_encrypted_rooms(sync), crypto$encrypted)
    if (length(fresh)) {
        crypto$encrypted <- c(crypto$encrypted, fresh)
        matrix_crypto_save_encrypted(crypto)
    }
    senders <- matrix_encrypted_senders(sync)
    devices <- if (length(senders)) {
        tryCatch(mx.client::mx_crypto_known_devices(mx, senders),
                 error = function(e) NULL)
    } else {
        NULL
    }

    res <- mx.client::mx_crypto_process_sync(
        crypto$account, crypto$sessions, sync, crypto$self_curve,
        self_id = mx$user_id, devices = devices)
    crypto$sessions <- res$sessions
    mx.client::mx_crypto_sessions_save(crypto$sessions, crypto$store)
    res$events
}

# Distinct senders the device query has to cover, so it asks about the
# people who actually spoke rather than every room member.
#
# Both halves matter, and the to-device half is the one that is easy to
# miss. sender_bound is stamped once, when a room key arrives over
# to-device, and it is persisted with the Megolm session; a later sync
# that finally carries a timeline message from that sender does not rebind
# it. A room key that arrives in a to-device-only sync -- which is the
# normal case, since the key is shared before the message -- would
# therefore be recorded unverified forever, and every message decrypted
# with it would report sender_verified = FALSE.
matrix_encrypted_senders <- function(sync) {
    out <- character()
    for (room in sync$rooms$join %||% list()) {
        for (ev in room$timeline$events %||% list()) {
            if (isTRUE(ev$type == "m.room.encrypted") && !is.null(ev$sender)) {
                out <- c(out, ev$sender)
            }
        }
    }
    for (ev in sync$to_device$events %||% list()) {
        if (isTRUE(ev$type == "m.room.encrypted") && !is.null(ev$sender)) {
            out <- c(out, ev$sender)
        }
    }
    unique(out)
}

# Is this room one the adapter knows to be encrypted?
#
# Fails closed. A room not already known encrypted is asked about, so one
# that turned encryption on between polls does not get a cleartext send --
# and if that question cannot be answered, the caller gets an error rather
# than FALSE. An expired token, a timeout, or a 500 all used to come back
# as "not encrypted", which sent the message in the clear: on an E2EE
# client, unknown is not the same answer as unencrypted.
matrix_room_is_encrypted <- function(crypto, mx, room_id) {
    if (is.null(crypto)) {
        return(FALSE)
    }
    if (room_id %in% crypto$encrypted) {
        return(TRUE)
    }
    enc <- withCallingHandlers(
                               tryCatch(mx.client::mx_room_encrypted(mx, room_id),
                                        error = function(e) {
        stop("chat.api: cannot determine the encryption state of ", room_id,
             ": ", conditionMessage(e),
             ". Refusing to send, because an unanswered question is ",
             "not a plaintext room.", call. = FALSE)
    }), warning = function(w) invokeRestart("muffleWarning"))
    if (isTRUE(enc)) {
        crypto$encrypted <- c(crypto$encrypted, room_id)
        matrix_crypto_save_encrypted(crypto)
    }
    isTRUE(enc)
}

# The m.room.message content an encrypted send wraps. Deliberately the
# same shape mx_send_text() PUTs in the clear -- markdown becomes
# formatted_body, mentions become pills plus m.mentions -- so a room's
# encryption state changes the envelope and nothing a reader sees.
matrix_crypto_content <- function(text, msgtype = "m.text", markdown = FALSE,
                                  mentions = NULL) {
    content <- list(msgtype = msgtype, body = text)
    if (isTRUE(markdown) || length(mentions)) {
        html <- mx.client::mx_markdown_to_html(text)
        if (length(mentions)) {
            html <- mx.client::mx_pill_mentions(html, mentions)
        }
        content$format <- "org.matrix.custom.html"
        content$formatted_body <- html
    }
    if (length(mentions)) {
        content[["m.mentions"]] <- list(user_ids = as.list(mentions))
    }
    content
}

# Encrypt and send. Errors propagate, the same way the cleartext path's do
# -- a caller that wants "no event id" on failure wraps the call, and one
# that does not should hear about it.
#
# Membership discovery is not best-effort. mx_send_encrypted() derives the
# recipient devices from member_ids, so an empty list means it shares the
# room key with nobody, posts the m.room.encrypted event anyway, and
# returns an event id. On a fresh outbound session nobody in the room can
# read that message, while the caller records a successful send. Swallowing
# the lookup error bought exactly that outcome, so it is gone: skipping
# individual devices that cannot be verified is mx.client's decision to
# make, and it is a different one.
matrix_crypto_send <- function(crypto, mx, room_id, text, msgtype = "m.text",
                               markdown = FALSE, mentions = NULL) {
    members <- mx.api::mx_room_members(mx.client::mx_client_session(mx),
                                       room_id)
    if (!length(members)) {
        stop("chat.api: no members found for ", room_id,
             ". Refusing to send an encrypted event whose room key would ",
             "reach nobody.", call. = FALSE)
    }
    content <- matrix_crypto_content(text, msgtype = msgtype,
                                     markdown = markdown, mentions = mentions)
    res <- mx.client::mx_send_encrypted(mx, crypto$account, crypto$sessions,
                                        room_id, content, crypto$store,
                                        member_ids = members)
    crypto$sessions <- res$sessions
    res$event_id
}
