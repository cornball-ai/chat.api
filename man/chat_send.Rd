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
  rich = NULL,
  content = NULL,
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

\item{rich}{Adapter-native markup for the platforms that accept it,
or NULL. Matrix takes an HTML fragment and sends it as
\code{formatted_body}, Telegram sends it with the HTML parse mode;
adapters whose \code{chat_capabilities()$rich_markup} is empty
ignore it.

\code{text} is still required and still has to stand on its own. It
is what a client that cannot render the markup shows, what a push
notification carries, and what every other transport gets -- so a
\code{rich} that holds the real content and a \code{text} that says
"see above" is a message half the room cannot read.

Ignored rather than refused where unsupported, on
\code{\link{chat_typing}}'s reasoning: the text is the message and
the markup is decoration, so losing it costs presentation and
nothing else.}

\item{content}{Keys of the caller's own for the message's content, as
a named list, or NULL. Matrix adds them to the \code{m.room.message}
content beside \code{body} and \code{msgtype}, inside the ciphertext
in an encrypted room, so a consumer can carry data its own client
reads and every other client ignores, under a namespaced key such
as \code{"ai.cornball.agent"}. A received message carries its
content in \code{raw$content}, and the loopback adapter records
these keys there too; the other adapters ignore them, as they
ignore \code{rich}, so \code{text} has to stand on its own.

A key chat.api writes itself is refused: \code{body},
\code{msgtype}, \code{format}, \code{formatted_body},
\code{m.relates_to}, \code{m.mentions} and \code{m.new_content}.
\code{text}, \code{kind}, \code{rich}, \code{thread} and the
\code{mentions} option set those. With \code{files}, the keys go on
the text's event, not on the attachments'.}

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
\examples{
cl <- chat_loopback()
id <- chat_send(cl, "general", "hello", markup = "plain")
chat_send(cl, "general", "a reply", thread = id)
chat_poll(cl)$messages
}
