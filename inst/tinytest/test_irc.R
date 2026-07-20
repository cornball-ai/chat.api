# IRC adapter roundtrip against an in-process fake server
# (serverSocket + socketAccept, R >= 4.0). Skips where binding a
# localhost port is not permitted.

ss <- tryCatch(serverSocket(0L), error = function(e) NULL)
if (!is.null(ss)) {
    port <- summary(ss)$port %||% NULL
    # serverSocket(0) picks an ephemeral port; fall back to a fixed one
    # if the summary does not expose it
    if (is.null(port)) {
        close(ss)
        ss <- tryCatch(serverSocket(48123L), error = function(e) NULL)
        port <- 48123L
    }
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (!is.null(ss)) {
    cl <- chat_irc("127.0.0.1", port, nick = "testbot", channels = "#lab")
    srv <- socketAccept(ss, blocking = FALSE, open = "r+")
    Sys.sleep(0.3)

    # Registration reached the server
    reg <- sub("\r$", "", readLines(srv, warn = FALSE))
    expect_true("NICK testbot" %in% reg)
    expect_true("JOIN #lab" %in% reg)

    # Server PING answered, PRIVMSG surfaced as a chat_message
    writeLines(c("PING :srv\r", ":alice!a@h PRIVMSG #lab :hello bot\r"), srv)
    flush(srv)
    got <- chat_poll(cl, timeout = 2)
    expect_identical(length(got$messages), 1L)
    m <- got$messages[[1L]]
    expect_identical(m$sender, "alice")
    expect_identical(m$channel, "#lab")
    expect_identical(m$body, "hello bot")
    Sys.sleep(0.2)
    expect_true("PONG :srv" %in% sub("\r$", "", readLines(srv, warn = FALSE)))

    # Sends arrive; notices use NOTICE
    chat_send(cl, "#lab", "hi alice")
    chat_send(cl, "#lab", "psst", kind = "notice")
    Sys.sleep(0.2)
    out <- sub("\r$", "", readLines(srv, warn = FALSE))
    expect_true("PRIVMSG #lab :hi alice" %in% out)
    expect_true("NOTICE #lab :psst" %in% out)

    # Capabilities are honest: plain text only, no threads
    caps <- chat_capabilities(cl)
    expect_false(caps$threads)
    expect_identical(caps$markup_dialects, "plain")

    expect_true(chat_disconnect(cl))
    close(srv)
    close(ss)
}

# resolve prefixes bare channel names; needs no connection
offline <- structure(list(), class = c("chat_irc", "chat_client"))
expect_identical(chat_resolve(offline, "lab"), "#lab")
expect_identical(chat_resolve(offline, "#lab"), "#lab")
