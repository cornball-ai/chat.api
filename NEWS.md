# chat.api 0.1.0.1

* Matrix clients can take part in a room's call: `chat_call_join()`
  announces the client as a MatrixRTC member, obtains the media server's
  address and token, and exchanges per-member media keys over Olm for as
  long as the client polls; `chat_call_media()` hands a media side what it
  needs to connect, `chat_call_updates()` reports keys and membership that
  arrived since the last look, `chat_call_leave()` withdraws. The media
  itself is the caller's. Each call operation is handed the client's live
  credentials and Olm sessions, and the sessions it opens come back into
  the client's crypto state. Needs an `e2ee` client and mx.client 0.2.1.1;
  the new capability flag is `calls`, FALSE on every other adapter.

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
