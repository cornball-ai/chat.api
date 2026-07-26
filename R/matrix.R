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
#' @return A \code{chat_client} of class \code{chat_matrix}.
#' @export
chat_matrix <- function(app = "chat.api", path = NULL, save_cursor = TRUE,
                        mx = NULL, .sync = NULL, .extract = NULL,
                        .send = NULL, .media = NULL) {
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
                   media_fn = .media %||% mx.client::mx_send_media),
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
    # raw carries the full sync response for Matrix-specific consumers
    # (invites, reactions, E2EE decryption) that the generic contract
    # does not model yet
    list(messages = messages, cursor = res$client$sync_token,
         raw = res$sync)
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

#' @export
chat_typing.chat_matrix <- function(client, channel, on = TRUE, ...) {
    ok <- tryCatch({
        # mx.api wants a session, not the client config
        sess <- mx.client::mx_client_session(client$env$mx)
        mx.api::mx_typing(sess, channel, typing = isTRUE(on),
                          timeout = 30000L)
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
    list(threads = FALSE, thread_replies = TRUE, edits = FALSE,
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
