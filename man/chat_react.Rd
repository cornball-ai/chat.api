% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_react}
\alias{chat_react}
\title{React to a message}
\usage{
chat_react(client, channel, message_id, key, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{message_id}{Identifier of the message being reacted to, as
returned by \code{\link{chat_send}} or carried on a
\code{\link{chat_message}}'s \code{id}.}

\item{key}{The reaction itself. Platforms differ on what they accept:
Matrix takes any string and conventionally an emoji character,
Slack takes a short name without colons (\code{"thumbsup"}). Passed
through unchanged, since translating between the two would have to
guess.}

\item{...}{Adapter-specific options.}
}
\value{
The reaction's identifier where the platform gives it one
  (Matrix), invisibly; \code{TRUE} where it does not (Slack).
}
\description{
Places a reaction (an emoji or short key) on an existing message.
}
\details{
The default method throws. A reaction that silently does nothing is
worse than one that fails: the caller believes it acknowledged
something and no one can see that it did not. This differs from
\code{\link{chat_typing}}, whose default is a quiet FALSE, because a
missing typing indicator costs nothing and a missing acknowledgement
can be the whole message. Check \code{chat_capabilities()$reactions}
before calling on an unknown adapter.

}
