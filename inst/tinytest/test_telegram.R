# Telegram adapter verification. No bot token in CI, so this pins the
# adapter to httr's installed signatures (API-drift detection) and
# exercises every verb through the .api seam, asserting on the wire
# shape each Bot API method receives. Live traffic needs
# TELEGRAM_BOT_TOKEN.

`%||%` <- function(a, b) if (is.null(a)) b else a

if (requireNamespace("httr", quietly = TRUE)) {
    # Every httr entry point the HTTP layer uses, by the arguments it
    # passes. The seam can be wrong in the same direction as the code;
    # only the installed package settles it.
    expect_true(all(c("url", "body", "encode") %in% names(formals(httr::POST))))
    expect_true(all(c("url", "config") %in% names(formals(httr::GET))))
    expect_true(all(c("x", "as", "type") %in% names(formals(httr::content))))
    expect_true("path" %in% names(formals(httr::upload_file)))
    expect_true(all(c("path", "overwrite") %in% names(formals(httr::write_disk))))
    expect_true("seconds" %in% names(formals(httr::timeout)))
    expect_true("x" %in% names(formals(httr::status_code)))

    # Constructor: refuses to build without a token
    expect_error(chat_telegram(token = ""), pattern = "token")
    cl <- chat_telegram(token = "123:fake")
    expect_true(inherits(cl, "chat_client"))
    expect_true(inherits(cl, "chat_telegram"))
    expect_identical(cl$timeout, 30L)
    expect_identical(cl$api_url, "https://api.telegram.org")
    # A trailing slash on a local Bot API server does not double up.
    expect_identical(chat_telegram(token = "t",
                                   api_url = "http://localhost:8081/")$api_url,
                     "http://localhost:8081")
}

# ---- Seams ----
# A client that needs neither httr nor the network. The download seam
# defaults to a no-op that reports the destination it was handed.
tg_client <- function(api, download = function(file_id, file_path, dest) dest,
                      ...) {
    chat_telegram(token = "123:fake", .api = api, .download = download, ...)
}

# A seam that records every call and answers from a table keyed by
# method: a static response, or a function of (params, files).
tg_scripted <- function(answers) {
    calls <- list()
    api <- function(method, params = list(), files = NULL) {
        calls[[length(calls) + 1L]] <<- list(method = method, params = params,
                                             files = files)
        a <- answers[[method]]
        if (is.function(a)) {
            a(params, files)
        } else {
            a %||% list(ok = TRUE, result = TRUE)
        }
    }
    list(api = api, calls = function() calls,
         of = function(method) Filter(function(x) x$method == method, calls))
}

me_ok <- list(ok = TRUE, result = list(id = 999, is_bot = TRUE,
                                       first_name = "Corteza",
                                       username = "corteza_bot"))

# ---- Capabilities are honest ----
local({
    caps <- chat_capabilities(tg_client(function(...) NULL))
    expect_true(caps$threads)
    expect_true(caps$thread_replies)
    expect_true(caps$edits)
    expect_true(caps$reactions)
    expect_true(caps$reaction_events)
    expect_true(caps$channel_info)
    expect_true(caps$whoami)
    expect_true(caps$set_identity)
    expect_true(caps$leave)
    expect_true(caps$files)
    expect_true(caps$attachments)
    expect_true(caps$typing)
    expect_false(caps$members)
    expect_false(caps$invites)
    expect_false(caps$join)
    expect_false(caps$channels)
    expect_false(caps$history)
    expect_false(caps$pending)
    expect_false(caps$mark_read)
    expect_false(caps$channel_create)
    expect_false(caps$set_state)
    expect_false(caps$e2ee)
    expect_false(caps$identity_override)
    expect_identical(caps$rich_markup, "html")
    expect_identical(caps$markup_dialects, c("plain", "markdown"))
    expect_identical(caps$max_message_bytes, 4096L)
})

# The verbs the flags say are missing refuse rather than pretend, and
# the quiet ones stay quiet.
local({
    cl <- tg_client(function(...) stop("no call expected"))
    expect_error(chat_members(cl, "5"), "not supported by this adapter")
    expect_error(chat_channels(cl), "not supported by this adapter")
    expect_error(chat_history(cl, "5"), "not supported by this adapter")
    expect_error(chat_join(cl, "5"), "not supported by this adapter")
    expect_error(chat_channel_create(cl, "x"), "not supported by this adapter")
    expect_error(chat_pending(cl), "not supported by this adapter")
    expect_error(chat_set_state(cl, "5", "t", list()),
                 "not supported by this adapter")
    expect_false(chat_mark_read(cl, "5", "7"))
    expect_true(chat_disconnect(cl))
})

