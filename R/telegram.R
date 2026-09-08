#' @title Telegram adapter
#' @description chat.api methods for the Telegram Bot API, with HTTP
#'   delegated to the suggested httr package, or to a
#'   \code{telegram::TGBot} when one is supplied. Receive is getUpdates
#'   long polling: one call returns every update Telegram is holding
#'   for the bot across every chat it is in, so the cursor is a single
#'   update offset rather than one per channel. Sends, edits,
#'   reactions, typing, chat metadata, leaving, and files in both
#'   directions go through the same API.
#'
#'   Known platform limits, reflected in \code{chat_capabilities()}:
#'   the Bot API has no history read, no member list, no list of the
#'   chats a bot is in, and no read markers. A bot cannot join a chat
#'   or create one; a member adds it. Reaction events reach a bot in a
#'   group only when it is an administrator there.

#' Create a Telegram chat client
#'
#' Requires the suggested \pkg{httr} package and a bot token from
#' BotFather, or a \code{telegram::TGBot} that carries one.
#'
#' Channels are chat identifiers as Telegram reports them -- a
#' positive number for a private chat, a negative one for a group or
#' channel -- always as character. \code{\link{chat_resolve}} turns a
#' public \code{@@username} into one.
#'
#' The first poll returns whatever updates Telegram is still holding
#' for the bot (it keeps them for 24 hours). That is the mail that
#' arrived while the bot was down rather than channel history, so it
#' comes out as ordinary traffic. Passing the returned cursor back as
#' \code{since} confirms it; Telegram re-sends anything unconfirmed.
#'
#' @param token Bot token; defaults to the \code{TELEGRAM_BOT_TOKEN}
#'   environment variable.
#' @param timeout Long-poll wait in seconds, used by
#'   \code{\link{chat_poll}} when it is given no \code{timeout}.
#' @param api_url Base URL of the Bot API. The default is Telegram's;
#'   a local Bot API server takes its own. Ignored when \code{bot} is
#'   given, since the class fixes the host.
#' @param bot A \code{telegram::TGBot} from the suggested \pkg{telegram}
#'   package, or NULL. When given, every request goes through its public
#'   \code{req()} method, so its proxy settings apply and \code{token}
#'   may be left empty: the object holds its own. The class's verbs are
#'   not used, only its transport. Its \code{getUpdates()} can neither
#'   long-poll nor choose update kinds, its parser flattens updates into
#'   data frames, and it has no edit, reaction, chat or leave methods;
#'   \code{req()} is what carries this adapter. Attachments are fetched
#'   from the URL its \code{getFile()} returns.
#' @param .api Testing seam: replacement for the HTTP layer, a
#'   \code{function(method, params, files)} returning the parsed
#'   response (\code{list(ok =, result =)}). \code{params} arrives
#'   already in wire form: NULLs dropped, logicals as
#'   \code{"true"}/\code{"false"}, numbers as plain digits. Leave NULL
#'   in production.
#' @param .download Testing seam: replacement for the file fetch, a
#'   \code{function(file_id, file_path, dest)} writing the bytes behind
#'   a getFile answer to \code{dest}. Leave NULL in production; when
#'   both seams are supplied neither httr nor a bot is required.
#' @return A \code{chat_client} of class \code{chat_telegram}.
#' @export
chat_telegram <- function(token = Sys.getenv("TELEGRAM_BOT_TOKEN"),
                          timeout = 30L,
                          api_url = "https://api.telegram.org", bot = NULL,
                          .api = NULL, .download = NULL) {
    has_bot <- !is.null(bot)
    if (has_bot && !is.function(bot$req)) {
        stop("chat_telegram(): `bot` must be a telegram::TGBot, or an ",
             "object with a req(method, body) method.", call. = FALSE)
    }
    # httr carries both transports: it is the direct one, and it is what
    # unwraps a TGBot's responses -- telegram imports it, so a TGBot never
    # arrives without it.
    if ((is.null(.api) || is.null(.download)) &&
        !requireNamespace("httr", quietly = TRUE)) {
        stop("chat_telegram() requires the 'httr' package. ",
             "Install it first.", call. = FALSE)
    }
    token <- as.character(token %||% "")[[1L]]
    if (!has_bot && (is.na(token) || !nzchar(token))) {
        stop("chat_telegram() needs a bot token (TELEGRAM_BOT_TOKEN) or ",
             "a telegram::TGBot as `bot`.", call. = FALSE)
    }
    api_url <- sub("/+$", "", api_url)
    env <- new.env(parent = emptyenv())
    env$cursor <- NULL
    env$whoami <- NULL
    structure(list(env = env, token = token, timeout = as.integer(timeout),
                   api_url = api_url, bot = bot,
                   api_fn = .api %||% if (has_bot) {
                telegram_tgbot_api(bot)
            } else {
                telegram_http(token, api_url)
            },
                   download_fn = .download %||% if (has_bot) {
                telegram_tgbot_download(bot)
            } else {
                telegram_http_download(token, api_url)
            }),
              class = c("chat_telegram", "chat_client"))
}

