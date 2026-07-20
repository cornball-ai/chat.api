# chat.api extraction

- [x] Contract generics + chat_message + loopback reference adapter
- [ ] Matrix adapter: extract corteza R/matrix.R mx glue behind the contract
- [ ] Rewire corteza loop to chat_poll/chat_send; land corteza PR #155 as identity option
- [ ] Slack adapter (Suggests slackr; Web API polling receive)
- [ ] IRC adapter (base socketConnection; buffers into poll)
- [ ] Telegram adapter (getUpdates; shape-identical to Matrix sync)
