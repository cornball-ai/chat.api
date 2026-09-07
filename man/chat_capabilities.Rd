% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_capabilities}
\alias{chat_capabilities}
\title{Describe what a chat client's platform supports}
\usage{
chat_capabilities(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
A list with at least: \code{threads} (can post into
  threads), \code{thread_replies} (thread replies come back out of
  \code{\link{chat_poll}}), \code{edits}, \code{reactions}
  (\code{\link{chat_react}} works), \code{reaction_events} (reactions
  come back out of \code{\link{chat_poll}}), \code{channel_info}
  (\code{\link{chat_channel_info}} works), \code{members}
  (\code{\link{chat_members}} works), \code{invites} (invitations come
  back out of \code{\link{chat_poll}}), \code{join}
  (\code{\link{chat_join}} works), \code{whoami}
  (\code{\link{chat_whoami}} works, and with it the default
  \code{\link{chat_addressed}}), \code{channel_create}
  (\code{\link{chat_channel_create}} works), \code{leave}
  (\code{\link{chat_leave}} works), \code{set_state}
  (durable channel state: both \code{\link{chat_set_state}} and
  \code{\link{chat_get_state}} work -- a transport has the pair or
  neither), \code{files} (outbound:
  \code{chat_send(files =)} works), \code{attachments} (inbound:
  media comes back out of \code{\link{chat_poll}} as
  \code{\link{chat_attachment}} records), \code{typing},
  \code{e2ee}, \code{identity_override} (logicals),
  \code{markup_dialects} (character), \code{max_message_bytes}
  (integer or NA).

  Sending and receiving get separate flags wherever a platform does
  one and not the other, which is why \code{threads} and
  \code{thread_replies} are two entries rather than one. Reactions
  split the same way: Slack can place one, and does not report anyone
  else's through the history endpoint this adapter polls, so a
  consumer reading a single flag would wait forever for events that
  never arrive.
}
\description{
Describe what a chat client's platform supports
}