# ---- Pure helpers ----
# Ids never go through as.character() on a double: R writes 100000 as
# "1e+05", and a chat id at a round number would never match itself.
expect_identical(chat.api:::telegram_chr(100000), "100000")
expect_identical(chat.api:::telegram_chr(-1001234567890), "-1001234567890")
expect_identical(chat.api:::telegram_chr(42L), "42")
expect_identical(chat.api:::telegram_chr("abc"), "abc")
expect_null(chat.api:::telegram_chr(NULL))

# Wire form: NULLs dropped, logicals lowercase, numbers as digits.
expect_identical(chat.api:::telegram_form(list(a = NULL, b = TRUE, c = FALSE,
                                               d = 100000, e = "x")),
                 list(b = "true", c = "false", d = "100000", e = "x"))
expect_identical(chat.api:::telegram_form(list()), list())
expect_identical(chat.api:::telegram_json_array(c("a", 'b"c')),
                 '["a","b\\"c"]')
expect_identical(chat.api:::telegram_reaction_json("\U0001F44D"),
                 '[{"type":"emoji","emoji":"\U0001F44D"}]')
expect_identical(chat.api:::telegram_reaction_json(""), "[]")

# Rendering: plain is untouched with no parse_mode, the one mode where
# nothing needs escaping.
expect_identical(chat.api:::telegram_render("a < b & *c*", "plain"),
                 list(text = "a < b & *c*", parse_mode = NULL))
# markdown becomes Telegram's HTML subset, escaped first.
local({
    r <- chat.api:::telegram_render(
        "**bold** and *it* and `x < y` and [d](https://x.y) and chat_send_now and _em_",
        "markdown")
    expect_identical(r$parse_mode, "HTML")
    expect_identical(r$text, paste0(
        "<b>bold</b> and <i>it</i> and <code>x &lt; y</code> and ",
        "<a href=\"https://x.y\">d</a> and chat_send_now and <i>em</i>"))
})
# Fenced code is escaped and left unstyled; the language tag goes.
expect_identical(chat.api:::telegram_markdown_html(
    "see\n```r\nx <- 1 * 2\n```\ndone **ok**"),
    "see\n<pre>x &lt;- 1 * 2</pre>\ndone <b>ok</b>")
# A supplied rich fragment is already HTML and wins.
expect_identical(chat.api:::telegram_render("plain", "plain",
                                            rich = "<b>hi</b>"),
                 list(text = "<b>hi</b>", parse_mode = "HTML"))

# ---- Polling ----
tg_msg <- function(message_id, text = NULL, chat_id = -100123,
                   type = "supergroup", from = 42, date = 1700000000, ...) {
    m <- list(message_id = message_id, chat = list(id = chat_id, type = type),
              from = list(id = from), date = date)
    if (!is.null(text)) {
        m$text <- text
    }
    c(m, list(...))
}

# First poll: no offset, the configured wait, the update kinds asked
# for explicitly. Service messages are skipped, channel posts carry
# the channel as sender, and the cursor is the next offset.
local({
    s <- tg_scripted(list(
        getMe = me_ok,
        getUpdates = function(params, files) {
            if (is.null(params$offset)) {
                list(ok = TRUE, result = list(
                    list(update_id = 100000,
                         message = tg_msg(7, "hello")),
                    list(update_id = 100001,
                         message = tg_msg(8, date = 1700000001,
                                          new_chat_members = list(list(id = 999)))),
                    list(update_id = 100002,
                         channel_post = list(message_id = 9,
                                             chat = list(id = -100999, type = "channel"),
                                             sender_chat = list(id = -100999),
                                             date = 1700000002,
                                             text = "announcement",
                                             message_thread_id = 5))))
            } else {
                list(ok = TRUE, result = list())
            }
        }))
    cl <- tg_client(s$api, timeout = 7L)
    p1 <- chat_poll(cl)
    gu <- s$calls()[[1L]]
    expect_identical(gu$method, "getUpdates")
    expect_null(gu$params$offset)
    expect_identical(gu$params$timeout, "7")
    expect_identical(gu$params$allowed_updates,
                     '["message","channel_post","message_reaction"]')
    expect_null(gu$files)

    expect_identical(length(p1$messages), 2L)
    m <- p1$messages[[1L]]
    expect_inherits(m, "chat_message")
    expect_identical(m$id, "7")
    expect_identical(m$channel, "-100123")
    expect_identical(m$sender, "42")
    expect_identical(m$body, "hello")
    expect_identical(as.numeric(m$ts), 1700000000)
    expect_null(m$thread)
    expect_false(m$self)
    expect_identical(m$markup, "plain")
    expect_identical(m$kind, "message")
    expect_null(m$attachments)
    expect_identical(m$raw$message_id, 7)
    m2 <- p1$messages[[2L]]
    expect_identical(m2$id, "9")
    expect_identical(m2$channel, "-100999")
    expect_identical(m2$sender, "-100999")
    expect_identical(m2$thread, "5")
    expect_identical(p1$cursor, "100003")
    expect_identical(p1$reactions, list())
    expect_identical(length(p1$raw), 3L)

    # The second poll confirms: the offset is the cursor. An empty
    # answer leaves it where it was.
    p2 <- chat_poll(cl, timeout = 0)
    gu2 <- s$of("getUpdates")[[2L]]
    expect_identical(gu2$params$offset, "100003")
    expect_identical(gu2$params$timeout, "0")
    expect_identical(p2$messages, list())
    expect_identical(p2$cursor, "100003")
    # getMe once per client, not once per poll.
    expect_identical(length(s$of("getMe")), 1L)
})

