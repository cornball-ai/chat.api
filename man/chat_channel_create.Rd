% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_channel_create}
\alias{chat_channel_create}
\title{Create a channel}
\usage{
chat_channel_create(client, name, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{name}{Character. Human-readable name for the new channel.}

\item{...}{Adapter-specific options (topic, visibility, invitees).}
}
\value{
The new channel's identifier, invisibly. Everything else --
  sends, joins, membership -- takes the identifier, not the name,
  so the return value is the point of the call.
}
\description{
Capability-gated: check \code{chat_capabilities()$channel_create}.
Bots open rooms about as often as they are invited to them; a
contract without creation forces every such consumer below the
seam, into adapter-native calls.
}
\examples{
cl <- chat_loopback()
id <- chat_channel_create(cl, "general")
chat_send(cl, id, "hello")
}
