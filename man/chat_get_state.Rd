% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_get_state}
\alias{chat_get_state}
\title{Read durable typed state from a channel}
\usage{
chat_get_state(client, channel, type, state_key = "", ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{type}{Character. Namespaced event type.}

\item{state_key}{Character. Sub-key within the type, defaulting to
the empty string.}

\item{...}{Adapter-specific options.}
}
\value{
The stored content as a named list, or \code{NULL} when no
  state is set for that \code{type}/\code{state_key} pair.
}
\description{
The counterpart of \code{\link{chat_set_state}}, reading back what
it wrote. Capability-gated on the same
\code{chat_capabilities()$set_state}: a transport with durable
channel state has both halves or neither.
}
\details{
Absent state is \code{NULL}, not an error. "Nothing was ever
written here" is an ordinary answer for a caller checking whether a
marker is set, and one it should not have to wrap in a handler. A
state store that cannot be reached at all still errors, because
that is a different fact.

}
