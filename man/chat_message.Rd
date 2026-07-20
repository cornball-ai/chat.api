% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_message}
\alias{chat_message}
\title{Construct a normalized chat message}
\usage{
chat_message(id, channel, sender, body, ts, thread = NULL, markup = "plain",
             kind = "message", raw = NULL)
}
\arguments{
\item{id}{Message identifier (character).}

\item{channel}{Channel/room identifier (character).}

\item{sender}{Sender identifier (character).}

\item{body}{Message text (character).}

\item{ts}{POSIXct timestamp.}

\item{thread}{Thread identifier or NULL.}

\item{markup}{Source markup hint (character, e.g. "plain", "html").}

\item{kind}{Message kind (character; "message" default).}

\item{raw}{The platform-native event, unmodified.}
}
\value{
A list with class \code{chat_message}.
}
\description{
The record every adapter's \code{\link{chat_poll}} returns. \code{raw}
carries the untouched platform event for consumers that need more.
}
