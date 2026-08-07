% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_channels}
\alias{chat_channels}
\title{List the channels this client is in}
\usage{
chat_channels(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
Character vector of channel identifiers.
}
\description{
The state half of the contract. \code{\link{chat_poll}} answers "what
changed since my cursor"; this and its siblings answer "what is true
now", which is the question a process asks when it starts up with no
useful cursor at all.
}
\examples{
chat_channels(chat_loopback())
}
