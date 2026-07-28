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
#'   \code{mx.client::mx_client_load()}.
#' @param path Explicit config path, or NULL for the app default.
#' @param save_cursor Logical. Persist the sync token after each poll.
#'   Consumers that manage their own config (corteza) pass FALSE and
#'   persist the returned cursor themselves.
#' @param mx A ready mx.client client config to wrap, for consumers
#'   that already load and manage one; NULL (default) loads via
#'   \code{app}/\code{path}.
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
#'   \code{\link{chat_poll}} on this class returns \code{first_run}
#'   alongside \code{messages}, \code{cursor}, and \code{raw}: TRUE when
#'   the sync started from no cursor, so the messages are a backfill
#'   baseline rather than new traffic.
#' @export
chat_matrix <- function(app = "chat.api", path = NULL, save_cursor = TRUE,
                        mx = NULL, .sync = NULL, .extract = NULL,
                        .send = NULL, .media = NULL, .typing = NULL) {
    seams <- list(.sync, .extract, .send, .media)
    if ((is.null(mx) || any(vapply(seams, is.null, logical(1)))) &&
        !requireNamespace("mx.client", quietly = TRUE)) {
        stop("chat_matrix() requires the 'mx.client' package. ",
             "Install it first.", call. = FALSE)
    }
    if (is.null(mx)) {
        mx <- if (is.null(path)) {
            mx.client::mx_client_load(app = app)
        } else {
            mx.client::mx_client_load(app = app, path = path)
        }
    }
    env <- new.env(parent = emptyenv())
    env$mx <- mx
    structure(list(env = env, app = app, save_cursor = isTRUE(save_cursor),
                   sync_fn = .sync %||% mx.client::mx_sync_update,
                   extract_fn = .extract %||% mx.client::mx_extract_text_events,
                   send_fn = .send %||% mx.client::mx_send_text,
                   media_fn = .media %||% mx.client::mx_send_media,
                   typing_fn = .typing),
              class = c("chat_matrix", "chat_client"))
}

#' @export
chat_poll.chat_matrix <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since)) {
        client$env$mx$sync_token <- since
    }
    res <- client$sync_fn(client$env$mx,
                          timeout = as.integer((timeout %||% 0) * 1000),
                          save = client$save_cursor,
                          app = client$app)
    client$env$mx <- res$client

    recs <- client$extract_fn(res$sync, self_id = res$client$user_id)
    messages <- lapply(recs, function(r) {
        ts <- if (is.null(r$ts)) {
            Sys.time()
        } else {
            as.POSIXct(r$ts / 1000, origin = "1970-01-01")
        }
        chat_message(id = as.character(r$event_id),
                     channel = as.character(r$room_id),
                     sender = as.character(r$sender),
                     body = as.character(r$body), ts = ts,
                     markup = "plain", kind = r$msgtype %||% "message",
                     raw = r)
    })
    # first_run says the sync ran without a stored cursor, so these
    # messages are the homeserver's backfill baseline, not new traffic.
    # A consumer that drops it replays its whole history as fresh mail
    # every restart, so it has to survive the trip out of the adapter.
    #
    # raw carries the full sync response for Matrix-specific consumers
    # (invites, reactions, E2EE decryption) that the generic contract
    # does not model yet
    list(messages = messages, cursor = res$client$sync_token,
         first_run = isTRUE(res$first_run), raw = res$sync)
}

#' @export
chat_send.chat_matrix <- function(client, channel, text,
                                  markup = c("plain", "markdown"),
                                  thread = NULL, reply_to = NULL,
                                  identity = NULL, files = NULL,
                                  kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    if (!is.null(files)) {
        for (f in files) {
            client$media_fn(client$env$mx, f, room = channel)
        }
    }
    msgtype <- if (identical(kind, "notice")) {
        "m.notice"
    } else if (identical(kind, "emote")) {
        "m.emote"
    } else {
        "m.text"
    }
    id <- client$send_fn(client$env$mx, text, room = channel,
                         msgtype = msgtype,
                         markdown = identical(markup, "markdown"))
    invisible(as.character(id))
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
    list(threads = FALSE, thread_replies = FALSE, edits = FALSE,
         reactions = TRUE, files = TRUE, typing = TRUE,
         e2ee = requireNamespace("mx.crypto", quietly = TRUE),
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
