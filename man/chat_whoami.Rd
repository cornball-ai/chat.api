% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_whoami}
\alias{chat_whoami}
\title{Who is this client logged in as?}
\usage{
chat_whoami(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
A \code{\link{chat_identity}}.
}
\description{
The client's own account, as the transport identifies it.
}
\details{
The default method throws rather than guessing. Every use of an
identity is a comparison -- is this message mine, did someone address
me -- and a wrong answer to either is silent: the bot answers itself
in a loop, or never answers anyone. An adapter that cannot say who it
is should say so.

}
\examples{
chat_whoami(chat_loopback())
}
