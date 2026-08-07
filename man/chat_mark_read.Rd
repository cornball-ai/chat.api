% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_mark_read}
\alias{chat_mark_read}
\title{Mark a message as read}
\usage{
chat_mark_read(client, channel, message_id, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{message_id}{The message to mark read, and everything before it.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE if the marker was sent, FALSE otherwise, invisibly.
}
\description{
The default is a quiet FALSE, on \code{\link{chat_typing}}'s
reasoning rather than \code{\link{chat_react}}'s: a read marker that
does not appear costs a human a little context about what the bot has
seen, and nothing more. Nobody is waiting on it the way they wait on
an acknowledgement.
}
\details{
Write-only. Reading other participants' read state is a much larger
surface -- per-user, per-device, and absent entirely on some
platforms -- and no consumer needs it yet.

}
