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

    # And chat_send's upload path against slackr_upload
    up_formals <- names(formals(slackr::slackr_upload))
    expect_true(all(c("filename", "channels", "token") %in% up_formals))

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
