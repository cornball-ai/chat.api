% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_typing}
\alias{chat_typing}
\title{Signal typing state in a channel}
\usage{
chat_typing(client, channel, on = TRUE, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{on}{Logical.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE if the signal was sent, FALSE otherwise, invisibly.
}
\description{
Capability-gated: the default method is a no-op so adapters without
typing indicators need not implement it.
}
