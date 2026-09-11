% tinyrox says don't edit this manually, but it can't stop you!
\name{chat.api-package}
\alias{chat.api-package}
\alias{chat.api}
\title{Transport-agnostic chat connectivity}
\description{
A common interface for chat messages, attachments, rooms, and identity.
Use \code{\link{chat_loopback}} for local development, or connect through
\code{\link{chat_matrix}}, \code{\link{chat_irc}},
\code{\link{chat_slack}}, or \code{\link{chat_telegram}}.
Inspect \code{\link{chat_capabilities}} before using optional operations.
}
\examples{
cl <- chat_loopback()
chat_send(cl, "general", "hello")
chat_poll(cl)$messages
}
\keyword{package}
