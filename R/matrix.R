#' @title Matrix adapter
#' @description chat.api methods for Matrix, delegating to the suggested
#'   mx.client package.

#' Create a Matrix chat client
#'
#' Wraps an \code{mx.client} client config (see
#' \code{mx.client::mx_client_load()}). The sync cursor lives inside the
#' mx.client config; with \code{save_cursor = TRUE} every poll persists
#' it, so a restarted process resumes where it left off.
#'
#' @param app Application namespace passed to
#'   \code{mx.client::mx_client_load()}, defaulting to "chat.api" for the
#'   load. NULL (the default) is also what gets forwarded to
#'   \code{mx_sync_update()}, which leaves the wrapped config's own
#'   \code{app}/\code{path} attributes in charge of where the cursor is
#'   persisted. Naming an app here overrides them, so only name one when
#'   this adapter owns the config file.
#' @param path Explicit config path, or NULL for the app default.
#' @param save_cursor Logical. Persist the sync token after each poll,
#'   through mx.client, into the config file the wrapped client points
#'   at. Pass FALSE only if you persist \code{chat_poll()}'s
#'   \code{cursor} yourself; nothing else writes it, so a FALSE that
#'   isn't paired with a save makes every restart replay history from a
#'   frozen token.
#' @param mx A ready mx.client client config to wrap, for consumers
#'   that already load and manage one; NULL (default) loads via
#'   \code{app}/\code{path}.
#' @param relogin Logical. Wrap each sync in
#'   \code{mx.client::mx_with_relogin()}, which catches an invalidated
#'   access token, re-logs in with the stored password on the same
#'   device_id (so an E2EE identity survives), and retries once. The
#'   refreshed config lands back in the client, so the next poll and any
#'   send use the new token. FALSE lets \code{mx_error_M_UNKNOWN_TOKEN}
#'   propagate.
#' @param e2ee Logical. Own Olm/Megolm state in the adapter, so
#'   \code{\link{chat_send}} encrypts for rooms that advertise
#'   \code{m.room.encryption} and \code{\link{chat_poll}} decrypts
#'   inbound. FALSE (the default) is the previous behaviour exactly:
#'   cleartext only, no crypto state, and \code{e2ee} stays FALSE in
#'   \code{\link{chat_capabilities}}. Requires the 'mx.crypto' package,
#'   which needs a Rust toolchain, and both \code{user_id} and
#'   \code{device_id} on the wrapped config.
#'
#'   Three things change when it is on. The crypto state is built on
#'   first use rather than here: from \code{\link{chat_poll}} that means
#'   key publication happens after the sync, so a relogin has already
#'   replaced a rejected token, while a \code{\link{chat_send}} that runs
#'   before any poll publishes with the token it has -- the same exposure
#'   any direct send already carries, since \code{mx_with_relogin()}
#'   wraps only the sync. The sync cursor is held back until the crypto
#'   state is safe, on disk and on the client, so a sync carrying a room
#'   key is not marked consumed until that key is stored. And attachments
#'   are refused in encrypted rooms, because Matrix media uploads are not
#'   encrypted by this adapter -- \code{\link{chat_capabilities}} reports
#'   \code{files = FALSE} to match.
#' @param crypto_store Character or NULL. Directory holding the pickled
#'   Olm account and sessions. NULL derives it from \code{app} via
#'   \code{mx.client::mx_crypto_store_dir()}, with a per-device
#'   subdirectory, so moving a config does not cost the device identity
#'   and two bots under one app namespace do not share an Olm account.
#'
#'   A Matrix device has one Olm identity for its whole life, and three
#'   things hold that. The store records the \code{(user_id, device_id)}
#'   it belongs to and refuses to open for a different one. Within a
#'   process, one device gets one context and one store, so pointing a
#'   second store at it is an error rather than a second account. And on
#'   first use the account's keys are checked against the ones the
#'   homeserver already has for that \code{device_id} -- the only one of
#'   the three that survives a restart, and so the one that catches a
#'   store swapped between runs. Log in again for a new \code{device_id}
#'   rather than re-homing an existing one.
#'
#'   That last check distinguishes three cases: no published device is a
#'   first run, a published device whose keys match is this account, and
#'   a published device that either differs or fails signature
#'   verification is an error. A \code{/keys/query} that returns a
#'   \code{failures} map is an error too, since the empty result beside
#'   it is an unanswered question rather than an absent device. It cannot
#'   see a homeserver that omits the device deliberately, which is
#'   indistinguishable from a first run without key pinning or
#'   cross-signing.
#'
#'   A Windows drive-relative \code{crypto_store} (\code{"C:store"}) is
#'   rejected. It names a directory relative to the current directory of
#'   that drive, which cannot be read here, so two such paths cannot be
#'   told apart and two stores could share one context. Pass an absolute
#'   path.
#' @param .sync Testing seam: replacement for
#'   \code{mx.client::mx_sync_update}. Leave NULL in production.
#' @param .extract Testing seam: replacement for
#'   \code{mx.client::mx_extract_text_events}. Leave NULL in production.
#' @param .send Testing seam: replacement for
#'   \code{mx.client::mx_send_text}. Leave NULL in production.
#' @param .media Testing seam: replacement for
#'   \code{mx.client::mx_send_media}. Leave NULL in production. Supplying
#'   all four seams together with \code{mx} lets poll and send run
#'   without mx.client installed; \code{chat_typing()} and
#'   \code{chat_resolve()} still require it.
#' @param .typing Testing seam: replacement for
#'   \code{mx.api::mx_typing}. Leave NULL in production. It is resolved
#'   when \code{chat_typing()} is called, not here, so a NULL seam costs
#'   nothing on installs without mx.api.
#' @param .crypto Testing seam: a named list overriding any of the
#'   adapter's four crypto operations -- \code{init}, \code{encrypted},
#'   \code{send}, \code{decrypt}. Leave NULL in production. Supplying
#'   \code{init} is what lets \code{e2ee = TRUE} be tested on a runner
#'   with neither mx.crypto nor a Rust toolchain; E2EE is the one part of
#'   this adapter with no honest way to reach a real homeserver from a
#'   test.
#' @param .save Testing seam: replacement for
#'   \code{mx.client::mx_client_save}. Leave NULL in production. Only
#'   reached on an \code{e2ee} client, which writes the sync cursor after
#'   the crypto state rather than inside the sync.
#' @param .react Testing seam: replacement for \code{mx.api::mx_react}.
#'   Leave NULL in production. Resolved when \code{chat_react()} is
#'   called, not here, so a NULL seam costs nothing on installs without
#'   mx.api.
#' @param .info Testing seam: a list with \code{name} and \code{topic},
#'   replacing \code{mx.api::mx_room_name} and
#'   \code{mx.api::mx_room_topic}. Leave NULL in production.
#' @param .members Testing seam: replacement for
#'   \code{mx.api::mx_room_members}. Leave NULL in production.
#' @param .join Testing seam: replacement for
#'   \code{mx.api::mx_room_join}. Leave NULL in production.
#' @param .channels Testing seam: replacement for
#'   \code{mx.api::mx_rooms}. Leave NULL in production.
#' @param .history Testing seam: replacement for
#'   \code{mx.api::mx_messages}. Leave NULL in production.
#' @param .pending Testing seam: replacement for \code{mx.api::mx_sync},
#'   used by \code{\link{chat_pending}} for its cursorless snapshot.
#'   Leave NULL in production.
#' @param .read Testing seam: replacement for
#'   \code{mx.api::mx_read_receipt}. Leave NULL in production.
#' @param .identity Testing seam: replacement for
#'   \code{mx.client::mx_set_displayname}. Leave NULL in production.
#' @return A \code{chat_client} of class \code{chat_matrix}.
#'   \code{\link{chat_poll}} on this class returns \code{first_run} and
#'   \code{client} alongside \code{messages}, \code{cursor}, and
#'   \code{raw}. \code{first_run} is TRUE when the sync started from no
#'   cursor, so the messages are a backfill baseline rather than new
#'   traffic. \code{client} is the post-sync mx.client config, which a
#'   consumer needs whenever it drives mx.api directly (read receipts,
#'   member lookups) because a relogin may have replaced the token this
#'   poll cycle.
#' @export
chat_matrix <- function(app = NULL, path = NULL, save_cursor = TRUE,
                        mx = NULL, relogin = TRUE, e2ee = FALSE,
                        crypto_store = NULL, .sync = NULL, .extract = NULL,
                        .send = NULL, .media = NULL, .typing = NULL,
                        .crypto = NULL, .save = NULL, .react = NULL,
                        .info = NULL, .members = NULL, .join = NULL,
                        .channels = NULL, .history = NULL, .pending = NULL,
                        .read = NULL, .identity = NULL) {
    seams <- list(.sync, .extract, .send, .media)
    if ((is.null(mx) || any(vapply(seams, is.null, logical(1)))) &&
        !requireNamespace("mx.client", quietly = TRUE)) {
        stop("chat_matrix() requires the 'mx.client' package. ",
             "Install it first.", call. = FALSE)
    }
    if (is.null(mx)) {
        load_app <- app %||% "chat.api"
        mx <- if (is.null(path)) {
            mx.client::mx_client_load(app = load_app)
        } else {
            mx.client::mx_client_load(app = load_app, path = path)
        }
    }
    env <- new.env(parent = emptyenv())
    env$mx <- mx
    # Crypto state lives on the same env as the client, so a consumer
    # holds one object and never touches Olm or Megolm itself. NULL when
    # e2ee is off, which is the default and is exactly the pre-existing
    # behaviour.
    # No crypto context yet, even with e2ee on. Initialization publishes
    # keys, which is an authenticated request, and the stored token may
    # already be rejected at process start. Doing it here put that upload
    # ahead of any relogin, so the constructor threw before the poll loop
    # existed and every restart repeated with the same dead token. It is
    # built on first use instead, off a config that has just worked. See
    # matrix_crypto_require().
    env$crypto <- NULL
    # The identity check runs now rather than at first use, so a config
    # that can never key a store fails while the caller is still looking
    # at the constructor.
    if (isTRUE(e2ee)) {
        matrix_crypto_identity(mx)
    }
    structure(list(env = env, app = app, save_cursor = isTRUE(save_cursor),
                   relogin = isTRUE(relogin), e2ee = isTRUE(e2ee),
                   crypto_store = crypto_store,
                   sync_fn = .sync %||% mx.client::mx_sync_update,
                   extract_fn = .extract %||% mx.client::mx_extract_text_events,
                   send_fn = .send %||% mx.client::mx_send_text,
                   media_fn = .media %||% mx.client::mx_send_media,
                   # Left unresolved, like typing_fn. The four seams above
                   # are only defaulted when their seam is NULL, and R's
                   # lazy `%||%` never forces the mx.client side when one
                   # is supplied -- which is what makes the documented
                   # four-seams-without-mx.client configuration work.
                   # Defaulting this one here forced mx.client on every
                   # client, cleartext ones included, and broke exactly
                   # that configuration. It is resolved where it is used,
                   # on the deferred-save path, which only e2ee reaches.
                   save_fn = .save,
                   typing_fn = .typing, react_fn = .react,
                   info_fn = .info, members_fn = .members, join_fn = .join,
                   channels_fn = .channels, history_fn = .history,
                   pending_fn = .pending, read_fn = .read,
                   identity_fn = .identity,
                   crypto_ops = matrix_crypto_ops(.crypto)),
              class = c("chat_matrix", "chat_client"))
}

