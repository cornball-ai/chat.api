% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_telegram}
\alias{chat_telegram}
\title{Create a Telegram chat client}
\usage{
chat_telegram(
  token = Sys.getenv("TELEGRAM_BOT_TOKEN"),
  timeout = 30L,
  api_url = "https://api.telegram.org",
  .api = NULL,
  .download = NULL
)
}
\arguments{
\item{token}{Bot token; defaults to the \code{TELEGRAM_BOT_TOKEN}
environment variable.}

\item{timeout}{Long-poll wait in seconds, used by
\code{\link{chat_poll}} when it is given no \code{timeout}.}

\item{api_url}{Base URL of the Bot API. The default is Telegram's;
a local Bot API server takes its own.}

\item{.api}{Testing seam: replacement for the HTTP layer, a
\code{function(method, params, files)} returning the parsed
response (\code{list(ok =, result =)}). \code{params} arrives
already in wire form: NULLs dropped, logicals as
\code{"true"}/\code{"false"}, numbers as plain digits. Leave NULL
in production.}

\item{.download}{Testing seam: replacement for the file fetch, a
\code{function(file_path, dest)} writing the bytes behind a
getFile path to \code{dest}. Leave NULL in production; when both
seams are supplied the httr package is not required.}
}
\value{
A \code{chat_client} of class \code{chat_telegram}.
}
\description{
Requires the suggested \pkg{httr} package and a bot token from
BotFather.
}
\details{
Channels are chat identifiers as Telegram reports them -- a
positive number for a private chat, a negative one for a group or
channel -- always as character. \code{\link{chat_resolve}} turns a
public \code{@@username} into one.

The first poll returns whatever updates Telegram is still holding
for the bot (it keeps them for 24 hours). That is the mail that
arrived while the bot was down rather than channel history, so it
comes out as ordinary traffic. Passing the returned cursor back as
\code{since} confirms it; Telegram re-sends anything unconfirmed.

}
