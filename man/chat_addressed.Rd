% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_addressed}
\alias{chat_addressed}
\title{Does a message address this client?}
\usage{
chat_addressed(client, message, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{message}{A \code{\link{chat_message}}.}

\item{...}{Adapter-specific options.}
}
\value{
\code{TRUE} or \code{FALSE}.
}
\description{
Answers the question a bot in a room full of people has to ask before
replying. Two signals feed it, and which ones exist is the adapter's
business rather than the caller's:
}
\details{
\enumerate{
\item The message's declared mentions -- Matrix \code{m.mentions},
a Slack user ref. Structured, unambiguous, and the only signal the
default method reads.
\item The plain-text conventions of the transport. Matrix has
\code{@@bot} and the full user id, Slack has \code{<@U0123>}, IRC
has a leading \code{nick:}. These are the reason this is a verb
and not a field: writing the Matrix form into a consumer is how
that consumer ends up knowing it is talking to Matrix.
}

The default reads only the declared mentions, so an adapter that does
not override it under-reports rather than over-reports. A bot that
misses being addressed stays quiet; one that thinks it was addressed
when it was not talks over people, and unprompted is worse than
absent.

}
\examples{
cl <- chat_loopback()
chat_send(cl, "general", "hi")
chat_addressed(cl, chat_poll(cl)$messages[[1L]])
}
