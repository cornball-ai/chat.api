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
#' @param rich Adapter-native markup for the platforms that accept it,
#'   or NULL. Matrix takes an HTML fragment and sends it as
#'   \code{formatted_body}; adapters whose
#'   \code{chat_capabilities()} is empty ignore it.
#'
#'   \code{text} is still required and still has to stand on its own. It
#'   is what a client that cannot render the markup shows, what a push
#'   notification carries, and what every other transport gets -- so a
#'   \code{rich} that holds the real content and a \code{text} that says
#'   "see above" is a message half the room cannot read.
#'
#'   Ignored rather than refused where unsupported, on
#'   \code{\link{chat_typing}}'s reasoning: the text is the message and
#'   the markup is decoration, so losing it costs presentation and
#'   nothing else.
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
                      files = NULL, kind = "message", notify = TRUE,
                      rich = NULL, ...) {
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
#'   (\code{\link{chat_join}} works), \code{whoami}
#'   (\code{\link{chat_whoami}} works, and with it the default
#'   \code{\link{chat_addressed}}), \code{files}, \code{typing},
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

#' Who is this client logged in as?
#'
#' The client's own account, as the transport identifies it.
#'
#' The default method throws rather than guessing. Every use of an
#' identity is a comparison -- is this message mine, did someone address
#' me -- and a wrong answer to either is silent: the bot answers itself
#' in a loop, or never answers anyone. An adapter that cannot say who it
#' is should say so.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return A \code{\link{chat_identity}}.
#' @examples
#' chat_whoami(chat_loopback())
#' @export
chat_whoami <- function(client, ...) {
    UseMethod("chat_whoami")
}

#' @export
chat_whoami.default <- function(client, ...) {
    stop("chat_whoami() is not supported by this adapter (",
         paste(class(client), collapse = "/"), ").", call. = FALSE)
}

#' Construct an identity record
#'
#' @param id The account identifier, in whatever form the transport
#'   uses. Comparable against \code{\link{chat_message}}'s \code{sender}
#'   and against the entries of its \code{mentions}: that comparability
#'   is the point of the field, so an adapter whose two sides disagree
#'   has a bug here rather than a choice.
#' @param display Human-readable name, or NA when the adapter would have
#'   to ask the server for it. Never used for matching -- it is not
#'   unique, and on most transports any account can set it to any other
#'   account's. For logs and prompts only.
#' @param raw The adapter's platform-native identity payload.
#' @return A list with class \code{chat_identity}.
#' @examples
#' chat_identity("@bot:example.org", display = "corteza")
#' @export
chat_identity <- function(id, display = NA_character_, raw = NULL) {
    stopifnot(is.character(id), length(id) == 1L, nzchar(id))
    structure(list(id = id,
                   display = if (is.null(display)) NA_character_ else display,
                   raw = raw),
              class = "chat_identity")
}

#' @export
print.chat_identity <- function(x, ...) {
    cat(sprintf("%s%s\n", x$id,
            if (is.na(x$display)) "" else sprintf(" (%s)", x$display)))
    invisible(x)
}

#' Does a message address this client?
#'
#' Answers the question a bot in a room full of people has to ask before
#' replying. Two signals feed it, and which ones exist is the adapter's
#' business rather than the caller's:
#'
#' \enumerate{
#'   \item The message's declared mentions -- Matrix \code{m.mentions},
#'     a Slack user ref. Structured, unambiguous, and the only signal the
#'     default method reads.
#'   \item The plain-text conventions of the transport. Matrix has
#'     \code{@@bot} and the full user id, Slack has \code{<@U0123>}, IRC
#'     has a leading \code{nick:}. These are the reason this is a verb
#'     and not a field: writing the Matrix form into a consumer is how
#'     that consumer ends up knowing it is talking to Matrix.
#' }
#'
#' The default reads only the declared mentions, so an adapter that does
#' not override it under-reports rather than over-reports. A bot that
#' misses being addressed stays quiet; one that thinks it was addressed
#' when it was not talks over people, and unprompted is worse than
#' absent.
#'
#' @param client A \code{chat_client}.
#' @param message A \code{\link{chat_message}}.
#' @param ... Adapter-specific options.
#' @return \code{TRUE} or \code{FALSE}.
#' @examples
#' cl <- chat_loopback()
#' chat_send(cl, "general", "hi")
#' chat_addressed(cl, chat_poll(cl)$messages[[1L]])
#' @export
chat_addressed <- function(client, message, ...) {
    UseMethod("chat_addressed")
}

#' @export
chat_addressed.default <- function(client, message, ...) {
    identity_mentioned(chat_whoami(client)$id, message)
}

#' Is this id among a message's declared mentions?
#'
#' The transport-neutral half of \code{\link{chat_addressed}}, shared by
#' every method so that an adapter overriding the verb adds its
#' plain-text conventions rather than reimplementing this and getting it
#' subtly different.
#' @noRd
identity_mentioned <- function(id, message) {
    # Forced before the short circuit below can skip it. The default
    # method passes chat_whoami(client)$id straight in, and && stops at
    # an empty mentions list without ever evaluating the promise -- so an
    # adapter that cannot say who it is quietly answered FALSE to "were
    # you addressed" instead of raising. Silence is what that bug looks
    # like from outside, which is also what working looks like.
    force(id)
    mentions <- unlist(message$mentions, use.names = FALSE)
    length(mentions) > 0L && id %in% mentions
}

#' Escape a literal string for use inside a regular expression
#'
#' Identifiers carry regex metacharacters: a Matrix localpart may contain
#' \code{.}, \code{+} and \code{/}, all legal per the spec. Interpolating
#' one unescaped turns \code{@@a.bot} into a pattern that also matches
#' \code{@@axbot}.
#' @noRd
escape_rx <- function(x) {
    gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
}

#' List the channels this client is in
#'
#' The state half of the contract. \code{\link{chat_poll}} answers "what
#' changed since my cursor"; this and its siblings answer "what is true
#' now", which is the question a process asks when it starts up with no
#' useful cursor at all.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return Character vector of channel identifiers.
#' @examples
#' chat_channels(chat_loopback())
#' @export
chat_channels <- function(client, ...) {
    UseMethod("chat_channels")
}

#' @export
chat_channels.default <- function(client, ...) {
    stop("chat_channels() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$channels.", call. = FALSE)
}

#' Read a channel's recent messages
#'
#' Independent of the poll cursor: a restarted process uses this to
#' recover the context it lost, and asking for it must not move the
#' cursor or consume anything.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param limit Maximum messages to return.
#' @param cursor Opaque continuation token from a previous call's
#'   \code{cursor}, to read the page before it; NULL starts from the most
#'   recent.
#' @param ... Adapter-specific options.
#' @return A list with \code{messages} (list of \code{\link{chat_message}},
#'   oldest first) and \code{cursor} (opaque; pass it back to read
#'   further into the past, NULL when the channel has no more history).
#'
#' @section The cursor is opaque, like chat_poll's:
#' Not a message id. This started out taking one and it was wrong on the
#' reference transport: Matrix's \code{/messages} takes a pagination
#' token from a previous response, and handing it an event id does not
#' page from that event -- it fails, or worse, silently returns the wrong
#' window. Slack pages by its own \code{next_cursor}. There is no id that
#' means the same thing on both, so the contract does what it already
#' does for \code{\link{chat_poll}}: the token is the adapter's, and a
#' consumer only ever passes back what it was given.
#'
#' @section Order:
#' Chronological, oldest first, whatever the platform's native direction
#' is. Matrix \code{dir = "b"} and Slack \code{conversations.history}
#' both hand back newest-first and every consumer replaying history into
#' a transcript has to flip it. One flip in the adapter beats one per
#' consumer, and a consumer that gets it wrong produces a transcript
#' that reads backwards without erroring.
#'
#' Note that pages run backwards while each page runs forwards: call it
#' twice and the second page's messages all precede the first page's.
#' A consumer assembling a full transcript prepends.
#'
#' @section Overlap with chat_poll:
#' The same message can arrive from both, and adapters must return the
#' same \code{id} for it either way. That id is the only thing a consumer
#' has to deduplicate on -- a startup backfill and the first poll after
#' it routinely cover the same events.
#' @examples
#' cl <- chat_loopback()
#' chat_send(cl, "general", "hello")
#' chat_history(cl, "general")$messages
#' @export
chat_history <- function(client, channel, limit = 50L, cursor = NULL, ...) {
    UseMethod("chat_history")
}

#' @export
chat_history.default <- function(client, channel, limit = 50L, cursor = NULL,
                                 ...) {
    stop("chat_history() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$history.", call. = FALSE)
}

#' Read standing state that is not tied to a cursor
#'
#' Today: pending invitations. \code{\link{chat_poll}} reports an
#' invitation when it arrives, which is no help to a client that was not
#' running at the time -- and some homeservers only report invites newer
#' than the \code{since} token, so the poll loop never sees them again.
#'
#' This is a separate verb rather than a mode of \code{\link{chat_poll}}
#' deliberately. Overloading the cursor would make "start from nothing"
#' and "tell me what is standing" the same call, and a client that asked
#' for pending invitations and thereby reset its read position would
#' replay every channel it is in.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return A list with \code{invites}, a list of \code{\link{chat_invite}}.
#' @examples
#' \dontrun{
#' pending <- chat_pending(client)
#' for (iv in pending$invites) chat_join(client, iv$channel)
#' }
#' @export
chat_pending <- function(client, ...) {
    UseMethod("chat_pending")
}

#' @export
chat_pending.default <- function(client, ...) {
    stop("chat_pending() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$pending.", call. = FALSE)
}

#' Mark a message as read
#'
#' The default is a quiet FALSE, on \code{\link{chat_typing}}'s
#' reasoning rather than \code{\link{chat_react}}'s: a read marker that
#' does not appear costs a human a little context about what the bot has
#' seen, and nothing more. Nobody is waiting on it the way they wait on
#' an acknowledgement.
#'
#' Write-only. Reading other participants' read state is a much larger
#' surface -- per-user, per-device, and absent entirely on some
#' platforms -- and no consumer needs it yet.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param message_id The message to mark read, and everything before it.
#' @param ... Adapter-specific options.
#' @return TRUE if the marker was sent, FALSE otherwise, invisibly.
#' @export
chat_mark_read <- function(client, channel, message_id, ...) {
    UseMethod("chat_mark_read")
}

#' @export
chat_mark_read.default <- function(client, channel, message_id, ...) {
    invisible(FALSE)
}

#' Set this client's persistent identity
#'
#' The account's own display name, as everyone in every channel sees it
#' until it is changed again. Distinct from \code{\link{chat_send}}'s
#' \code{identity} argument, which decorates a single message on
#' platforms that allow it.
#'
#' Owning this matters beyond tidiness. On Matrix the rename is an
#' authenticated call that can rotate the access token underneath the
#' caller, and a consumer that made that call itself had to notice the
#' rotation and get the new token back into its client -- usually via
#' whatever file both of them happened to share. Behind the contract the
#' rotation lands in the client that performed it, and nothing outside
#' has to know it happened.
#'
#' @param client A \code{chat_client}.
#' @param display New display name.
#' @param ... Adapter-specific options.
#' @return TRUE if the identity was changed, invisibly.
#' @export
chat_set_identity <- function(client, display, ...) {
    UseMethod("chat_set_identity")
}

#' @export
chat_set_identity.default <- function(client, display, ...) {
    stop("chat_set_identity() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$set_identity.", call. = FALSE)
}

#' Refresh this client's credentials
#'
#' Forces the re-authentication that adapters otherwise perform on
#' demand. The refreshed credentials stay inside the client.
#'
#' The default throws rather than returning quietly. "I could not
#' refresh" and "there was nothing to refresh" look identical to a
#' caller that gets FALSE, and the first means the next call will fail
#' with a stale token.
#'
#' @param client A \code{chat_client}.
#' @param ... Adapter-specific options.
#' @return TRUE, invisibly.
#' @export
chat_relogin <- function(client, ...) {
    UseMethod("chat_relogin")
}

#' @export
chat_relogin.default <- function(client, ...) {
    stop("chat_relogin() is not supported by this adapter (",
         paste(class(client), collapse = "/"), ").", call. = FALSE)
}

#' Replace the text of a message already sent
#'
#' What makes a progress message possible: post "working on it", then
#' keep replacing it as the work happens, instead of narrating into the
#' channel one message at a time.
#'
#' The default throws. An edit that silently does nothing leaves the old
#' text on screen, and stale content is worse than a visible failure --
#' the reader has no way to tell that what they are looking at is no
#' longer true. Check \code{chat_capabilities()$edits}.
#'
#' @param client A \code{chat_client}.
#' @param channel Channel/room identifier.
#' @param message_id The message to replace, as returned by
#'   \code{\link{chat_send}}.
#' @param text The replacement text, in full. Not a delta: every
#'   platform that supports this takes the whole new body, and a
#'   contract that took a patch would have to reconstruct the old one to
#'   apply it.
#' @param markup \code{"plain"} or \code{"markdown"}, as
#'   \code{\link{chat_send}}.
#' @param ... Adapter-specific options.
#' @return The identifier of the event the edit created where the
#'   platform makes one (Matrix), or of the edited message where it does
#'   not (Slack), invisibly.
#'
#' @section What a consumer must not assume:
#' That the edit is what readers see. A client that does not implement
#' edits shows the original and an "* edited" fallback beside it, and
#' notifications almost always carry the text as first sent. So the
#' first version has to stand on its own -- "working on it" is a fine
#' thing to be paged with, a half-finished sentence is not.
#' @export
chat_edit <- function(client, channel, message_id, text,
                      markup = c("plain", "markdown"), rich = NULL, ...) {
    UseMethod("chat_edit")
}

#' @export
chat_edit.default <- function(client, channel, message_id, text,
                              markup = c("plain", "markdown"), rich = NULL,
                              ...) {
    stop("chat_edit() is not supported by this adapter (",
         paste(class(client), collapse = "/"),
         "). Check chat_capabilities()$edits.", call. = FALSE)
}