# since overrides the live cursor, and a numeric one is not written in
# scientific notation.
local({
    s <- tg_scripted(list(getMe = me_ok,
                          getUpdates = list(ok = TRUE, result = list())))
    cl <- tg_client(s$api)
    chat_poll(cl, since = "555")
    chat_poll(cl, since = 100000)
    expect_identical(s$of("getUpdates")[[1L]]$params$offset, "555")
    expect_identical(s$of("getUpdates")[[2L]]$params$offset, "100000")
})

# self: a message from the bot's own id is flagged, and an identity
# the adapter could not fetch reports NULL, which is "cannot tell"
# rather than "not me".
local({
    upd <- list(ok = TRUE, result = list(
        list(update_id = 1, message = tg_msg(1, "x", from = 999)),
        list(update_id = 2, message = tg_msg(2, "y", from = 42))))
    s <- tg_scripted(list(getMe = me_ok, getUpdates = upd))
    got <- chat_poll(tg_client(s$api))$messages
    expect_true(got[[1L]]$self)
    expect_false(got[[2L]]$self)

    s2 <- tg_scripted(list(getMe = list(ok = FALSE, description = "Unauthorized"),
                           getUpdates = upd))
    got2 <- chat_poll(tg_client(s2$api))$messages
    expect_null(got2[[1L]]$self)
    expect_null(got2[[2L]]$self)
})

# A transport failure or a refusal propagates rather than reading as a
# quiet poll. Telegram says no in the body with {ok: false}.
expect_error(chat_poll(tg_client(function(...) stop("connection reset"))),
             "connection reset")
expect_error(chat_poll(tg_client(function(...) {
    list(ok = FALSE, description = "Unauthorized")
})), "Telegram refused getUpdates: Unauthorized")
expect_error(chat_poll(tg_client(function(...) list(ok = FALSE))),
             "no description given")
expect_error(chat_poll(tg_client(function(...) NULL)), "no usable answer")

# Declared mentions are text_mention entities (a user object, for
# people without a handle). An @username stays in the text.
local({
    s <- tg_scripted(list(getMe = me_ok, getUpdates = list(ok = TRUE, result = list(
        list(update_id = 1, message = tg_msg(
            1, "hi Bob and @corteza_bot",
            entities = list(
                list(type = "text_mention", offset = 3, length = 3,
                     user = list(id = 100000)),
                list(type = "mention", offset = 11, length = 12))))))))
    cl <- tg_client(s$api)
    m <- chat_poll(cl)$messages[[1L]]
    expect_identical(m$mentions, "100000")
    expect_true(chat_addressed(cl, m))
})

# ---- Inbound media ----
# A photo is every size of one picture, largest last; a document
# carries its own name and type. url stays NA: the fetchable location
# comes from getFile and embeds the token.
local({
    s <- tg_scripted(list(getMe = me_ok, getUpdates = list(ok = TRUE, result = list(
        list(update_id = 1, message = tg_msg(
            1, chat_id = 5, type = "private", caption = "see plot",
            photo = list(list(file_id = "small", file_size = 100),
                         list(file_id = "big", file_size = 5000)))),
        list(update_id = 2, message = tg_msg(
            2, chat_id = 5, type = "private",
            document = list(file_id = "doc1", file_name = "report.pdf",
                            mime_type = "application/pdf", file_size = 2048))),
        list(update_id = 3, message = tg_msg(
            3, chat_id = 5, type = "private",
            sticker = list(file_id = "stk")))))))
    got <- chat_poll(tg_client(s$api))$messages
    expect_identical(length(got), 3L)
    a1 <- got[[1L]]$attachments[[1L]]
    expect_inherits(a1, "chat_attachment")
    expect_identical(a1$id, "big")
    expect_identical(a1$bytes, 5000L)
    expect_true(is.na(a1$name))
    expect_true(is.na(a1$mime))
    expect_true(is.na(a1$url))
    expect_identical(got[[1L]]$body, "see plot")
    a2 <- got[[2L]]$attachments[[1L]]
    expect_identical(a2$id, "doc1")
    expect_identical(a2$name, "report.pdf")
    expect_identical(a2$mime, "application/pdf")
    expect_identical(a2$bytes, 2048L)
    # The filename stands in for a body, as on Matrix; a sticker has
    # neither and stays "".
    expect_identical(got[[2L]]$body, "report.pdf")
    expect_identical(got[[3L]]$body, "")
    expect_identical(got[[3L]]$attachments[[1L]]$id, "stk")
})

