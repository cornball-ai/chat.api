% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_history}
\alias{chat_history}
\title{Read a channel's recent messages}
\usage{
chat_history(client, channel, limit = 50L, before = NULL, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{limit}{Maximum messages to return.}

\item{before}{Return messages older than this message id, for paging
backwards; NULL starts from the most recent.}

\item{...}{Adapter-specific options.}
}
\value{
A list of \code{\link{chat_message}}, oldest first.
}
\description{
Independent of the poll cursor: a restarted process uses this to
recover the context it lost, and asking for it must not move the
cursor or consume anything.
}
\section{Order}{
Chronological, oldest first, whatever the platform's native direction
is. Matrix \code{dir = "b"} and Slack \code{conversations.history}
both hand back newest-first and every consumer replaying history into
a transcript has to flip it. One flip in the adapter beats one per
consumer, and a consumer that gets it wrong produces a transcript
that reads backwards without erroring.

}
\section{Overlap with chat_poll}{
The same message can arrive from both, and adapters must return the
same \code{id} for it either way. That id is the only thing a consumer
has to deduplicate on -- a startup backfill and the first poll after
it routinely cover the same events.
}
\examples{
cl <- chat_loopback()
chat_send(cl, "general", "hello")
chat_history(cl, "general")
}
