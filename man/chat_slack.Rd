% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_slack}
\alias{chat_slack}
\title{Create a Slack chat client}
\usage{
chat_slack(channels = character(), token = Sys.getenv("SLACK_TOKEN"),
           username = "chat.api")
}
\arguments{
\item{channels}{Character vector of channels to poll.}

\item{token}{Bot token; defaults to the \code{SLACK_TOKEN}
environment variable.}

\item{username}{Default bot display name for sends. Slack allows
per-message identity: the \code{identity} argument of
\code{\link{chat_send}} overrides name and icon per post.}
}
\value{
A \code{chat_client} of class \code{chat_slack}.
}
\description{
Requires the suggested \pkg{slackr} package and a bot token.
\code{\link{chat_poll}} polls \code{slackr::slackr_history()} for
each configured channel; the cursor is a named list of per-channel
message timestamps.
}
