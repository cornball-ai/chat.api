% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_matrix_configure}
\alias{chat_matrix_configure}
\title{Configure a Matrix account interactively}
\usage{
chat_matrix_configure(
  server,
  user,
  password,
  room = NULL,
  app = NULL,
  path = NULL,
  device_id = NULL,
  extra = list()
)
}
\arguments{
\item{server}{Homeserver base URL.}

\item{user}{Localpart or full user id.}

\item{password}{Account password.}

\item{room}{Room id or alias to record as the default.}

\item{app}{Application namespace to save under.}

\item{path}{Explicit path to save to, overriding \code{app}.}

\item{device_id}{Device id to log in as. Reusing one keeps an
existing E2EE identity; a new one starts a new device.}

\item{extra}{Named list of application fields to store alongside the
credentials.}
}
\value{
A \code{\link{chat_config}}, invisibly.
}
\description{
Logs in to a homeserver, resolves the room, and writes the resulting
credentials.
}
\examples{
\dontrun{
cfg <- chat_matrix_configure(server = "https://matrix.example.org",
                             user = "bot", password = pw,
                             room = "#lab:example.org", app = "corteza")
}
}
