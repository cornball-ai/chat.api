% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_download}
\alias{chat_download}
\title{Fetch an attachment's bytes to a local file}
\usage{
chat_download(client, attachment, dest = NULL, ...)
}
\arguments{
\item{client}{A \code{chat_client}.}

\item{attachment}{A \code{\link{chat_attachment}} record, as carried
on a \code{\link{chat_message}}'s \code{attachments}.}

\item{dest}{Destination path. NULL picks a temporary file, keeping
the attachment's extension where it has one.}

\item{...}{Adapter-specific options.}
}
\value{
The destination path, invisibly.
}
\description{
Inbound attachments name where their content lives, not what it is:
\code{\link{chat_attachment}}'s \code{url} is a platform handle that
usually needs this client's credentials, so a consumer cannot simply
download it. This is the verb that turns one into a file on disk.
}
\details{
Capability-gated on \code{chat_capabilities()$attachments}, the same
flag that says inbound media arrives at all. The default method
throws, on \code{\link{chat_react}}'s reasoning: a fetch that
quietly did nothing leaves the caller pointing at a path with no
bytes behind it.

An attachment already on disk (\code{path} set, as the loopback
adapter records) is copied rather than fetched, so a consumer needs
one code path for both.

}
