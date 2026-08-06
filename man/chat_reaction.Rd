% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_reaction}
\alias{chat_reaction}
\title{Construct a normalized reaction record}
\usage{
chat_reaction(id, channel, sender, target, key, ts, self = NULL, raw = NULL)
}
\arguments{
\item{id}{The reaction's own identifier, or NULL where the platform
does not give it one. Not the identifier of the message it is
attached to -- see \code{target}.}

\item{channel}{Channel/room identifier (character).}

\item{sender}{Sender identifier (character).}

\item{target}{Identifier of the message being reacted to (character).}

\item{key}{The reaction itself (character): an emoji on Matrix, a
short name on Slack.}

\item{ts}{POSIXct timestamp, or \code{NA} when the transport does not
report one -- the same rule \code{\link{chat_message}} follows, and
for the same reason.}

\item{self}{Logical: did this client place the reaction? A consumer
that reacts to acknowledge needs this to avoid answering its own
acknowledgement. NULL when the adapter cannot tell.}

\item{raw}{The adapter's platform-native payload.}
}
\value{
A list with class \code{chat_reaction}.
}
\description{
The record \code{\link{chat_poll}} returns in \code{$reactions} on
adapters whose \code{chat_capabilities()$reaction_events} is TRUE.
}
\details{
Deliberately not a \code{\link{chat_message}}. A reaction has a target
and no body, and the message record has a body and no target;
\code{thread} is the closest slot and it means something else, so
folding one into the other would make every consumer disambiguate by
inspecting fields.

}