# Fetching: getFile names the path, the download seam gets the path
# and never the token, and a record with no name takes its extension
# from that path.
local({
    fetched <- NULL
    s <- tg_scripted(list(getFile = function(params, files) {
        list(ok = TRUE, result = list(file_id = params$file_id,
                                      file_path = "photos/file_1.jpg"))
    }))
    cl <- tg_client(s$api, download = function(file_id, file_path, dest) {
        fetched <<- list(file_id = file_id, file_path = file_path,
                         dest = dest)
        writeBin(as.raw(1:4), dest)
        dest
    })
    att <- chat_attachment("big")
    dest <- chat_download(cl, att)
    expect_identical(s$calls()[[1L]]$params$file_id, "big")
    expect_identical(fetched$file_id, "big")
    expect_identical(fetched$file_path, "photos/file_1.jpg")
    expect_identical(fetched$dest, dest)
    expect_true(grepl("[.]jpg$", dest))
    expect_true(file.exists(dest))
    expect_false(grepl("fake", fetched$file_path, fixed = TRUE))
    # An explicit destination is honoured, and a record's own name
    # decides the extension when it has one.
    d2 <- tempfile(fileext = ".bin")
    expect_identical(chat_download(cl, att, d2), d2)
    expect_true(grepl("[.]pdf$", chat_download(cl, chat_attachment(
        "doc1", name = "report.pdf"))))
})
# No file_path is what Telegram answers for a file the Bot API will not
# serve, and a refusal propagates either way.
expect_error(chat_download(tg_client(function(...) {
    list(ok = TRUE, result = list(file_id = "x"))
}), chat_attachment("x")), "no file_path")
expect_error(chat_download(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: file is too big")
}), chat_attachment("x")), "file is too big")

# ---- Sending ----
local({
    s <- tg_scripted(list(sendMessage = function(params, files) {
        list(ok = TRUE, result = list(message_id = 77, chat = list(id = -100123)))
    }))
    cl <- tg_client(s$api)
    # Plain goes out untouched with no parse_mode and nothing else.
    expect_identical(chat_send(cl, "-100123", "keep *this* literal"), "77")
    c1 <- s$calls()[[1L]]
    expect_identical(c1$method, "sendMessage")
    expect_identical(c1$params, list(chat_id = "-100123",
                                     text = "keep *this* literal"))
    expect_null(c1$files)
    # markdown is rendered to HTML and says so.
    chat_send(cl, "-100123", "**bold** [x](https://y)", markup = "markdown")
    p2 <- s$calls()[[2L]]$params
    expect_identical(p2$parse_mode, "HTML")
    expect_identical(p2$text, "<b>bold</b> <a href=\"https://y\">x</a>")
    # rich wins over text and goes out as HTML.
    chat_send(cl, "-100123", "fallback", rich = "<i>real</i>")
    expect_identical(s$calls()[[3L]]$params$text, "<i>real</i>")
    expect_identical(s$calls()[[3L]]$params$parse_mode, "HTML")
    # Thread, reply and silence ride their own parameters.
    chat_send(cl, -100123, "in thread", thread = 5, reply_to = "7",
              notify = FALSE)
    p4 <- s$calls()[[4L]]$params
    expect_identical(p4$chat_id, "-100123")
    expect_identical(p4$message_thread_id, "5")
    expect_identical(p4$reply_parameters, '{"message_id":7}')
    expect_identical(p4$disable_notification, "true")
    # identity is ignored, not refused: identity_override is FALSE.
    chat_send(cl, "-100123", "as gc", identity = list(name = "gc"))
    expect_identical(names(s$calls()[[5L]]$params), c("chat_id", "text"))
})

