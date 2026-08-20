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
    # Bounded, not a repeat. A cursor that fails to advance makes this
    # loop forever, and a hung suite is a worse failure report than a
    # wrong one: no line number, no diff, just a runner that never
    # finishes. Ten is generous for five messages two at a time, and
    # cur being non-NULL at the end is what says the walk did not
    # terminate on its own.
    for (i in seq_len(10L)) {
        pg <- chat_history(cl, "general", limit = 2L, cursor = cur)
        walked <- c(vapply(pg$messages, function(m) m$body, character(1)),
                    walked)
        cur <- pg$cursor
        if (is.null(cur)) {
            break
        }
    }
    expect_null(cur)
    expect_identical(walked, c("m1", "m2", "m3", "m4", "m5"))
})

# The generic's signature is the contract. `before` took a message id
# once, which Matrix's /messages cannot use -- it wants a pagination
# token out of a previous response.
expect_true("cursor" %in% names(formals(chat_history)))
expect_false("before" %in% names(formals(chat_history)))

# ---- Edits on the reference adapter ----
local({
    cl <- chat_loopback()
    id <- chat_send(cl, "general", "working on it")
    expect_identical(chat_history(cl, "general")$messages[[1L]]$body,
                     "working on it")
    expect_identical(chat_edit(cl, "general", id, "done"), id)
    # Replaced in place, not appended. An edit that added a message
    # would leave the channel reading as a stutter.
    h <- chat_history(cl, "general")$messages
    expect_identical(length(h), 1L)
    expect_identical(h[[1L]]$body, "done")
    expect_identical(h[[1L]]$id, id)
    # markup rides along, so a plain first draft can become a formatted
    # final one.
    chat_edit(cl, "general", id, "**done**", markup = "markdown")
    expect_identical(chat_history(cl, "general")$messages[[1L]]$markup,
                     "markdown")
})

# Editing something that was never sent is an error, not a no-op. A
# consumer doing that has lost track of what it sent, and the reference
# adapter is where that should be loudest.
expect_error(chat_edit(chat_loopback(), "general", "nope", "x"),
             "no message")
expect_true(chat_capabilities(chat_loopback())$edits)

# IRC has no edits: a line is on the wire and gone. The default method
# is what answers, and it throws.
local({
    cl <- structure(list(env = new.env(parent = emptyenv()), nick = "bot"),
                    class = c("chat_irc", "chat_client"))
    expect_false(chat_capabilities(cl)$edits)
    expect_error(chat_edit(cl, "#lab", "1", "x"),
                 "not supported by this adapter")
})

# ---- Channel lifecycle on the reference adapter ----
# A created channel exists before any traffic: chat_channels() must
# report it, or a consumer that creates and then lists sees its own
# channel missing and creates it again.
local({
    cl <- chat_loopback()
    id <- chat_channel_create(cl, "warroom")
    expect_identical(id, "warroom")
    expect_true("warroom" %in% chat_channels(cl))
    chat_send(cl, id, "first")
    expect_identical(chat_history(cl, id)$messages[[1L]]$body, "first")
    # Creating twice is an error, not a no-op: the caller has lost
    # track of its own state.
    expect_error(chat_channel_create(cl, "warroom"), "already exists")
})

# Loopback has no membership, so leave refuses rather than pretending.
local({
    lo <- chat_loopback()
    expect_true(chat_capabilities(lo)$channel_create)
    expect_false(chat_capabilities(lo)$leave)
    expect_error(chat_leave(lo, "general"), "not supported by this adapter")
})

# ---- Channel state on the reference adapter ----
# A write is durable and keyed by channel/type/state_key; a second
# write to the same key replaces the content whole, never merges.
local({
    lo <- chat_loopback()
    expect_true(chat_capabilities(lo)$set_state)
    id <- chat_set_state(lo, "general", "ai.example.marker",
                         list(state = "parked", since = "2026-08-19"))
    expect_true(is.character(id) && nzchar(id))
    key <- paste("general", "ai.example.marker", "", sep = "\r")
    expect_identical(lo$env$state[[key]],
                     list(state = "parked", since = "2026-08-19"))
    chat_set_state(lo, "general", "ai.example.marker",
                   list(state = "active"))
    expect_identical(lo$env$state[[key]], list(state = "active"))
    # Distinct state_keys are distinct slots under one type.
    chat_set_state(lo, "general", "ai.example.marker",
                   list(state = "parked"), state_key = "alt")
    expect_identical(lo$env$state[[key]], list(state = "active"))
})

