% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_relogin}
\alias{chat_relogin}
\title{Refresh this client's credentials}
\usage{
chat_relogin(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE, invisibly.
}
\description{
Forces the re-authentication that adapters otherwise perform on
demand. The refreshed credentials stay inside the client.
}
\details{
The default throws rather than returning quietly. "I could not
refresh" and "there was nothing to refresh" look identical to a
caller that gets FALSE, and the first means the next call will fail
with a stale token.

}
