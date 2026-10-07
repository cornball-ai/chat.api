% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_call_updates}
\alias{chat_call_updates}
\title{What changed in a call since the last look}
\usage{
chat_call_updates(call)
}
\arguments{
\item{call}{A \code{chat_call}.}
}
\value{
A list: \code{keys}, a list of the peers' keys received
  (each \code{identity}, \code{key}, \code{index}); \code{own}, this
  client's key when it changed (\code{key}, \code{index}), else
  \code{NULL}; \code{members}, the members' identities when the
  membership changed, else \code{NULL}; \code{shared_with}, the
  identities this client's key has reached, when that set changed,
  else \code{NULL}; \code{ended}, \code{TRUE} once the call has been
  left.
}
\description{
Keys and membership that arrived through the polls since this was
last called, cleared on return. A media side in another process
forwards them: a peer's key before that peer's audio can be heard,
and this client's own key when it rotated (which it does when a
member leaves), or what it publishes stops being decodable.
}