# The update kinds the poll asks for. Passing the list on every
# getUpdates is how Telegram wants it set; it persists server-side
# until changed. Edits are not requested: an edited message is not new
# conversation, and a consumer that replied to the original would
# answer it twice.
telegram_update_kinds <- c("message", "channel_post", "message_reaction")

# Identifiers as strings, never through as.character() on a double.
# R writes 100000 as "1e+05", and every id Telegram sends is a number
# to its JSON parser and a string to this contract. A chat id at a
# round hundred thousand would otherwise never match itself.
telegram_chr <- function(x) {
    if (is.null(x) || !length(x)) {
        return(NULL)
    }
    if (is.numeric(x)) {
        return(sprintf("%.0f", x))
    }
    as.character(x)
}

telegram_time <- function(s) {
    if (is.null(s)) {
        as.POSIXct(NA)
    } else {
        as.POSIXct(as.numeric(s), origin = "1970-01-01")
    }
}

telegram_int <- function(x) {
    if (is.null(x)) {
        NA_integer_
    } else {
        suppressWarnings(as.integer(x))
    }
}

# Parameters as they go on the wire. Form encoding is what every Bot
# API method accepts, so no JSON is built for the common case -- the
# two array-valued parameters (allowed_updates, reaction) are handed
# over as JSON strings by their callers. Logicals become Telegram's
# lowercase spelling, which "TRUE" is not, and numbers go through
# telegram_chr() for the same reason ids do.
telegram_form <- function(params) {
    params <- params[!vapply(params, is.null, logical(1))]
    lapply(params, function(v) {
        if (is.logical(v)) {
            if (isTRUE(v)) "true" else "false"
        } else if (is.numeric(v)) {
            telegram_chr(v)
        } else {
            v
        }
    })
}

telegram_json_string <- function(x) {
    x <- gsub("\\", "\\\\", x, fixed = TRUE)
    gsub('"', '\\"', x, fixed = TRUE)
}

telegram_json_array <- function(x) {
    paste0('["', paste(vapply(x, telegram_json_string, ""), collapse = '","'),
           '"]')
}

# The production HTTP layer, one closure per client so the token stays
# out of the seam. Every method is a POST to /bot<token>/<method>;
# multipart is used only when there is a file to carry.
telegram_http <- function(token, api_url) {
    force(token)
    force(api_url)
    function(method, params = list(), files = NULL) {
        url <- sprintf("%s/bot%s/%s", api_url, token, method)
        body <- params
        encode <- "form"
        if (length(files)) {
            body <- c(body, lapply(files, httr::upload_file))
            encode <- "multipart"
        }
        # A long poll has to outlive its own wait; nothing else waits.
        wait <- suppressWarnings(as.numeric(params$timeout %||% 0))
        if (is.na(wait)) {
            wait <- 0
        }
        resp <- httr::POST(url, body = body, encode = encode,
                           httr::timeout(wait + 30))
        telegram_parse(resp, method)
    }
}

# Read the body whatever the status: Telegram says no with a 4xx that
# still carries {ok: false, description}, and the description is the
# part worth reporting.
telegram_parse <- function(resp, method) {
    parsed <- tryCatch(
                       httr::content(resp, as = "parsed", type = "application/json"),
                       error = function(e) NULL)
    if (!is.list(parsed)) {
        stop("chat.api: Telegram ", method, " answered HTTP ",
             httr::status_code(resp), " with no JSON body.", call. = FALSE)
    }
    parsed
}

