# chat.api 0.0.1.25

* Matrix E2EE saves ratchet state before room-key request transport, retries
  unsent requests with their stable ids, and treats transport failures as
  warnings so a decrypted sync batch is not lost or replayed.
* Same-user forwarded-key recovery requires a cross-signing chain matching
  the master key in the local crypto store. Missing or unreadable local keys
  leave the user's devices untrusted for recovery.
* Matrix E2EE now requires mx.client >= 0.2.0.8 and mx.crypto >= 0.2.1.1 for
  durable request handling and local cross-signing key access.
