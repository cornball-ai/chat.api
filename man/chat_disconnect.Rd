% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_disconnect}
\alias{chat_disconnect}
\title{Close a chat client's connection}
\usage{
chat_disconnect(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE, invisibly.
}
\description{
The default method is a no-op: HTTP-poll transports have nothing to
close. Persistent-socket transports (IRC) override it.
}