# The same layer over a telegram::TGBot. Its public req() is a POST of
# a body to /bot<token>/<method> with the object's proxy applied, and
# it hands back the httr response, which is exactly what the direct
# layer builds for itself. It also runs httr::warn_for_status(), so a
# refused call warns there and then errors in telegram_call() with
# Telegram's description; both are kept, since the first is the
# package's and the second is the one with the reason in it. There is
# no request timeout on that path: a long poll waits as long as curl
# does.
telegram_tgbot_api <- function(bot) {
    force(bot)
    function(method, params = list(), files = NULL) {
        body <- params
        if (length(files)) {
            body <- c(body, lapply(files, httr::upload_file))
        }
        telegram_parse(bot$req(method, body = body), method)
    }
}

# The file half. getFile hands back a path that is only fetchable
# through /file/bot<token>/, so the token has to be here too.
telegram_http_download <- function(token, api_url) {
    force(token)
    force(api_url)
    function(file_id, file_path, dest) {
        telegram_fetch(sprintf("%s/file/bot%s/%s", api_url, token, file_path),
                       dest)
    }
}

# Over a TGBot the token is private, so the download URL comes from the
# class's own getFile(), called without a destfile: that is the one
# thing it returns rather than downloads. It answers NULL rather than
# raising for a file the Bot API will not serve, which is turned back
# into the error the direct path raises. The class's own download would
# have gone through curl without its proxy anyway, so nothing is lost
# by fetching the URL here.
telegram_tgbot_download <- function(bot, fetch = telegram_fetch) {
    force(bot)
    force(fetch)
    function(file_id, file_path, dest) {
        url <- bot$getFile(file_id)
        if (!is.character(url) || length(url) != 1L || !nzchar(url)) {
            stop("chat.api: Telegram getFile served no download URL for ",
                 file_id, ".", call. = FALSE)
        }
        fetch(url, dest)
    }
}

telegram_fetch <- function(url, dest) {
    resp <- httr::GET(url, httr::write_disk(dest, overwrite = TRUE))
    if (!identical(httr::status_code(resp), 200L)) {
        stop("chat.api: Telegram file fetch answered HTTP ",
             httr::status_code(resp), ".", call. = FALSE)
    }
    invisible(dest)
}

# One place for the answer shape. A refused call is {ok: false,
# description} and raises with the description; a good one is
# unwrapped to its result. A seam that answers with something that is
# not a Bot API response at all is an error too, rather than a NULL
# that every caller would then have to index into.
telegram_call <- function(client, method, params = list(), files = NULL) {
    res <- client$api_fn(method, telegram_form(params), files)
    if (!is.list(res) || is.null(res$ok)) {
        stop("chat.api: Telegram ", method, " returned no usable answer.",
             call. = FALSE)
    }
    if (!isTRUE(res$ok)) {
        stop("chat.api: Telegram refused ", method, ": ",
             res$description %||% "no description given", call. = FALSE)
    }
    res$result
}

#' Render contract markup for Telegram
#'
#' HTML parse mode is the target. MarkdownV2 requires a dozen ordinary
#' characters to be escaped in prose, and legacy Markdown swallows the
#' underscores in identifiers; HTML needs only the three escapes and
#' accepts the tags the contract's markdown maps to. plain sends the
#' text untouched with no parse_mode, the one mode where nothing needs
#' escaping. A supplied \code{rich} fragment is already HTML and wins.
#' @noRd
telegram_render <- function(text, markup, rich = NULL) {
    if (!is.null(rich)) {
        return(list(text = rich, parse_mode = "HTML"))
    }
    if (!identical(markup, "markdown")) {
        return(list(text = text, parse_mode = NULL))
    }
    list(text = telegram_markdown_html(text), parse_mode = "HTML")
}

telegram_escape_html <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
}

