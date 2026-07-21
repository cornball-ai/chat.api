#' @title chat.api contract generics
#' @description Transport-agnostic chat interface: connect, poll, send.
#'   Adapters provide methods for their platform class.

#' Poll a chat client for new messages
#'
#' Poll-shaped everywhere: long-poll transports (Matrix /sync, Telegram
#' getUpdates) map directly; persistent-socket transports (IRC) buffer
#' into the poll. The cursor is opaque and adapter-specific; pass the
#' returned cursor back as \code{since} on the next call.
#'
#' @param client A \code{chat_client}.
#' @param since Opaque cursor from the previous poll, or NULL to start.
#' @param timeout Seconds to wait for activity; NULL for the adapter
#'   default.
#' @param ... Adapter-specific options.
#' @return A list with \code{messages} (list of \code{chat_message}) and
#'   \code{cursor} (opaque, for the next \code{since}).
#' @export
chat_poll <- function(client, since = NULL, timeout = NULL, ...) {
    UseMethod("chat_poll")
}

#' Send a message through a chat client
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier (adapter-native or resolved
#'   via \code{\link{chat_resolve}}).
#' @param text Message text.
#' @param markup \code{"plain"} or \code{"markdown"}; adapters render
#'   markdown to their dialect (HTML for Matrix, mrkdwn for Slack,
#'   stripped for IRC).
#' @param thread Thread identifier to post into, or NULL.
#' @param reply_to Message id being replied to, or NULL.
#' @param identity Optional per-message identity override
#'   (\code{list(name =, icon =)}) where the platform supports it.
#' @param files Character vector of file paths to attach, or NULL.
#' @param kind Message kind; \code{"message"} (default) or an
#'   adapter-understood alternative (e.g. \code{"notice"}, \code{"emote"}).
#' @param notify Logical; FALSE requests a silent delivery where
#'   supported.
#' @param ... Adapter-specific options.
#' @return The sent message id (character), invisibly.
#' @export
chat_send <- function(client, channel, text, markup = c("plain", "markdown"),
                      thread = NULL, reply_to = NULL, identity = NULL,
                      files = NULL, kind = "message", notify = TRUE, ...) {
    UseMethod("chat_send")
}

#' Signal typing state in a channel
#'
#' Capability-gated: the default method is a no-op so adapters without
#' typing indicators need not implement it.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param on Logical.
#' @param ... Adapter-specific options.
#' @return TRUE if the signal was sent, FALSE otherwise, invisibly.
#' @export
chat_typing <- function(client, channel, on = TRUE, ...) {
    UseMethod("chat_typing")
}

#' @export
chat_typing.default <- function(client, channel, on = TRUE, ...) {
    invisible(FALSE)
}

#' Resolve a human channel name to its identifier
#'
#' @param client A \code{chat_client}.
#' @param name Channel name, alias, or identifier.
#' @param ... Adapter-specific options.
#' @return The adapter-native channel identifier (character).
#' @export
chat_resolve <- function(client, name, ...) {
    UseMethod("chat_resolve")
}

#' Describe what a chat client's platform supports
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return A list with at least: \code{threads} (can post into
#'   threads), \code{thread_replies} (thread replies come back out of
#'   \code{\link{chat_poll}}), \code{edits}, \code{reactions},
#'   \code{files}, \code{typing}, \code{e2ee},
#'   \code{identity_override} (logicals), \code{markup_dialects}
#'   (character), \code{max_message_bytes} (integer or NA).
#' @export
chat_capabilities <- function(client, ...) {
    UseMethod("chat_capabilities")
}

#' Close a chat client's connection
#'
#' The default method is a no-op: HTTP-poll transports have nothing to
#' close. Persistent-socket transports (IRC) override it.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return TRUE, invisibly.
#' @export
chat_disconnect <- function(client, ...) {
    UseMethod("chat_disconnect")
}

#' @export
chat_disconnect.default <- function(client, ...) {
    invisible(TRUE)
}

#' Construct a normalized chat message
#'
#' The record every adapter's \code{\link{chat_poll}} returns. \code{raw}
#' carries the untouched platform event for consumers that need more.
#'
#' @param id Message identifier (character).
#' @param channel Channel/room identifier (character).
#' @param sender Sender identifier (character).
#' @param body Message text (character).
#' @param ts POSIXct timestamp.
#' @param thread Thread identifier or NULL.
#' @param markup Source markup hint (character, e.g. "plain", "html").
#' @param kind Message kind (character; "message" default).
#' @param raw The platform-native event, unmodified.
#' @return A list with class \code{chat_message}.
#' @export
chat_message <- function(id, channel, sender, body, ts, thread = NULL,
                         markup = "plain", kind = "message", raw = NULL) {
    stopifnot(is.character(id), is.character(channel), is.character(sender),
              is.character(body))
    structure(list(id = id, channel = channel, sender = sender,
                   body = body, ts = ts, thread = thread,
                   markup = markup, kind = kind, raw = raw),
              class = "chat_message")
}

#' @export
print.chat_message <- function(x, ...) {
    cat(sprintf("[%s] %s in %s: %s\n", format(x$ts, "%H:%M:%S"), x$sender,
                x$channel, substr(x$body, 1L, 60L)))
    invisible(x)
}
