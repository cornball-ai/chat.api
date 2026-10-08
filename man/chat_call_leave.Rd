% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_call_leave}
\alias{chat_call_leave}
\title{Leave a call}
\usage{
chat_call_leave(client, call, ...)
}
\arguments{
\item{client}{The \code{chat_client} the call was joined on.}

\item{call}{A \code{chat_call} from \code{\link{chat_call_join}}.}

\item{...}{Adapter-specific options.}
}
\value{
The call, invisibly.
}
\description{
Withdraws the membership \code{\link{chat_call_join}} announced and
stops advancing the call. The media side, if the caller opened one,
is the caller's to close.
}