# The same handful of constructs slack_render() translates, plus code.
# Fenced blocks are split out first so nothing inside one is styled,
# and a language tag on the opening fence is dropped rather than
# printed as the block's first line.
telegram_markdown_html <- function(text) {
    parts <- strsplit(text, "```", fixed = TRUE)[[1L]]
    out <- character(length(parts))
    for (i in seq_along(parts)) {
        p <- parts[[i]]
        if (i %% 2L == 0L) {
            p <- sub("^[[:alnum:]_+-]*\n", "", p)
            p <- sub("\n$", "", p)
            out[[i]] <- paste0("<pre>", telegram_escape_html(p), "</pre>")
            next
        }
        p <- telegram_escape_html(p)
        p <- gsub("`([^`]+)`", "<code>\\1</code>", p)
        p <- gsub("\\[([^]]+)\\]\\(([^)]+)\\)", "<a href=\"\\2\">\\1</a>", p)
        p <- gsub("\\*\\*([^*]+)\\*\\*", "<b>\\1</b>", p)
        p <- gsub("\\*([^*]+)\\*", "<i>\\1</i>", p)
        # Underscores inside a word are identifiers, not emphasis.
        p <- gsub("(^|[^[:alnum:]_])_([^_]+)_(?![[:alnum:]_])",
                  "\\1<i>\\2</i>", p, perl = TRUE)
        out[[i]] <- p
    }
    paste(out, collapse = "")
}

#' @export
chat_poll.chat_telegram <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since)) {
        client$env$cursor <- telegram_chr(since)
    }
    updates <- telegram_call(client, "getUpdates", list(
            offset = client$env$cursor,
            timeout = as.integer(timeout %||% client$timeout),
            allowed_updates = telegram_json_array(telegram_update_kinds)))
    # For `self`. Telegram does not echo a bot's own sends through
    # getUpdates, so the comparison is belt and braces; what matters
    # is that an unknown identity reports NULL rather than FALSE.
    self_id <- telegram_self_id(client)
    messages <- list()
    reactions <- list()
    last <- NULL
    for (u in updates) {
        uid <- u$update_id
        if (is.numeric(uid) && (is.null(last) || uid > last)) {
            last <- uid
        }
        rec <- telegram_message(u$message %||% u$channel_post, self_id)
        if (!is.null(rec)) {
            messages[[length(messages) + 1L]] <- rec
        }
        for (r in telegram_reaction_records(u$message_reaction, self_id)) {
            reactions[[length(reactions) + 1L]] <- r
        }
    }
    # The cursor is the next offset: handing it back confirms
    # everything up to and including the last update seen, which is
    # the only way Telegram has of being told.
    if (!is.null(last)) {
        client$env$cursor <- sprintf("%.0f", last + 1)
    }
    list(messages = messages, cursor = client$env$cursor,
         reactions = reactions, raw = updates)
}

telegram_self_id <- function(client) {
    who <- tryCatch(chat_whoami(client), error = function(e) NULL)
    if (is.null(who)) {
        NULL
    } else {
        who$id
    }
}

# A message, or NULL for a service message (someone joined, a pin, a
# title change). Those carry neither text nor media and are not
# conversation; a consumer replying to one would be talking to a
# system notice.
telegram_message <- function(m, self_id) {
    if (is.null(m)) {
        return(NULL)
    }
    body <- m$text %||% m$caption
    att <- telegram_attachment(m)
    if (is.null(body) && is.null(att)) {
        return(NULL)
    }
    if (is.null(body)) {
        # The filename, as Matrix does: what a client that cannot
        # show the picture shows. A photo has none, and stays "".
        body <- if (is.na(att$name)) "" else att$name
    }
    # sender_chat first: a channel post has no `from`, and an
    # anonymous group admin's `from` is Telegram's placeholder bot
    # while sender_chat is the group they speak for.
    sender <- telegram_chr(m$sender_chat$id %||% m$from$id) %||% ""
    chat_message(id = telegram_chr(m$message_id),
                 channel = telegram_chr(m$chat$id),
                 sender = sender,
                 body = as.character(body),
                 ts = telegram_time(m$date),
                 thread = telegram_chr(m$message_thread_id),
                 markup = "plain", kind = "message",
                 self = if (is.null(self_id)) NULL else
                 identical(sender, self_id),
                 mentions = telegram_mentions(m),
                 attachments = if (is.null(att)) NULL else list(att),
                 raw = m)
}

