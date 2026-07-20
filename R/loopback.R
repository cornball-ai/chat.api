#' @title Loopback adapter
#' @description In-memory reference adapter: what every transport
#'   adapter must look like, and the test double for contract consumers.

#' Create a loopback chat client
#'
#' Messages sent to any channel are appended to an in-memory log and
#' come back out of \code{\link{chat_poll}}. The cursor is the integer
#' position in that log.
#'
#' @return A \code{chat_client} of class \code{chat_loopback}.
#' @examples
#' cl <- chat_loopback()
#' chat_send(cl, "general", "hello")
#' chat_poll(cl)$messages
#' @export
chat_loopback <- function() {
    env <- new.env(parent = emptyenv())
    env$log <- list()
    structure(list(env = env), class = c("chat_loopback", "chat_client"))
}

#' @export
chat_send.chat_loopback <- function(client, channel, text,
                                    markup = c("plain", "markdown"),
                                    thread = NULL, reply_to = NULL,
                                    identity = NULL, files = NULL,
                                    kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    id <- sprintf("loopback-%d", length(client$env$log) + 1L)
    msg <- chat_message(id = id, channel = channel,
                        sender = if (is.null(identity$name)) "loopback"
        else identity$name,
                        body = text, ts = Sys.time(), thread = thread,
                        markup = markup, kind = kind)
    client$env$log[[length(client$env$log) + 1L]] <- msg
    invisible(id)
}

#' @export
chat_poll.chat_loopback <- function(client, since = NULL, timeout = NULL, ...) {
    from <- if (is.null(since)) {
        0L
    } else {
        as.integer(since)
    }
    log <- client$env$log
    idx <- seq_along(log)
    idx <- idx[idx > from]
    list(messages = log[idx], cursor = length(log))
}

#' @export
chat_resolve.chat_loopback <- function(client, name, ...) {
    name
}

#' @export
chat_capabilities.chat_loopback <- function(client, ...) {
    list(threads = TRUE, edits = FALSE, reactions = FALSE, files = FALSE,
         typing = FALSE, e2ee = FALSE, identity_override = TRUE,
         markup_dialects = c("plain", "markdown"),
         max_message_bytes = NA_integer_)
}
