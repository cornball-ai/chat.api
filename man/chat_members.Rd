% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_members}
\alias{chat_members}
\title{List a channel's members}
\usage{
chat_members(client, channel, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{...}{Adapter-specific options.}
}
\value{
Character vector of member identifiers. Empty when the channel
  has none; an adapter that cannot answer throws, so an empty room is
  never confused with an unanswerable question. Check
  \code{chat_capabilities()$members} first.
}
\description{
Separate from \code{\link{chat_channel_info}} because it is the
expensive half: a member list is unbounded where a name and a topic
are two short strings, and it goes stale on a different schedule.
}
