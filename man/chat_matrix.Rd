% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_matrix}
\alias{chat_matrix}
\title{Create a Matrix chat client}
\usage{
chat_matrix(app = "chat.api", path = NULL, save_cursor = TRUE, mx = NULL,
            .sync = NULL, .extract = NULL, .send = NULL, .media = NULL)
}
\arguments{
\item{app}{Application namespace passed to
\code{mx.client::mx_client_load()}.}

\item{path}{Explicit config path, or NULL for the app default.}

\item{save_cursor}{Logical. Persist the sync token after each poll.
Consumers that manage their own config (corteza) pass FALSE and
persist the returned cursor themselves.}

\item{mx}{A ready mx.client client config to wrap, for consumers
that already load and manage one; NULL (default) loads via
\code{app}/\code{path}.}

\item{.sync}{Testing seam: replacement for
\code{mx.client::mx_sync_update}. Leave NULL in production.}

\item{.extract}{Testing seam: replacement for
\code{mx.client::mx_extract_text_events}. Leave NULL in production.}

\item{.send}{Testing seam: replacement for
\code{mx.client::mx_send_text}. Leave NULL in production.}

\item{.media}{Testing seam: replacement for
\code{mx.client::mx_send_media}. Leave NULL in production. Supplying
all four seams together with \code{mx} lets poll and send run
without mx.client installed; \code{chat_typing()} and
\code{chat_resolve()} still require it.}
}
\value{
A \code{chat_client} of class \code{chat_matrix}.
}
\description{
Wraps an \code{mx.client} client config (see
\code{mx.client::mx_client_load()}). The sync cursor lives inside the
mx.client config; with \code{save_cursor = TRUE} every poll persists
it, so a restarted process resumes where it left off.
}
