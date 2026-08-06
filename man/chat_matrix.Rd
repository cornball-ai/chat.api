% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_matrix}
\alias{chat_matrix}
\title{Create a Matrix chat client}
\usage{
chat_matrix(
  app = NULL,
  path = NULL,
  save_cursor = TRUE,
  mx = NULL,
  relogin = TRUE,
  e2ee = FALSE,
  crypto_store = NULL,
  .sync = NULL,
  .extract = NULL,
  .send = NULL,
  .media = NULL,
  .typing = NULL,
  .crypto = NULL,
  .save = NULL,
  .react = NULL,
  .info = NULL,
  .members = NULL,
  .join = NULL
)
}
\arguments{
\item{app}{Application namespace passed to
\code{mx.client::mx_client_load()}, defaulting to "chat.api" for the
load. NULL (the default) is also what gets forwarded to
\code{mx_sync_update()}, which leaves the wrapped config's own
\code{app}/\code{path} attributes in charge of where the cursor is
persisted. Naming an app here overrides them, so only name one when
this adapter owns the config file.}

\item{path}{Explicit config path, or NULL for the app default.}

\item{save_cursor}{Logical. Persist the sync token after each poll,
through mx.client, into the config file the wrapped client points
at. Pass FALSE only if you persist \code{chat_poll()}'s
\code{cursor} yourself; nothing else writes it, so a FALSE that
isn't paired with a save makes every restart replay history from a
frozen token.}

\item{mx}{A ready mx.client client config to wrap, for consumers
that already load and manage one; NULL (default) loads via
\code{app}/\code{path}.}

\item{relogin}{Logical. Wrap each sync in
\code{mx.client::mx_with_relogin()}, which catches an invalidated
access token, re-logs in with the stored password on the same
device_id (so an E2EE identity survives), and retries once. The
refreshed config lands back in the client, so the next poll and any
send use the new token. FALSE lets \code{mx_error_M_UNKNOWN_TOKEN}
propagate.}

\item{e2ee}{Logical. Own Olm/Megolm state in the adapter, so
\code{\link{chat_send}} encrypts for rooms that advertise
\code{m.room.encryption} and \code{\link{chat_poll}} decrypts
inbound. FALSE (the default) is the previous behaviour exactly:
cleartext only, no crypto state, and \code{e2ee} stays FALSE in
\code{\link{chat_capabilities}}. Requires the 'mx.crypto' package,
which needs a Rust toolchain, and both \code{user_id} and
\code{device_id} on the wrapped config.

Three things change when it is on. The crypto state is built on
first use rather than here: from \code{\link{chat_poll}} that means
key publication happens after the sync, so a relogin has already
replaced a rejected token, while a \code{\link{chat_send}} that runs
before any poll publishes with the token it has -- the same exposure
any direct send already carries, since \code{mx_with_relogin()}
wraps only the sync. The sync cursor is held back until the crypto
state is safe, on disk and on the client, so a sync carrying a room
key is not marked consumed until that key is stored. And attachments
are refused in encrypted rooms, because Matrix media uploads are not
encrypted by this adapter -- \code{\link{chat_capabilities}} reports
\code{files = FALSE} to match.}

\item{crypto_store}{Character or NULL. Directory holding the pickled
Olm account and sessions. NULL derives it from \code{app} via
\code{mx.client::mx_crypto_store_dir()}, with a per-device
subdirectory, so moving a config does not cost the device identity
and two bots under one app namespace do not share an Olm account.

A Matrix device has one Olm identity for its whole life, and three
things hold that. The store records the \code{(user_id, device_id)}
it belongs to and refuses to open for a different one. Within a
process, one device gets one context and one store, so pointing a
second store at it is an error rather than a second account. And on
first use the account's keys are checked against the ones the
homeserver already has for that \code{device_id} -- the only one of
the three that survives a restart, and so the one that catches a
store swapped between runs. Log in again for a new \code{device_id}
rather than re-homing an existing one.

That last check distinguishes three cases: no published device is a
first run, a published device whose keys match is this account, and
a published device that either differs or fails signature
verification is an error. A \code{/keys/query} that returns a
\code{failures} map is an error too, since the empty result beside
it is an unanswered question rather than an absent device. It cannot
see a homeserver that omits the device deliberately, which is
indistinguishable from a first run without key pinning or
cross-signing.

A Windows drive-relative \code{crypto_store} (\code{"C:store"}) is
rejected. It names a directory relative to the current directory of
that drive, which cannot be read here, so two such paths cannot be
told apart and two stores could share one context. Pass an absolute
path.}

\item{.sync}{Testing seam: replacement for
\code{mx.client::mx_sync_update}. Leave NULL in production.}

\item{.extract}{Testing seam: replacement for
\code{mx.client::mx_extract_text_events}. Leave NULL in production.}

\item{.send}{Testing seam: replacement for
\code{mx.client::mx_send_text}. Leave NULL in production.}

\item{.media}{Testing seam: replacement for
\code{mx.client::mx_send_media}. Leave NULL in production. Supplying
all four seams together with \code{mx} lets poll and send run
without mx.client installed; \code{chat_typing()} and
\code{chat_resolve()} still require it.}

\item{.typing}{Testing seam: replacement for
\code{mx.api::mx_typing}. Leave NULL in production. It is resolved
when \code{chat_typing()} is called, not here, so a NULL seam costs
nothing on installs without mx.api.}

\item{.crypto}{Testing seam: a named list overriding any of the
adapter's four crypto operations -- \code{init}, \code{encrypted},
\code{send}, \code{decrypt}. Leave NULL in production. Supplying
\code{init} is what lets \code{e2ee = TRUE} be tested on a runner
with neither mx.crypto nor a Rust toolchain; E2EE is the one part of
this adapter with no honest way to reach a real homeserver from a
test.}

\item{.save}{Testing seam: replacement for
\code{mx.client::mx_client_save}. Leave NULL in production. Only
reached on an \code{e2ee} client, which writes the sync cursor after
the crypto state rather than inside the sync.}

\item{.react}{Testing seam: replacement for \code{mx.api::mx_react}.
Leave NULL in production. Resolved when \code{chat_react()} is
called, not here, so a NULL seam costs nothing on installs without
mx.api.}

\item{.info}{Testing seam: a list with \code{name} and \code{topic},
replacing \code{mx.api::mx_room_name} and
\code{mx.api::mx_room_topic}. Leave NULL in production.}

\item{.members}{Testing seam: replacement for
\code{mx.api::mx_room_members}. Leave NULL in production.}

\item{.join}{Testing seam: replacement for
\code{mx.api::mx_room_join}. Leave NULL in production.}
}
\value{
A \code{chat_client} of class \code{chat_matrix}.
  \code{\link{chat_poll}} on this class returns \code{first_run} and
  \code{client} alongside \code{messages}, \code{cursor}, and
  \code{raw}. \code{first_run} is TRUE when the sync started from no
  cursor, so the messages are a backfill baseline rather than new
  traffic. \code{client} is the post-sync mx.client config, which a
  consumer needs whenever it drives mx.api directly (read receipts,
  member lookups) because a relogin may have replaced the token this
  poll cycle.
}
\description{
Wraps an \code{mx.client} client config (see
\code{mx.client::mx_client_load()}). The sync cursor lives inside the
mx.client config; with \code{save_cursor = TRUE} every poll persists
it, so a restarted process resumes where it left off.
}
