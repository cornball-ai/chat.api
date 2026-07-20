% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_resolve}
\alias{chat_resolve}
\title{Resolve a human channel name to its identifier}
\usage{
chat_resolve(client, name, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{name}{Channel name, alias, or identifier.}

\item{...}{Adapter-specific options.}
}
\value{
The adapter-native channel identifier (character).
}
\description{
Resolve a human channel name to its identifier
}
