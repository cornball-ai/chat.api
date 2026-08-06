% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_slack}
\alias{chat_slack}
\title{Create a Slack chat client}
\usage{
chat_slack(
  channels = character(),
  token = Sys.getenv("SLACK_TOKEN"),
  username = NULL,
  .history = NULL,
  .post = NULL,
  .react = NULL,
  .api = NULL
)
}
\arguments{
\item{channels}{Character vector of channels to poll.}

\item{token}{Bot token; defaults to the \code{SLACK_TOKEN}
environment variable.}

\item{username}{Default display-name override for sends, or NULL
(default) to post as the bot's own identity.}

\item{.history}{Testing seam: replacement for
\code{slackr::slackr_history}. Leave NULL in production.}

\item{.post}{Testing seam: replacement for
\code{slackr::slackr_msg}. Leave NULL in production; when both
seams are supplied the slackr package is not required.}

\item{.react}{Testing seam: replacement for
\code{slackr::call_slack_api}. Leave NULL in production. Resolved
when \code{chat_react()} is called, not here.}

\item{.api}{Testing seam: replacement for
\code{slackr::call_slack_api} on the read paths
(\code{chat_channel_info()}, \code{chat_members()}). Leave NULL in
production.}
}
\value{
A \code{chat_client} of class \code{chat_slack}.
}
\description{
Requires the suggested \pkg{slackr} package and a bot token.
Channel names are normalized to bare names (no \code{#}), matching
what slackr's channel translation accepts.
}
\details{
Sends explicitly suppress slackr's \code{SLACK_USERNAME} /
\code{SLACK_ICON_EMOJI} environment defaults: a plain
\code{chat_send()} posts as the bot's own identity, and authorship
is only overridden through \code{username} here or
\code{chat_send(identity =)} (both need the chat:write.customize
scope).

}
