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
    # Channels declared by chat_channel_create(); chat_channels()
    # reports these plus every channel the log has seen traffic in.
    env$channels <- character()
    # Durable channel state written by chat_set_state(), keyed by
    # channel/type/state_key. A write replaces the previous content for
    # its key, which is the Matrix semantic consumers test against.
    env$state <- list()
    structure(list(env = env), class = c("chat_loopback", "chat_client"))
}

#' @export
chat_channel_create.chat_loopback <- function(client, name, ...) {
    stopifnot(is.character(name), length(name) == 1L, nzchar(name))
    # The name is the identifier, which is the simplest honest answer
    # for an in-memory adapter -- and creating twice is an error, not a
    # no-op, because a consumer that creates a channel it already made
    # has lost track of its own state, and the reference adapter is
    # where that should be loudest.
    if (name %in% chat_channels(client)) {
        stop("chat_channel_create(): channel '", name, "' already exists.",
             call. = FALSE)
    }
    client$env$channels <- c(client$env$channels, name)
    invisible(name)
}

#' @export
chat_set_state.chat_loopback <- function(client, channel, type, content,
    state_key = "", ...) {
    stopifnot(is.character(channel), length(channel) == 1L, nzchar(channel),
              is.character(type), length(type) == 1L, nzchar(type),
              is.list(content), is.character(state_key),
              length(state_key) == 1L)
    key <- paste(channel, type, state_key, sep = "\r")
    client$env$state[[key]] <- content
    invisible(sprintf("loopback-state-%d", length(client$env$state)))
}

#' @export
chat_send.chat_loopback <- function(client, channel, text,
                                    markup = c("plain", "markdown"),
                                    thread = NULL, reply_to = NULL,
                                    identity = NULL, files = NULL,
                                    kind = "message", notify = TRUE,
                                    rich = NULL, ...) {
    markup <- match.arg(markup)
    attachments <- NULL
    if (!is.null(files)) {
        # A missing file errors rather than sending a message that
        # quietly lost its attachment; the reference adapter is where
        # that should be loudest.
        missing <- files[!file.exists(files)]
        if (length(missing)) {
            stop("chat_send(): no such file: ",
                 paste(missing, collapse = ", "), call. = FALSE)
        }
        attachments <- lapply(seq_along(files), function(i) {
            chat_attachment(
                            id = sprintf("loopback-file-%d-%d",
                    length(client$env$log) + 1L, i),
                            name = basename(files[[i]]),
                            bytes = as.integer(file.size(files[[i]])),
                            path = files[[i]])
        })
    }
    id <- sprintf("loopback-%d", length(client$env$log) + 1L)
    msg <- chat_message(id = id, channel = channel,
                        sender = if (is.null(identity$name)) "loopback"
        else identity$name,
                        body = text, ts = Sys.time(), thread = thread,
                        markup = markup, kind = kind,
                        attachments = attachments)
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
    list(threads = TRUE, thread_replies = TRUE, edits = TRUE,
         reactions = FALSE, reaction_events = FALSE, channel_info = FALSE,
         members = FALSE, invites = FALSE, join = FALSE, whoami = TRUE,
         channels = TRUE, history = TRUE, pending = FALSE,
         mark_read = FALSE, set_identity = FALSE, relogin = FALSE,
         channel_create = TRUE, leave = FALSE, set_state = TRUE,
         # files records the paths it was handed; attachments hands
         # them back out of the poll. Both TRUE is what makes loopback
         # the round-trip test double for media-carrying consumers.
         files = TRUE, attachments = TRUE, typing = FALSE, e2ee = FALSE,
         identity_override = TRUE, rich_markup = character(),
         markup_dialects = c("plain", "markdown"),
         max_message_bytes = NA_integer_)
}

#' @export
chat_whoami.chat_loopback <- function(client, ...) {
    # The sender chat_send() stamps when the caller supplies no identity.
    # Fixed rather than configurable, so a consumer's self-check has
    # something stable to compare against across a test.
    chat_identity("loopback")
}

#' @export
chat_channels.chat_loopback <- function(client, ...) {
    unique(c(client$env$channels,
             vapply(client$env$log, function(m) m$channel, character(1))))
}

#' @export
chat_history.chat_loopback <- function(client, channel, limit = 50L,
                                       cursor = NULL, ...) {
    log <- client$env$log
    keep <- vapply(log, function(m) identical(m$channel, channel), logical(1))
    log <- log[keep]
    # The cursor is a count of how many of this channel's messages the
    # caller has already seen from the end. An integer, deliberately
    # opaque: the reference adapter is what a new adapter is read as an
    # example, and one that paged by message id would teach the wrong
    # thing -- Matrix cannot do that at all.
    seen <- if (is.null(cursor)) {
        0L
    } else {
        as.integer(cursor)
    }
    if (seen > 0L) {
        log <- if (seen >= length(log)) {
            list()
        } else {
            log[seq_len(length(log) - seen)]
        }
    }
    # The tail, still oldest-first. limit trims the far end, not the near
    # one: "the last 20 messages" means the 20 most recent.
    if (length(log) > limit) {
        log <- log[seq.int(length(log) - limit + 1L, length(log))]
        nxt <- seen + limit
    } else {
        nxt <- NULL
    }
    list(messages = log, cursor = nxt)
}

#' @export
chat_edit.chat_loopback <- function(client, channel, message_id, text,
                                    markup = c("plain", "markdown"),
                                    rich = NULL, kind = "message", ...) {
    markup <- match.arg(markup)
    pos <- which(vapply(client$env$log,
                        function(m) identical(m$id, message_id), logical(1)))
    if (!length(pos)) {
        # Not a no-op. A consumer editing a message that is not there has
        # lost track of what it sent, and the reference adapter is where
        # that should be loudest.
        stop("chat_edit(): no message ", message_id, " in this log.",
             call. = FALSE)
    }
    msg <- client$env$log[[pos[[1L]]]]
    msg$body <- text
    msg$markup <- markup
    client$env$log[[pos[[1L]]]] <- msg
    invisible(message_id)
}
