# The loopback adapter is the reference implementation of the contract.

cl <- chat_loopback()
expect_true(inherits(cl, "chat_client"))

# Send returns an id; poll returns the message and a cursor
id <- chat_send(cl, "general", "hello world")
expect_true(is.character(id) && nzchar(id))

got <- chat_poll(cl)
expect_identical(length(got$messages), 1L)
m <- got$messages[[1L]]
expect_true(inherits(m, "chat_message"))
expect_identical(m$channel, "general")
expect_identical(m$body, "hello world")
expect_identical(m$kind, "message")

# Cursor advances: nothing new on the next poll, new sends appear
cur <- got$cursor
expect_identical(length(chat_poll(cl, since = cur)$messages), 0L)
chat_send(cl, "general", "second", markup = "markdown", thread = id)
got2 <- chat_poll(cl, since = cur)
expect_identical(length(got2$messages), 1L)
expect_identical(got2$messages[[1L]]$thread, id)
expect_identical(got2$messages[[1L]]$markup, "markdown")

# Per-message identity override lands in sender
chat_send(cl, "general", "as the architect",
          identity = list(name = "architect"))
last <- chat_poll(cl, since = got2$cursor)$messages[[1L]]
expect_identical(last$sender, "architect")

# Typing is a capability-gated no-op by default
expect_false(chat_typing(cl, "general", TRUE))

# Capabilities carry the required schema
caps <- chat_capabilities(cl)
required <- c("threads", "thread_replies", "edits", "reactions",
              "files", "typing", "e2ee",
              "identity_override", "markup_dialects", "max_message_bytes")
expect_true(all(required %in% names(caps)))

# Resolve is identity for loopback
expect_identical(chat_resolve(cl, "general"), "general")

# Invalid markup errors via match.arg
expect_error(chat_send(cl, "general", "x", markup = "html"))

# chat_matrix() wraps a caller-supplied mx.client object without loading
if (requireNamespace("mx.client", quietly = TRUE)) {
    fake_mx <- list(user_id = "@bot:example.org", sync_token = "s123")
    cm <- chat_matrix(mx = fake_mx, save_cursor = FALSE)
    expect_true(inherits(cm, "chat_matrix"))
    expect_identical(cm$env$mx$user_id, "@bot:example.org")
    expect_false(cm$save_cursor)
}

# ---- Every adapter answers the reaction capability pair ----
# A flag one adapter reports and another omits is worse than either
# answer: a consumer reading it gets NULL, and NULL is not FALSE.
#
# The capability methods are called directly rather than through
# constructors, because chat_irc() opens a socket and chat_matrix()
# wants a config. Every one of them ignores its client argument for
# these flags, which is what makes that safe -- and if one stops
# ignoring it, this is where that shows up.
local({
    for (adapter in c("chat_loopback", "chat_irc", "chat_slack",
                      "chat_matrix")) {
        m <- getS3method("chat_capabilities", adapter)
        caps <- m(structure(list(env = new.env()), class = adapter))
        for (flag in c("reactions", "reaction_events")) {
            expect_true(flag %in% names(caps), info = paste(adapter, flag))
            expect_true(is.logical(caps[[flag]]) && length(caps[[flag]]) == 1L,
                        info = paste(adapter, flag))
            expect_false(is.na(caps[[flag]]), info = paste(adapter, flag))
        }
    }
})

# An adapter with no reaction support refuses rather than pretending: a
# silent no-op leaves the caller believing it acknowledged something.
local({
    lo <- chat_loopback()
    expect_false(chat_capabilities(lo)$reactions)
    expect_error(chat_react(lo, "c", "m", "y"), "not supported by this adapter")
})

# The two flags mean different things, and the pair is what a consumer
# reads: Slack can place a reaction and cannot report anyone else's.
local({
    slack <- getS3method("chat_capabilities", "chat_slack")(NULL)
    expect_true(slack$reactions)
    expect_false(slack$reaction_events)
})

# ---- Every adapter answers the channel-metadata pair ----
# Same rule as the reaction flags: a flag one adapter reports and another
# omits gives a consumer NULL, and NULL is not FALSE.
local({
    for (adapter in c("chat_loopback", "chat_irc", "chat_slack",
                      "chat_matrix")) {
        m <- getS3method("chat_capabilities", adapter)
        caps <- m(structure(list(env = new.env()), class = adapter))
        for (flag in c("channel_info", "members")) {
            expect_true(flag %in% names(caps), info = paste(adapter, flag))
            expect_true(is.logical(caps[[flag]]) && length(caps[[flag]]) == 1L,
                        info = paste(adapter, flag))
            expect_false(is.na(caps[[flag]]), info = paste(adapter, flag))
        }
    }
})

# An adapter that cannot answer refuses, so "cannot ask" stays distinct
# from "asked, and there is none" -- which is the whole reason a missing
# name is NULL rather than an error.
local({
    lo <- chat_loopback()
    expect_false(chat_capabilities(lo)$channel_info)
    expect_false(chat_capabilities(lo)$members)
    expect_error(chat_channel_info(lo, "c"), "not supported by this adapter")
    expect_error(chat_members(lo, "c"), "not supported by this adapter")
})

# Membership is its own verb, not a field on channel info. The two go
# stale on different schedules and one of them is unbounded, so a
# consumer reading a topic must not pay for a member list.
local({
    m <- getS3method("chat_capabilities", "chat_matrix")
    caps <- m(structure(list(env = new.env()), class = "chat_matrix"))
    expect_true(caps$channel_info && caps$members)
    expect_false("members" %in% names(formals(chat_channel_info)))
})

