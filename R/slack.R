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
#' @param .react Testing seam: replacement for
#'   \code{slackr::call_slack_api}. Leave NULL in production. Resolved
#'   when \code{chat_react()} is called, not here.
#' @param .api Testing seam: replacement for
#'   \code{slackr::call_slack_api} on the read paths
#'   (\code{chat_channel_info()}, \code{chat_members()}). Leave NULL in
#'   production.
#' @return A \code{chat_client} of class \code{chat_slack}.
#' @export
chat_slack <- function(channels = character(),
                       token = Sys.getenv("SLACK_TOKEN"), username = NULL,
                       .history = NULL, .post = NULL, .react = NULL,
                       .api = NULL) {
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
                   post_fn = .post %||% slackr::slackr_msg,
                   react_fn = .react, api_fn = .api),
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
            # FAILED seed (R error) stays unseeded for retry. A
            # zero-row seed is AMBIGUOUS: slackr collapses ok = FALSE
            # API responses and truly empty channels into the same
            # empty tibble, so the baseline must be safe for both --
            # the wall clock at request start (Slack-style ts) is: an
            # empty channel has nothing older to skip, and a failed
            # call must never replay history from "0". Clock skew vs
            # Slack's server stamps shifts the join point by at most
            # the skew, once.
            t0 <- sprintf("%.6f", as.numeric(Sys.time()))
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
                t0
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
                                 kind = "message", notify = TRUE,
                                 rich = NULL, ...) {
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
chat_react.chat_slack <- function(client, channel, message_id, key, ...) {
    # reactions.add through slackr's generic Web API caller: slackr has
    # no reaction helper of its own, and calling the endpoint directly
    # would put an HTTP dependency in a package that has none.
    #
    # key goes through unchanged except for stripping colons, which are
    # how the same emoji is written in Slack prose (":thumbsup:") and are
    # rejected by the API. Translating a Matrix-style emoji character
    # into a Slack short name would have to guess, so it does not -- the
    # contract says the two platforms take different keys.
    react_fn <- client$react_fn %||% slackr::call_slack_api
    # body, not `...`. call_slack_api() feeds `...` to the query string on
    # its GET path and ignores it on POST, where only `body` is sent -- so
    # passing these as dots produced a reactions.add carrying no channel,
    # no timestamp and no name, and Slack refused every one of them.
    resp <- react_fn("/api/reactions.add", .method = "POST",
                     token = client$token,
                     body = list(channel = sub("^#", "", channel), timestamp = message_id,
                                 name = gsub(":", "", key)))
    # Slack answers a refused call with HTTP 200 and {ok: false, error},
    # and call_slack_api() only checks the status code, so a bad channel
    # or an unknown emoji comes back looking like success. Returning TRUE
    # on that reports a reaction that was never placed.
    slack_stop_for_error(resp, "reactions.add")
    # No id: reactions.add answers {ok: true} and Slack gives a reaction
    # no identity of its own.
    invisible(TRUE)
}

#' Raise on a Slack response that is HTTP 200 and {ok: false}
#'
#' Slack signals a refused call in the body, not the status, and
#' \code{slackr::call_slack_api()} only checks the status. Without this a
#' send that Slack rejected is indistinguishable from one it accepted.
#'
#' Unwrapping an httr response needs httr, which is not chat.api's
#' dependency but is slackr's -- if there is a Slack response to inspect,
#' slackr made it and httr is installed. An already-parsed body is taken
#' as-is, which is what a \code{.react} seam hands back and what lets the
#' decision here be tested on the shape Slack actually sends rather than
#' on a hand-built imitation of httr's internals.
#'
#' A response that cannot be parsed is left alone rather than guessed at:
#' failing a good call is worse than the status check alone, which is
#' what the rest of this adapter already lives with.
#' @noRd
slack_stop_for_error <- function(resp, what) {
    body <- slack_body(resp)
    if (is.null(body) || is.null(body$ok)) {
        return(invisible(resp))
    }
    if (!isTRUE(body$ok)) {
        stop("chat.api: Slack refused ", what, ": ",
             body$error %||% "no error given", call. = FALSE)
    }
    invisible(resp)
}

#' @export
chat_channel_info.chat_slack <- function(client, channel, ...) {
    # One call, where Matrix takes two: conversations.info carries name
    # and topic together. That is the other half of why membership is a
    # separate verb -- conversations.members is a separate call here too,
    # and a paginated one.
    api <- client$api_fn %||% slackr::call_slack_api
    body <- slack_body(api("/api/conversations.info", .method = "GET",
                           token = client$token,
                           channel = sub("^#", "", channel)))
    slack_stop_for_error(body, "conversations.info")
    ch <- body$channel %||% list()
    # An unset purpose comes back as "" rather than being omitted, and ""
    # is not a topic. NULL is what the contract says "there is none"
    # looks like.
    blank <- function(x) {
        if (is.null(x) || !length(x) || !nzchar(x[[1L]])) {
            NULL
        } else {
            as.character(x)[[1L]]
        }
    }
    list(id = blank(ch$id) %||% sub("^#", "", channel),
         name = blank(ch$name),
         topic = blank(ch$topic$value) %||% blank(ch$purpose$value))
}

#' @export
chat_join.chat_slack <- function(client, channel, ...) {
    # conversations.join, which works for a public channel the bot is not
    # in yet. It cannot join a private one: Slack requires a member to add
    # the bot, and that arrives as no event this adapter can see -- which
    # is why `invites` is FALSE here while `join` is TRUE.
    api <- client$api_fn %||% slackr::call_slack_api
    body <- slack_body(api("/api/conversations.join", .method = "POST",
                           token = client$token,
                           body = list(channel = sub("^#", "", channel))))
    slack_stop_for_error(body, "conversations.join")
    invisible(sub("^#", "", channel))
}

#' @export
chat_channel_create.chat_slack <- function(client, name, ...) {
    # conversations.create. The name is normalized the way every other
    # channel argument here is; Slack's own naming rules (lowercase, no
    # spaces or periods) are enforced by the API and its refusal
    # propagates. Adapter options (is_private = TRUE) ride through ...
    # into the request body. The created channel is NOT added to the
    # poll set: channels= is fixed at construction, the same bargain
    # chat_join() makes.
    api <- client$api_fn %||% slackr::call_slack_api
    body <- slack_body(api("/api/conversations.create", .method = "POST",
                           token = client$token,
                           body = list(name = sub("^#", "", name), ...)))
    slack_stop_for_error(body, "conversations.create")
    invisible(as.character(body$channel$name %||% body$channel$id))
}

#' @export
chat_leave.chat_slack <- function(client, channel, ...) {
    # conversations.leave. A refusal (not_in_channel) propagates: a
    # leave that quietly failed keeps delivering a channel the caller
    # believes it has left.
    api <- client$api_fn %||% slackr::call_slack_api
    body <- slack_body(api("/api/conversations.leave", .method = "POST",
                           token = client$token,
                           body = list(channel = sub("^#", "", channel))))
    slack_stop_for_error(body, "conversations.leave")
    invisible(sub("^#", "", channel))
}

#' @export
chat_members.chat_slack <- function(client, channel, ...) {
    api <- client$api_fn %||% slackr::call_slack_api
    out <- character()
    cursor <- ""
    # Paginated, and a partial answer is worse than none here: a member
    # list truncated at the first page reads as a smaller room, which is
    # how a consumer gating on member count reaches the wrong decision
    # without anything looking wrong. Every page is walked before
    # anything is returned.
    repeat {
        body <- slack_body(api("/api/conversations.members", .method = "GET",
                               token = client$token,
                               channel = sub("^#", "", channel), limit = 200L,
                               cursor = cursor))
        slack_stop_for_error(body, "conversations.members")
        out <- c(out, as.character(body$members %||% character()))
        cursor <- body$response_metadata$next_cursor %||% ""
        if (!length(cursor) || !nzchar(cursor)) {
            break
        }
    }
    out
}

#' Parsed body of a Slack response
#'
#' Accepts an httr response or an already-parsed list, so a seam can hand
#' back the shape Slack's JSON becomes without building an imitation of
#' httr's internals. httr is slackr's own dependency: if there is a
#' response object to unwrap, slackr made it.
#' @noRd
slack_body <- function(resp) {
    if (is.list(resp) && !inherits(resp, "response")) {
        return(resp)
    }
    if (!requireNamespace("httr", quietly = TRUE)) {
        return(NULL)
    }
    tryCatch(httr::content(resp, as = "parsed"), error = function(e) NULL)
}

#' @export
chat_resolve.chat_slack <- function(client, name, ...) {
    sub("^#", "", name)
}

#' @export
chat_capabilities.chat_slack <- function(client, ...) {
    # reactions has been TRUE since before there was a chat_react() to
    # back it -- the flag claimed something no verb could deliver. It is
    # true now.
    #
    # reaction_events is FALSE. conversations.history, which this adapter
    # polls, reports reactions as an aggregate on the message
    # ({name, users, count}) rather than as events: no per-reaction id and
    # no per-reaction timestamp, so there is nothing to build a
    # chat_reaction() from that a consumer could deduplicate across polls.
    # Reading them as events needs the Events API or Socket Mode, which is
    # a different transport than this one.
    list(threads = TRUE, thread_replies = FALSE, edits = TRUE,
         reactions = TRUE, reaction_events = FALSE, channel_info = TRUE,
         members = TRUE,
         # A Slack bot is added to a channel rather than invited, and
         # conversations.history says nothing about it -- there is no
         # invitation to hand a consumer. Joining an open channel is a
         # different thing, and does work.
         invites = FALSE, join = TRUE, whoami = TRUE,
         channels = TRUE, history = TRUE, pending = FALSE,
         mark_read = TRUE, set_identity = TRUE, relogin = FALSE,
         channel_create = TRUE, leave = TRUE,
         files = FALSE, attachments = FALSE, typing = FALSE, e2ee = FALSE,
         identity_override = TRUE, rich_markup = character(),
         markup_dialects = c("plain", "markdown"),
         max_message_bytes = 40000L)
}

#' @export
chat_whoami.chat_slack <- function(client, ...) {
    # Cached for the client's lifetime. Unlike Matrix, where the id is
    # already a field of the config in hand, Slack only answers this over
    # the network -- and chat_addressed() asks once per message. The
    # answer is a property of the token, which cannot change underneath a
    # client that was constructed with it.
    if (!is.null(client$env$whoami)) {
        return(client$env$whoami)
    }
    api <- client$api_fn %||% slackr::call_slack_api
    body <- slack_body(api("/api/auth.test", .method = "GET",
                           token = client$token))
    slack_stop_for_error(body, "auth.test")
    id <- body$user_id
    if (is.null(id) || !length(id) || !nzchar(as.character(id)[[1L]])) {
        stop("chat.api: Slack auth.test returned no user_id.", call. = FALSE)
    }
    who <- chat_identity(as.character(id)[[1L]],
                         display = body$user %||% NA_character_,
                         raw = body)
    client$env$whoami <- who
    who
}

#' @export
chat_addressed.chat_slack <- function(client, message, ...) {
    id <- chat_whoami(client)$id
    if (identity_mentioned(id, message)) {
        return(TRUE)
    }
    body <- message$body %||% ""
    # Slack does not leave a mention as text: the sending client rewrites
    # it to <@U0123> before the message is stored, so this is a literal
    # match and there is no @name form to also look for. Someone who
    # typed the bot's display name without selecting the completion did
    # not mention it, and Slack agrees -- no notification goes out.
    nzchar(body) && grepl(sprintf("<@%s>", id), body, fixed = TRUE)
}

#' @export
chat_channels.chat_slack <- function(client, ...) {
    api <- client$api_fn %||% slackr::call_slack_api
    out <- character()
    cursor <- ""
    repeat {
        args <- list("/api/conversations.list", .method = "GET",
                     token = client$token, limit = 200L,
                     types = "public_channel,private_channel")
        if (nzchar(cursor)) {
            args$cursor <- cursor
        }
        body <- slack_body(do.call(api, args))
        slack_stop_for_error(body, "conversations.list")
        for (ch in body$channels %||% list()) {
            # Only the ones this bot is in. conversations.list reports
            # every channel the workspace has, and a consumer reading
            # this as "where I can post" would fan out across the org.
            if (isTRUE(ch$is_member)) {
                out <- c(out, as.character(ch$id))
            }
        }
        cursor <- body$response_metadata$next_cursor %||% ""
        if (!nzchar(cursor)) {
            break
        }
    }
    out
}

#' @export
chat_history.chat_slack <- function(client, channel, limit = 50L,
                                    cursor = NULL, ...) {
    api <- client$api_fn %||% slackr::call_slack_api
    args <- list("/api/conversations.history", .method = "GET",
                 token = client$token, channel = sub("^#", "", channel),
                 limit = as.integer(limit))
    if (!is.null(cursor)) {
        # Slack's own cursor, not a `latest` timestamp. Both page
        # backwards here and a message ts would even work, but the
        # contract's token has to mean one thing across adapters, and on
        # Matrix it cannot be a message id at all.
        args$cursor <- cursor
    }
    body <- slack_body(do.call(api, args))
    slack_stop_for_error(body, "conversations.history")
    msgs <- body$messages %||% list()
    # Slack pages backwards too, newest first. The contract promises the
    # other order.
    msgs <- rev(msgs)
    out <- list()
    for (m in msgs) {
        # Joins, leaves, channel renames. They carry a subtype and are
        # not conversation.
        if (!is.null(m$subtype)) {
            next
        }
        ts <- suppressWarnings(as.numeric(m$ts))
        out[[length(out) + 1L]] <- chat_message(
            id = as.character(m$ts),
            channel = as.character(channel),
            sender = as.character(m$user %||% m$bot_id %||% ""),
            body = as.character(m$text %||% ""),
            ts = if (is.na(ts)) as.POSIXct(NA) else
            as.POSIXct(ts, origin = "1970-01-01"),
            markup = "plain", kind = "message",
            thread = m$thread_ts, raw = m)
    }
    # Slack sends "" rather than omitting next_cursor when there is no
    # more, and an empty-string cursor handed back to conversations.history
    # is an error rather than a no-op.
    nxt <- body$response_metadata$next_cursor
    if (is.null(nxt) || !nzchar(nxt)) {
        nxt <- NULL
    }
    list(messages = out, cursor = nxt)
}

#' @export
chat_mark_read.chat_slack <- function(client, channel, message_id, ...) {
    ok <- tryCatch({
        api <- client$api_fn %||% slackr::call_slack_api
        resp <- api("/api/conversations.mark", .method = "POST",
                    token = client$token,
                    body = list(channel = sub("^#", "", channel), ts = message_id))
        slack_stop_for_error(resp, "conversations.mark")
        TRUE
    }, error = function(e) FALSE)
    invisible(ok)
}

#' @export
chat_set_identity.chat_slack <- function(client, display, ...) {
    api <- client$api_fn %||% slackr::call_slack_api
    resp <- api("/api/users.profile.set", .method = "POST",
                token = client$token,
                body = list(profile = sprintf('{"display_name":"%s"}',
                gsub('"', '\\\\"', display))))
    slack_stop_for_error(resp, "users.profile.set")
    # The cached identity carries a display name, and it is now wrong.
    client$env$whoami <- NULL
    invisible(TRUE)
}

#' @export
chat_edit.chat_slack <- function(client, channel, message_id, text,
                                 markup = c("plain", "markdown"),
                                 rich = NULL, kind = "message", ...) {
    markup <- match.arg(markup)
    api <- client$api_fn %||% slackr::call_slack_api
    resp <- api("/api/chat.update", .method = "POST", token = client$token,
                body = list(channel = sub("^#", "", channel), ts = message_id,
                            text = slack_render(text, markup)))
    slack_stop_for_error(resp, "chat.update")
    # Slack edits in place, so the identifier is the one that went in.
    # Matrix mints a new event for the edit and returns that instead --
    # the contract promises "the id of the thing that happened", not
    # that the two adapters agree on which thing that is.
    invisible(message_id)
}