# Files: one sendDocument per file, then the text, ids in that order,
# every one to the same place. A missing file errors before anything
# goes out, and a files-only send never posts an empty text.
local({
    f <- tempfile(fileext = ".png")
    writeBin(as.raw(1:8), f)
    n <- 0L
    s <- tg_scripted(list(
        sendDocument = function(params, files) {
            n <<- n + 1L
            list(ok = TRUE, result = list(message_id = 10 + n))
        },
        sendMessage = function(params, files) {
            list(ok = TRUE, result = list(message_id = 20))
        }))
    cl <- tg_client(s$api)
    expect_identical(chat_send(cl, "5", "see plot", files = c(f, f), thread = 3),
                     c("11", "12", "20"))
    calls <- s$calls()
    expect_identical(vapply(calls, `[[`, "", "method"),
                     c("sendDocument", "sendDocument", "sendMessage"))
    expect_identical(calls[[1L]]$files, list(document = f))
    expect_identical(calls[[1L]]$params,
                     list(chat_id = "5", message_thread_id = "3"))
    expect_null(calls[[3L]]$files)
    expect_identical(calls[[3L]]$params$message_thread_id, "3")

    expect_identical(chat_send(cl, "5", "", files = f), "13")
    expect_identical(length(s$calls()), 4L)

    before <- length(s$calls())
    expect_error(chat_send(cl, "5", "x",
                           files = c(f, file.path(tempdir(), "nope.png"))),
                 "no such file")
    expect_identical(length(s$calls()), before)
})

# A refusal is an error, not a message id.
expect_error(chat_send(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: chat not found")
}), "1", "x"), "Telegram refused sendMessage: Bad Request: chat not found")

# ---- Edits ----
local({
    s <- tg_scripted(list(editMessageText = list(
        ok = TRUE, result = list(message_id = 7))))
    cl <- tg_client(s$api)
    expect_identical(chat_edit(cl, "5", "7", "done"), "7")
    expect_identical(s$calls()[[1L]]$method, "editMessageText")
    expect_identical(s$calls()[[1L]]$params,
                     list(chat_id = "5", message_id = "7", text = "done"))
    chat_edit(cl, "5", "7", "**done**", markup = "markdown")
    expect_identical(s$calls()[[2L]]$params$text, "<b>done</b>")
    expect_identical(s$calls()[[2L]]$params$parse_mode, "HTML")
})
expect_error(chat_edit(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: message can't be edited")
}), "5", "7", "x"), "can't be edited")

# ---- Reactions ----
local({
    s <- tg_scripted(list(setMessageReaction = list(ok = TRUE, result = TRUE)))
    cl <- tg_client(s$api)
    expect_true(chat_react(cl, "5", "7", "\U0001F44D"))
    expect_identical(s$calls()[[1L]]$method, "setMessageReaction")
    expect_identical(s$calls()[[1L]]$params, list(
        chat_id = "5", message_id = "7",
        reaction = '[{"type":"emoji","emoji":"\U0001F44D"}]'))
    # An empty key clears the bot's reaction, the API's only way back.
    chat_react(cl, "5", "7", "")
    expect_identical(s$calls()[[2L]]$params$reaction, "[]")
})
expect_error(chat_react(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: REACTION_INVALID")
}), "5", "7", "x"), "REACTION_INVALID")

# Reaction events: Telegram reports one user's whole before-and-after
# set on one message, so an addition is what is new and not old. A
# removal has no shape in the contract and is not reported.
local({
    thumbs <- list(type = "emoji", emoji = "\U0001F44D")
    react <- function(user, date, old, new) {
        list(chat = list(id = -100123, type = "supergroup"), message_id = 7,
             user = list(id = user), date = date,
             old_reaction = old, new_reaction = new)
    }
    s <- tg_scripted(list(getMe = me_ok, getUpdates = list(ok = TRUE, result = list(
        list(update_id = 1,
             message_reaction = react(42, 1700000005, list(), list(thumbs))),
        list(update_id = 2,
             message_reaction = react(999, 1700000006, list(thumbs),
                                      list(thumbs, list(type = "custom_emoji",
                                                        custom_emoji_id = "c1")))),
        list(update_id = 3,
             message_reaction = react(42, 1700000007, list(thumbs), list()))))))
    got <- chat_poll(tg_client(s$api))
    expect_identical(got$messages, list())
    expect_identical(length(got$reactions), 2L)
    r1 <- got$reactions[[1L]]
    expect_inherits(r1, "chat_reaction")
    expect_null(r1$id)
    expect_identical(r1$channel, "-100123")
    expect_identical(r1$sender, "42")
    expect_identical(r1$target, "7")
    expect_identical(r1$key, "\U0001F44D")
    expect_identical(as.numeric(r1$ts), 1700000005)
    expect_false(r1$self)
    r2 <- got$reactions[[2L]]
    expect_identical(r2$key, "c1")
    expect_true(r2$self)
    expect_identical(got$cursor, "4")
})

