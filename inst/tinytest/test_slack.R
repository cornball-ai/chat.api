# Slack adapter verification. No workspace token in CI, so this pins
# the adapter to slackr's installed signatures (API-drift detection)
# and exercises the offline paths; live sends need SLACK_TOKEN.

if (requireNamespace("slackr", quietly = TRUE)) {
    # Every argument chat_send passes must exist in slackr_msg
    msg_formals <- names(formals(slackr::slackr_msg))
    expect_true(all(c("txt", "channel", "username", "icon_emoji",
                      "token", "thread_ts") %in% msg_formals))

    # Every argument chat_poll passes must exist in slackr_history
    hist_formals <- names(formals(slackr::slackr_history))
    expect_true(all(c("message_count", "channel", "token",
                      "posted_from_time", "paginate", "inclusive")
                    %in% hist_formals))

    # Constructor: refuses to build without a token, normalizes '#'
    expect_error(chat_slack(channels = "#lab", token = ""),
                 pattern = "token")
    cl <- chat_slack(channels = c("#lab", "ops"), token = "xoxb-fake")
    expect_identical(cl$channels, c("lab", "ops"))
    expect_null(cl$username)

    # Capabilities are honest: threads postable but replies not
    # received; files off while slackr uses the retired endpoint
    caps <- chat_capabilities(cl)
    expect_true(caps$threads)
    expect_false(caps$thread_replies)
    expect_false(caps$files)
    expect_true(caps$identity_override)

    # Channel resolution strips the hash (Slack API wants bare names)
    expect_identical(chat_resolve(cl, "#general"), "general")

    # A client with no channels polls to empty without any API call
    empty <- chat_slack(channels = character(), token = "xoxb-fake")
    got <- chat_poll(empty)
    expect_identical(length(got$messages), 0L)
    expect_identical(got$cursor, list())
}

# Markup rendering is pure and testable without slackr:
# markdown translates the mrkdwn divergences
expect_identical(chat.api:::slack_render("**bold** move", "markdown"),
                 "*bold* move")
expect_identical(chat.api:::slack_render("see [docs](https://x.y)", "markdown"),
                 "see <https://x.y|docs>")
# plain escapes Slack's three specials and nothing else
expect_identical(chat.api:::slack_render("a < b & c > d", "plain"),
                 "a &lt; b &amp; c &gt; d")
expect_identical(chat.api:::slack_render("*not bold*", "plain"),
                 "*not bold*")

# ---- Behavioral tests via injection seams (no slackr, no network) ----

# Scripted history: call 1 errors (transient outage), call 2 seeds at
# ts 100, call 3 returns a burst
hist_calls <- new.env()
hist_calls$n <- 0L
hist_calls$args <- list()
fake_history <- function(...) {
    hist_calls$n <- hist_calls$n + 1L
    hist_calls$args[[hist_calls$n]] <- list(...)
    if (hist_calls$n == 1L) {
        stop("transient Slack outage")
    }
    if (hist_calls$n == 2L) {
        return(data.frame(ts = "100.000", user = "U1", text = "old news",
                          stringsAsFactors = FALSE))
    }
    data.frame(ts = c("103.000", "101.000", "102.000"),
               user = c("U3", "U1", "U2"),
               text = c("third", "first", "second"),
               stringsAsFactors = FALSE)
}
post_calls <- new.env()
post_calls$args <- list()
fake_post <- function(...) {
    post_calls$args[[length(post_calls$args) + 1L]] <- list(...)
    list(ok = TRUE, ts = "999.001")
}

cl <- chat_slack(channels = "lab", token = "xoxb-fake",
                 .history = fake_history, .post = fake_post)

# Poll 1: seed FAILS -> channel stays unseeded (no epoch-zero cursor)
p1 <- chat_poll(cl)
expect_identical(length(p1$messages), 0L)
expect_false("lab" %in% names(p1$cursor))

# Poll 2: seed succeeds at the newest message, emits nothing (no
# history replay after recovery)
p2 <- chat_poll(cl)
expect_identical(length(p2$messages), 0L)
expect_identical(p2$cursor$lab, "100.000")

# Poll 3: burst arrives oldest-first, cursor advances, seed message
# is NOT replayed
p3 <- chat_poll(cl)
expect_identical(length(p3$messages), 3L)
expect_identical(vapply(p3$messages, `[[`, "", "body"),
                 c("first", "second", "third"))
