% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_channel_info}
\alias{chat_channel_info}
\title{Describe a channel}
\usage{
chat_channel_info(client, channel, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{...}{Adapter-specific options.}
}
\value{
A list with \code{id}, \code{name}, and \code{topic}.
  \code{id} is the channel as the platform addresses it; \code{name}
  and \code{topic} are character or NULL.
}
\description{
Returns the channel's descriptive metadata: what it is called and what
it is for.
}
\details{
Membership is deliberately not here, and \code{\link{chat_members}} is
a separate verb. The two look like one lookup and are not: a name and
a topic are two short strings that change rarely, while a member list
is unbounded and changes constantly. Bundling them makes every read of
a topic pay for a member list, which on a busy room is the expensive
part -- and a consumer caches the two on different schedules for
exactly that reason.

A NULL field means the channel has no such thing: a Matrix room with
no \code{m.room.name} really has no name. An adapter that cannot
answer at all throws, so "cannot ask" and "asked, and there is none"
stay distinguishable. Check \code{chat_capabilities()$channel_info}
first.

}