# ---- Typing ----
local({
    s <- tg_scripted(list(sendChatAction = list(ok = TRUE, result = TRUE)))
    cl <- tg_client(s$api)
    expect_true(chat_typing(cl, "5", TRUE))
    expect_identical(s$calls()[[1L]]$method, "sendChatAction")
    expect_identical(s$calls()[[1L]]$params, list(chat_id = "5", action = "typing"))
    # There is no "stopped typing" to send.
    expect_false(chat_typing(cl, "5", FALSE))
    expect_identical(length(s$calls()), 1L)
})
# A dropped indicator is a quiet FALSE, chat_typing()'s bargain.
expect_false(chat_typing(tg_client(function(...) stop("down")), "5"))

# ---- Channel info ----
local({
    s <- tg_scripted(list(getChat = list(ok = TRUE, result = list(
        id = -1001234567890, type = "supergroup", title = "lab",
        description = "the lab"))))
    cl <- tg_client(s$api)
    info <- chat_channel_info(cl, "-1001234567890")
    expect_identical(s$calls()[[1L]]$method, "getChat")
    expect_identical(s$calls()[[1L]]$params, list(chat_id = "-1001234567890"))
    expect_identical(info, list(id = "-1001234567890", name = "lab",
                                topic = "the lab"))
})
# A private chat has no title: the other party's name is what a human
# would call it, and no description is NULL, not "".
local({
    cl <- tg_client(function(...) list(ok = TRUE, result = list(
        id = 5, type = "private", first_name = "Ann", last_name = "Lee",
        username = "ann")))
    expect_identical(chat_channel_info(cl, "5"),
                     list(id = "5", name = "Ann Lee", topic = NULL))
})
local({
    cl <- tg_client(function(...) list(ok = TRUE, result = list(
        id = 5, type = "private", username = "ann", description = "")))
    expect_identical(chat_channel_info(cl, "5")$name, "ann")
    expect_null(chat_channel_info(cl, "5")$topic)
})
expect_error(chat_channel_info(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: chat not found")
}), "1"), "chat not found")

# ---- Leaving ----
local({
    s <- tg_scripted(list(leaveChat = list(ok = TRUE, result = TRUE)))
    cl <- tg_client(s$api)
    expect_identical(chat_leave(cl, "-100123"), "-100123")
    expect_identical(s$calls()[[1L]]$method, "leaveChat")
    expect_identical(s$calls()[[1L]]$params, list(chat_id = "-100123"))
})
# A refusal propagates, so a failed leave never reads as a quiet one.
expect_error(chat_leave(tg_client(function(...) {
    list(ok = FALSE, description = "Forbidden: bot is not a member")
}), "1"), "not a member")

# ---- Resolving ----
# An id passes through without a call; a public username goes to
# getChat with its @, whether or not the caller typed one.
local({
    s <- tg_scripted(list(getChat = list(ok = TRUE, result = list(
        id = -1001234567890, type = "supergroup"))))
    cl <- tg_client(s$api)
    expect_identical(chat_resolve(cl, "-100123"), "-100123")
    expect_identical(chat_resolve(cl, "5"), "5")
    expect_identical(length(s$calls()), 0L)
    expect_identical(chat_resolve(cl, "@rstats"), "-1001234567890")
    expect_identical(s$calls()[[1L]]$params, list(chat_id = "@rstats"))
    expect_identical(chat_resolve(cl, "rstats"), "-1001234567890")
    expect_identical(s$calls()[[2L]]$params$chat_id, "@rstats")
})
expect_error(chat_resolve(tg_client(function(...) {
    list(ok = FALSE, description = "Bad Request: chat not found")
}), "@nope"), "chat not found")

# ---- Identity ----
tg_message <- function(body, type = "supergroup", reply_from = NULL,
                       mentions = NULL) {
    raw <- list(chat = list(id = -100123, type = type))
    if (!is.null(reply_from)) {
        raw$reply_to_message <- list(from = list(id = reply_from))
    }
    chat_message(id = "1", channel = "-100123", sender = "42", body = body,
                 ts = Sys.time(), mentions = mentions, raw = raw)
}