expect_identical(p3$cursor$lab, "103.000")
# and the burst request paginated from the cursor
expect_true(isTRUE(hist_calls$args[[3L]]$paginate))
expect_identical(hist_calls$args[[3L]]$posted_from_time, "100.000")

# Plain sends disable mrkdwn and suppress slackr's env-var identity
ts <- chat_send(cl, "#lab", "keep *this* literal")
expect_identical(ts, "999.001")
a1 <- post_calls$args[[1L]]
expect_false(a1$mrkdwn)
expect_identical(a1$username, "")
expect_identical(a1$icon_emoji, "")
expect_identical(a1$channel, "lab")

# Markdown sends leave mrkdwn on and translate the dialect
chat_send(cl, "lab", "**bold** [x](https://y)", markup = "markdown")
a2 <- post_calls$args[[2L]]
expect_null(a2$mrkdwn)
expect_identical(a2$txt, "*bold* <https://y|x>")

# Identity override rides username/icon; threads ride thread_ts
chat_send(cl, "lab", "as gc", identity = list(name = "gc", icon = ":corn:"),
          thread = "42.1")
a3 <- post_calls$args[[3L]]
expect_identical(a3$username, "gc")
expect_identical(a3$icon_emoji, ":corn:")
expect_identical(a3$thread_ts, "42.1")

# Files warn without any upload attempt, and the text ts survives
expect_warning(ts4 <- chat_send(cl, "lab", "with file",
                                files = "/tmp/x.png"),
               pattern = "files.upload")
expect_identical(ts4, "999.001")

# Zero-row seed is ambiguous: slackr returns the same empty tibble for
# ok = FALSE API errors and truly empty channels. The wall-clock
# baseline must prevent history replay after recovery.
hist2 <- new.env()
hist2$n <- 0L
t_now <- as.numeric(Sys.time())
fake_history2 <- function(...) {
    hist2$n <- hist2$n + 1L
    if (hist2$n == 1L) {
        return(data.frame())
    }
    data.frame(ts = sprintf("%.6f", c(t_now - 1000, t_now + 100)),
               user = c("U1", "U2"),
               text = c("ancient history", "fresh message"),
               stringsAsFactors = FALSE)
}
cl2 <- chat_slack(channels = "lab", token = "xoxb-fake",
                  .history = fake_history2, .post = fake_post)

# Seed poll: empty frame -> baseline is the wall clock, not "0"
s1 <- chat_poll(cl2)
expect_identical(length(s1$messages), 0L)
expect_true(as.numeric(s1$cursor$lab) >= t_now - 1)

# Recovery poll: only the post-baseline message comes through;
# pre-existing history is NOT replayed
s2 <- chat_poll(cl2)
expect_identical(length(s2$messages), 1L)
expect_identical(s2$messages[[1L]]$body, "fresh message")

# ---- Reactions ----
# Implemented here as well as on Matrix, in the same change as the
# generic: an interface with one implementer is a shape traced around
# that implementer. Slack is what proves this one is not Matrix-shaped.
#
# The seam mirrors call_slack_api()'s real signature, `body` and all.
# An earlier version took `...` and asserted on what arrived there, which
# passed while production sent an empty POST: slackr feeds `...` to the
# query string on GET and ignores it on POST. A seam whose shape differs
# from the function it stands in for tests the seam.

slack_react_client <- function(react) {
    chat_slack(channels = "lab", token = "xoxb-test",
               .history = function(...) NULL, .post = function(...) "1.1",
               .react = react)
}
ok_resp <- structure(list(), class = "response")

local({
    seen <- NULL
    cl <- slack_react_client(function(path, ..., body = NULL, .method, token) {
        seen <<- list(path = path, body = body, .method = .method,
                      token = token, dots = list(...))
        ok_resp
    })
    expect_true(chat_react(cl, "#lab", "1700000000.000100", "thumbsup"))
    expect_identical(seen$path, "/api/reactions.add")
    expect_identical(seen$.method, "POST")
    expect_identical(seen$token, "xoxb-test")
    # The three required fields ride in body, which is the only thing
    # call_slack_api() sends on POST.
    expect_identical(seen$body$channel, "lab")
    expect_identical(seen$body$timestamp, "1700000000.000100")
    expect_identical(seen$body$name, "thumbsup")
    # ... and nothing is left in the dots, where it would be dropped.
    expect_identical(length(seen$dots), 0L)
})

