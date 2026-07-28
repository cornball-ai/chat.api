#' @title Matrix adapter
#' @description chat.api methods for Matrix, delegating to the suggested
#'   mx.client package.

#' Create a Matrix chat client
#'
#' Wraps an \code{mx.client} client config (see
#' \code{mx.client::mx_client_load()}). The sync cursor lives inside the
#' mx.client config; with \code{save_cursor = TRUE} every poll persists
#' it, so a restarted process resumes where it left off.
#'
#' @param app Application namespace passed to
#'   \code{mx.client::mx_client_load()}, defaulting to "chat.api" for the
#'   load. NULL (the default) is also what gets forwarded to
#'   \code{mx_sync_update()}, which leaves the wrapped config's own
#'   \code{app}/\code{path} attributes in charge of where the cursor is
#'   persisted. Naming an app here overrides them, so only name one when
#'   this adapter owns the config file.
#' @param path Explicit config path, or NULL for the app default.
#' @param save_cursor Logical. Persist the sync token after each poll,
#'   through mx.client, into the config file the wrapped client points
#'   at. Pass FALSE only if you persist \code{chat_poll()}'s
#'   \code{cursor} yourself; nothing else writes it, so a FALSE that
#'   isn't paired with a save makes every restart replay history from a
#'   frozen token.
#' @param mx A ready mx.client client config to wrap, for consumers
#'   that already load and manage one; NULL (default) loads via
#'   \code{app}/\code{path}.
#' @param relogin Logical. Wrap each sync in
#'   \code{mx.client::mx_with_relogin()}, which catches an invalidated
#'   access token, re-logs in with the stored password on the same
#'   device_id (so an E2EE identity survives), and retries once. The
#'   refreshed config lands back in the client, so the next poll and any
#'   send use the new token. FALSE lets \code{mx_error_M_UNKNOWN_TOKEN}
#'   propagate.
#' @param .sync Testing seam: replacement for
#'   \code{mx.client::mx_sync_update}. Leave NULL in production.
#' @param .extract Testing seam: replacement for
#'   \code{mx.client::mx_extract_text_events}. Leave NULL in production.
#' @param .send Testing seam: replacement for
#'   \code{mx.client::mx_send_text}. Leave NULL in production.
#' @param .media Testing seam: replacement for
#'   \code{mx.client::mx_send_media}. Leave NULL in production. Supplying
#'   all four seams together with \code{mx} lets poll and send run
#'   without mx.client installed; \code{chat_typing()} and
#'   \code{chat_resolve()} still require it.
#' @param .typing Testing seam: replacement for
#'   \code{mx.api::mx_typing}. Leave NULL in production. It is resolved
#'   when \code{chat_typing()} is called, not here, so a NULL seam costs
#'   nothing on installs without mx.api.
#' @return A \code{chat_client} of class \code{chat_matrix}.
#'   \code{\link{chat_poll}} on this class returns \code{first_run} and
#'   \code{client} alongside \code{messages}, \code{cursor}, and
#'   \code{raw}. \code{first_run} is TRUE when the sync started from no
#'   cursor, so the messages are a backfill baseline rather than new
#'   traffic. \code{client} is the post-sync mx.client config, which a
#'   consumer needs whenever it drives mx.api directly (read receipts,
#'   member lookups) because a relogin may have replaced the token this
#'   poll cycle.
#' @export
chat_matrix <- function(app = NULL, path = NULL, save_cursor = TRUE,
                        mx = NULL, relogin = TRUE, .sync = NULL,
                        .extract = NULL, .send = NULL, .media = NULL,
                        .typing = NULL) {
    seams <- list(.sync, .extract, .send, .media)
    if ((is.null(mx) || any(vapply(seams, is.null, logical(1)))) &&
        !requireNamespace("mx.client", quietly = TRUE)) {
        stop("chat_matrix() requires the 'mx.client' package. ",
             "Install it first.", call. = FALSE)
    }
    if (is.null(mx)) {
        load_app <- app %||% "chat.api"
        mx <- if (is.null(path)) {
            mx.client::mx_client_load(app = load_app)
        } else {
            mx.client::mx_client_load(app = load_app, path = path)
        }
    }
    env <- new.env(parent = emptyenv())
    env$mx <- mx
    structure(list(env = env, app = app, save_cursor = isTRUE(save_cursor),
                   relogin = isTRUE(relogin),
                   sync_fn = .sync %||% mx.client::mx_sync_update,
                   extract_fn = .extract %||% mx.client::mx_extract_text_events,
                   send_fn = .send %||% mx.client::mx_send_text,
                   media_fn = .media %||% mx.client::mx_send_media,
                   typing_fn = .typing),
              class = c("chat_matrix", "chat_client"))
}

