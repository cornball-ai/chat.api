% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_history}
\alias{chat_history}
\title{Read a channel's recent messages}
\usage{
chat_history(client, channel, limit = 50L, cursor = NULL, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{limit}{Maximum messages to return.}

\item{cursor}{Opaque continuation token from a previous call's
\code{cursor}, to read the page before it; NULL starts from the most
recent.}

\item{...}{Adapter-specific options.}
}
\value{
A list with \code{messages} (list of \code{\link{chat_message}},
  oldest first) and \code{cursor} (opaque; pass it back to read
  further into the past, NULL when the channel has no more history).
}
\description{
Independent of the poll cursor: a restarted process uses this to
recover the context it lost, and asking for it must not move the
cursor or consume anything.
}
\section{The cursor is opaque, like chat_poll's}{
Not a message id. This started out taking one and it was wrong on the
reference transport: Matrix's \code{/messages} takes a pagination
token from a previous response, and handing it an event id does not
page from that event -- it fails, or worse, silently returns the wrong
window. Slack pages by its own \code{next_cursor}. There is no id that
means the same thing on both, so the contract does what it already
does for \code{\link{chat_poll}}: the token is the adapter's, and a
consumer only ever passes back what it was given.

}
\section{Order}{
Chronological, oldest first, whatever the platform's native direction
is. Matrix \code{dir = "b"} and Slack \code{conversations.history}
both hand back newest-first and every consumer replaying history into
a transcript has to flip it. One flip in the adapter beats one per
consumer, and a consumer that gets it wrong produces a transcript
that reads backwards without erroring.

Note that pages run backwards while each page runs forwards: call it
twice and the second page's messages all precede the first page's.
A consumer assembling a full transcript prepends.

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
chat_history(cl, "general")$messages
}
