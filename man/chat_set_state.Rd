% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_set_state}
\alias{chat_set_state}
\title{Set durable typed state on a channel}
\usage{
chat_set_state(client, channel, type, content, state_key = "", ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{type}{Character. Namespaced event type, e.g.
\code{"m.room.topic"} or a reversed-domain custom type.}

\item{content}{Named list. The state content. A write replaces the
whole content for its \code{type}/\code{state_key} pair; there is
no merge.}

\item{state_key}{Character. Sub-key within the type. Most state is
keyed by the empty string, the default.}

\item{...}{Adapter-specific options.}
}
\value{
The state event's identifier where the platform gives one
  (Matrix), invisibly; \code{TRUE} where it does not.
}
\description{
Attaches a typed, durable piece of metadata to a channel, readable
by every client in it and replaced by the next write to the same
\code{type} and \code{state_key}. On Matrix this is a state event;
most platforms have no equivalent, which is why it is
capability-gated: check \code{chat_capabilities()$set_state}.
}
\details{
The default method throws, on \code{\link{chat_react}}'s reasoning:
a state write that silently did nothing leaves the caller believing
a marker is set that no reader will ever see.

}