# origin_server_ts for every joined-room timeline event, keyed by event
# id. mx_extract_text_events only started carrying ts in mx.client
# 0.1.1.1's development sources, and builds on either side of that
# change share a version string, so the adapter cannot tell from the
# version whether the record will have one. Reading it off the sync the
# extractor was handed makes the timestamp right on both builds. This is
# a keyed lookup, not a second extractor: it does no msgtype filtering
# and takes whatever event ids the extractor decided to return.
matrix_event_times <- function(sync) {
    joined <- sync$rooms$join
    out <- list()
    for (room in joined) {
        for (ev in room$timeline$events) {
            if (!is.null(ev$event_id) && !is.null(ev$origin_server_ts)) {
                out[[as.character(ev$event_id)]] <- ev$origin_server_ts
            }
        }
    }
    out
}

# Each timeline event's position in the sync, by event id. Walks the same
# structure matrix_event_times() does, and for the same reason: it is the
# only place the homeserver's own ordering survives, since the cleartext
# extractor and the decrypt step each return their own events and neither
# knows about the other's.
#
# Not origin_server_ts. Two events in one room can share a millisecond,
# and a homeserver's clock is not the ordering the room agreed on.
matrix_event_order <- function(sync) {
    out <- list()
    i <- 0L
    for (room in sync$rooms$join %||% list()) {
        for (ev in room$timeline$events %||% list()) {
            i <- i + 1L
            if (!is.null(ev$event_id)) {
                out[[as.character(ev$event_id)]] <- i
            }
        }
    }
    out
}