local({
    s <- tg_scripted(list(getMe = me_ok))
    cl <- tg_client(s$api)
    who <- chat_whoami(cl)
    expect_inherits(who, "chat_identity")
    expect_identical(who$id, "999")
    # The username is the display: it is what a mention is written as.
    expect_identical(who$display, "corteza_bot")
    expect_identical(s$calls()[[1L]]$method, "getMe")
    # One call per client. chat_addressed() asks on every message.
    chat_whoami(cl)
    expect_identical(length(s$calls()), 1L)

    # @username stays in the text on Telegram, so this is a literal,
    # bounded, case-insensitive match on the handle.
    expect_true(chat_addressed(cl, tg_message("hey @corteza_bot look")))
    expect_true(chat_addressed(cl, tg_message("@Corteza_Bot?")))
    expect_false(chat_addressed(cl, tg_message("hey @corteza_bot2 look")))
    expect_false(chat_addressed(cl, tg_message("mail x@corteza_bot now")))
    expect_false(chat_addressed(cl, tg_message("hey corteza_bot")))
    expect_false(chat_addressed(cl, tg_message("")))
    # A private chat is a conversation with the bot.
    expect_true(chat_addressed(cl, tg_message("anything", type = "private")))
    # A reply to something the bot said.
    expect_true(chat_addressed(cl, tg_message("yes", reply_from = 999)))
    expect_false(chat_addressed(cl, tg_message("yes", reply_from = 42)))
    # Declared mentions still count.
    expect_true(chat_addressed(cl, tg_message("nothing", mentions = "999")))
    expect_identical(length(s$calls()), 1L)
})

# A bot with no username is not addressed by one.
local({
    cl <- tg_client(function(...) list(ok = TRUE, result = list(
        id = 999, is_bot = TRUE, first_name = "Corteza")))
    expect_identical(chat_whoami(cl)$display, "Corteza")
    expect_false(chat_addressed(cl, tg_message("@corteza_bot")))
})

expect_error(chat_whoami(tg_client(function(...) {
    list(ok = FALSE, description = "Unauthorized")
})), "Unauthorized")
expect_error(chat_whoami(tg_client(function(...) {
    list(ok = TRUE, result = list(is_bot = TRUE))
})), "no id")

# set_identity changes the bot's name and drops the cached identity,
# which carried the old one.
local({
    s <- tg_scripted(list(getMe = me_ok,
                          setMyName = list(ok = TRUE, result = TRUE)))
    cl <- tg_client(s$api)
    chat_whoami(cl)
    expect_true(chat_set_identity(cl, "Cornball"))
    expect_identical(s$calls()[[2L]]$method, "setMyName")
    expect_identical(s$calls()[[2L]]$params, list(name = "Cornball"))
    chat_whoami(cl)
    expect_identical(length(s$of("getMe")), 2L)
})
expect_error(chat_set_identity(tg_client(function(...) {
    list(ok = FALSE, description = "Too Many Requests: retry after 3600")
}), "x"), "Too Many Requests")

# ---- Transport over a telegram::TGBot ----
# Only the class's transport is borrowed: its public req() posts a body
# to the method URL with the object's proxy applied and hands back the
# httr response, which is what the direct layer builds for itself. Its
# verbs are not used -- getUpdates() cannot long-poll or choose update
# kinds, its parser flattens updates into data frames, and it has no
# edit, reaction, chat or leave methods.

# Drift detection against the real package. The bindings on a TGBot are
# locked, so behavior is tested on a stand-in below; this pins the two
# members the stand-in imitates.
if (requireNamespace("telegram", quietly = TRUE)) {
    b <- telegram::TGBot$new(token = "123:fake")
    expect_true(is.function(b$req))
    expect_identical(names(formals(b$req)), c("method", "body"))
    expect_true(is.function(b$getFile))
    expect_identical(names(formals(b$getFile)), c("file_id", "destfile"))
    # A real TGBot builds a client with no token of its own.
    cl <- chat_telegram(token = "", bot = b)
    expect_true(inherits(cl, "chat_telegram"))
    expect_identical(cl$bot, b)
}

# What req() hands back, as a seam would build it.
tg_response <- function(json, status = 200L,
                        type = "application/json") {
    structure(list(url = "https://api.telegram.org/bot123:fake/x",
                   status_code = as.integer(status),
                   headers = list("content-type" = type),
                   content = charToRaw(json)),
              class = "response")
}

# A stand-in with the two members the adapter uses, recording calls.
tg_fake_bot <- function(answer, file_url = NULL) {
    calls <- list()
    list(req = function(method, body = NULL) {
             calls[[length(calls) + 1L]] <<- list(method = method, body = body)
             if (is.function(answer)) answer(method, body) else answer
         },
         getFile = function(file_id, destfile = NULL) {
             calls[[length(calls) + 1L]] <<- list(method = "getFile*",
                                                  file_id = file_id,
                                                  destfile = destfile)
             invisible(file_url)
         },
         calls = function() calls)
}