# ---- Every adapter answers the invite pair ----
local({
    for (adapter in c("chat_loopback", "chat_irc", "chat_slack",
                      "chat_matrix")) {
        m <- getS3method("chat_capabilities", adapter)
        caps <- m(structure(list(env = new.env()), class = adapter))
        for (flag in c("invites", "join")) {
            expect_true(flag %in% names(caps), info = paste(adapter, flag))
            expect_true(is.logical(caps[[flag]]) && length(caps[[flag]]) == 1L,
                        info = paste(adapter, flag))
            expect_false(is.na(caps[[flag]]), info = paste(adapter, flag))
        }
    }
})

# Receiving invitations and being able to join are separate: Slack does
# the second and not the first. A single flag would have a consumer
# either wait for invitations that never arrive or refuse to join a
# channel it could.
local({
    slack <- getS3method("chat_capabilities", "chat_slack")(NULL)
    expect_false(slack$invites)
    expect_true(slack$join)
})

local({
    lo <- chat_loopback()
    expect_false(chat_capabilities(lo)$join)
    expect_error(chat_join(lo, "c"), "not supported by this adapter")
})

# ---- Identity record ----
id <- chat_identity("@bot:ex", display = "corteza")
expect_inherits(id, "chat_identity")
expect_identical(id$id, "@bot:ex")
expect_identical(id$display, "corteza")
expect_true(is.na(chat_identity("@bot:ex")$display))
expect_true(is.na(chat_identity("@bot:ex", display = NULL)$display))
expect_error(chat_identity(""))
expect_error(chat_identity(NULL))
expect_error(chat_identity(c("@a:ex", "@b:ex")))

# An adapter that cannot say who it is says so, rather than answering NA
# and letting every self-check silently report "not me".
nothing <- structure(list(), class = c("chat_nothing", "chat_client"))
expect_error(chat_whoami(nothing), "not supported by this adapter")

# ---- chat_addressed, the default ----
# Declared mentions only. An adapter that does not override this
# under-reports: a bot that misses being addressed stays quiet, one that
# over-reports talks over people unprompted.
local({
    cl <- chat_loopback()
    expect_identical(chat_whoami(cl)$id, "loopback")
    m <- function(body, mentions = NULL) {
        chat_message(id = "1", channel = "c", sender = "ann", body = body,
                     ts = Sys.time(), mentions = mentions)
    }
    expect_true(chat_addressed(cl, m("x", mentions = "loopback")))
    expect_true(chat_addressed(cl, m("x", mentions = c("ann", "loopback"))))
    expect_false(chat_addressed(cl, m("x", mentions = "ann")))
    # The plain-text form is not read by the default, deliberately.
    expect_false(chat_addressed(cl, m("hey loopback")))
    expect_false(chat_addressed(cl, m("x")))
    expect_false(chat_addressed(cl, m("x", mentions = character())))
    expect_true(chat_capabilities(cl)$whoami)
})

# The default needs an identity, so an adapter with neither reports the
# missing one rather than a bare FALSE.
expect_error(chat_addressed(nothing,
                            chat_message(id = "1", channel = "c",
                                         sender = "a", body = "b",
                                         ts = Sys.time())),
             "not supported by this adapter")

# ---- chat_history paging on the reference adapter ----
# The loopback adapter is what a new adapter gets read as an example, so
# its cursor is deliberately not a message id. Matrix cannot page by one
# at all, and a reference implementation that did would teach the wrong
# contract.
local({
    cl <- chat_loopback()
    for (i in 1:5) {
        chat_send(cl, "general", sprintf("m%d", i))
    }
    chat_send(cl, "other", "elsewhere")

    all <- chat_history(cl, "general")
    expect_identical(length(all$messages), 5L)
    # Oldest first, and only this channel's.
    expect_identical(vapply(all$messages, function(m) m$body, character(1)),
                     c("m1", "m2", "m3", "m4", "m5"))
    # Nothing left behind it, so no continuation.
    expect_null(all$cursor)

    # limit takes the most recent, not the first stored.
    page1 <- chat_history(cl, "general", limit = 2L)
    expect_identical(vapply(page1$messages, function(m) m$body, character(1)),
                     c("m4", "m5"))
    expect_false(is.null(page1$cursor))

    # Pages run backwards while each page runs forwards.
    page2 <- chat_history(cl, "general", limit = 2L, cursor = page1$cursor)
    expect_identical(vapply(page2$messages, function(m) m$body, character(1)),
                     c("m2", "m3"))
    page3 <- chat_history(cl, "general", limit = 2L, cursor = page2$cursor)
    expect_identical(vapply(page3$messages, function(m) m$body, character(1)),
                     "m1")
    # The start of the channel: nothing more to ask for.
    expect_null(page3$cursor)

    # Paging past the start is empty, not an error and not a wrap-around.
    past <- chat_history(cl, "general", limit = 2L, cursor = 99L)
    expect_identical(past$messages, list())
    expect_null(past$cursor)

    # Every page put together is the whole channel, once.
    walked <- character()
    cur <- NULL
    repeat {
        pg <- chat_history(cl, "general", limit = 2L, cursor = cur)
        walked <- c(vapply(pg$messages, function(m) m$body, character(1)),
                    walked)
        cur <- pg$cursor
        if (is.null(cur)) {
            break
        }
    }
    expect_identical(walked, c("m1", "m2", "m3", "m4", "m5"))
})

# The generic's signature is the contract. `before` took a message id
# once, which Matrix's /messages cannot use -- it wants a pagination
# token out of a previous response.
expect_true("cursor" %in% names(formals(chat_history)))
expect_false("before" %in% names(formals(chat_history)))
