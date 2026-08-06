% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_invite}
\alias{chat_invite}
\title{Construct a normalized invitation record}
\usage{
chat_invite(channel, inviter = NA_character_, raw = NULL)
}
\arguments{
\item{channel}{Channel/room identifier the client has been invited to
(character). Pass it to \code{\link{chat_join}} to accept.}

\item{inviter}{Who issued the invitation, or \code{NA} when the
transport does not say. NA rather than NULL, and deliberately: a
consumer deciding whether to accept has to tell "someone I do not
trust" from "I could not tell who", and both refuse for different
reasons. NULL would collapse the second into the absence of a field.}

\item{raw}{The adapter's platform-native payload.}
}
\value{
A list with class \code{chat_invite}.
}
\description{
The record \code{\link{chat_poll}} returns in \code{$invites} on
adapters whose \code{chat_capabilities()$invites} is TRUE.
}
\section{No timestamp}{
Unlike \code{\link{chat_message}} and \code{\link{chat_reaction}},
there is no \code{ts}. An invitation is a standing state rather than
an event at a moment, and Matrix's stripped invite state carries no
reliable \code{origin_server_ts} to report. A field that could only
ever be NA is worse than no field.
}