# The sync's reactions, as contract records, in the homeserver's order.
#
# Empty when the extractor seam is in play but predates the reaction
# extractor: mx.client gained mx_extract_reactions() in 0.2.0.3, and a
# client built against an older one should report no reactions rather
# than fail every poll. chat_capabilities()$reaction_events says the same
# thing, so the two cannot disagree.
matrix_reactions <- function(client, sync, positions) {
    if (!matrix_reactions_available()) {
        return(list())
    }
    recs <- mx.client::mx_extract_reactions(sync,
        self_id = client$env$mx$user_id)
    out <- lapply(recs, function(r) {
        ms <- r$ts
        chat_reaction(id = r$event_id,
                      channel = as.character(r$room_id),
                      sender = as.character(r$sender),
                      target = as.character(r$target_event_id),
                      key = as.character(r$key),
                      ts = if (is.null(ms)) as.POSIXct(NA) else
                      as.POSIXct(ms / 1000, origin = "1970-01-01"),
                      self = isTRUE(r$is_self), raw = r)
    })
    matrix_order_by_position(out, positions)
}

matrix_reactions_available <- function() {
    requireNamespace("mx.client", quietly = TRUE) &&
    "mx_extract_reactions" %in% getNamespaceExports("mx.client")
}

# The sync's pending invites, as contract records.
#
# mx_extract_invite_records() carries the inviter, which is the whole of
# whether an invite should be accepted -- and NA when the stripped state
# does not say, which a consumer has to be able to tell from a sender it
# simply does not trust. Passed through unchanged for that reason.
matrix_invites <- function(client, sync) {
    if (!matrix_invites_available()) {
        return(list())
    }
    recs <- mx.client::mx_extract_invite_records(sync,
        self_id = client$env$mx$user_id)
    lapply(recs, function(r) {
        chat_invite(channel = as.character(r$room_id), inviter = r$inviter,
                    raw = r)
    })
}