# Declared mentions: text_mention entities, which carry a user object
# for people without a username. An @username mention is text, and
# chat_addressed() reads it there.
telegram_mentions <- function(m) {
    ents <- c(m$entities, m$caption_entities)
    ids <- character()
    for (e in ents) {
        if (identical(e$type, "text_mention") && !is.null(e$user$id)) {
            ids <- c(ids, telegram_chr(e$user$id))
        }
    }
    if (length(ids)) ids else NULL
}

telegram_media_kinds <- c("document", "audio", "video", "voice",
                          "animation", "sticker", "video_note")

# The one attachment a Telegram message can carry, as a record. url is
# left NA on purpose: the fetchable location comes from getFile, is
# temporary, and embeds the bot token, so it is not something to put on
# a record that consumers pass around.
telegram_attachment <- function(m) {
    if (length(m$photo)) {
        # Every size of the same picture, smallest first.
        p <- m$photo[[length(m$photo)]]
        return(chat_attachment(id = as.character(p$file_id),
                               bytes = telegram_int(p$file_size), raw = p))
    }
    for (kind in telegram_media_kinds) {
        x <- m[[kind]]
        if (!is.null(x) && !is.null(x$file_id)) {
            return(chat_attachment(id = as.character(x$file_id),
                                   name = x$file_name %||% NA_character_,
                                   mime = x$mime_type %||% NA_character_,
                                   bytes = telegram_int(x$file_size),
                                   raw = x))
        }
    }
    NULL
}

telegram_reaction_key <- function(x) {
    switch(x$type %||% "", emoji = x$emoji, custom_emoji = x$custom_emoji_id,
           paid = "paid", NULL)
}

# One record per reaction added. Telegram reports the whole before and
# after set of one user's reactions on one message, so an addition is
# what is in the new set and not the old; a removal has no shape in
# the contract and is not reported.
telegram_reaction_records <- function(r, self_id) {
    if (is.null(r)) {
        return(list())
    }
    old <- unlist(lapply(r$old_reaction, telegram_reaction_key))
    new <- unlist(lapply(r$new_reaction, telegram_reaction_key))
    added <- setdiff(new, old)
    sender <- telegram_chr(r$user$id %||% r$actor_chat$id) %||% ""
    lapply(added, function(k) {
        chat_reaction(id = NULL, channel = telegram_chr(r$chat$id),
                      sender = sender, target = telegram_chr(r$message_id),
                      key = as.character(k), ts = telegram_time(r$date),
                      self = if (is.null(self_id)) NULL else
                      identical(sender, self_id),
                      raw = r)
    })
}

#' @export
chat_send.chat_telegram <- function(client, channel, text,
                                    markup = c("plain", "markdown"),
                                    thread = NULL, reply_to = NULL,
                                    identity = NULL, files = NULL,
                                    kind = "message", notify = TRUE,
                                    rich = NULL, ...) {
    markup <- match.arg(markup)
    # identity is ignored: a bot posts as itself and Telegram has no
    # per-message override, which identity_override = FALSE says. kind
    # too: there is no notice or emote, only messages.
    where <- list(chat_id = telegram_chr(channel),
                  message_thread_id = telegram_chr(thread),
                  reply_parameters = if (is.null(reply_to)) NULL else
                  sprintf('{"message_id":%s}', telegram_chr(reply_to)),
                  disable_notification = if (isTRUE(notify)) NULL else TRUE)
    ids <- character()
    # Each file is its own message, then the text, the order Matrix
    # sends in. A missing file errors before anything goes out.
    for (f in files) {
        if (!file.exists(f)) {
            stop("chat_send(): no such file: ", f, call. = FALSE)
        }
    }
    for (f in files) {
        sent <- telegram_call(client, "sendDocument", where,
                              files = list(document = f))
        ids <- c(ids, telegram_chr(sent$message_id))
    }
    # Telegram refuses an empty text, so a send that was only files
    # stops here. Empty with no files still goes out and is refused,
    # which is the right report for that.
    if (nzchar(text) || !length(files)) {
        r <- telegram_render(text, markup, rich)
        sent <- telegram_call(client, "sendMessage",
                              c(where, list(text = r$text, parse_mode = r$parse_mode)))
        ids <- c(ids, telegram_chr(sent$message_id))
    }
    invisible(ids)
}

