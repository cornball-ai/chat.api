% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_poll}
\alias{chat_poll}
\title{Poll a chat client for new messages}
\usage{
chat_poll(client, since = NULL, timeout = NULL, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{since}{Opaque cursor from the previous poll, or NULL to start.}

\item{timeout}{Seconds to wait for activity; NULL for the adapter
default.}

\item{...}{Adapter-specific options.}
}
\value{
A list with \code{messages} (list of \code{chat_message}) and
  \code{cursor} (opaque, for the next \code{since}). An adapter with
  the \code{calls} capability also returns \code{calls}: one notice
  per channel where someone other than this client announced or
  withdrew a call membership in this poll, each
  \code{list(channel, members, left)} with \code{members} the
  identities now in the call and \code{left} those who withdrew. A
  consumer that joins calls on demand acts on these (see
  \code{\link{chat_call_join}}).
}
\description{
Poll-shaped everywhere: long-poll transports (Matrix /sync, Telegram
getUpdates) map directly; persistent-socket transports (IRC) buffer
into the poll. The cursor is opaque and adapter-specific; pass the
returned cursor back as \code{since} on the next call.
}
\examples{
cl <- chat_loopback()
chat_send(cl, "general", "hello")
batch <- chat_poll(cl)
batch$messages
chat_poll(cl, since = batch$cursor)$messages
}
