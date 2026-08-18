% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_message}
\alias{chat_message}
\title{Construct a normalized chat message}
\usage{
chat_message(
  id,
  channel,
  sender,
  body,
  ts,
  thread = NULL,
  markup = "plain",
  kind = "message",
  self = NULL,
  mentions = NULL,
  raw = NULL,
  encrypted = FALSE,
  sender_verified = NULL,
  attachments = NULL
)
}
\arguments{
\item{id}{Message identifier (character).}

\item{channel}{Channel/room identifier (character).}

\item{sender}{Sender identifier (character).}

\item{body}{Message text (character).}

\item{ts}{POSIXct timestamp of when the platform recorded the
message, or \code{NA} when the transport does not report one. It is
never a stand-in for the poll's wall clock: a consumer windowing or
ordering by \code{ts} has to be able to tell a real event time from
a missing one.}

\item{thread}{Thread identifier or NULL.}

\item{markup}{Source markup hint (character, e.g. "plain", "html").}

\item{kind}{Message kind (character; "message" default). Contract
vocabulary, not platform vocabulary: \code{"message"},
\code{"notice"}, \code{"emote"}. Adapters translate their native
type into it on the way in, the same mapping \code{\link{chat_send}}
applies on the way out.}

\item{self}{Logical: did this client send the message? Poll returns
the bot's own traffic like any other, so a consumer that replies to
inbound mail needs this to avoid answering itself. NULL when the
adapter cannot tell.}

\item{mentions}{Character vector of user identifiers the message
explicitly mentioned (Matrix \code{m.mentions}, Slack user refs), or
NULL. The signal a bot in a multi-human room gates on; body
substring matching misses rich mentions that carry no plain text.}

\item{raw}{The adapter's platform-native payload for this message,
exactly as the transport layer handed it over. Shape is
adapter-specific and may already be normalized by the transport
package (Matrix hands over an extracted record, not the timeline
event), so it is an escape hatch, not a guarantee of completeness.}

\item{encrypted}{Logical: did this message arrive end-to-end
encrypted? FALSE on transports without E2EE and on cleartext
messages in rooms that have it.}

\item{sender_verified}{Logical: does the sender identifier bind to a
device whose keys this client verified? NULL on cleartext messages,
where the transport asserts the sender and there is nothing to
verify. On an encrypted message FALSE is a real answer, not a
missing one: the payload decrypted, but its claimed sender could not
be tied to a verified device, so the identifier is the homeserver's
word rather than cryptographic fact.}

\item{attachments}{List of \code{\link{chat_attachment}} records,
or NULL. Inbound media: what a sent \code{files =} looks like
from the receiving side, on adapters whose
\code{chat_capabilities()$attachments} is TRUE.}
}
\value{
A list with class \code{chat_message}.
}
\description{
The record every adapter's \code{\link{chat_poll}} returns.
}
