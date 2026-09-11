# chat.api 0.1.0

* First CRAN release.
* A common interface for polling, sending, editing, reactions, attachments,
  room membership, history, state, and identity, with capability flags for
  adapter-specific support.
* An in-memory loopback adapter for local development and testing, plus
  adapters for Matrix, IRC, Slack, and Telegram.
* Matrix supports encrypted messaging, durable room-key requests,
  verification against local cross-signing keys, and credential persistence
  through mx.client and mx.crypto.
* Slack supports channel creation and leaving, bot identity customization,
  and posting as a workspace member when configured with a user token.
* Telegram supports long polling, threads, replies, files, edits, reactions,
  and identity. Requests can use httr directly or a telegram::TGBot object
  with its configured proxy.
