# chat.api

Transport-agnostic chat contract for R agents. Zero dependencies.

One interface — `chat_poll()`, `chat_send()`, `chat_typing()`,
`chat_resolve()`, `chat_capabilities()`, `chat_disconnect()` — with
adapters that wake up when their platform client is installed:

| Adapter | Constructor | Delegates to | Status |
|---|---|---|---|
| Loopback | `chat_loopback()` | (in-memory) | reference implementation |
| Matrix | `chat_matrix()` | mx.client (Suggests) | working |
| IRC | `chat_irc()` | base R sockets | working |
| Slack | `chat_slack()` | slackr (Suggests) | signature-verified, review-hardened; live roundtrip pending a workspace token |

```r
cl <- chat.api::chat_matrix(app = "mybot")
got <- chat.api::chat_poll(cl, timeout = 30)
for (m in got$messages) print(m)
chat.api::chat_send(cl, "#general", "hello from the contract",
                    markup = "markdown")
```

Every adapter is poll-shaped: long-poll transports (Matrix /sync,
Telegram getUpdates) map directly, persistent sockets (IRC) buffer into
the poll. `chat_capabilities()` tells the truth about what each
platform can do (threads, markup dialects, E2EE, per-message identity),
so consumers degrade deliberately instead of accidentally.

See `DESIGN.md` for the ecosystem survey and the contract rationale.

## License

Apache-2.0