# Colons are how the same emoji is written in Slack prose, and the API
# rejects them.
local({
    seen <- NULL
    cl <- slack_react_client(function(path, ..., body = NULL, .method,
                                      token) {
        seen <<- body
        ok_resp
    })
    chat_react(cl, "lab", "1.1", ":tada:")
    expect_identical(seen$name, "tada")
})

# A transport failure propagates rather than reporting a reaction that
# was never placed.
expect_error(chat_react(slack_react_client(function(...) stop("not_in_channel")),
                        "lab", "1.1", "x"),
             "not_in_channel")

# Slack refuses a call with HTTP 200 and {ok: false}, which
# call_slack_api()'s stop_for_status() does not catch. Returning TRUE on
# that reports a reaction that was never placed.
#
# The fixtures are parsed bodies -- exactly what Slack's JSON becomes --
# rather than hand-built httr response objects. The decision under test
# is what to do with {ok: false}, not how httr unwraps a payload.
expect_error(
    chat_react(slack_react_client(function(...) {
        list(ok = FALSE, error = "channel_not_found")
    }), "lab", "1.1", "x"),
    "Slack refused reactions.add: channel_not_found")
# ok = TRUE is not an error.
expect_true(chat_react(slack_react_client(function(...) list(ok = TRUE)),
                       "lab", "1.1", "x"))
# A refusal with no error string still fails, and says so.
expect_error(chat_react(slack_react_client(function(...) list(ok = FALSE)),
                        "lab", "1.1", "x"), "no error given")
# A body with no `ok` field is left alone rather than guessed at:
# failing a good call is worse than the status check alone, which is
# what the rest of this adapter already lives with.
expect_true(chat_react(slack_react_client(function(...) list(x = 1)),
                       "lab", "1.1", "x"))

# Drift detection against the real slackr. This is the check that would
# have caught the dots-versus-body mistake: the seam can be wrong in the
# same direction as the code, and only the installed package settles it.
if (requireNamespace("slackr", quietly = TRUE)) {
    fmls <- names(formals(slackr::call_slack_api))
    expect_true(all(c("path", "body", ".method", "token") %in% fmls))
    expect_identical(fmls[1L], "path")
    # POST sends `body`, and `...` reaches only the GET query. If that
    # ever changes, the adapter has to change with it.
    src <- paste(deparse(body(slackr::call_slack_api)), collapse = " ")
    expect_true(grepl("POST\\(.*body = ", src))
    expect_true(grepl("query = add_cursor_get\\(\\.\\.\\.", src))
}

# The capability pair is honest in both directions. reactions was TRUE
# here before any verb existed to back it; reaction_events is FALSE
# because conversations.history reports reactions as an aggregate on the
# message, with no per-reaction id or timestamp to build a record from.
local({
    caps <- chat_capabilities(chat_slack(channels = "lab", token = "t",
                                         .history = function(...) NULL,
                                         .post = function(...) "1"))
    expect_true(caps$reactions)
    expect_false(caps$reaction_events)
})

# ---- Channel info and members ----
# One call for name and topic, where Matrix takes two: conversations.info
# carries both. Membership is a separate, paginated call -- which is the
# other half of why it is a separate verb.

slack_api_client <- function(api) {
    chat_slack(channels = "lab", token = "xoxb-test",
               .history = function(...) NULL, .post = function(...) "1.1",
               .api = api)
}

local({
    seen <- NULL
    cl <- slack_api_client(function(path, ..., .method, token) {
        seen <<- c(list(path = path, .method = .method), list(...))
        list(ok = TRUE, channel = list(id = "C123", name = "lab",
                                       topic = list(value = "the lab"),
                                       purpose = list(value = "ignored")))
    })
    info <- chat_channel_info(cl, "#lab")
    expect_identical(seen$path, "/api/conversations.info")
    expect_identical(seen$.method, "GET")
    # The leading # is stripped, as everywhere else in this adapter.
    expect_identical(seen$channel, "lab")
    expect_identical(info$id, "C123")
    expect_identical(info$name, "lab")
    # topic wins over purpose when both are set.
    expect_identical(info$topic, "the lab")
})

# An unset topic comes back as "" rather than being omitted, and "" is
# not a topic. purpose is the fallback, and an unset one is NULL too.
local({
    cl <- slack_api_client(function(...) {
        list(ok = TRUE, channel = list(id = "C1", name = "lab",
                                       topic = list(value = ""),
                                       purpose = list(value = "why we are here")))
    })
    expect_identical(chat_channel_info(cl, "lab")$topic, "why we are here")
})
local({
    cl <- slack_api_client(function(...) {
        list(ok = TRUE, channel = list(id = "C1", name = "lab",
                                       topic = list(value = ""),
                                       purpose = list(value = "")))
    })
    expect_null(chat_channel_info(cl, "lab")$topic)
})

