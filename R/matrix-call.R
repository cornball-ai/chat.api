# MatrixRTC calls on the Matrix adapter: the signaling side of a call,
# advanced from chat_poll().
#
# mx.client does the protocol (mx_call_join / mx_call_handle /
# mx_call_leave: membership state, the token service, per-member media
# keys over Olm). What this file adds is the adapter's ownership of
# the pieces those need and would otherwise be copied out of it:
#
# - the live credentials. A call lives across relogins, so the mx_call
#   is handed client$env$mx again before every operation, never a copy
#   taken at join time (the derive-at-use rule that applies to every
#   credential in this adapter).
# - the Olm sessions. Sending a key opens Olm sessions with the other
#   members' devices; those sessions have to come back into the
#   adapter's crypto state, or the adapter's next save writes an older
#   set over them and the peers' later to-device traffic cannot be
#   decrypted. The call is given the adapter's sessions before each
#   operation and the adapter adopts them after.
# - the decrypted to-device events. The adapter decrypts the sync
#   once, in matrix_crypto_decrypt(); the call reads the result rather
#   than decrypting the same sync again (which would advance the Olm
#   ratchets twice).
#
# The media itself never comes here. A caller opens the media server
# leg where it wants (corteza: in a worker process) from what
# chat_call_media() hands it, and feeds it what chat_call_updates()
# reports after each poll.

.MATRIX_CALLS_MIN <- "0.2.1.1"

matrix_calls_available <- function(ops = NULL) {
    if (!is.null(ops)) {
        return(TRUE)
    }
    requireNamespace("mx.client", quietly = TRUE) &&
    utils::packageVersion("mx.client") >= .MATRIX_CALLS_MIN
}

# The three mx.client verbs, resolved at the point of use so the
# package is only loaded when a call is made; a test supplies fakes.
matrix_call_ops <- function(override = NULL) {
    ops <- list(join = function(...) mx.client::mx_call_join(...),
                handle = function(...) mx.client::mx_call_handle(...),
                leave = function(...) mx.client::mx_call_leave(...))
    for (nm in names(override)) {
        ops[[nm]] <- override[[nm]]
    }
    ops
}

#' @export
chat_call_join.chat_matrix <- function(client, channel, intent = "voice",
                                       service_url = NULL, ...) {
    if (!isTRUE(client$e2ee)) {
        stop("chat_call_join() needs a client built with e2ee = TRUE: a ",
             "call's media keys travel over Olm", call. = FALSE)
    }
    if (!matrix_calls_available(client$call_override)) {
        stop("chat_call_join() needs mx.client >= ", .MATRIX_CALLS_MIN,
             call. = FALSE)
    }
    # The calls live on the identity's crypto context, not on this
    # client object: a consumer that builds a client per poll (corteza
    # does) keeps its calls, since the context is interned per identity
    # and store. The keys a call holds are in that context's Olm
    # sessions anyway.
    crypto <- matrix_crypto_require(client)
    if (!is.null(crypto$calls[[channel]]) &&
        !isTRUE(crypto$calls[[channel]]$changes$ended)) {
        stop("already in the call in ", channel, "; chat_call_leave() it first",
             call. = FALSE)
    }
    mx_call <- client$call_ops$join(client$env$mx, crypto$account,
                                    crypto$sessions, channel, intent = intent,
                                    store_dir = crypto$store, connect = FALSE,
                                    service_url = service_url)
    matrix_call_adopt_sessions(crypto, mx_call)
    call <- new.env(parent = emptyenv())
    call$channel <- channel
    call$identity <- mx_call$identity
    call$mx <- mx_call
    call$changes <- list(keys = list(), own = NULL, members = NULL,
                         ended = FALSE)
    call$media <- function() {
        list(url = mx_call$token$url, jwt = mx_call$token$jwt,
             identity = mx_call$identity,
             key = list(key = mx_call$keys$key, index = mx_call$keys$index))
    }
    call$peers <- function() {
        lapply(names(mx_call$keys$peers), function(id) {
            p <- mx_call$keys$peers[[id]]
            list(identity = id, key = p$key, index = p$index)
        })
    }
    class(call) <- "chat_call"
    if (is.null(crypto$calls)) {
        crypto$calls <- list()
    }
    crypto$calls[[channel]] <- call
    call
}

#' @export
chat_call_leave.chat_matrix <- function(client, call, ...) {
    stopifnot(inherits(call, "chat_call"))
    if (isTRUE(call$changes$ended)) {
        return(invisible(call))
    }
    call$mx$client <- client$env$mx
    client$call_ops$leave(call$mx)
    call$changes$ended <- TRUE
    crypto <- matrix_crypto_require(client)
    if (!is.null(crypto)) {
        crypto$calls[[call$channel]] <- NULL
    }
    invisible(call)
}