#' @export
chat_edit.chat_telegram <- function(client, channel, message_id, text,
                                    markup = c("plain", "markdown"),
                                    rich = NULL, kind = "message", ...) {
    markup <- match.arg(markup)
    r <- telegram_render(text, markup, rich)
    telegram_call(client, "editMessageText",
                  list(chat_id = telegram_chr(channel),
                       message_id = telegram_chr(message_id), text = r$text,
                       parse_mode = r$parse_mode))
    # Edited in place, as Slack: the identifier is the one that went in.
    invisible(as.character(message_id))
}

telegram_reaction_json <- function(key) {
    if (!nzchar(key)) {
        return("[]")
    }
    sprintf('[{"type":"emoji","emoji":"%s"}]', telegram_json_string(key))
}

#' @export
chat_react.chat_telegram <- function(client, channel, message_id, key, ...) {
    # An emoji character, passed through as the contract says. Telegram
    # accepts a fixed set and refuses the rest, and that refusal
    # propagates. An empty key clears the bot's reactions on the
    # message, which is the only way the API has of taking one back.
    telegram_call(client, "setMessageReaction",
                  list(chat_id = telegram_chr(channel),
                       message_id = telegram_chr(message_id),
                       reaction = telegram_reaction_json(key)))
    # No id: setMessageReaction answers True.
    invisible(TRUE)
}

#' @export
chat_typing.chat_telegram <- function(client, channel, on = TRUE, ...) {
    # There is no "stopped typing": the indicator expires on its own
    # after a few seconds or when a message arrives, so on = FALSE has
    # nothing to send and says so.
    if (!isTRUE(on)) {
        return(invisible(FALSE))
    }
    ok <- tryCatch({
        telegram_call(client, "sendChatAction",
                      list(chat_id = telegram_chr(channel), action = "typing"))
        TRUE
    }, error = function(e) FALSE)
    invisible(ok)
}

#' @export
chat_channel_info.chat_telegram <- function(client, channel, ...) {
    ch <- telegram_call(client, "getChat",
                        list(chat_id = telegram_chr(channel)))
    blank <- function(x) {
        if (is.null(x) || !length(x) || !nzchar(as.character(x)[[1L]])) {
            NULL
        } else {
            as.character(x)[[1L]]
        }
    }
    name <- blank(ch$title)
    if (is.null(name)) {
        # A private chat has no title. The other party's name is what
        # a human would call the conversation.
        person <- trimws(paste(c(ch$first_name, ch$last_name), collapse = " "))
        name <- blank(person) %||% blank(ch$username)
    }
    list(id = telegram_chr(ch$id) %||% telegram_chr(channel),
         name = name, topic = blank(ch$description))
}

#' @export
chat_leave.chat_telegram <- function(client, channel, ...) {
    # Errors propagate: a leave that quietly failed keeps delivering a
    # chat the caller believes it has left.
    telegram_call(client, "leaveChat", list(chat_id = telegram_chr(channel)))
    invisible(as.character(channel))
}

#' @export
chat_resolve.chat_telegram <- function(client, name, ...) {
    name <- as.character(name)
    # Already an id. Everything else is a public username, which getChat
    # takes with its @ and answers with the numeric id.
    if (grepl("^-?[0-9]+$", name)) {
        return(name)
    }
    handle <- if (startsWith(name, "@")) name else paste0("@", name)
    ch <- telegram_call(client, "getChat", list(chat_id = handle))
    id <- telegram_chr(ch$id)
    if (is.null(id)) {
        stop("chat.api: Telegram getChat returned no id for ", handle, ".",
             call. = FALSE)
    }
    id
}

