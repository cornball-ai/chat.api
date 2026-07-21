#' @title Slack adapter
#' @description chat.api methods for Slack, delegating to the suggested
#'   slackr package. Receive is per-channel Web API polling
#'   (conversations.history via slackr_history): the first poll per
#'   channel seeds the cursor at the newest message (no history
#'   replay; a failed seed stays unseeded and retries), later polls
#'   paginate the full window since the cursor so bursts larger than
#'   one page are never dropped.
#'
#'   Known platform limits, reflected in \code{chat_capabilities()}:
#'   thread REPLIES are not returned by conversations.history
#'   (\code{thread_replies = FALSE}); file upload is unsupported and
#'   warns without calling the endpoint, because slackr (<= 3.3.1)
#'   still targets the retired files.upload API; per-message identity
#'   requires the chat:write.customize scope.

#' Create a Slack chat client
#'
#' Requires the suggested \pkg{slackr} package and a bot token.
#' Channel names are normalized to bare names (no \code{#}), matching
#' what slackr's channel translation accepts.
#'
#' Sends explicitly suppress slackr's \code{SLACK_USERNAME} /
#' \code{SLACK_ICON_EMOJI} environment defaults: a plain
#' \code{chat_send()} posts as the bot's own identity, and authorship
#' is only overridden through \code{username} here or
#' \code{chat_send(identity =)} (both need the chat:write.customize
#' scope).
#'
#' @param channels Character vector of channels to poll.
#' @param token Bot token; defaults to the \code{SLACK_TOKEN}
#'   environment variable.
#' @param username Default display-name override for sends, or NULL
#'   (default) to post as the bot's own identity.
#' @param .history Testing seam: replacement for
#'   \code{slackr::slackr_history}. Leave NULL in production.
#' @param .post Testing seam: replacement for
#'   \code{slackr::slackr_msg}. Leave NULL in production; when both
#'   seams are supplied the slackr package is not required.
#' @return A \code{chat_client} of class \code{chat_slack}.
#' @export
chat_slack <- function(channels = character(),
                       token = Sys.getenv("SLACK_TOKEN"), username = NULL,
                       .history = NULL, .post = NULL) {
    if ((is.null(.history) || is.null(.post)) &&
        !requireNamespace("slackr", quietly = TRUE)) {
        stop("chat_slack() requires the 'slackr' package. ",
             "Install it first.", call. = FALSE)
    }
    if (!nzchar(token)) {
        stop("chat_slack() needs a bot token (SLACK_TOKEN).", call. = FALSE)
    }
    env <- new.env(parent = emptyenv())
    env$cursor <- list()
    structure(list(env = env, channels = sub("^#", "", channels),
                   token = token, username = username,
                   history_fn = .history %||% slackr::slackr_history,
                   post_fn = .post %||% slackr::slackr_msg),
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

#' Render contract markup for Slack
#'
#' markdown: translate the common mrkdwn divergences -- **bold** to
#' *bold*, [text](url) to <url|text>; italics, inline code, and fences
#' already agree. plain: escape the three characters Slack requires
#' (&, <, >); the send also passes mrkdwn = FALSE so emphasis
#' characters are not styled.
#' @noRd
slack_render <- function(text, markup) {
    if (identical(markup, "markdown")) {
        text <- gsub("\\*\\*([^*]+)\\*\\*", "*\\1*", text)
        text <- gsub("\\[([^]]+)\\]\\(([^)]+)\\)", "<\\2|\\1>", text)
        return(text)
    }
    text <- gsub("&", "&amp;", text, fixed = TRUE)
    text <- gsub("<", "&lt;", text, fixed = TRUE)
    gsub(">", "&gt;", text, fixed = TRUE)
}

#' @export
chat_poll.chat_slack <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since) && is.list(since)) {
        client$env$cursor <- since
    }
    messages <- list()
    for (ch in client$channels) {
        last <- client$env$cursor[[ch]]

        if (is.null(last)) {
            # First contact: seed the cursor at the newest message so a
            # restart never replays channel history as new traffic. A
            # FAILED seed stays unseeded for retry -- seeding at "0"
            # after an error would replay the whole channel once the
            # API recovers.
            seed <- tryCatch(
                             client$history_fn(message_count = 1L, channel = ch,
                    token = client$token, paginate = FALSE),
                             error = function(e) NULL
            )
            if (is.null(seed)) {
                next
            }
            client$env$cursor[[ch]] <- if (NROW(seed)) {
                max(as.character(seed$ts))
            } else {
                "0"
            }
            next
        }

        # paginate = TRUE walks every page in the window since the
        # cursor: a burst larger than one page (or the 15-object limit
        # newer Slack app classes get) is never silently dropped
        hist <- tryCatch(
                         client$history_fn(message_count = 100L,
                channel = ch,
                token = client$token,
                posted_from_time = last,
                inclusive = FALSE,
                paginate = TRUE),
                         error = function(e) NULL
        )
        if (is.null(hist) || !NROW(hist)) {
            next
        }
        ts_chr <- as.character(hist$ts)
        keep <- which(as.numeric(ts_chr) > as.numeric(last))
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
    name_override <- if (is.null(identity$name)) {
        client$username
    } else {
        identity$name
    }
    # Empty strings suppress slackr's SLACK_USERNAME/SLACK_ICON_EMOJI
    # env defaults (the same value an unset variable produces), so an
    # ordinary send never silently inherits a customized identity
    args <- list(txt = slack_render(text, markup),
                 channel = sub("^#", "", channel),
                 token = client$token,
                 username = name_override %||% "",
                 icon_emoji = if (is.null(identity$icon)) {
            ""
        } else {
            identity$icon
        })
    if (identical(markup, "plain")) {
        # Rides slackr_msg's ... into the chat.postMessage body:
        # without it Slack styles *emphasis* even in "plain" text
        args$mrkdwn <- FALSE
    }
    if (!is.null(thread)) {
        args$thread_ts <- thread
    }
    res <- do.call(client$post_fn, args)
    ts <- tryCatch(as.character(res$ts), error = function(e) NA_character_)

    if (!is.null(files)) {
        # Not attempted: slackr (<= 3.3.1) targets the retired
        # files.upload endpoint, which returns ok = FALSE without an R
        # error -- calling it would fail silently, so warn instead
        warning("chat_send(): Slack file upload unsupported (slackr ",
                "uses the retired files.upload endpoint); skipped: ",
                paste(files, collapse = ", "), call. = FALSE)
    }
    invisible(ts)
}

#' @export
chat_resolve.chat_slack <- function(client, name, ...) {
    sub("^#", "", name)
}

#' @export
chat_capabilities.chat_slack <- function(client, ...) {
    list(threads = TRUE, thread_replies = FALSE, edits = FALSE,
         reactions = TRUE, files = FALSE, typing = FALSE, e2ee = FALSE,
         identity_override = TRUE, markup_dialects = c("plain", "markdown"),
         max_message_bytes = 40000L)
}
