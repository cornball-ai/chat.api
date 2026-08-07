% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_identity}
\alias{chat_identity}
\title{Construct an identity record}
\usage{
chat_identity(id, display = NA_character_, raw = NULL)
}
\arguments{
\item{id}{The account identifier, in whatever form the transport
uses. Comparable against \code{\link{chat_message}}'s \code{sender}
and against the entries of its \code{mentions}: that comparability
is the point of the field, so an adapter whose two sides disagree
has a bug here rather than a choice.}

\item{display}{Human-readable name, or NA when the adapter would have
to ask the server for it. Never used for matching -- it is not
unique, and on most transports any account can set it to any other
account's. For logs and prompts only.}

\item{raw}{The adapter's platform-native identity payload.}
}
\value{
A list with class \code{chat_identity}.
}
\description{
Construct an identity record
}
\examples{
chat_identity("@bot:example.org", display = "corteza")
}
