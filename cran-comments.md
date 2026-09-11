## Submission

This is the first submission of chat.api, version 0.1.0.

The package provides a common chat interface with Matrix, IRC, Slack,
Telegram, and in-memory adapters. It has no hard package dependencies.
All suggested packages and required versions are available from CRAN.

## Test environments

* Ubuntu 24.04.5 LTS, x86_64, R 4.6.1.
* Windows R-release: uploaded to win-builder on 2026-09-11; results pending.
* Windows Server 2022, R-devel (2026-09-10 r90519 ucrt): the first
  win-builder check found 3 Unix-specific test assertions. The tests now
  accept Windows absolute paths and check Unix file modes only on Unix.
  A corrected Windows check is pending.

## R CMD check results

Linux: 0 errors | 0 warnings | 1 note

The note is "New submission".

The Linux check used `--as-cran --run-donttest`, including PDF and HTML
manual generation. All 1,414 tinytest assertions passed with all suggested
packages installed: mx.api 0.3.1, mx.client 0.2.1, mx.crypto 0.2.2,
slackr 3.3.1, telegram 0.7.1, httr 1.4.9, and tinytest 1.4.3.
With all optional platform packages absent, 1,039 assertions passed;
tests requiring mx.client's session constructor are guarded explicitly.

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
session temporary directory. The Linux check created no new files in R's
user cache, data, or configuration directories.
