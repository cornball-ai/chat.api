library(chat.api)
if (!chat.api:::matrix_attachment_crypto_available()) {
    exit_file("encrypted attachments need current mx.client and mx.crypto")
}
local({
    root <- tempfile("chat-media-")
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    chat.api:::matrix_crypto_forget()
    on.exit(chat.api:::matrix_crypto_forget(), add = TRUE)
    cfg <- list(server = "https://example.invalid", token = "fixture-token",
                user_id = "@bot:example.invalid", device_id = "FIXTURE")
    path <- file.path(root, "plot.png")
    bytes <- as.raw(0:255)
    writeBin(bytes, path)
    upload <- mx.api::mx_upload
    download <- mx.api::mx_download
    on.exit({
        assignInNamespace("mx_upload", upload, "mx.api")
        assignInNamespace("mx_download", download, "mx.api")
    }, add = TRUE)
    payload <- NULL
    sent <- list()
    decrypted <- list()
    assignInNamespace("mx_upload", function(session, path, content_type, filename) {
        expect_identical(session$token, "rotated-fixture-token")
        expect_identical(content_type, "application/octet-stream")
        expect_identical(filename, "encrypted")
        payload <<- readBin(path, "raw", file.size(path))
        "mxc://example.invalid/media"
    }, "mx.api")
    assignInNamespace("mx_download", function(session, mxc_url, dest) {
        expect_identical(session$token, "rotated-fixture-token")
        writeBin(payload, dest)
        invisible(dest)
    }, "mx.api")
    ops <- list(init = function(...) new.env(), encrypted = function(...) TRUE,
                decrypt = function(...) decrypted,
                send = function(crypto, mx, room_id, text, msgtype, extra = NULL, ...) {
                    expect_identical(mx$token, "rotated-fixture-token")
                    sent[[length(sent) + 1L]] <<- c(list(body = text, msgtype = msgtype), extra)
                    paste0("$event", length(sent))
                })
    client <- chat_matrix(mx = cfg, e2ee = TRUE, .crypto = ops,
        .sync = function(mx, ...) list(client = mx, sync = list(), first_run = FALSE),
        .save = function(mx, ...) mx, .extract = function(...) list(),
        .send = function(...) stop("plaintext send"),
        .media = function(...) stop("plaintext upload"))
    client$env$mx$token <- "rotated-fixture-token"
    expect_true(chat_capabilities(client)$files)
    expect_identical(chat_send(client, "!room:example.invalid", "", files = path), "$event1")
    expect_length(sent, 1L) # no empty text bubble
    expect_null(sent[[1]]$url)
    expect_identical(sent[[1]]$msgtype, "m.image")
    expect_false(identical(payload, bytes))
    expect_identical(mx.crypto::mxc_attachment_decrypt(payload, sent[[1]]$file), bytes)
    # Incoming Megolm-decoded media must carry the encrypted-file object,
    # rather than being flattened into a filename-only text message.
    decrypted <- list(list(type = "m.room.message", content = sent[[1]],
        body = "plot.png", msgtype = "m.image", room_id = "!room:example.invalid",
        event_id = "$incoming", sender = "@alice:example.invalid",
        sender_verified = TRUE))
    messages <- chat_poll(client)$messages
    expect_length(messages, 1L)
    expect_true(messages[[1]]$encrypted)
    expect_true(messages[[1]]$sender_verified)
    expect_length(messages[[1]]$attachments, 1L)
    attachment <- messages[[1]]$attachments[[1]]
    expect_identical(attachment$raw$file, sent[[1]]$file)
    dest <- file.path(root, "received.png")
    expect_identical(chat_download(client, attachment, dest), dest)
    expect_identical(readBin(dest, "raw", 256), bytes)
    payload[1] <- as.raw(bitwXor(as.integer(payload[1]), 1L))
    expect_error(chat_download(client, attachment, dest), "integrity")
    expect_identical(readBin(dest, "raw", 256), bytes)
    expect_error(chat_send(client, "!room:example.invalid", "", files = path,
                           thread = "$thread"), "leave the thread")
    expect_length(sent, 1L)
})
