% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_channel_invite}
\alias{chat_channel_invite}
\title{Invite a user to a channel}
\usage{
chat_channel_invite(client, channel, user, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{user}{The invitee's platform identifier, such as a Matrix user
id (\code{"@alice:example.org"}).}

\item{...}{Adapter-specific options.}
}
\value{
The channel identifier, invisibly.
}
\description{
The other side of an invitation: \code{\link{chat_poll}} reports the
ones this client receives, and this verb issues one. A bot that files
rooms for people needs it about as often as it needs
\code{\link{chat_channel_create}}, because a room nobody but the bot
can enter does not exist for anyone else. Capability-gated: check
\code{chat_capabilities()$channel_invite}.
}
\details{
The default method throws, on \code{\link{chat_join}}'s reasoning: an
invitation that silently did not go out leaves the caller believing
someone can see a room they cannot.

}
\examples{
cl <- chat_loopback()
chat_channel_invite(cl, "general", "@alice:example.org")
}
