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
  \code{cursor} (opaque, for the next \code{since}).
}
\description{
Poll-shaped everywhere: long-poll transports (Matrix /sync, Telegram
getUpdates) map directly; persistent-socket transports (IRC) buffer
into the poll. The cursor is opaque and adapter-specific; pass the
returned cursor back as \code{since} on the next call.
}
