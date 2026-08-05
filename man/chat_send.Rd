% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_send}
\alias{chat_send}
\title{Send a message through a chat client}
\usage{
chat_send(
  client,
  channel,
  text,
  markup = c("plain", "markdown"),
  thread = NULL,
  reply_to = NULL,
  identity = NULL,
  files = NULL,
  kind = "message",
  notify = TRUE,
  ...
)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier (adapter-native or resolved
via \code{\link{chat_resolve}}).}

\item{text}{Message text.}

\item{markup}{\code{"plain"} or \code{"markdown"}; adapters render
markdown to their dialect (HTML for Matrix, mrkdwn for Slack,
stripped for IRC).}

\item{thread}{Thread identifier to post into, or NULL.}

\item{reply_to}{Message id being replied to, or NULL.}

\item{identity}{Optional per-message identity override
(\code{list(name =, icon =)}) where the platform supports it.}

\item{files}{Character vector of file paths to attach, or NULL.}

\item{kind}{Message kind; \code{"message"} (default) or an
adapter-understood alternative (e.g. \code{"notice"}, \code{"emote"}).}

\item{notify}{Logical; FALSE requests a silent delivery where
supported.}

\item{...}{Adapter-specific options.}
}
\value{
Character vector of the message ids this call created, in the
  order they were sent, invisibly. Usually length one. A platform that
  splits a send into several events returns one id per event: the
  Matrix adapter sends each attachment as its own event, so a send
  with files returns the attachment ids followed by the text id.
  Callers that track their own traffic by id must handle every
  element, or an unclaimed event reads as somebody else's message.
}
\description{
Send a message through a chat client
}
