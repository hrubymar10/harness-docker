# Beeper and notifications

The optional beeper is a small host HTTP service. Copy the notifier example to
the ignored live path, choose the category-aware host integration, and start or
stop the server through the controller:

```bash
cp config/harness-notifier.example config/harness-notifier
harness-docker-ctrl beeper-start
harness-docker-ctrl beeper-stop
```

Compose mounts `config/harness-notifier` at the shared notifier path, and the
image exposes it through harness-specific names (`claude-notifier`,
`codex-notifier`, `pi-notifier`, `vibe-notifier`, and `opencode-notifier`). The
script receives a notification category and sends the request to
`http://host.docker.internal:9999/beep` by default.

`BEEPER_BIND` controls the listening address. `BEEPER_ALLOW` is a comma-separated
IP/CIDR allowlist. Keep the service inaccessible to untrusted networks. The
bundled audio command is macOS-specific; replace its player on other hosts.

Claude instruction and hook examples are in
[`config/notifier-examples/`](../config/notifier-examples/). Copy and adapt an
example rather than editing the committed template in place. Lifecycle events
may also invoke the shared notifier hook.
