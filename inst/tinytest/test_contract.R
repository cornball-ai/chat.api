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
