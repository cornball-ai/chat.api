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

local({
    seen <- NULL
    cl <- chat_slack(channels = "lab", token = "xoxb-test",
                     .history = function(...) NULL,
                     .post = function(...) "1.1",
                     .react = function(path, ..., .method, token) {
                         seen <<- c(list(path = path, .method = .method,
                                         token = token), list(...))
                         list(ok = TRUE)
                     })
    # Slack gives a reaction no identity of its own, so TRUE is the
    # honest answer rather than a fabricated id.
    expect_true(chat_react(cl, "#lab", "1700000000.000100", "thumbsup"))
    expect_identical(seen$path, "/api/reactions.add")
    expect_identical(seen$.method, "POST")
    expect_identical(seen$token, "xoxb-test")
    # timestamp, not "event id": Slack addresses a message by its ts.
    expect_identical(seen$timestamp, "1700000000.000100")
    # The leading # is stripped, matching what every other Slack call here
    # sends.
    expect_identical(seen$channel, "lab")
    # Colons are how the same emoji is written in Slack prose and are
    # rejected by the API.
    expect_identical(seen$name, "thumbsup")
})

local({
    seen <- NULL
    cl <- chat_slack(channels = "lab", token = "t",
                     .history = function(...) NULL, .post = function(...) "1",
                     .react = function(path, ...) { seen <<- list(...); TRUE })
    chat_react(cl, "lab", "1.1", ":tada:")
    expect_identical(seen$name, "tada")
})

# A failing call propagates rather than reporting a reaction that was
# never placed.
expect_error(chat_react(chat_slack(channels = "lab", token = "t",
                                   .history = function(...) NULL,
                                   .post = function(...) "1",
                                   .react = function(...) stop("not_in_channel")),
                        "lab", "1.1", "x"),
             "not_in_channel")

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
