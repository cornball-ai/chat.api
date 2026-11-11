## Submission

This is an update of chat.api from 0.1.0 to 0.2.0.

The release adds encrypted Matrix attachments, `chat_channel_invite()`,
an `avatar` argument to `chat_set_identity()`, and message edits in
encrypted rooms. It removes nothing that 0.1.0 exported. The package has
no hard package dependencies.

The Suggests floors rise to mx.client (>= 0.3.0) and mx.crypto (>= 0.3.0).
Both versions are on CRAN.

## Test environments

* Ubuntu 24.04.5 LTS, x86_64, R 4.6.1.
* Windows Server 2022 x64, R-release 4.6.2 (2026-10-29 ucrt), win-builder.
* Windows Server 2022 x64, R-devel (2026-11-10 r90874 ucrt), win-builder.

## R CMD check results

0 errors | 0 warnings | 0 notes on all three platforms.

Both Windows checks (win-builder, 2026-11-11) finished with Status: OK,
including CRAN incoming feasibility, installation, examples, and tests.

The Linux checks used `--as-cran --run-donttest`, including PDF and HTML
manual generation, in a library holding only CRAN releases.

With all suggested packages installed, all 1,476 tinytest assertions
passed: mx.api 0.4.0, mx.client 0.3.0, mx.crypto 0.3.0, slackr 3.3.1,
telegram 0.7.1, httr 1.4.9, and tinytest 1.4.3.

With mx.client and mx.crypto absent, the check also finished with
Status: OK and 1,122 assertions passed. Tests that need mx.client are
guarded explicitly.

## Reverse dependencies

chat.api has no reverse dependencies on CRAN.

## Examples and tests

Runnable examples use the in-memory adapter or temporary configuration
files. The following examples use `\dontrun{}` because they require
external services or account credentials:

* chat_matrix, chat_react, chat_join, chat_leave, chat_channel_info,
  chat_members, chat_pending, chat_set_identity, and chat_relogin require
  saved Matrix credentials and a homeserver connection; room operations
  also require access to the target room.
* chat_matrix_configure requires a real homeserver and account password.
* chat_slack requires a Slack token and access to a workspace channel.
* chat_telegram requires a Telegram bot token and access to a target chat.
* chat_irc requires a reachable IRC server and permission to join a channel.

Automated checks use simulated transports. The optional live Telegram
test is guarded by `tinytest::at_home()` and requires a bot token.
Test cache, data, and configuration directories are redirected into the
session temporary directory. The installed tests, run with an empty HOME,
left no files under it.