# Something that is not a TGBot is refused at construction, not at the
# first call.
expect_error(chat_telegram(token = "t", bot = list(token = "t")),
             "req\\(method, body\\)")
# And no token with no bot is the same error as before.
expect_error(chat_telegram(token = ""), "TELEGRAM_BOT_TOKEN")

if (requireNamespace("httr", quietly = TRUE)) {
    # Wire form reaches req() as its body: strings, NULLs dropped.
    local({
        bot <- tg_fake_bot(function(method, body) {
            if (identical(method, "getMe")) {
                tg_response('{"ok":true,"result":{"id":999,"is_bot":true,"first_name":"Corteza","username":"corteza_bot"}}')
            } else {
                tg_response('{"ok":true,"result":{"message_id":77}}')
            }
        })
        cl <- chat_telegram(token = "", bot = bot,
                            .download = function(...) NULL)
        who <- chat_whoami(cl)
        expect_identical(who$id, "999")
        expect_identical(bot$calls()[[1L]]$method, "getMe")
        expect_identical(bot$calls()[[1L]]$body, list())
        expect_identical(chat_send(cl, "5", "hi", notify = FALSE), "77")
        sent <- bot$calls()[[2L]]
        expect_identical(sent$method, "sendMessage")
        expect_identical(sent$body, list(chat_id = "5",
                                         disable_notification = "true",
                                         text = "hi"))
    })

    # A file rides the body as an httr upload, next to the fields.
    local({
        f <- tempfile(fileext = ".png")
        writeBin(as.raw(1:4), f)
        bot <- tg_fake_bot(tg_response('{"ok":true,"result":{"message_id":8}}'))
        cl <- chat_telegram(token = "", bot = bot,
                            .download = function(...) NULL)
        expect_identical(chat_send(cl, "5", "", files = f), "8")
        body <- bot$calls()[[1L]]$body
        expect_identical(body$chat_id, "5")
        expect_true(inherits(body$document, "form_file"))
        expect_identical(body$document$path, f)
    })

    # A refusal comes back through the response body with Telegram's
    # description, whatever req() warned on the way.
    local({
        bot <- tg_fake_bot(tg_response(
            '{"ok":false,"error_code":401,"description":"Unauthorized"}',
            status = 401L))
        cl <- chat_telegram(token = "", bot = bot,
                            .download = function(...) NULL)
        expect_error(chat_whoami(cl), "Telegram refused getMe: Unauthorized")
    })
    # A body that is not JSON at all is reported with its status.
    local({
        bot <- tg_fake_bot(tg_response("<html>bad gateway</html>",
                                       status = 502L, type = "text/html"))
        cl <- chat_telegram(token = "", bot = bot,
                            .download = function(...) NULL)
        expect_error(chat_whoami(cl), "answered HTTP 502 with no JSON body")
    })

    # Downloads: the token is private to the class, so the URL comes from
    # its own getFile(), asked without a destfile. The fetch itself is
    # seamed here; the URL it is handed is what matters.
    local({
        got <- NULL
        bot <- tg_fake_bot(NULL,
                           file_url = "https://api.telegram.org/file/bot123:fake/photos/x.jpg")
        dl <- chat.api:::telegram_tgbot_download(bot, fetch = function(url, dest) {
            got <<- list(url = url, dest = dest)
            dest
        })
        d <- tempfile(fileext = ".jpg")
        expect_identical(dl("big", "photos/x.jpg", d), d)
        expect_identical(bot$calls()[[1L]]$file_id, "big")
        expect_null(bot$calls()[[1L]]$destfile)
        expect_identical(got$url,
                         "https://api.telegram.org/file/bot123:fake/photos/x.jpg")
        expect_identical(got$dest, d)
    })
    # The class answers NULL for a file the Bot API will not serve; that
    # is an error here, as on the direct path.
    local({
        bot <- tg_fake_bot(NULL, file_url = NULL)
        dl <- chat.api:::telegram_tgbot_download(bot, fetch = function(...) stop("not reached"))
        expect_error(dl("big", "photos/x.jpg", tempfile()), "served no download URL")
    })
}

# ---- Live, opt-in ----
# A read-only round trip against the real API, only where a token is
# set and only at home. getMe is the cheapest call there is.
if (tinytest::at_home() && nzchar(Sys.getenv("TELEGRAM_BOT_TOKEN")) &&
    requireNamespace("httr", quietly = TRUE)) {
    who <- chat_whoami(chat_telegram())
    expect_true(nzchar(who$id))
    expect_true(isTRUE(who$raw$is_bot))
}
