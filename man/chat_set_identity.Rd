% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_set_identity}
\alias{chat_set_identity}
\title{Set this client's persistent identity}
\usage{
chat_set_identity(client, display, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{display}{New display name.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE if the identity was changed, invisibly.
}
\description{
The account's own display name, as everyone in every channel sees it
until it is changed again. Distinct from \code{\link{chat_send}}'s
\code{identity} argument, which decorates a single message on
platforms that allow it.
}
\details{
Owning this matters beyond tidiness. On Matrix the rename is an
authenticated call that can rotate the access token underneath the
caller, and a consumer that made that call itself had to notice the
rotation and get the new token back into its client -- usually via
whatever file both of them happened to share. Behind the contract the
rotation lands in the client that performed it, and nothing outside
has to know it happened.

}
