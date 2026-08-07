% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_matrix_config}
\alias{chat_matrix_config}
\title{Load a Matrix configuration}
\usage{
chat_matrix_config(app = NULL, path = NULL, env_var = NULL)
}
\arguments{
\item{app}{Application namespace, e.g. \code{"corteza"}. Decides the
default path under \code{tools::R_user_dir(app, "config")}.}

\item{path}{Explicit file path, overriding \code{app}'s default.}

\item{env_var}{Name of an environment variable that, when set,
overrides both.}
}
\value{
A list with class \code{chat_config}.
}
\description{
Reads the credentials an application saved, and returns them as a
\code{chat_config}: a list carrying the transport's own fields plus
whatever else the application stored alongside them, with the app
namespace and file path attached as attributes so
\code{\link{chat_config_save}} can write it back where it came from.
}
\section{Why the extra fields survive}{
Applications keep their own settings in the same file -- which
accounts count as bots, who may open a private conversation, a
preferred model. Those are the application's, not the transport's,
and a loader that dropped them would make the file unreadable by its
owner. They pass through untouched and unvalidated.

}
\examples{
\dontrun{
cfg <- chat_matrix_config(app = "corteza",
                          env_var = "CORTEZA_MATRIX_CONFIG")
client <- chat_matrix(mx = cfg)
}
}