matrix_invites_available <- function() {
    requireNamespace("mx.client", quietly = TRUE) &&
    "mx_extract_invite_records" %in% getNamespaceExports("mx.client")
}

# Sort messages or reactions into sync order, by their own event id.
# Unpositioned events keep their arrival order at the end rather than
# being dropped or interleaved by guesswork, and the tie-break on index
# makes the result deterministic either way.
matrix_order_by_position <- function(records, positions) {
    if (length(records) < 2L) {
        return(records)
    }
    pos <- vapply(records, function(r) {
        p <- positions[[as.character(r$id)]]
        if (is.null(p)) Inf else as.numeric(p)
    }, numeric(1))
    records[order(pos, seq_along(pos))]
}

# Matrix msgtype -> the contract's kind vocabulary. chat_send maps the
# same pair in the other direction, so a message that makes a round trip
# keeps its kind. Leaving m.text on the record would make every Matrix
# message fail a cross-adapter `kind == "message"` filter that Slack,
# IRC, and loopback traffic passes.
matrix_kind <- function(msgtype) {
    switch(msgtype %||% "m.text", m.notice = "notice", m.emote = "emote",
           "message")
}

# The same mapping, but NA rather than "message" for a msgtype the
# contract has no word for. chat_poll() can afford the lenient version:
# its extractor has already filtered to the msgtypes it was asked for.
# chat_history() reads the timeline raw, so an m.image would otherwise
# arrive as a "message" whose body is a filename.
matrix_kind_strict <- function(msgtype) {
    if (!is.character(msgtype) || length(msgtype) != 1L || is.na(msgtype)) {
        return(NA_character_)
    }
    unname(c(m.text = "message", m.notice = "notice", m.emote = "emote")[msgtype])
}

