% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_typing}
\alias{chat_typing}
\alias{chat_typing.chat_matrix}
\title{Signal typing state in a channel}
\usage{
chat_typing(client, channel, on = TRUE, ...)

\method{chat_typing}{chat_matrix}(client, channel, on = TRUE, timeout = 30, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{on}{Logical.}

\item{...}{Adapter-specific options.}

\item{timeout}{Seconds the typing indicator should stand before the
homeserver clears it, for \code{on = TRUE}. Seconds, not
milliseconds: \code{chat_poll()} takes seconds too, and the adapter
converts at the mx.api boundary. A caller running a slow model
turn wants a long one (say 120) and an explicit
\code{on = FALSE} when the turn ends.}
}
\value{
TRUE if the signal was sent, FALSE otherwise, invisibly.
}
\description{
Capability-gated: the default method is a no-op so adapters without
typing indicators need not implement it.
}