#' @export
chat_capabilities.chat_telegram <- function(client, ...) {
    list(threads = TRUE, thread_replies = TRUE, edits = TRUE,
         # Reaction events arrive only where the bot is an
         # administrator, or in a private chat. The flag says the
         # poll can carry them, which it can; the group setting is
         # the consumer's to arrange.
         reactions = TRUE, reaction_events = TRUE, channel_info = TRUE,
         # The Bot API has no member list, only a count and the
         # administrators, and a list of admins is not a room.
         members = FALSE,
         # A bot is added to a chat by a member. Nothing arrives to
         # accept, and there is no call by which it could join.
         invites = FALSE, join = FALSE, whoami = TRUE,
         # No history, no list of chats, no read markers in the Bot
         # API. The chats a bot is in are whatever sends it updates.
         channels = FALSE, history = FALSE, pending = FALSE,
         mark_read = FALSE, set_identity = TRUE, relogin = FALSE,
         channel_create = FALSE, leave = TRUE, set_state = FALSE,
         files = TRUE, attachments = TRUE, typing = TRUE, e2ee = FALSE,
         identity_override = FALSE, user_identity = FALSE,
         rich_markup = "html",
         markup_dialects = c("plain", "markdown"),
         # 4096 characters after entities parsing. Characters, not
         # bytes, so a message of multibyte text hits it sooner than
         # the number suggests.
         max_message_bytes = 4096L)
}

#' @export
chat_whoami.chat_telegram <- function(client, ...) {
    # Cached for the client's lifetime, as Slack: the answer is a
    # property of the token, and chat_addressed() asks once per message.
    if (!is.null(client$env$whoami)) {
        return(client$env$whoami)
    }
    me <- telegram_call(client, "getMe")
    id <- telegram_chr(me$id)
    if (is.null(id) || !nzchar(id)) {
        stop("chat.api: Telegram getMe returned no id.", call. = FALSE)
    }
    # The username is the display: it is what a mention is written as.
    who <- chat_identity(id, display = me$username %||% me$first_name %||%
                         NA_character_, raw = me)
    client$env$whoami <- who
    who
}

#' @export
chat_addressed.chat_telegram <- function(client, message, ...) {
    who <- chat_whoami(client)
    if (identity_mentioned(who$id, message)) {
        return(TRUE)
    }
    # A private chat is a conversation with the bot. Everything in it
    # is for the bot; there is no one else it could be for.
    if (identical(message$raw$chat$type, "private")) {
        return(TRUE)
    }
    # A reply to something the bot said.
    if (identical(telegram_chr(message$raw$reply_to_message$from$id), who$id)) {
        return(TRUE)
    }
    # @username stays in the text on Telegram, unlike Slack, so this is
    # a literal match on the handle -- bounded, so @bot is not @bots.
    user <- who$raw$username
    if (is.null(user) || !nzchar(user)) {
        return(FALSE)
    }
    body <- message$body %||% ""
    nzchar(body) && grepl(sprintf("(^|[^[:alnum:]_])@%s(?![[:alnum:]_])",
                                  escape_rx(user)),
                          body, ignore.case = TRUE, perl = TRUE)
}

#' @export
chat_set_identity.chat_telegram <- function(client, display, ...) {
    # setMyName changes the bot's name, not its username: the handle
    # people address it by is fixed at BotFather. The cached identity
    # carried the old display and is now wrong.
    telegram_call(client, "setMyName", list(name = display))
    client$env$whoami <- NULL
    invisible(TRUE)
}

#' @export
chat_download.chat_telegram <- function(client, attachment, dest = NULL, ...) {
    got <- telegram_call(client, "getFile", list(file_id = attachment$id))
    path <- got$file_path
    if (is.null(path) || !nzchar(path)) {
        stop("chat.api: Telegram getFile returned no file_path for ",
             attachment$id, ". Files over 20 MB cannot be fetched ",
             "through the Bot API.", call. = FALSE)
    }
    if (is.null(dest)) {
        # A photo carries no filename, but the path getFile hands back
        # has an extension, and the temporary file should too.
        named <- attachment
        if (is.na(named$name)) {
            named$name <- basename(path)
        }
        dest <- attachment_dest(named, NULL)
    }
    # Errors propagate, chat_react()'s reasoning: a fetch that quietly
    # failed leaves the caller pointing at a path with no bytes.
    client$download_fn(attachment$id, path, dest)
    invisible(dest)
}