# An adapter that cannot write state says so.
local({
    nothing <- structure(list(), class = c("chat_nothing", "chat_client"))
    expect_error(chat_set_state(nothing, "c", "t", list()),
                 "not supported by this adapter")
    expect_error(chat_get_state(nothing, "c", "t"),
                 "not supported by this adapter")
})

# Reading state back is the other half of the same capability.
local({
    lo <- chat_loopback()
    # State never written reads as NULL rather than erroring: "no marker
    # here" is an ordinary answer, and a caller checking for one should
    # not need a handler to get it.
    expect_null(chat_get_state(lo, "general", "ai.example.marker"))
    chat_set_state(lo, "general", "ai.example.marker",
                   list(state = "parked", since = "2026-08-20"))
    expect_identical(chat_get_state(lo, "general", "ai.example.marker"),
                     list(state = "parked", since = "2026-08-20"))
    # Keyed by channel, type and state_key alike, so neither a
    # different room nor a different key sees this one.
    expect_null(chat_get_state(lo, "other", "ai.example.marker"))
    expect_null(chat_get_state(lo, "general", "ai.other.marker"))
    expect_null(chat_get_state(lo, "general", "ai.example.marker",
                               state_key = "alt"))
    # A write replaces the whole content, and the read sees that.
    chat_set_state(lo, "general", "ai.example.marker", list(state = "active"))
    expect_identical(chat_get_state(lo, "general", "ai.example.marker"),
                     list(state = "active"))
})

# An adapter that cannot create says so.
local({
    nothing <- structure(list(), class = c("chat_nothing", "chat_client"))
    expect_error(chat_channel_create(nothing, "x"),
                 "not supported by this adapter")
    expect_error(chat_leave(nothing, "x"), "not supported by this adapter")
})

# ---- Every adapter answers the lifecycle and media flags ----
# Same rule as the reaction flags: a flag one adapter reports and
# another omits gives a consumer NULL, and NULL is not FALSE.
local({
    for (adapter in c("chat_loopback", "chat_irc", "chat_slack",
                      "chat_matrix")) {
        m <- getS3method("chat_capabilities", adapter)
        caps <- m(structure(list(env = new.env()), class = adapter))
        for (flag in c("channel_create", "leave", "files", "attachments")) {
            expect_true(flag %in% names(caps), info = paste(adapter, flag))
            expect_true(is.logical(caps[[flag]]) && length(caps[[flag]]) == 1L,
                        info = paste(adapter, flag))
            expect_false(is.na(caps[[flag]]), info = paste(adapter, flag))
        }
    }
})

# ---- Attachment record ----
att <- chat_attachment("mxc://ex/abc", name = "plot.png",
                       mime = "image/png", bytes = 1024L)
expect_inherits(att, "chat_attachment")
expect_identical(att$id, "mxc://ex/abc")
expect_true(is.na(chat_attachment("mxc://ex/abc")$sha256))
expect_error(chat_attachment(""))
expect_error(chat_attachment(NULL))

# chat_message() validates attachments: a list of records or nothing.
# A character vector of paths here is a send-side files= that leaked
# through an adapter unconverted, which should fail at construction
# rather than at the first consumer that indexes into it.
local({
    m <- chat_message(id = "1", channel = "c", sender = "ann", body = "x",
                      ts = Sys.time(), attachments = list(att))
    expect_identical(m$attachments[[1L]]$name, "plot.png")
    expect_error(chat_message(id = "1", channel = "c", sender = "ann",
                              body = "x", ts = Sys.time(),
                              attachments = "plot.png"),
                 "chat_attachment")
    expect_error(chat_message(id = "1", channel = "c", sender = "ann",
                              body = "x", ts = Sys.time(),
                              attachments = list()),
                 "chat_attachment")
})

# Files round-trip on the reference adapter: sent paths come back out
# of the poll as attachment records, which is what makes loopback the
# test double for media-carrying consumers.
local({
    cl <- chat_loopback()
    f <- tempfile(fileext = ".png")
    writeBin(as.raw(1:16), f)
    chat_send(cl, "general", "see plot", files = f)
    msg <- chat_poll(cl)$messages[[1L]]
    expect_identical(length(msg$attachments), 1L)
    expect_identical(msg$attachments[[1L]]$name, basename(f))
    expect_identical(msg$attachments[[1L]]$bytes, 16L)
    expect_identical(msg$attachments[[1L]]$path, f)
    # A missing file errors rather than sending a message that quietly
    # lost its attachment.
    expect_error(chat_send(cl, "general", "x",
                           files = file.path(tempdir(), "not-there.png")),
                 "no such file")
})
