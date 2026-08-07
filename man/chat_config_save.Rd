% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_config_save}
\alias{chat_config_save}
\title{Persist a configuration}
\usage{
chat_config_save(config, app = NULL, path = NULL)
}
\arguments{
\item{config}{A \code{\link{chat_config}}, or a plain list together
with \code{app}/\code{path}.}

\item{app}{Override the app namespace the config was loaded under.}

\item{path}{Override the file to write.}
}
\value{
The config, invisibly.
}
\description{
Writes to the file the config came from, at mode 0600.
}
\examples{
\dontrun{
cfg$operators <- "@troy:example.org"
chat_config_save(cfg)
}
}
