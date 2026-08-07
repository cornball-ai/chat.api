% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_config}
\alias{chat_config}
\title{Construct a chat_config}
\usage{
chat_config(x, app = NULL, path = NULL)
}
\arguments{
\item{x}{A named list of configuration fields.}

\item{app}{Application namespace the config belongs to, or NULL.}

\item{path}{File the config was read from, or NULL for one that has
never been written.}
}
\value{
A list with class \code{chat_config}.
}
\description{
Construct a chat_config
}
\examples{
chat_config(list(server = "https://ex.invalid", user = "bot"),
            app = "demo")
}