# origin_server_ts for every joined-room timeline event, keyed by event
# id. mx_extract_text_events only started carrying ts in mx.client
# 0.1.1.1's development sources, and builds on either side of that
# change share a version string, so the adapter cannot tell from the
# version whether the record will have one. Reading it off the sync the
# extractor was handed makes the timestamp right on both builds. This is
# a keyed lookup, not a second extractor: it does no msgtype filtering
# and takes whatever event ids the extractor decided to return.
matrix_event_times <- function(sync) {
    joined <- sync$rooms$join
    out <- list()
    for (room in joined) {
        for (ev in room$timeline$events) {
            if (!is.null(ev$event_id) && !is.null(ev$origin_server_ts)) {
                out[[as.character(ev$event_id)]] <- ev$origin_server_ts
            }
        }
    }
    out
}

# Matrix msgtype -> the contract's kind vocabulary. chat_send maps the
# same pair in the other direction, so a message that makes a round trip
# keeps its kind. Leaving m.text on the record would make every Matrix
# message fail a cross-adapter `kind == "message"` filter that Slack,
# IRC, and loopback traffic passes.
matrix_kind <- function(msgtype) {
    switch(msgtype %||% "m.text",
           m.notice = "notice",
           m.emote = "emote",
           "message")
}

# chat_poll's `...` reaches mx_sync_update, so a caller can pass a
# server-side `filter` or an explicit `path`. chat_send's reaches
# mx_send_text, whose `mentions` argument is the only way to emit an
# m.mentions user_ids list -- the field modern clients key their push
# rules off, so without it a bot's reply never highlights anyone.
#' @export
chat_poll.chat_matrix <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since)) {
        client$env$mx$sync_token <- since
    }
    do_sync <- function(mx) {
        client$sync_fn(mx, timeout = as.integer((timeout %||% 0) * 1000),
                       save = client$save_cursor, app = client$app, ...)
    }
    # The relogin wrapper hands the retry a re-authenticated config, so
    # the sync has to run off whatever config it is given rather than
    # reaching back into client$env$mx. Wiring it the other way round
    # retries with the token the homeserver just rejected and the second
    # rejection escapes the handler that would have caught it.
    res <- if (client$relogin && requireNamespace("mx.client", quietly = TRUE)) {
        mx.client::mx_with_relogin(client$env$mx, do_sync)
    } else {
        do_sync(client$env$mx)
    }
    client$env$mx <- res$client

    event_ts <- matrix_event_times(res$sync)
    recs <- client$extract_fn(res$sync, self_id = res$client$user_id)
    messages <- lapply(recs, function(r) {
        # ts is the event's own origin_server_ts, from the record when
        # the extractor carries one and from the sync when it does not.
        # An unknown time stays NA: stamping Sys.time() would make a
        # restart's backfill look like it all arrived at once, and no
        # consumer sorting or windowing by ts could tell.
        ms <- r$ts %||% event_ts[[as.character(r$event_id)]]
        ts <- if (is.null(ms)) {
            as.POSIXct(NA)
        } else {
            as.POSIXct(ms / 1000, origin = "1970-01-01")
        }
        chat_message(id = as.character(r$event_id),
                     channel = as.character(r$room_id),
                     sender = as.character(r$sender),
                     body = as.character(r$body), ts = ts,
                     markup = "plain", kind = matrix_kind(r$msgtype),
                     self = isTRUE(r$is_self),
                     mentions = unlist(r$mentions, use.names = FALSE),
                     raw = r)
    })
    # first_run says the sync ran without a stored cursor, so these
    # messages are the homeserver's backfill baseline, not new traffic.
    # A consumer that drops it replays its whole history as fresh mail
    # every restart, so it has to survive the trip out of the adapter.
    #
    # client is the post-sync config. A relogin can have replaced the
    # token mid-poll, and a consumer that keeps driving mx.api off its
    # own pre-poll copy would spend the rest of the cycle authenticating
    # with the token the homeserver just rejected.
    #
    # raw carries the full sync response for Matrix-specific consumers
    # (invites, reactions, E2EE decryption) that the generic contract
    # does not model yet
    list(messages = messages, cursor = res$client$sync_token,
         first_run = isTRUE(res$first_run), client = res$client,
         raw = res$sync)
}