# A refusal is an error, not an empty channel.
expect_error(chat_channel_info(slack_api_client(function(...) {
    list(ok = FALSE, error = "channel_not_found")
}), "lab"), "Slack refused conversations.info: channel_not_found")

# Members paginate, and every page is walked before anything is
# returned. A list truncated at the first page reads as a smaller room,
# which is how a consumer gating on member count decides wrong quietly.
local({
    calls <- list()
    cl <- slack_api_client(function(path, ..., .method, token) {
        d <- list(...)
        calls[[length(calls) + 1L]] <<- d
        if (!nzchar(d$cursor)) {
            list(ok = TRUE, members = list("U1", "U2"),
                 response_metadata = list(next_cursor = "page2"))
        } else {
            list(ok = TRUE, members = list("U3"),
                 response_metadata = list(next_cursor = ""))
        }
    })
    expect_identical(chat_members(cl, "#lab"), c("U1", "U2", "U3"))
    expect_identical(length(calls), 2L)
    expect_identical(calls[[1L]]$cursor, "")
    expect_identical(calls[[2L]]$cursor, "page2")
    expect_identical(calls[[1L]]$channel, "lab")
})

# A response with no next_cursor at all ends the walk rather than
# looping forever.
local({
    n <- 0L
    cl <- slack_api_client(function(...) {
        n <<- n + 1L
        list(ok = TRUE, members = list("U1"))
    })
    expect_identical(chat_members(cl, "lab"), "U1")
    expect_identical(n, 1L)
})

# A refusal mid-pagination is an error, not a short list.
expect_error(chat_members(slack_api_client(function(...) {
    list(ok = FALSE, error = "not_in_channel")
}), "lab"), "Slack refused conversations.members: not_in_channel")

local({
    caps <- chat_capabilities(chat_slack(channels = "lab", token = "t",
                                         .history = function(...) NULL,
                                         .post = function(...) "1"))
    expect_true(caps$channel_info)
    expect_true(caps$members)
})

# ---- Joining ----
# Slack splits what Matrix bundles: a bot is added to a private channel
# by a member, which arrives as no event this adapter can see, but it can
# join an open one itself. So `invites` is FALSE and `join` is TRUE --
# the asymmetry is the point of having two flags.

local({
    seen <- NULL
    cl <- slack_api_client(function(path, ..., body = NULL, .method, token) {
        seen <<- list(path = path, body = body, .method = .method)
        list(ok = TRUE, channel = list(id = "C1"))
    })
    expect_identical(chat_join(cl, "#lab"), "lab")
    expect_identical(seen$path, "/api/conversations.join")
    expect_identical(seen$.method, "POST")
    # In the body, not the dots: call_slack_api() drops dots on POST.
    expect_identical(seen$body$channel, "lab")
})

# A refusal is an error, not a silent non-join. "already_in_channel" is
# not what this returns for -- Slack answers ok = TRUE for that.
expect_error(chat_join(slack_api_client(function(...) {
    list(ok = FALSE, error = "channel_not_found")
}), "lab"), "Slack refused conversations.join: channel_not_found")

local({
    caps <- chat_capabilities(chat_slack(channels = "lab", token = "t",
                                         .history = function(...) NULL,
                                         .post = function(...) "1"))
    expect_false(caps$invites)
    expect_true(caps$join)
})

# ---- Identity ----
slack_msg <- function(body = "", mentions = NULL) {
    chat_message(id = "1.1", channel = "lab", sender = "U999",
                 body = body, ts = Sys.time(), mentions = mentions)
}

local({
    seen <- NULL
    cl <- slack_api_client(function(path, ..., .method, token) {
        seen <<- list(path = path, .method = .method, token = token)
        list(ok = TRUE, user_id = "U0BOT", user = "corteza",
             team = "cornball", bot_id = "B1")
    })
    who <- chat_whoami(cl)
    expect_identical(seen$path, "/api/auth.test")
    expect_identical(seen$.method, "GET")
    expect_identical(seen$token, "xoxb-test")
    expect_identical(who$id, "U0BOT")
    expect_identical(who$display, "corteza")
})

