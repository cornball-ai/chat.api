% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_irc}
\alias{chat_irc}
\title{Create an IRC chat client}
\usage{
chat_irc(host, port = 6667L, nick, channels = character(), realname = nick)
}
\arguments{
\item{host}{Server hostname.}

\item{port}{Server port (plaintext; commonly 6667).}

\item{nick}{Nickname to register.}

\item{channels}{Character vector of channels to join (e.g.
\code{"#rstats"}).}

\item{realname}{Real-name field for USER registration.}
}
\value{
A \code{chat_client} of class \code{chat_irc}.
}
\description{
Connects, registers (NICK/USER), and joins \code{channels}. The
persistent socket buffers into \code{\link{chat_poll}}: each poll
drains available lines, answers server PINGs, and returns PRIVMSGs
as normalized messages. The cursor is a message counter.
}
