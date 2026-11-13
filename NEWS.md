# chat.api 0.2.0.1

* A Matrix client built without `e2ee` now says when an encrypted room's
  events reach it: `chat_poll()` emits a message naming the room the first
  time it sees `m.room.encrypted` there, once per room for the life of the
  client, instead of dropping the events in silence. Turning `e2ee` on is
  the fix; the message is what makes the need visible in a bot's log.

# chat.api 0.2.0

* Send encrypted Matrix attachments using the adapter's existing crypto
  context, with ciphertext-only uploads and encrypted file metadata.
* Preserve attachment metadata from decrypted room events and verify encrypted
  downloads before returning plaintext. File capability reporting follows the
  installed attachment helpers; older dependencies still refuse safely.
* Encrypted attachments need mx.client 0.3.0 and mx.crypto 0.3.0, the
  new floors in Suggests.
* `chat_set_identity()` takes `avatar`, a path to an image, alongside
  `display`: both are the account's persistent identity. Matrix uploads
  the file and points the profile at it (testing seam `.avatar`);
  adapters whose platform sets a bot's picture outside its API ignore
  it and answer FALSE when it was all that was asked for;
  `chat_capabilities()$avatar` says which is which. Both arguments are
  optional now, and asking for nothing is FALSE.
* `chat_channel_invite()` invites a user to a channel, the other side
  of the invitations `chat_poll()` reports. Matrix implements it over
  `mx.api::mx_room_invite()` (testing seam `.invite`), the loopback
  adapter records it, and `chat_capabilities()$channel_invite` says
  which adapters have it. (A consumer filing rooms under a space falls
  back to a direct invite when restricted join rules fail, and had no
  verb in the contract to do it with.)
* Matrix `chat_edit()` works in an encrypted room. The edit's "* "
  fallback body, its `m.new_content` and the `m.replace` relation now
  ride inside the Megolm ciphertext, so the replacement text stays off
  the homeserver; `chat_capabilities()$edits` is TRUE on an e2ee client.
* Decrypted room events without a body (keys, ring notifications,
  reactions) no longer become empty `chat_message` records in
  `chat_poll()`.

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
