% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_slack}
\alias{chat_slack}
\title{Create a Slack chat client}
\usage{
chat_slack(channels = character(), token = Sys.getenv("SLACK_TOKEN"),
           username = NULL)
}
\arguments{
\item{channels}{Character vector of channels to poll.}

\item{token}{Bot token; defaults to the \code{SLACK_TOKEN}
environment variable.}

\item{username}{Default display-name override for sends, or NULL
(default) to post as the bot's own identity. Any override,
including via \code{chat_send(identity =)}, needs the
chat:write.customize scope on the token.}
}
\value{
A \code{chat_client} of class \code{chat_slack}.
}
\description{
Requires the suggested \pkg{slackr} package and a bot token.
Channel names are normalized to bare names (no \code{#}), matching
what slackr's channel translation accepts.
}