# chat_poll's `...` reaches mx_sync_update, so a caller can pass a
# server-side `filter` or an explicit `path`. chat_send's reaches
# mx_send_text, whose `mentions` argument is the only way to emit an
# m.mentions user_ids list -- the field modern clients key their push
# rules off, so without it a bot's reply never highlights anyone.
#' @export
chat_poll.chat_matrix <- function(client, since = NULL, timeout = NULL, ...) {
    if (!is.null(since)) {
        client$env$mx$sync_token <- since
    }
    # With E2EE on the cursor is written after the crypto state, not
    # inside the sync. mx_sync_update(save = TRUE) commits the advanced
    # token before anything parses the response, which is what makes a
    # malformed event survivable -- crash, restart, resume past it. But a
    # sync carrying a room key is only consumed once that key is on disk,
    # and a crash between the two loses it permanently: the key is never
    # re-sent, so every later message in that room is undecryptable.
    #
    # So the poison-pill protection is traded for durability, and only on
    # e2ee clients. What is left in the window is one sync's worth of
    # replay, which is idempotent -- room keys and Megolm sessions are
    # keyed by session id.
    defer_save <- isTRUE(client$e2ee) && isTRUE(client$save_cursor)
    do_sync <- function(mx) {
        client$sync_fn(mx, timeout = as.integer((timeout %||% 0) * 1000),
                       save = isTRUE(client$save_cursor) && !defer_save,
                       app = client$app, ...)
    }
    # The relogin wrapper hands the retry a re-authenticated config, so
    # the sync has to run off whatever config it is given rather than
    # reaching back into client$env$mx. Wiring it the other way round
    # retries with the token the homeserver just rejected and the second
    # rejection escapes the handler that would have caught it.
    res <- if (client$relogin &&
        requireNamespace("mx.client", quietly = TRUE)) {
        mx.client::mx_with_relogin(client$env$mx, do_sync)
    } else {
        do_sync(client$env$mx)
    }
    # On an e2ee client the advanced cursor is held back until the crypto
    # state is safe, in memory as well as on disk. Keeping the cursor off
    # disk but live on the client only moves the skip: a caller that
    # catches the decrypt error and polls the same client again resumes
    # from the token the failed sync produced, and the room keys in it are
    # gone for good. The refreshed credentials are kept either way -- a
    # relogin is not what makes a sync consumed.
    if (isTRUE(client$e2ee)) {
        held <- res$client
        held$sync_token <- client$env$mx$sync_token
        client$env$mx <- held
    } else {
        client$env$mx <- res$client
    }

    # Crypto runs before the cursor is committed and after the sync has
    # succeeded: after, so a relogin has already replaced a rejected token
    # and initialization publishes keys with one that works; before, so a
    # sync whose room keys did not reach disk is not marked consumed.
    #
    # Errors propagate. mx.client already skips an individual event it has
    # no Megolm session for, so a throw here is the other kind of failure
    # -- to-device processing, or the session save itself -- and swallowing
    # it while keeping the advanced cursor acknowledged a sync whose keys
    # were lost.
    dec <- list()
    if (isTRUE(client$e2ee)) {
        crypto <- matrix_crypto_require(client)
        dec <- client$crypto_ops$decrypt(crypto, res$sync, client$env$mx)
        if (defer_save) {
            save_fn <- client$save_fn %||% mx.client::mx_client_save
            res$client <- save_fn(res$client, app = client$app)
        }
        # Nothing above threw, so the sync is consumed and its cursor
        # becomes the live one.
        client$env$mx <- res$client
    }

    event_ts <- matrix_event_times(res$sync)
    event_pos <- matrix_event_order(res$sync)
    recs <- client$extract_fn(res$sync, self_id = res$client$user_id)
    messages <- lapply(recs, function(r) {
        # ts is the event's own origin_server_ts, from the record when
        # the extractor carries one and from the sync when it does not.
        # An unknown time stays NA: stamping Sys.time() would make a
        # restart's backfill look like it all arrived at once, and no
        # consumer sorting or windowing by ts could tell.
        ms <- r$ts %||% event_ts[[as.character(r$event_id)]]
        ts <- if (is.null(ms)) {
            as.POSIXct(NA)
        } else {
            as.POSIXct(ms / 1000, origin = "1970-01-01")
        }
        chat_message(id = as.character(r$event_id),
                     channel = as.character(r$room_id),
                     sender = as.character(r$sender),
                     body = as.character(r$body), ts = ts,
                     markup = "plain", kind = matrix_kind(r$msgtype),
                     self = isTRUE(r$is_self),
                     mentions = unlist(r$mentions, use.names = FALSE),
                     raw = r)
    })
    # Decrypted traffic folds in alongside the cleartext, in the same
    # chat_message shape, so a consumer cannot tell which arrived
    # encrypted except by reading $encrypted. That is the whole point of
    # owning crypto here: corteza used to run its own decrypt off $raw and
    # concatenate the results itself.
    for (d in dec) {
        ms <- d$ts %||% event_ts[[as.character(d$event_id)]]
        messages[[length(messages) + 1L]] <- chat_message(
            id = as.character(d$event_id),
            channel = as.character(d$room_id),
            sender = as.character(d$sender),
            body = as.character(d$body),
            ts = if (is.null(ms)) as.POSIXct(NA) else
            as.POSIXct(ms / 1000, origin = "1970-01-01"),
            markup = "plain", kind = matrix_kind(d$msgtype),
            self = isTRUE(d$is_self),
            mentions = unlist(d$mentions, use.names = FALSE),
            encrypted = TRUE,
            sender_verified = isTRUE(d$sender_verified),
            raw = d)
    }
    # Back into the order the homeserver sent them. Appending the
    # decrypted events put every one of them after every cleartext one,
    # so an encrypted message followed by a plain reply came out
    # backwards -- which reorders a room's commands against the messages
    # they act on. Anything the sync did not position sorts last, in the
    # order it arrived.
    messages <- matrix_order_by_position(messages, event_pos)
    # first_run says the sync ran without a stored cursor, so these
    # messages are the homeserver's backfill baseline, not new traffic.
    # A consumer that drops it replays its whole history as fresh mail
    # every restart, so it has to survive the trip out of the adapter.
    #
    # client is the post-sync config. A relogin can have replaced the
    # token mid-poll, and a consumer that keeps driving mx.api off its
    # own pre-poll copy would spend the rest of the cycle authenticating
    # with the token the homeserver just rejected.
    #
    # raw is the untouched sync response, kept as an escape hatch for
    # whatever the contract still does not model. Nothing this adapter
    # reports needs it any more: messages, reactions and invites are all
    # records.
    #
    # reactions and invites follow messages exactly: returned on a first
    # run too, with first_run left to say what they are. A consumer that
    # acts on either has the same backfill problem it has with messages
    # and solves it the same way -- what it must not have to learn is
    # that one of the three lists plays by a different rule.
    # No `client`. The post-sync config used to be handed back so a
    # consumer could keep driving mx.api with a token this poll may have
    # rotated. That made the consumer the owner of a credential the
    # adapter had already refreshed in place, and the two stayed in step
    # only because both wrote the same file. Everything that needed it
    # is a verb now, and the refreshed config is on `client$env$mx`
    # where the next call will find it.
    list(messages = messages, cursor = client$env$mx$sync_token,
         first_run = isTRUE(res$first_run),
         reactions = matrix_reactions(client, res$sync, event_pos),
         invites = matrix_invites(client, res$sync),
         raw = res$sync)
}

