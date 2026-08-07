% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_matrix_config_path}
\alias{chat_matrix_config_path}
\title{Where a Matrix configuration lives}
\usage{
chat_matrix_config_path(app, env_var = NULL, legacy = FALSE)
}
\arguments{
\item{app}{Application namespace.}

\item{env_var}{Name of an environment variable that overrides the
default path, or NULL.}

\item{legacy}{Return the pre-\code{R_user_dir} location instead, for
an application that needs to migrate an older file.}
}
\value{
The file path (character).
}
\description{
Where a Matrix configuration lives
}
\examples{
chat_matrix_config_path("demo")
}
