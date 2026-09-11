#' Transport-agnostic chat connectivity
#'
#' A common interface for chat messages, attachments, rooms, and identity.
#' Use \code{\link{chat_loopback}} for local development, or connect through
#' \code{\link{chat_matrix}}, \code{\link{chat_irc}},
#' \code{\link{chat_slack}}, or \code{\link{chat_telegram}}.
#' Inspect \code{\link{chat_capabilities}} before using optional operations.
#'
#' @name chat.api-package
#' @aliases chat.api
#' @keywords package
#' @examples
#' cl <- chat_loopback()
#' chat_send(cl, "general", "hello")
#' chat_poll(cl)$messages
NULL
