% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_capabilities}
\alias{chat_capabilities}
\title{Describe what a chat client's platform supports}
\usage{
chat_capabilities(client, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{...}{Adapter-specific options.}
}
\value{
A list with at least: \code{threads}, \code{edits},
  \code{reactions}, \code{files}, \code{typing}, \code{e2ee},
  \code{identity_override} (logicals), \code{markup_dialects}
  (character), \code{max_message_bytes} (integer or NA).
}
\description{
Describe what a chat client's platform supports
}
