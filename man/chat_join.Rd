% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_join}
\alias{chat_join}
\title{Join a channel}
\usage{
chat_join(client, channel, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier, as carried on a
\code{\link{chat_invite}}'s \code{channel} or resolved by
\code{\link{chat_resolve}}.}

\item{...}{Adapter-specific options.}
}
\value{
The joined channel's identifier, invisibly.
}
\description{
Accepts a pending invitation, or joins an open channel where the
platform allows it.
}
\details{
The default method throws, on the same reasoning as
\code{\link{chat_react}}: a join that silently does nothing leaves the
caller believing it is in a room it will never hear from. Check
\code{chat_capabilities()$join}.

}