#' @export
chat_send.chat_matrix <- function(client, channel, text,
                                  markup = c("plain", "markdown"),
                                  thread = NULL, reply_to = NULL,
                                  identity = NULL, files = NULL,
                                  kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    media_ids <- character()
    if (!is.null(files)) {
        for (f in files) {
            media_ids <- c(media_ids,
                           as.character(client$media_fn(client$env$mx, f,
                                                        room = channel)))
        }
    }
    msgtype <- if (identical(kind, "notice")) {
        "m.notice"
    } else if (identical(kind, "emote")) {
        "m.emote"
    } else {
        "m.text"
    }
    # An attachment-only send is the uploads and nothing else. Matrix
    # accepts an empty body and clients render it as a blank bubble, so
    # posting one after every file leaves visible litter in the room.
    # With no text event to name, the media event ids are what comes
    # back; otherwise the caller has nothing to redact or react to.
    if (!length(media_ids) || any(nzchar(text))) {
        return(invisible(as.character(client$send_fn(client$env$mx, text,
            room = channel, msgtype = msgtype,
            markdown = identical(markup, "markdown"), ...))))
    }
    invisible(media_ids)
}

#' @param timeout Seconds the typing indicator should stand before the
#'   homeserver clears it, for \code{on = TRUE}. Seconds, not
#'   milliseconds: \code{chat_poll()} takes seconds too, and the adapter
#'   converts at the mx.api boundary. A caller running a slow model
#'   turn wants a long one (say 120) and an explicit
#'   \code{on = FALSE} when the turn ends.
#' @rdname chat_typing
#' @export
chat_typing.chat_matrix <- function(client, channel, on = TRUE, timeout = 30,
                                    ...) {
    ok <- tryCatch({
        # mx.api wants a session, not the client config
        sess <- mx.client::mx_client_session(client$env$mx)
        typing_fn <- client$typing_fn %||% mx.api::mx_typing
        typing_fn(sess, channel, typing = isTRUE(on),
                  timeout = as.integer((timeout %||% 30) * 1000))
        TRUE
    }, error = function(e) FALSE)
    invisible(ok)
}

#' @export
chat_resolve.chat_matrix <- function(client, name, ...) {
    mx.client::mx_resolve_room(client$env$mx, name)
}

#' @export
chat_capabilities.chat_matrix <- function(client, ...) {
    # thread_replies is FALSE because chat_poll cannot populate
    # chat_message$thread. Its only event source is
    # mx.client::mx_extract_text_events(), which returns room_id,
    # event_id, sender, is_self, body, msgtype, and mentions -- it drops
    # content$m.relates_to, so the relation never reaches this adapter.
    # Re-walking the raw sync behind the extractor would duplicate its
    # msgtype filtering and quietly break for anyone supplying .extract.
    # Mapping m.in_reply_to into $thread would be worse: chat_message
    # has no reply_to slot, so plain rich replies would report as
    # threads. Flip this to TRUE when mx.client surfaces relations and
    # chat_poll maps a real m.thread rel_type.
    #
    # Every flag here answers "can this adapter do it", not "can Matrix
    # do it". Matrix has reactions and E2EE; this adapter reaches
    # neither, and a mixed list is worse than a conservative one because
    # a consumer cannot tell which reading a given flag was written
    # under.
    #
    # reactions is FALSE because chat.api has no reaction verb to call
    # and mx_extract_text_events filters to m.text, so an m.reaction can
    # be neither sent nor received here.
    #
    # e2ee is FALSE because chat_send goes through mx_send_text, which
    # PUTs a cleartext m.room.message no matter what the room's
    # encryption state says, and chat_poll never sees an
    # m.room.encrypted event. Reporting TRUE off an installed mx.crypto
    # invites a consumer to hand this adapter a secret for an encrypted
    # room and have it land on the homeserver in the clear. Flip it when
    # the adapter routes through mx_send_encrypted and decrypts inbound.
    list(threads = FALSE, thread_replies = FALSE, edits = FALSE,
         reactions = FALSE, files = TRUE, typing = TRUE, e2ee = FALSE,
         identity_override = FALSE, markup_dialects = c("plain", "markdown"),
         max_message_bytes = NA_integer_)
}

`%||%` <- function(a, b) {
    if (is.null(a)) {
        b
    } else {
        a
    }
}
