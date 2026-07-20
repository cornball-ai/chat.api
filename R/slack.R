#' @title Slack adapter
#' @description chat.api methods for Slack, delegating to the suggested
#'   slackr package. Receive is Web API polling
#'   (conversations.history), poll-shaped like every other adapter.
#'
#'   Status: written to slackr's documented API; unverified until
#'   slackr is installed and a workspace token is configured. Treat as
#'   experimental.

#' Create a Slack chat client
#'
#' Requires the suggested \pkg{slackr} package and a configured bot
#' token (see \code{slackr::slackr_setup()}).
#'
#' @param token Bot token; defaults to the \code{SLACK_TOKEN}
#'   environment variable.
#' @param username Default bot display name for sends (Slack allows
#'   per-message identity; see the \code{identity} argument of
#'   \code{\link{chat_send}}).
#' @return A \code{chat_client} of class \code{chat_slack}.
#' @export
chat_slack <- function(token = Sys.getenv("SLACK_TOKEN"),
                       username = "chat.api") {
    if (!requireNamespace("slackr", quietly = TRUE)) {
        stop("chat_slack() requires the 'slackr' package. ",
             "Install it first.", call. = FALSE)
    }
    if (!nzchar(token)) {
        stop("chat_slack() needs a bot token (SLACK_TOKEN).", call. = FALSE)
    }
    env <- new.env(parent = emptyenv())
    env$cursor <- NULL
    structure(list(env = env, token = token, username = username),
              class = c("chat_slack", "chat_client"))
}

#' @export
chat_send.chat_slack <- function(client, channel, text,
                                 markup = c("plain", "markdown"),
                                 thread = NULL, reply_to = NULL,
                                 identity = NULL, files = NULL,
                                 kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    args <- list(txt = text, channel = channel, token = client$token,
                 username = if (is.null(identity$name)) {
            client$username
        } else {
            identity$name
        })
    if (!is.null(identity$icon)) {
        args$icon_emoji <- identity$icon
    }
    if (!is.null(thread)) {
        args$thread_ts <- thread
    }
    res <- do.call(slackr::slackr_msg, args)
    if (!is.null(files)) {
        for (f in files) {
            slackr::slackr_upload(f, channels = channel, token = client$token)
        }
    }
    ts <- tryCatch(as.character(res$ts), error = function(e) NA_character_)
    invisible(ts)
}

#' @export
chat_poll.chat_slack <- function(client, since = NULL, timeout = NULL, ...) {
    oldest <- since %||% client$env$cursor
    hist <- tryCatch(
                     slackr::slackr_history(token = client$token, oldest = oldest,
            paginate = FALSE),
                     error = function(e) NULL
    )
    if (is.null(hist) || !nrow(hist)) {
        return(list(messages = list(), cursor = oldest))
    }
    messages <- lapply(seq_len(nrow(hist)), function(i) {
        chat_message(id = as.character(hist$ts[i]),
                     channel = as.character(hist$channel %||% ""),
                     sender = as.character(hist$user[i]),
                     body = as.character(hist$text[i]),
                     ts = as.POSIXct(as.numeric(hist$ts[i]), origin = "1970-01-01"),
                     thread = if ("thread_ts" %in% names(hist)) {
                hist$thread_ts[i]
            } else {
                NULL
            },
                     markup = "plain", raw = hist[i,])
    })
    cursor <- max(as.character(hist$ts))
    client$env$cursor <- cursor
    list(messages = messages, cursor = cursor)
}

#' @export
chat_resolve.chat_slack <- function(client, name, ...) {
    sub("^#", "", name)
}

#' @export
chat_capabilities.chat_slack <- function(client, ...) {
    list(threads = TRUE, edits = FALSE, reactions = TRUE, files = TRUE,
         typing = FALSE, e2ee = FALSE, identity_override = TRUE,
         markup_dialects = c("plain", "markdown"), max_message_bytes = 40000L)
}
