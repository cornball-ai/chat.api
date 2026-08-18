% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_leave}
\alias{chat_leave}
\title{Leave a channel}
\usage{
chat_leave(client, channel, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{...}{Adapter-specific options.}
}
\value{
The left channel's identifier, invisibly.
}
\description{
The inverse of \code{\link{chat_join}}: after it returns, the
client stops receiving the channel's traffic, on platforms where
membership is a thing at all. Capability-gated: check
\code{chat_capabilities()$leave}.
}
