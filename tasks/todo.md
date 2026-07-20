# chat.api extraction

- [x] Contract generics + chat_message + loopback reference adapter
- [x] chat_disconnect lifecycle verb (forced by IRC; default no-op)
- [x] Matrix adapter delegating to mx.client (live-verified: 112 messages
      through chat_poll against cornball.ai, read-only)
- [x] IRC adapter over base sockets (roundtrip-tested against an
      in-process serverSocket fake)
- [x] Slack adapter skeleton (Suggests slackr) — UNVERIFIED: awaiting
      slackr install (Troy) + workspace token; verify slackr_msg /
      slackr_history signatures then
- [ ] Rewire corteza loop to chat_poll/chat_send; land corteza PR #155
      as the identity option
- [ ] Telegram adapter (getUpdates; shape-identical to Matrix sync)
- [ ] CI (r-ci); decide public flip once the corteza rewire proves the
      contract