#' @export
chat_send.chat_matrix <- function(client, channel, text,
                                  markup = c("plain", "markdown"),
                                  thread = NULL, reply_to = NULL,
                                  identity = NULL, files = NULL,
                                  kind = "message", notify = TRUE, ...) {
    markup <- match.arg(markup)
    # Resolved before anything is uploaded or posted. The encryption
    # question used to be asked after the attachment loop had already run,
    # which put the files on the homeserver in the clear before the text
    # took the Megolm path -- and an attachment-only send never asked at
    # all.
    crypto <- matrix_crypto_require(client)
    encrypted <- !is.null(crypto) &&
    client$crypto_ops$encrypted(crypto, client$env$mx, channel)
    if (encrypted && !is.null(files)) {
        # mx_send_media() posts an ordinary cleartext m.file event: the
        # upload is not encrypted, and neither is the URL. There is no
        # encrypted-attachment path to fall back to, so this refuses
        # rather than leaking. chat_capabilities()$files reports FALSE on
        # an e2ee client for the same reason.
        stop("chat.api: cannot send attachments to the encrypted room ",
             channel, ". Matrix media uploads are not encrypted by this ",
             "adapter, and posting them would put the file on the ",
             "homeserver in the clear.", call. = FALSE)
    }
    media_ids <- character()
    if (!is.null(files)) {
        for (f in files) {
            event <- client$media_fn(client$env$mx, f, room = channel)
            media_ids <- c(media_ids, as.character(event))
        }
    }
    # The contract's three kinds, plus a documented way past them: a
    # kind already spelled as a Matrix msgtype goes out as itself. The
    # contract has no word for an image or a file, and mapping those to
    # "m.text" -- which is what the else branch below does to anything
    # unrecognized -- posts a text message whose body is a filename.
    # Better a caller that names a Matrix type explicitly than a caller
    # forced around the contract entirely to send one.
    msgtype <- if (identical(kind, "notice")) {
        "m.notice"
    } else if (identical(kind, "emote")) {
        "m.emote"
    } else if (is.character(kind) && length(kind) == 1L &&
        startsWith(kind, "m.")) {
        kind
    } else {
        "m.text"
    }
    # An attachment-only send is the uploads and nothing else. Matrix
    # accepts an empty body and clients render it as a blank bubble, so
    # posting one after every file leaves visible litter in the room.
    #
    # Every event this call created comes back, media first, in the order
    # they were sent. A caller that only sees the text event treats each
    # attachment's echo as somebody else's message: corteza recognizes
    # its own traffic by event id.
    if (!length(media_ids) || any(nzchar(text))) {
        # markup and mentions carry through: the encrypted branch builds
        # the same m.room.message content the cleartext one does, so a
        # markdown send renders the same either way. Only the envelope
        # differs.
        if (encrypted) {
            event <- client$crypto_ops$send(crypto, client$env$mx, channel,
                text, msgtype = msgtype,
                markdown = identical(markup, "markdown"),
                mentions = list(...)$mentions)
            return(invisible(c(media_ids, as.character(event))))
        }
        event <- client$send_fn(client$env$mx, text, room = channel,
                                msgtype = msgtype,
                                markdown = identical(markup, "markdown"), ...)
        return(invisible(c(media_ids, as.character(event))))
    }
    invisible(media_ids)
}

#' @param timeout Seconds the typing indicator should stand before the
#'   homeserver clears it, for \code{on = TRUE}. Seconds, not
#'   milliseconds: \code{chat_poll()} takes seconds too, and the adapter
#'   converts at the mx.api boundary. A caller running a slow model
#'   turn wants a long one (say 120) and an explicit
#'   \code{on = FALSE} when the turn ends.
#' @rdname chat_typing
#' @export
chat_typing.chat_matrix <- function(client, channel, on = TRUE, timeout = 30,
                                    ...) {
    ok <- tryCatch({
        # mx.api wants a session, not the client config
        sess <- mx.client::mx_client_session(client$env$mx)
        typing_fn <- client$typing_fn %||% mx.api::mx_typing
        typing_fn(sess, channel, typing = isTRUE(on),
                  timeout = as.integer((timeout %||% 30) * 1000))
        TRUE
    }, error = function(e) FALSE)
    invisible(ok)
}

#' @export
chat_react.chat_matrix <- function(client, channel, message_id, key, ...) {
    # Errors propagate, unlike chat_typing()'s. A dropped typing
    # indicator costs nothing; a dropped reaction is an acknowledgement
    # the sender believes it made and no one can see.
    react_fn <- client$react_fn %||% mx.api::mx_react
    sess <- mx.client::mx_client_session(client$env$mx)
    invisible(react_fn(sess, channel, message_id, key))
}

#' @export
chat_channel_info.chat_matrix <- function(client, channel, ...) {
    s <- mx.client::mx_client_session(client$env$mx)
    info <- client$info_fn %||% list(name = mx.api::mx_room_name,
                                     topic = mx.api::mx_room_topic)
    # A room with neither is the ordinary case for a direct message, and
    # mx.api raises M_NOT_FOUND for an absent state event. That is the
    # answer "there is none", not a failure, so it becomes NULL -- which
    # is what the contract says a missing field means. A room the client
    # cannot reach at all fails earlier, in mx_client_session().
    absent <- function(f) {
        v <- tryCatch(f(s, channel), error = function(e) NULL)
        if (is.null(v) || !length(v) || !nzchar(v[[1L]])) {
            NULL
        } else {
            as.character(v)[[1L]]
        }
    }
    list(id = channel, name = absent(info$name), topic = absent(info$topic))
}

