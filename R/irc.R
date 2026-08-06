#' @title IRC adapter
#' @description chat.api methods for IRC over base R sockets. Zero
#'   dependencies; plaintext connections only (no TLS in base R).

#' Create an IRC chat client
#'
#' Connects, registers (NICK/USER), and joins \code{channels}. The
#' persistent socket buffers into \code{\link{chat_poll}}: each poll
#' drains available lines, answers server PINGs, and returns PRIVMSGs
#' as normalized messages. The cursor is a message counter.
#'
#' @param host Server hostname.
#' @param port Server port (plaintext; commonly 6667).
#' @param nick Nickname to register.
#' @param channels Character vector of channels to join (e.g.
#'   \code{"#rstats"}).
#' @param realname Real-name field for USER registration.
#' @return A \code{chat_client} of class \code{chat_irc}.
#' @export
chat_irc <- function(host, port = 6667L, nick, channels = character(),
                     realname = nick) {
    con <- socketConnection(host, port = as.integer(port), blocking = FALSE,
                            open = "r+")
    env <- new.env(parent = emptyenv())
    env$con <- con
    env$count <- 0L
    env$pending <- list()

    irc_write(con, sprintf("NICK %s", nick))
    irc_write(con, sprintf("USER %s 0 * :%s", nick, realname))
    for (ch in channels) {
        irc_write(con, sprintf("JOIN %s", ch))
    }

    structure(list(env = env, nick = nick),
              class = c("chat_irc", "chat_client"))
}

#' Write one CRLF-terminated IRC line
#' @noRd
irc_write <- function(con, line) {
    writeLines(paste0(line, "\r"), con, sep = "\n")
    flush(con)
}

#' Parse one raw IRC line into a chat_message, or NULL
#'
#' Handles ":nick!user@host PRIVMSG #chan :text". Anything else returns
#' NULL (numerics, JOIN/PART, and PINGs are handled by the poll loop).
#' @noRd
irc_parse_privmsg <- function(line, id) {
    m <- regmatches(line,
                    regexec("^:([^!\\s]+)[^ ]* PRIVMSG ([^ ]+) :(.*)$", line, perl = TRUE))[[1L]]
    if (length(m) != 4L) {
        return(NULL)
    }
    chat_message(id = as.character(id), channel = m[3L], sender = m[2L],
                 body = sub("\r$", "", m[4L]), ts = Sys.time(),
                 markup = "plain", raw = line)
}

#' @export
chat_poll.chat_irc <- function(client, since = NULL, timeout = NULL, ...) {
    deadline <- Sys.time() + (timeout %||% 0)
    messages <- list()
    repeat {
        lines <- readLines(client$env$con, warn = FALSE)
        for (line in lines) {
            if (startsWith(line, "PING")) {
                irc_write(client$env$con, sub("^PING", "PONG", line))
                next
            }
            client$env$count <- client$env$count + 1L
            msg <- irc_parse_privmsg(line, client$env$count)
            if (!is.null(msg)) {
                messages[[length(messages) + 1L]] <- msg
            }
        }
        if (length(messages) > 0L || Sys.time() >= deadline) {
            break
        }
        Sys.sleep(0.05)
    }
    list(messages = messages, cursor = client$env$count)
}

#' @export
chat_send.chat_irc <- function(client, channel, text,
                               markup = c("plain", "markdown"),
                               thread = NULL, reply_to = NULL,
                               identity = NULL, files = NULL,
                               kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    verb <- if (identical(kind, "notice")) {
        "NOTICE"
    } else {
        "PRIVMSG"
    }
    sent <- 0L
    for (line in strsplit(text, "\n", fixed = TRUE)[[1L]]) {
        # 512-byte line limit including "PRIVMSG <chan> :" and CRLF;
        # chunk conservatively
        while (nchar(line, type = "bytes") > 400L) {
            irc_write(client$env$con,
                      sprintf("%s %s :%s", verb, channel, substr(line, 1L, 400L)))
            line <- substr(line, 401L, nchar(line))
            sent <- sent + 1L
        }
        irc_write(client$env$con, sprintf("%s %s :%s", verb, channel, line))
        sent <- sent + 1L
    }
    invisible(sprintf("irc-%d", sent))
}

#' @export
chat_resolve.chat_irc <- function(client, name, ...) {
    if (startsWith(name, "#")) {
        name
    } else {
        paste0("#", name)
    }
}

#' @export
chat_capabilities.chat_irc <- function(client, ...) {
    list(threads = FALSE, thread_replies = FALSE, edits = FALSE,
         reactions = FALSE, reaction_events = FALSE, channel_info = FALSE,
         members = FALSE, invites = FALSE, join = FALSE, files = FALSE,
         typing = FALSE, e2ee = FALSE, identity_override = FALSE,
         markup_dialects = "plain", max_message_bytes = 400L)
}

#' @export
chat_disconnect.chat_irc <- function(client, ...) {
    tryCatch(irc_write(client$env$con, "QUIT :bye"), error = function(e) NULL)
    tryCatch(close(client$env$con), error = function(e) NULL)
    invisible(TRUE)
}