# One call per client, not one per message. chat_addressed() asks on
# every message, and the answer is a property of the token.
local({
    calls <- 0L
    cl <- slack_api_client(function(...) {
        calls <<- calls + 1L
        list(ok = TRUE, user_id = "U0BOT", user = "corteza")
    })
    chat_whoami(cl)
    chat_whoami(cl)
    chat_addressed(cl, slack_msg("hi <@U0BOT>"))
    expect_identical(calls, 1L)
})

# Slack refuses in the body with HTTP 200, so an invalid token comes back
# looking like a successful call that just did not say who we are.
expect_error(chat_whoami(slack_api_client(function(...) {
                 list(ok = FALSE, error = "invalid_auth")
             })), "invalid_auth")
expect_error(chat_whoami(slack_api_client(function(...) list(ok = TRUE))),
             "no user_id")

local({
    cl <- slack_api_client(function(...) list(ok = TRUE, user_id = "U0BOT",
                                              user = "corteza"))
    # The ref form Slack stores. There is no plain "@corteza" to find:
    # the sending client rewrote it before the message existed.
    expect_true(chat_addressed(cl, slack_msg("hey <@U0BOT> look")))
    expect_false(chat_addressed(cl, slack_msg("hey @corteza look")))
    expect_false(chat_addressed(cl, slack_msg("hey <@U0OTHER> look")))
    # A ref for a longer id that starts the same way is someone else.
    expect_false(chat_addressed(cl, slack_msg("hey <@U0BOTS> look")))
    expect_false(chat_addressed(cl, slack_msg("")))
    # Declared mentions still count, for a poll path that populates them.
    expect_true(chat_addressed(cl, slack_msg("nothing", mentions = "U0BOT")))
})

expect_true(chat_capabilities(slack_api_client(function(...) NULL))$whoami)

# ---- History paging ----
local({
    seen <- NULL
    cl <- slack_api_client(function(path, ..., .method, token) {
        seen <<- c(list(path = path), list(...))
        list(ok = TRUE,
             messages = list(
                 list(ts = "300.0", user = "U1", text = "third"),
                 list(ts = "200.0", user = "U1", text = "second"),
                 list(ts = "100.0", user = "U1", text = "first")),
             response_metadata = list(next_cursor = "c2"))
    })
    res <- chat_history(cl, "#lab", limit = 3L)
    expect_identical(seen$path, "/api/conversations.history")
    expect_identical(seen$channel, "lab")
    expect_identical(seen$limit, 3L)
    # Slack pages backwards too; the contract promises the other order.
    expect_identical(vapply(res$messages, function(m) m$body, character(1)),
                     c("first", "second", "third"))
    expect_identical(res$cursor, "c2")
    # Slack's own cursor, passed back as a cursor -- not as `latest`. A
    # message ts would work here and not on Matrix, and the contract's
    # token has to mean one thing across adapters.
    chat_history(cl, "lab", cursor = "c2")
    expect_identical(seen$cursor, "c2")
    expect_false("latest" %in% names(seen))
})

# Slack sends "" rather than omitting next_cursor at the end of a
# channel, and handing "" back to conversations.history is an error
# rather than a no-op -- so it has to become NULL here.
local({
    cl <- slack_api_client(function(...) {
        list(ok = TRUE, messages = list(list(ts = "1.0", user = "U1",
                                             text = "only")),
             response_metadata = list(next_cursor = ""))
    })
    expect_null(chat_history(cl, "lab")$cursor)
})
local({
    cl <- slack_api_client(function(...) {
        list(ok = TRUE, messages = list())
    })
    expect_null(chat_history(cl, "lab")$cursor)
    expect_identical(chat_history(cl, "lab")$messages, list())
})

# Joins, leaves and channel renames carry a subtype and are not
# conversation.
local({
    cl <- slack_api_client(function(...) {
        list(ok = TRUE, messages = list(
            list(ts = "2.0", user = "U1", text = "joined",
                 subtype = "channel_join"),
            list(ts = "1.0", user = "U1", text = "real")))
    })
    res <- chat_history(cl, "lab")
    expect_identical(length(res$messages), 1L)
    expect_identical(res$messages[[1L]]$body, "real")
})

# A refused call raises rather than reporting an empty channel. Slack
# says no in the body with HTTP 200, so "no messages" and "you may not
# read this channel" look identical without the check.
expect_error(chat_history(slack_api_client(function(...) {
                 list(ok = FALSE, error = "channel_not_found")
             }), "lab"), "channel_not_found")
