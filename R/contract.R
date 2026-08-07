#' @title chat.api contract generics
#' @description Transport-agnostic chat interface: connect, poll, send.
#'   Adapters provide methods for their platform class.

#' Poll a chat client for new messages
#'
#' Poll-shaped everywhere: long-poll transports (Matrix /sync, Telegram
#' getUpdates) map directly; persistent-socket transports (IRC) buffer
#' into the poll. The cursor is opaque and adapter-specific; pass the
#' returned cursor back as \code{since} on the next call.
#'
#' @param client A \code{chat_client}.
#' @param since Opaque cursor from the previous poll, or NULL to start.
#' @param timeout Seconds to wait for activity; NULL for the adapter
#'   default.
#' @param ... Adapter-specific options.
#' @return A list with \code{messages} (list of \code{chat_message}) and
#'   \code{cursor} (opaque, for the next \code{since}).
#' @export
chat_poll <- function(client, since = NULL, timeout = NULL, ...) {
    UseMethod("chat_poll")
}

#' Send a message through a chat client
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier (adapter-native or resolved
#'   via \code{\link{chat_resolve}}).
#' @param text Message text.
#' @param markup \code{"plain"} or \code{"markdown"}; adapters render
#'   markdown to their dialect (HTML for Matrix, mrkdwn for Slack,
#'   stripped for IRC).
#' @param thread Thread identifier to post into, or NULL.
#' @param reply_to Message id being replied to, or NULL.
#' @param identity Optional per-message identity override
#'   (\code{list(name =, icon =)}) where the platform supports it.
#' @param files Character vector of file paths to attach, or NULL.
#' @param kind Message kind; \code{"message"} (default) or an
#'   adapter-understood alternative (e.g. \code{"notice"}, \code{"emote"}).
#' @param notify Logical; FALSE requests a silent delivery where
#'   supported.
#' @param ... Adapter-specific options.
#' @return Character vector of the message ids this call created, in the
#'   order they were sent, invisibly. Usually length one. A platform that
#'   splits a send into several events returns one id per event: the
#'   Matrix adapter sends each attachment as its own event, so a send
#'   with files returns the attachment ids followed by the text id.
#'   Callers that track their own traffic by id must handle every
#'   element, or an unclaimed event reads as somebody else's message.
#' @export
chat_send <- function(client, channel, text, markup = c("plain", "markdown"),
                      thread = NULL, reply_to = NULL, identity = NULL,
                      files = NULL, kind = "message", notify = TRUE, ...) {
    UseMethod("chat_send")
}

#' Signal typing state in a channel
#'
#' Capability-gated: the default method is a no-op so adapters without
#' typing indicators need not implement it.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param on Logical.
#' @param ... Adapter-specific options.
#' @return TRUE if the signal was sent, FALSE otherwise, invisibly.
#' @export
chat_typing <- function(client, channel, on = TRUE, ...) {
    UseMethod("chat_typing")
}

#' @export
chat_typing.default <- function(client, channel, on = TRUE, ...) {
    invisible(FALSE)
}

#' Resolve a human channel name to its identifier
#'
#' @param client A \code{chat_client}.
#' @param name Channel name, alias, or identifier.
#' @param ... Adapter-specific options.
#' @return The adapter-native channel identifier (character).
#' @export
chat_resolve <- function(client, name, ...) {
    UseMethod("chat_resolve")
}

#' Describe what a chat client's platform supports
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return A list with at least: \code{threads} (can post into
#'   threads), \code{thread_replies} (thread replies come back out of
#'   \code{\link{chat_poll}}), \code{edits}, \code{reactions}
#'   (\code{\link{chat_react}} works), \code{reaction_events} (reactions
#'   come back out of \code{\link{chat_poll}}), \code{channel_info}
#'   (\code{\link{chat_channel_info}} works), \code{members}
#'   (\code{\link{chat_members}} works), \code{invites} (invitations come
#'   back out of \code{\link{chat_poll}}), \code{join}
#'   (\code{\link{chat_join}} works), \code{files}, \code{typing},
#'   \code{e2ee}, \code{identity_override} (logicals),
#'   \code{markup_dialects} (character), \code{max_message_bytes}
#'   (integer or NA).
#'
#'   Sending and receiving get separate flags wherever a platform does
#'   one and not the other, which is why \code{threads} and
#'   \code{thread_replies} are two entries rather than one. Reactions
#'   split the same way: Slack can place one, and does not report anyone
#'   else's through the history endpoint this adapter polls, so a
#'   consumer reading a single flag would wait forever for events that
#'   never arrive.
#' @export
chat_capabilities <- function(client, ...) {
    UseMethod("chat_capabilities")
}

#' React to a message
#'
#' Places a reaction (an emoji or short key) on an existing message.
#'
#' The default method throws. A reaction that silently does nothing is
#' worse than one that fails: the caller believes it acknowledged
#' something and no one can see that it did not. This differs from
#' \code{\link{chat_typing}}, whose default is a quiet FALSE, because a
#' missing typing indicator costs nothing and a missing acknowledgement
#' can be the whole message. Check \code{chat_capabilities()$reactions}
#' before calling on an unknown adapter.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param message_id Identifier of the message being reacted to, as
#'   returned by \code{\link{chat_send}} or carried on a
#'   \code{\link{chat_message}}'s \code{id}.
#' @param key The reaction itself. Platforms differ on what they accept:
#'   Matrix takes any string and conventionally an emoji character,
#'   Slack takes a short name without colons (\code{"thumbsup"}). Passed
#'   through unchanged, since translating between the two would have to
#'   guess.
#' @param ... Adapter-specific options.
#' @return The reaction's identifier where the platform gives it one
#'   (Matrix), invisibly; \code{TRUE} where it does not (Slack).
#' @export
chat_react <- function(client, channel, message_id, key, ...) {
    UseMethod("chat_react")
}

#' @export
chat_react.default <- function(client, channel, message_id, key, ...) {
    stop("chat_react() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$reactions.", call. = FALSE)
}

#' Join a channel
#'
#' Accepts a pending invitation, or joins an open channel where the
#' platform allows it.
#'
#' The default method throws, on the same reasoning as
#' \code{\link{chat_react}}: a join that silently does nothing leaves the
#' caller believing it is in a room it will never hear from. Check
#' \code{chat_capabilities()$join}.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier, as carried on a
#'   \code{\link{chat_invite}}'s \code{channel} or resolved by
#'   \code{\link{chat_resolve}}.
#' @param ... Adapter-specific options.
#' @return The joined channel's identifier, invisibly.
#' @export
chat_join <- function(client, channel, ...) {
    UseMethod("chat_join")
}

#' @export
chat_join.default <- function(client, channel, ...) {
    stop("chat_join() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$join.", call. = FALSE)
}

#' Construct a normalized invitation record
#'
#' The record \code{\link{chat_poll}} returns in \code{$invites} on
#' adapters whose \code{chat_capabilities()$invites} is TRUE.
#'
#' @param channel Channel/room identifier the client has been invited to
#'   (character). Pass it to \code{\link{chat_join}} to accept.
#' @param inviter Who issued the invitation, or \code{NA} when the
#'   transport does not say. NA rather than NULL, and deliberately: a
#'   consumer deciding whether to accept has to tell "someone I do not
#'   trust" from "I could not tell who", and both refuse for different
#'   reasons. NULL would collapse the second into the absence of a field.
#' @param raw The adapter's platform-native payload.
#' @return A list with class \code{chat_invite}.
#'
#' @section No timestamp:
#' Unlike \code{\link{chat_message}} and \code{\link{chat_reaction}},
#' there is no \code{ts}. An invitation is a standing state rather than
#' an event at a moment, and Matrix's stripped invite state carries no
#' reliable \code{origin_server_ts} to report. A field that could only
#' ever be NA is worse than no field.
#' @export
chat_invite <- function(channel, inviter = NA_character_, raw = NULL) {
    stopifnot(is.character(channel))
    structure(list(channel = channel,
                   inviter = if (is.null(inviter)) NA_character_ else inviter,
                   raw = raw),
              class = "chat_invite")
}

#' @export
print.chat_invite <- function(x, ...) {
    cat(sprintf("invite to %s from %s\n", x$channel,
            if (is.na(x$inviter)) "someone unknown" else x$inviter))
    invisible(x)
}

#' Describe a channel
#'
#' Returns the channel's descriptive metadata: what it is called and what
#' it is for.
#'
#' Membership is deliberately not here, and \code{\link{chat_members}} is
#' a separate verb. The two look like one lookup and are not: a name and
#' a topic are two short strings that change rarely, while a member list
#' is unbounded and changes constantly. Bundling them makes every read of
#' a topic pay for a member list, which on a busy room is the expensive
#' part -- and a consumer caches the two on different schedules for
#' exactly that reason.
#'
#' A NULL field means the channel has no such thing: a Matrix room with
#' no \code{m.room.name} really has no name. An adapter that cannot
#' answer at all throws, so "cannot ask" and "asked, and there is none"
#' stay distinguishable. Check \code{chat_capabilities()$channel_info}
#' first.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param ... Adapter-specific options.
#' @return A list with \code{id}, \code{name}, and \code{topic}.
#'   \code{id} is the channel as the platform addresses it; \code{name}
#'   and \code{topic} are character or NULL.
#' @export
chat_channel_info <- function(client, channel, ...) {
    UseMethod("chat_channel_info")
}

#' @export
chat_channel_info.default <- function(client, channel, ...) {
    stop("chat_channel_info() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$channel_info.", call. = FALSE)
}

#' List a channel's members
#'
#' Separate from \code{\link{chat_channel_info}} because it is the
#' expensive half: a member list is unbounded where a name and a topic
#' are two short strings, and it goes stale on a different schedule.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param ... Adapter-specific options.
#' @return Character vector of member identifiers. Empty when the channel
#'   has none; an adapter that cannot answer throws, so an empty room is
#'   never confused with an unanswerable question. Check
#'   \code{chat_capabilities()$members} first.
#' @export
chat_members <- function(client, channel, ...) {
    UseMethod("chat_members")
}

#' @export
chat_members.default <- function(client, channel, ...) {
    stop("chat_members() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$members.", call. = FALSE)
}

#' Construct a normalized reaction record
#'
#' The record \code{\link{chat_poll}} returns in \code{$reactions} on
#' adapters whose \code{chat_capabilities()$reaction_events} is TRUE.
#'
#' Deliberately not a \code{\link{chat_message}}. A reaction has a target
#' and no body, and the message record has a body and no target;
#' \code{thread} is the closest slot and it means something else, so
#' folding one into the other would make every consumer disambiguate by
#' inspecting fields.
#'
#' @param id The reaction's own identifier, or NULL where the platform
#'   does not give it one. Not the identifier of the message it is
#'   attached to -- see \code{target}.
#' @param channel Channel/room identifier (character).
#' @param sender Sender identifier (character).
#' @param target Identifier of the message being reacted to (character).
#' @param key The reaction itself (character): an emoji on Matrix, a
#'   short name on Slack.
#' @param ts POSIXct timestamp, or \code{NA} when the transport does not
#'   report one -- the same rule \code{\link{chat_message}} follows, and
#'   for the same reason.
#' @param self Logical: did this client place the reaction? A consumer
#'   that reacts to acknowledge needs this to avoid answering its own
#'   acknowledgement. NULL when the adapter cannot tell.
#' @param raw The adapter's platform-native payload.
#' @return A list with class \code{chat_reaction}.
#' @export
chat_reaction <- function(id, channel, sender, target, key, ts, self = NULL,
                          raw = NULL) {
    stopifnot(is.character(channel), is.character(sender),
              is.character(target), is.character(key))
    structure(list(id = id, channel = channel, sender = sender,
                   target = target, key = key, ts = ts, self = self,
                   raw = raw),
              class = "chat_reaction")
}

#' @export
print.chat_reaction <- function(x, ...) {
    cat(sprintf("[%s] %s reacted %s to %s in %s\n", format(x$ts, "%H:%M:%S"),
                x$sender, x$key, x$target, x$channel))
    invisible(x)
}

#' Close a chat client's connection
#'
#' The default method is a no-op: HTTP-poll transports have nothing to
#' close. Persistent-socket transports (IRC) override it.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return TRUE, invisibly.
#' @export
chat_disconnect <- function(client, ...) {
    UseMethod("chat_disconnect")
}

#' @export
chat_disconnect.default <- function(client, ...) {
    invisible(TRUE)
}

#' Construct a normalized chat message
#'
#' The record every adapter's \code{\link{chat_poll}} returns.
#'
#' @param id Message identifier (character).
#' @param channel Channel/room identifier (character).
#' @param sender Sender identifier (character).
#' @param body Message text (character).
#' @param ts POSIXct timestamp of when the platform recorded the
#'   message, or \code{NA} when the transport does not report one. It is
#'   never a stand-in for the poll's wall clock: a consumer windowing or
#'   ordering by \code{ts} has to be able to tell a real event time from
#'   a missing one.
#' @param thread Thread identifier or NULL.
#' @param markup Source markup hint (character, e.g. "plain", "html").
#' @param kind Message kind (character; "message" default). Contract
#'   vocabulary, not platform vocabulary: \code{"message"},
#'   \code{"notice"}, \code{"emote"}. Adapters translate their native
#'   type into it on the way in, the same mapping \code{\link{chat_send}}
#'   applies on the way out.
#' @param self Logical: did this client send the message? Poll returns
#'   the bot's own traffic like any other, so a consumer that replies to
#'   inbound mail needs this to avoid answering itself. NULL when the
#'   adapter cannot tell.
#' @param mentions Character vector of user identifiers the message
#'   explicitly mentioned (Matrix \code{m.mentions}, Slack user refs), or
#'   NULL. The signal a bot in a multi-human room gates on; body
#'   substring matching misses rich mentions that carry no plain text.
#' @param raw The adapter's platform-native payload for this message,
#'   exactly as the transport layer handed it over. Shape is
#'   adapter-specific and may already be normalized by the transport
#'   package (Matrix hands over an extracted record, not the timeline
#'   event), so it is an escape hatch, not a guarantee of completeness.
#' @param encrypted Logical: did this message arrive end-to-end
#'   encrypted? FALSE on transports without E2EE and on cleartext
#'   messages in rooms that have it.
#' @param sender_verified Logical: does the sender identifier bind to a
#'   device whose keys this client verified? NULL on cleartext messages,
#'   where the transport asserts the sender and there is nothing to
#'   verify. On an encrypted message FALSE is a real answer, not a
#'   missing one: the payload decrypted, but its claimed sender could not
#'   be tied to a verified device, so the identifier is the homeserver's
#'   word rather than cryptographic fact.
#' @return A list with class \code{chat_message}.
#' @export
chat_message <- function(id, channel, sender, body, ts, thread = NULL,
                         markup = "plain", kind = "message", self = NULL,
                         mentions = NULL, raw = NULL, encrypted = FALSE,
                         sender_verified = NULL) {
    stopifnot(is.character(id), is.character(channel), is.character(sender),
              is.character(body))
    structure(list(id = id, channel = channel, sender = sender,
                   body = body, ts = ts, thread = thread,
                   markup = markup, kind = kind, self = self,
                   mentions = mentions, raw = raw,
                   encrypted = isTRUE(encrypted),
                   sender_verified = sender_verified),
              class = "chat_message")
}

#' @export
print.chat_message <- function(x, ...) {
    cat(sprintf("[%s] %s in %s: %s\n", format(x$ts, "%H:%M:%S"), x$sender,
                x$channel, substr(x$body, 1L, 60L)))
    invisible(x)
}
