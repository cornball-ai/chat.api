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

    # Constructor: refuses to build without a token
    expect_error(chat_slack(channels = "#lab", token = ""),
                 pattern = "token")

    # With a token it builds and reports honest capabilities
    cl <- chat_slack(channels = c("#lab"), token = "xoxb-fake")
    expect_true(inherits(cl, "chat_client"))
    caps <- chat_capabilities(cl)
    expect_true(caps$threads)
    expect_true(caps$identity_override)
    expect_false(caps$e2ee)

    # Channel resolution strips the hash (Slack API wants bare names)
    expect_identical(chat_resolve(cl, "#general"), "general")

    # A client with no channels polls to empty without any API call
    empty <- chat_slack(channels = character(), token = "xoxb-fake")
    got <- chat_poll(empty)
    expect_identical(length(got$messages), 0L)
    expect_identical(got$cursor, list())
}
