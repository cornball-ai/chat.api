% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_slack}
\alias{chat_slack}
\title{Create a Slack chat client}
\usage{
chat_slack(token = Sys.getenv("SLACK_TOKEN"), username = "chat.api")
}
\arguments{
\item{token}{Bot token; defaults to the \code{SLACK_TOKEN}
environment variable.}

\item{username}{Default bot display name for sends (Slack allows
per-message identity; see the \code{identity} argument of
\code{\link{chat_send}}).}
}
\value{
A \code{chat_client} of class \code{chat_slack}.
}
\description{
Requires the suggested \pkg{slackr} package and a configured bot
token (see \code{slackr::slackr_setup()}).
}
