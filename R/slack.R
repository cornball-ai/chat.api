#' @title Slack adapter
#' @description chat.api methods for Slack, delegating to the suggested
#'   slackr package. Receive is per-channel Web API polling
#'   (conversations.history via slackr_history), so channels are
#'   configured at connect time, IRC-style. Verified against slackr's
#'   installed signatures; the tinytest pins them.

#' Create a Slack chat client
#'
#' Requires the suggested \pkg{slackr} package and a bot token.
#' \code{\link{chat_poll}} polls \code{slackr::slackr_history()} for
#' each configured channel; the cursor is a named list of per-channel
#' message timestamps.
#'
#' @param channels Character vector of channels to poll.
#' @param token Bot token; defaults to the \code{SLACK_TOKEN}
#'   environment variable.
#' @param username Default bot display name for sends. Slack allows
#'   per-message identity: the \code{identity} argument of
#'   \code{\link{chat_send}} overrides name and icon per post.
#' @return A \code{chat_client} of class \code{chat_slack}.
#' @export
chat_slack <- function(channels = character(),
                       token = Sys.getenv("SLACK_TOKEN"),
                       username = "chat.api") {
    if (!requireNamespace("slackr", quietly = TRUE)) {
        stop("chat_slack() requires the 'slackr' package. ",
             "Install it first.", call. = FALSE)
    }
    if (!nzchar(token)) {
        stop("chat_slack() needs a bot token (SLACK_TOKEN).", call. = FALSE)
    }
    env <- new.env(parent = emptyenv())
    env$cursor <- list()
    structure(list(env = env, channels = channels, token = token,
                   username = username),
              class = c("chat_slack", "chat_client"))
}

#' Safe column pull from a history frame
#' @noRd
slack_col <- function(df, nm, i) {
    if (nm %in% names(df)) {
        as.character(df[[nm]][i])
    } else {
        NA_character_
    }
}

#' @export
chat_poll.chat_slack <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since) && is.list(since)) {
        client$env$cursor <- since
    }
    messages <- list()
    for (ch in client$channels) {
        args <- list(message_count = 100L, channel = ch,
                     token = client$token, paginate = FALSE)
        last <- client$env$cursor[[ch]]
        if (!is.null(last)) {
            args$posted_from_time <- last
            args$inclusive <- FALSE
        }
        hist <- tryCatch(do.call(slackr::slackr_history, args),
                         error = function(e) NULL)
        if (is.null(hist) || !NROW(hist)) {
            next
        }
        ts_chr <- as.character(hist$ts)
        keep <- if (is.null(last)) {
            seq_along(ts_chr)
        } else {
            which(as.numeric(ts_chr) > as.numeric(last))
        }
        keep <- keep[order(as.numeric(ts_chr[keep]))]
        for (i in keep) {
            thread <- slack_col(hist, "thread_ts", i)
            messages[[length(messages) + 1L]] <- chat_message(
                id = ts_chr[i], channel = ch,
                sender = slack_col(hist, "user", i),
                body = slack_col(hist, "text", i),
                ts = as.POSIXct(as.numeric(ts_chr[i]), origin = "1970-01-01"),
                thread = if (is.na(thread)) NULL else thread,
                markup = "plain", raw = hist[i,])
        }
        if (length(keep)) {
            client$env$cursor[[ch]] <- ts_chr[keep[length(keep)]]
        }
    }
    list(messages = messages, cursor = client$env$cursor)
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
            slackr::slackr_upload(filename = f, channels = channel,
                                  token = client$token)
        }
    }
    invisible(tryCatch(as.character(res$ts), error = function(e) NA_character_))
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
