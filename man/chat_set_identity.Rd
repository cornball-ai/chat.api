% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_set_identity}
\alias{chat_set_identity}
\title{Set this client's persistent identity}
\usage{
chat_set_identity(client, display = NULL, avatar = NULL, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{display}{New display name, or NULL to leave it as it is.}

\item{avatar}{Path to an image file for the account's picture, or
NULL to leave it. Set where the platform lets a bot change its own
picture: Matrix uploads the file and points the profile at it. An
adapter whose platform sets a bot's picture outside its API
ignores it, on \code{\link{chat_typing}}'s reasoning, and answers
FALSE when it was all that was asked for.}

\item{...}{Adapter-specific options.}
}
\value{
TRUE if the identity was changed, invisibly; FALSE when
  nothing was asked for that the adapter can set.
}
\description{
The account's own display name and, where the platform lets a bot
set one, its picture, as everyone in every channel sees them until
they are changed again. Distinct from \code{\link{chat_send}}'s
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
\examples{
\dontrun{
# Requires a saved Matrix configuration and account credentials.
cl <- chat_matrix(app = "mybot")
chat_set_identity(cl, "Example Bot")
chat_set_identity(cl, avatar = "face.png")
}
}
