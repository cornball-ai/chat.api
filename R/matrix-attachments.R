matrix_attachment_crypto_available <- function() {
    requireNamespace("mx.client", quietly = TRUE) &&
    requireNamespace("mx.crypto", quietly = TRUE) &&
    all(c("mx_upload_encrypted", "mx_download_encrypted") %in%
        getNamespaceExports("mx.client")) &&
    all(c("mxc_attachment_encrypt", "mxc_attachment_decrypt") %in%
        getNamespaceExports("mx.crypto"))
}

# Reuse the media extractor on the decrypted inner event. The outer sync
# contains only Megolm ciphertext and cannot supply attachment metadata.
matrix_decrypted_attachments <- function(event, self_id) {
    if (!is.list(event$content) || !matrix_media_available()) {
        return(NULL)
    }
    inner <- list(type = event$type %||% "m.room.message",
                  content = event$content, event_id = event$event_id,
                  sender = event$sender, origin_server_ts = event$ts)
    sync <- list(rooms = list(join = setNames(list(list(
        timeline = list(events = list(inner)))), event$room_id)))
    records <- mx.client::mx_extract_media_events(sync, self_id)
    if (!length(records)) return(NULL)
    lapply(records, function(a) chat_attachment(
        id = as.character(a$url), name = a$filename %||% a$body %||% NA_character_,
        mime = a$mime %||% NA_character_, bytes = a$size %||% NA_integer_,
        url = as.character(a$url), sha256 = a$sha256 %||% NA_character_, raw = a))
}
