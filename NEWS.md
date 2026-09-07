# chat.api 0.0.1.27

* New Telegram adapter, chat_telegram(), over the Bot API with HTTP
  delegated to the suggested httr package. getUpdates long polling is
  the poll, with a single update offset as the cursor. Sends render
  markdown to Telegram HTML and carry threads, replies, files, and
  silent delivery; edits, emoji reactions and reaction events, typing,
  chat info, leaving, identity, @username addressing, and attachment
  fetch through getFile are wired. Capabilities report what the Bot
  API lacks: history, member and chat lists, read markers, joining,
  and creating.

# chat.api 0.0.1.26

* Slack gains chat_channel_create() and chat_leave(), posting
  conversations.create and conversations.leave through the adapter's API
  seam. Adapter options such as is_private = TRUE pass through to the
  request body, and Slack's own refusals (name_taken, invalid_name,
  not_in_channel) propagate as errors. Both capability flags are now TRUE.

# chat.api 0.0.1.25

* Matrix E2EE saves ratchet state before room-key request transport, retries
  unsent requests with their stable ids, and treats transport failures as
  warnings so a decrypted sync batch is not lost or replayed.
* Same-user forwarded-key recovery requires a cross-signing chain matching
  the master key in the local crypto store. Missing or unreadable local keys
  leave the user's devices untrusted for recovery.
* Matrix E2EE now requires mx.client >= 0.2.0.8 and mx.crypto >= 0.2.1.1 for
  durable request handling and local cross-signing key access.