# The call-membership events this sync carries, as notices: for each
# room where someone other than this client announced or withdrew a
# call membership, who is in (by mx.client's reading of the events:
# non-empty content, a LiveKit focus, not expired) and who left (an
# empty membership). A notice says the room's call changed; the room's
# full membership is the call's own business once joined
# (chat_call_updates()). Nothing without mx.client's call API.
matrix_call_notices <- function(client, sync) {
    if (!matrix_calls_available(client$call_override)) {
        return(list())
    }
    self <- client$env$mx$user_id
    out <- list()
    for (room_id in names(sync$rooms$join)) {
        room <- sync$rooms$join[[room_id]]
        evs <- c(room$state$events %||% list(), room$timeline$events %||% list())
        evs <- Filter(function(ev) {
            identical(ev$type, .MATRIX_CALL_MEMBER) &&
                is.character(ev$sender) && !identical(ev$sender, self)
        }, evs)
        if (!length(evs)) {
            next
        }
        members <- vapply(mx.client::mx_call_members(evs), function(m) m$identity, "")
        left <- unique(unlist(lapply(evs, function(ev) {
            if (!length(ev$content)) ev$sender
        })))
        out[[length(out) + 1L]] <- structure(
            list(channel = room_id, members = unique(members),
                 left = as.character(left %||% character())),
            class = "chat_call_notice")
    }
    out
}

# The membership state event's type (MSC3401; the per-device form both
# Element Call and FluffyChat write in 2026).
.MATRIX_CALL_MEMBER <- "org.matrix.msc3401.call.member"

# Advance every live call with this poll's sync. Runs after the sync
# is decrypted and consumed; a failure here is reported, not thrown,
# since throwing would lose the poll's messages for a sync the cursor
# has already moved past, and the next poll retries what a call needs
# (membership and keys are re-read from room state and resent).
matrix_calls_sync <- function(client, sync, crypto) {
    if (is.null(crypto)) {
        return(invisible(NULL))
    }
    calls <- crypto$calls
    if (!length(calls)) {
        crypto$to_device <- NULL
        return(invisible(NULL))
    }
    processed <- list(to_device = crypto$to_device %||% list(),
                      events = crypto$decrypted %||% list())
    crypto$to_device <- NULL
    crypto$decrypted <- NULL
    traffic <- crypto$call_traffic
    crypto$call_traffic <- NULL
    if (!is.null(traffic) &&
        (length(traffic$raw) || length(traffic$decrypted) || traffic$room_keys > 0L)) {
        message("chat.api call: to-device raw [",
                paste(traffic$raw, collapse = ", "), "] decrypted [",
                paste(traffic$decrypted, collapse = ", "), "]",
                if (traffic$room_keys > 0L) {
                    paste0("; ", traffic$room_keys, " call key event(s) in a room ",
                           "timeline, which the call does not read")
                })
    }
    for (channel in names(calls)) {
        call <- calls[[channel]]
        if (isTRUE(call$changes$ended)) {
            next
        }
        mx_call <- call$mx
        mx_call$client <- client$env$mx
        mx_call$sessions <- crypto$sessions
        own_before <- list(key = mx_call$keys$key, index = mx_call$keys$index)
        res <- tryCatch(client$call_ops$handle(mx_call, sync,
                processed = processed),
                        error = function(e) {
            warning("chat.api: the call in ", channel, " could not be advanced: ",
                    conditionMessage(e), call. = FALSE)
            NULL
        })
        matrix_call_adopt_sessions(crypto, mx_call)
        if (is.null(res)) {
            next
        }
        for (id in res$keys) {
            p <- mx_call$keys$peers[[id]]
            if (!is.null(p)) {
                call$changes$keys[[length(call$changes$keys) + 1L]] <-
                list(identity = id, key = p$key, index = p$index)
            }
        }
        if (!identical(own_before$key, mx_call$keys$key) ||
            !identical(own_before$index, mx_call$keys$index)) {
            call$changes$own <- list(key = mx_call$keys$key,
                                     index = mx_call$keys$index)
        }
        if (!is.null(res$members)) {
            call$changes$members <- vapply(res$members, function(m) m$identity, "")
        }
    }
    invisible(NULL)
}

# The Olm sessions a call operation left behind are the adapter's now.
matrix_call_adopt_sessions <- function(crypto, mx_call) {
    if (!is.null(mx_call$sessions)) {
        crypto$sessions <- mx_call$sessions
    }
    invisible(NULL)
}
