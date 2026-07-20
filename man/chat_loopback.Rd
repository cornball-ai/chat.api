% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_loopback}
\alias{chat_loopback}
\title{Create a loopback chat client}
\usage{
chat_loopback()
}
\value{
A \code{chat_client} of class \code{chat_loopback}.
}
\description{
Messages sent to any channel are appended to an in-memory log and
come back out of \code{\link{chat_poll}}. The cursor is the integer
position in that log.
}
\examples{
cl <- chat_loopback()
chat_send(cl, "general", "hello")
chat_poll(cl)$messages
}
