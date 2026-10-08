% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_call_join}
\alias{chat_call_join}
\title{Join a channel's call}
\usage{
chat_call_join(client, channel, intent = "voice", ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{intent}{\code{"voice"} or \code{"video"}, what the membership
announces.}

\item{...}{Adapter-specific options. Matrix: \code{service_url}, the
media token service to use instead of discovering one.}
}
\value{
A \code{chat_call}: an environment the adapter keeps
  advancing on every poll until \code{\link{chat_call_leave}}. Its
  \code{channel} and \code{identity} are plain fields.
}
\description{
Takes part in the channel's live call as this client's identity: the
signaling side only. The client announces itself as a call member,
obtains the media server's address and a token for it, and exchanges
media keys with the other members as they come and go, for as long
as the client keeps polling. The media itself (joining the media
server, audio in and out) is the caller's, typically in another
process: \code{\link{chat_call_media}} gives it what it needs, and
\code{\link{chat_call_updates}} the keys that arrive later. Every
\code{\link{chat_poll}} on the client advances its calls.
Capability-gated: check \code{chat_capabilities()$calls}.
}
\details{
On Matrix this is a MatrixRTC call (what Element Call and FluffyChat
2.10 join), over LiveKit, encrypted end to end with per-member keys
sent over Olm; it needs an \code{e2ee} client.

}
\examples{
\dontrun{
cl <- chat_matrix(app = "mybot", e2ee = TRUE)
call <- chat_call_join(cl, "!room:example.org")
chat_call_media(call)$url
repeat {
    chat_poll(cl, timeout = 1)
    upd <- chat_call_updates(call)
    for (k in upd$keys) message("key from ", k$identity)
}
}
}
