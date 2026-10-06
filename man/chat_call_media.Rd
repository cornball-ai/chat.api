% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_call_media}
\alias{chat_call_media}
\title{What a media client needs to join a call}
\usage{
chat_call_media(call)
}
\arguments{
\item{call}{A \code{chat_call}.}
}
\value{
A list: \code{url}, \code{jwt}, \code{identity},
  \code{key} (a list with \code{key}, raw bytes, and \code{index}),
  and \code{peers}, a list of the other members' keys known so far,
  each a list with \code{identity}, \code{key} and \code{index}.
}
\description{
The media server's address, the token that admits this identity, the
identity itself, and this client's current media key, as the adapter
holds them now. Taken once when the media side starts; a key that
rotates later arrives through \code{\link{chat_call_updates}}.
}
