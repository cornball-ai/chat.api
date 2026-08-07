% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_edit}
\alias{chat_edit}
\title{Replace the text of a message already sent}
\usage{
chat_edit(
  client,
  channel,
  message_id,
  text,
  markup = c("plain", "markdown"),
  rich = NULL,
  ...
)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{channel}{Channel/room identifier.}

\item{message_id}{The message to replace, as returned by
\code{\link{chat_send}}.}

\item{text}{The replacement text, in full. Not a delta: every
platform that supports this takes the whole new body, and a
contract that took a patch would have to reconstruct the old one to
apply it.}

\item{markup}{\code{"plain"} or \code{"markdown"}, as
\code{\link{chat_send}}.}

\item{...}{Adapter-specific options.}
}
\value{
The identifier of the event the edit created where the
  platform makes one (Matrix), or of the edited message where it does
  not (Slack), invisibly.
}
\description{
What makes a progress message possible: post "working on it", then
keep replacing it as the work happens, instead of narrating into the
channel one message at a time.
}
\details{
The default throws. An edit that silently does nothing leaves the old
text on screen, and stale content is worse than a visible failure --
the reader has no way to tell that what they are looking at is no
longer true. Check \code{chat_capabilities()$edits}.

}
\section{What a consumer must not assume}{
That the edit is what readers see. A client that does not implement
edits shows the original and an "* edited" fallback beside it, and
notifications almost always carry the text as first sent. So the
first version has to stand on its own -- "working on it" is a fine
thing to be paged with, a half-finished sentence is not.
}
