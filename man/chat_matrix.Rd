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
  .crypto = NULL
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
which needs a Rust toolchain.}

\item{crypto_store}{Character or NULL. Directory holding the pickled
Olm account and sessions. NULL derives it from \code{app} via
\code{mx.client::mx_crypto_store_dir()}, which keys one store per
app namespace regardless of where the config file lives, so moving a
config does not cost the device identity. Because that key is the app
name alone, an \code{e2ee = TRUE} client built from an explicit
\code{path} with no \code{app} is an error: name one or the other, or
two such clients would quietly share a device identity.}

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