#' @export
chat_join.chat_matrix <- function(client, channel, ...) {
    # Errors propagate. A join that quietly failed leaves the caller
    # believing it is in a room it will never hear a word from, which is
    # indistinguishable from an idle room.
    sess <- mx.client::mx_client_session(client$env$mx)
    join_fn <- client$join_fn %||% mx.api::mx_room_join
    invisible(as.character(join_fn(sess, channel)))
}

#' @export
chat_members.chat_matrix <- function(client, channel, ...) {
    # Errors propagate. An empty room and an unanswerable question are
    # different things, and character() has to mean only the first.
    sess <- mx.client::mx_client_session(client$env$mx)
    members_fn <- client$members_fn %||% mx.api::mx_room_members
    as.character(members_fn(sess, channel))
}

#' @export
chat_resolve.chat_matrix <- function(client, name, ...) {
    mx.client::mx_resolve_room(client$env$mx, name)
}

#' @export
chat_capabilities.chat_matrix <- function(client, ...) {
    # thread_replies is FALSE because chat_poll cannot populate
    # chat_message$thread. Its only event source is
    # mx.client::mx_extract_text_events(), which returns room_id,
    # event_id, sender, is_self, body, msgtype, and mentions -- it drops
    # content$m.relates_to, so the relation never reaches this adapter.
    # Re-walking the raw sync behind the extractor would duplicate its
    # msgtype filtering and quietly break for anyone supplying .extract.
    # Mapping m.in_reply_to into $thread would be worse: chat_message
    # has no reply_to slot, so plain rich replies would report as
    # threads. Flip this to TRUE when mx.client surfaces relations and
    # chat_poll maps a real m.thread rel_type.
    #
    # Every flag here answers "can this adapter do it", not "can Matrix
    # do it". Matrix has reactions and E2EE; this adapter reaches
    # neither, and a mixed list is worse than a conservative one because
    # a consumer cannot tell which reading a given flag was written
    # under.
    #
    # reactions and reaction_events are both TRUE: mx.api::mx_react()
    # places one and mx.client::mx_extract_reactions() reports the rest.
    # reaction_events tracks what is actually installed rather than
    # asserting it, because an mx.client older than 0.2.0.3 has no
    # reaction extractor and chat_poll would report an empty list forever
    # while the flag said otherwise.
    #
    # e2ee answers for this client, not for Matrix and not for the
    # installed packages: it is TRUE when this client was built with
    # e2ee = TRUE, which is what routes sends through mx_send_encrypted
    # and decrypts inbound. Reporting TRUE off an installed mx.crypto
    # would invite a consumer to hand a secret to a client that PUTs it in
    # the clear. It reads the setting rather than the crypto context
    # because the context is built on first use, and a capability that
    # flipped after the first poll would be worse than either answer.
    #
    # files is FALSE on an e2ee client. mx_send_media() posts a cleartext
    # m.file event whatever the room's encryption state says, and this
    # adapter has no encrypted-attachment path, so chat_send() refuses
    # attachments to an encrypted room. TRUE would advertise something
    # that fails in exactly the rooms such a client exists for.
    list(threads = FALSE, thread_replies = FALSE, edits = FALSE,
         reactions = TRUE, reaction_events = matrix_reactions_available(),
         channel_info = TRUE, members = TRUE,
         invites = matrix_invites_available(), join = TRUE, whoami = TRUE,
         channels = TRUE, history = TRUE,
         pending = matrix_invites_available(), mark_read = TRUE,
         set_identity = TRUE, relogin = TRUE, files = !isTRUE(client$e2ee),
         typing = TRUE, e2ee = isTRUE(client$e2ee),
         identity_override = FALSE, markup_dialects = c("plain", "markdown"),
         max_message_bytes = NA_integer_)
}

#' @export
chat_whoami.chat_matrix <- function(client, ...) {
    mx <- client$env$mx
    id <- mx$user_id
    if (!is.character(id) || length(id) != 1L || !nzchar(id)) {
        stop("chat.api: this Matrix client has no user_id. ",
             "Log in with mx.client before asking who it is.", call. = FALSE)
    }
    # raw carries the identity, not the config it came from. That config
    # holds an access token and possibly a password, and an identity
    # record is exactly the kind of thing a consumer prints into a log.
    chat_identity(id, display = mx$displayname %||% NA_character_,
                  raw = list(user_id = id, device_id = mx$device_id))
}

# Everything between the leading sigil and the first colon:
# "@bot:example.org" -> "bot". "" for anything not shaped like a user id,
# which the caller must read as "no localpart to match on" rather than
# building an empty pattern that matches everywhere.
matrix_localpart <- function(id) {
    if (!grepl("^@[^:]+:", id)) {
        return("")
    }
    sub(":.*$", "", sub("^@", "", id))
}

# The characters a Matrix localpart may contain, per the identifier
# grammar. Used as a negative lookahead so "@bot" does not match inside
# "@bot2" or "@bot.deploy", both of which are somebody else.
MATRIX_LOCALPART_CHARS <- "a-z0-9._=/+-"

