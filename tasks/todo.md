# chat.api extraction

- [x] Contract generics + chat_message + loopback reference adapter
- [x] chat_disconnect lifecycle verb (forced by IRC; default no-op)
- [x] Matrix adapter delegating to mx.client (live-verified: 112 messages
      through chat_poll against cornball.ai, read-only)
- [x] IRC adapter over base sockets (roundtrip-tested against an
      in-process serverSocket fake)
- [x] Slack adapter verified against installed slackr signatures
      (formals pinned in tinytest; per-channel history polling with
      per-channel cursors). Live send/poll still needs a workspace
      token + test channel.
- [ ] Rewire corteza loop to chat_poll/chat_send; land corteza PR #155
      as the identity option
- [ ] Telegram adapter (getUpdates; shape-identical to Matrix sync)
- [ ] CI (r-ci); decide public flip once the corteza rewire proves the
      contract

## corteza rewire map (recon 2026-07-20)

Message plane (round 1, contract-ready): sync+extract (matrix.R:995,188),
text sends (matrix_send:179, matrix_send_maybe_encrypted plaintext branch
in matrix_crypto.R:148), typing (matrix.R:1187).
Control plane (later rounds, verb-by-verb): invites (612/945), reaction
approvals (mx_react 771, verdicts 848), room metadata (name/topic/members),
backfill (1372), relogin wrapper (995), E2EE (matrix_crypto.R, stays in
corteza round 1; chat_send handles plaintext only there).
Seams chat.api needs: chat_matrix(mx=) accepting a ready mx.client object;
chat_poll returning the raw sync response for control-plane consumers.
