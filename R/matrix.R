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
#' @param e2ee Logical. Own Olm/Megolm state in the adapter, so
#'   \code{\link{chat_send}} encrypts for rooms that advertise
#'   \code{m.room.encryption} and \code{\link{chat_poll}} decrypts
#'   inbound. FALSE (the default) is the previous behaviour exactly:
#'   cleartext only, no crypto state, and \code{e2ee} stays FALSE in
#'   \code{\link{chat_capabilities}}. Requires the 'mx.crypto' package,
#'   which needs a Rust toolchain.
#' @param crypto_store Character or NULL. Directory holding the pickled
#'   Olm account and sessions. NULL derives it from \code{app} via
#'   \code{mx.client::mx_crypto_store_dir()}, which keys one store per
#'   app namespace regardless of where the config file lives, so moving a
#'   config does not cost the device identity. Because that key is the app
#'   name alone, an \code{e2ee = TRUE} client built from an explicit
#'   \code{path} with no \code{app} is an error: name one or the other, or
#'   two such clients would quietly share a device identity.
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
#' @param .crypto Testing seam: a named list overriding any of the
#'   adapter's four crypto operations -- \code{init}, \code{encrypted},
#'   \code{send}, \code{decrypt}. Leave NULL in production. Supplying
#'   \code{init} is what lets \code{e2ee = TRUE} be tested on a runner
#'   with neither mx.crypto nor a Rust toolchain; E2EE is the one part of
#'   this adapter with no honest way to reach a real homeserver from a
#'   test.
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
                        mx = NULL, relogin = TRUE, e2ee = FALSE,
                        crypto_store = NULL, .sync = NULL, .extract = NULL,
                        .send = NULL, .media = NULL, .typing = NULL,
                        .crypto = NULL) {
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
    # Crypto state lives on the same env as the client, so a consumer
    # holds one object and never touches Olm or Megolm itself. NULL when
    # e2ee is off, which is the default and is exactly the pre-existing
    # behaviour.
    env$crypto <- NULL
    ops <- matrix_crypto_ops(.crypto)
    if (isTRUE(e2ee)) {
        # An explicit config path with no app names one specific identity,
        # but the default store is keyed on the app namespace alone, so
        # two bots loaded that way would share one account.pickle and the
        # second would come up wearing the first's device keys. Deriving
        # the store from the config's own directory instead only trades
        # that for a quieter failure: move the config and the bot mints a
        # new identity and loses every Megolm session it had. So ask.
        if (is.null(crypto_store) && !is.null(path) && is.null(app)) {
            stop("chat_matrix(e2ee = TRUE) with an explicit `path` needs ",
                 "`app` or `crypto_store` too, so the crypto store is ",
                 "unique to this identity.", call. = FALSE)
        }
        # Interned per identity: rebuilding a client for the same bot
        # reuses its one Olm account instead of loading a second and
        # republishing its keys. A consumer that derives a fresh client
        # per use, so the rotating access token is never cached, still
        # keeps one crypto identity across the whole run.
        env$crypto <- matrix_crypto_context(
            matrix_crypto_cache_key(crypto_store, app),
            function() ops$init(mx, store = crypto_store, app = app))
    }
    structure(list(env = env, app = app, save_cursor = isTRUE(save_cursor),
                   relogin = isTRUE(relogin), e2ee = isTRUE(e2ee),
                   sync_fn = .sync %||% mx.client::mx_sync_update,
                   extract_fn = .extract %||% mx.client::mx_extract_text_events,
                   send_fn = .send %||% mx.client::mx_send_text,
                   media_fn = .media %||% mx.client::mx_send_media,
                   typing_fn = .typing, crypto_ops = ops),
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
    switch(msgtype %||% "m.text", m.notice = "notice", m.emote = "emote",
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
    res <- if (client$relogin &&
        requireNamespace("mx.client", quietly = TRUE)) {
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
    # Decrypted traffic folds in alongside the cleartext, in the same
    # chat_message shape, so a consumer cannot tell which arrived
    # encrypted except by reading $encrypted. That is the whole point of
    # owning crypto here: corteza used to run its own decrypt off $raw and
    # concatenate the results itself.
    if (!is.null(client$env$crypto)) {
        dec <- tryCatch(
                        client$crypto_ops$decrypt(client$env$crypto, res$sync,
                client$env$mx),
                        error = function(e) {
            warning("chat.api: decrypt failed: ", conditionMessage(e),
                    call. = FALSE)
            list()
        })
        for (d in dec) {
            ms <- d$ts %||% event_ts[[as.character(d$event_id)]]
            messages[[length(messages) + 1L]] <- chat_message(
                id = as.character(d$event_id),
                channel = as.character(d$room_id),
                sender = as.character(d$sender),
                body = as.character(d$body),
                ts = if (is.null(ms)) as.POSIXct(NA) else
                as.POSIXct(ms / 1000, origin = "1970-01-01"),
                markup = "plain", kind = matrix_kind(d$msgtype),
                self = isTRUE(d$is_self),
                mentions = unlist(d$mentions, use.names = FALSE),
                encrypted = TRUE,
                sender_verified = isTRUE(d$sender_verified),
                raw = d)
        }
    }
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
    # (invites, reactions) that the generic contract does not model yet.
    # E2EE no longer needs it.
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
            event <- client$media_fn(client$env$mx, f, room = channel)
            media_ids <- c(media_ids, as.character(event))
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
    #
    # Every event this call created comes back, media first, in the order
    # they were sent. A caller that only sees the text event treats each
    # attachment's echo as somebody else's message: corteza recognizes
    # its own traffic by event id.
    if (!length(media_ids) || any(nzchar(text))) {
        crypto <- client$env$crypto
        # Encrypted rooms take the Megolm path. Asked per send rather than
        # trusting the cached room set, so a room that turned on
        # encryption between polls does not get one cleartext message
        # first.
        #
        # markup and mentions carry through: the encrypted branch builds
        # the same m.room.message content the cleartext one does, so a
        # markdown send renders the same either way. Only the envelope
        # differs.
        if (!is.null(crypto) &&
            client$crypto_ops$encrypted(crypto, client$env$mx, channel)) {
            event <- client$crypto_ops$send(crypto, client$env$mx, channel,
                text, msgtype = msgtype,
                markdown = identical(markup, "markdown"),
                mentions = list(...)$mentions)
            return(invisible(c(media_ids, as.character(event))))
        }
        event <- client$send_fn(client$env$mx, text, room = channel,
                                msgtype = msgtype,
                                markdown = identical(markup, "markdown"), ...)
        return(invisible(c(media_ids, as.character(event))))
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
    # e2ee answers for this client, not for Matrix and not for the
    # installed packages: it is TRUE only when chat_matrix(e2ee = TRUE)
    # built a crypto context, which is what actually routes sends through
    # mx_send_encrypted and decrypts inbound. Reporting TRUE off an
    # installed mx.crypto would invite a consumer to hand a secret to a
    # client that PUTs it on the homeserver in the clear.
    list(threads = FALSE, thread_replies = FALSE, edits = FALSE,
         reactions = FALSE, files = TRUE, typing = TRUE,
         e2ee = !is.null(client$env$crypto), identity_override = FALSE,
         markup_dialects = c("plain", "markdown"),
         max_message_bytes = NA_integer_)
}

`%||%` <- function(a, b) {
    if (is.null(a)) {
        b
    } else {
        a
    }
}
