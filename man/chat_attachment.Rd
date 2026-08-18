% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_attachment}
\alias{chat_attachment}
\title{Construct a normalized attachment record}
\usage{
chat_attachment(
  id,
  name = NA_character_,
  mime = NA_character_,
  bytes = NA_integer_,
  url = NA_character_,
  path = NA_character_,
  sha256 = NA_character_,
  raw = NULL
)
}
\arguments{
\item{id}{Adapter-native identifier for the content (a Matrix mxc
URI, a Slack file id). The stable handle; everything else here is
description.}

\item{name}{Filename as the sender labeled it, or NA.}

\item{mime}{MIME type, or NA when the transport does not say.}

\item{bytes}{Size in bytes, or NA.}

\item{url}{A fetchable location, or NA. It may require this
client's credentials; a consumer must not assume it is public.}

\item{path}{Local filesystem path when the content is already on
disk, or NA.}

\item{sha256}{Content hash, or NA. Adapters fill it only when the
transport carries one (Matrix encrypted attachments do); they
must not compute it speculatively, because NA meaning
"unverified" is what tells a consumer that needs provenance to
hash at ingest and record the result.}

\item{raw}{The adapter's platform-native payload.}
}
\value{
A list with class \code{chat_attachment}.
}
\description{
Inbound media on a \code{\link{chat_message}}: \code{chat_poll()}
and \code{chat_history()} put these in the message's
\code{attachments} on adapters whose
\code{chat_capabilities()$attachments} is TRUE.
}
\examples{
chat_attachment("mxc://ex/abc", name = "plot.png", mime = "image/png")
}