#' @export
chat_addressed.chat_matrix <- function(client, message, ...) {
    id <- chat_whoami(client)$id
    if (identity_mentioned(id, message)) {
        return(TRUE)
    }
    body <- message$body %||% ""
    if (!nzchar(body)) {
        return(FALSE)
    }
    # The full user id, spelled out. A rich mention renders as a pill
    # whose plain-text fallback is usually the display name, so this is
    # for the person who typed the id instead of clicking a completion.
    if (grepl(id, body, fixed = TRUE)) {
        return(TRUE)
    }
    localpart <- matrix_localpart(id)
    if (!nzchar(localpart)) {
        return(FALSE)
    }
    # "@bot" as a whole word. The lookahead is what \\b would be if \\b
    # knew about Matrix: a localpart may contain "." and "-", so \\b ends
    # the word early and "@bot.deploy" matches "@bot" -- the wrong bot
    # answers, and the right one never sees it.
    grepl(sprintf("@%s(?![%s])", escape_rx(localpart), MATRIX_LOCALPART_CHARS),
          body, perl = TRUE, ignore.case = TRUE)
}

`%||%` <- function(a, b) {
    if (is.null(a)) {
        b
    } else {
        a
    }
}

# mx.client is a Suggests, and the config lifecycle has no seams: unlike
# poll and send, there is nothing to fake -- these functions exist to
# touch a real file and a real homeserver.
matrix_require_client <- function(what) {
    if (!requireNamespace("mx.client", quietly = TRUE)) {
        stop(what, "() requires the 'mx.client' package. Install it first.",
             call. = FALSE)
    }
    invisible(TRUE)
}

#' @export
chat_channels.chat_matrix <- function(client, ...) {
    # Built before the call, not inside it. R would otherwise hand the
    # seam a promise, and a seam that ignores its session argument --
    # every test double here does -- never forces it. That makes a
    # config too broken to build a session from look fine under test and
    # fail only in production, where the real mx.api function reads it.
    sess <- mx.client::mx_client_session(client$env$mx)
    fn <- client$channels_fn %||% mx.api::mx_rooms
    as.character(fn(sess))
}

#' @export
chat_history.chat_matrix <- function(client, channel, limit = 50L,
                                     before = NULL, ...) {
    fn <- client$history_fn %||% mx.api::mx_messages
    sess <- mx.client::mx_client_session(client$env$mx)
    args <- list(sess, channel, dir = "b", limit = as.integer(limit))
    if (!is.null(before)) {
        args$from <- before
    }
    res <- do.call(fn, args)
    chunk <- res$chunk %||% list()
    # Matrix pages backwards, so the chunk arrives newest-first. The
    # contract promises oldest-first, and this is the one place that
    # knows which direction it asked for.
    chunk <- rev(chunk)
    out <- list()
    for (ev in chunk) {
        if (!isTRUE(ev$type == "m.room.message")) {
            next
        }
        msgtype <- ev$content$msgtype %||% ""
        kind <- matrix_kind_strict(msgtype)
        if (is.na(kind)) {
            # A msgtype the contract has no word for -- an image, a
            # file. Skipping beats inventing a kind: a consumer
            # replaying history into a transcript would otherwise get an
            # empty "message" where a picture was.
            next
        }
        ms <- ev$origin_server_ts
        out[[length(out) + 1L]] <- chat_message(
            id = as.character(ev$event_id),
            channel = as.character(channel),
            sender = as.character(ev$sender %||% ""),
            body = as.character(ev$content$body %||% ""),
            ts = if (is.null(ms)) as.POSIXct(NA) else
            as.POSIXct(ms / 1000, origin = "1970-01-01"),
            markup = "plain", kind = kind,
            self = identical(ev$sender, client$env$mx$user_id),
            mentions = unlist(ev$content[["m.mentions"]]$user_ids,
                              use.names = FALSE),
            raw = ev)
    }
    out
}

#' @export
chat_pending.chat_matrix <- function(client, ...) {
    if (!matrix_invites_available()) {
        stop("chat_pending() needs an mx.client with ",
             "mx_extract_invite_records(). Upgrade mx.client.", call. = FALSE)
    }
    fn <- client$pending_fn %||% mx.api::mx_sync
    # No `since`. That is the whole point: a homeserver that only
    # reports invites newer than the cursor will never mention, in the
    # poll loop, an invitation issued while this client was down.
    # timeout 0 makes it a snapshot rather than a long poll.
    sess <- mx.client::mx_client_session(client$env$mx)
    sync <- fn(sess, timeout = 0L)
    recs <- mx.client::mx_extract_invite_records(sync, client$env$mx$user_id)
    list(invites = lapply(recs, function(r) {
        chat_invite(channel = as.character(r$room_id),
                    inviter = r$inviter %||% NA_character_, raw = r)
    }))
}

#' @export
chat_mark_read.chat_matrix <- function(client, channel, message_id, ...) {
    ok <- tryCatch({
        fn <- client$read_fn %||% mx.api::mx_read_receipt
        sess <- mx.client::mx_client_session(client$env$mx)
        fn(sess, channel, message_id)
        TRUE
    }, error = function(e) FALSE)
    invisible(ok)
}
