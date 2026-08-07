% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_pending}
\alias{chat_pending}
\title{Read standing state that is not tied to a cursor}
\usage{
chat_pending(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
A list with \code{invites}, a list of \code{\link{chat_invite}}.
}
\description{
Today: pending invitations. \code{\link{chat_poll}} reports an
invitation when it arrives, which is no help to a client that was not
running at the time -- and some homeservers only report invites newer
than the \code{since} token, so the poll loop never sees them again.
}
\details{
This is a separate verb rather than a mode of \code{\link{chat_poll}}
deliberately. Overloading the cursor would make "start from nothing"
and "tell me what is standing" the same call, and a client that asked
for pending invitations and thereby reset its read position would
replay every channel it is in.

}
\examples{
\dontrun{
pending <- chat_pending(client)
for (iv in pending$invites) chat_join(client, iv$channel)
}
}
