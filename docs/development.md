# Development

The repository is split into small host and container helpers:

- `docker-filter-proxy/` validates Docker API requests before forwarding them.
- `beeper/` is an optional host-side HTTP notification server.
- `scripts/` contains container entrypoints and wrappers.
- `docker/` contains system configuration installed in the image.
- `config/` holds committed examples; machine-local files remain ignored.
- `gpg-keys/` is reserved for ignored local signing keys.

Use the Make targets as the supported development interface:

```bash
make lint
make test
```

At this stage `make lint` checks shell sources and `make test` runs the Go unit
tests for the Docker filter proxy and beeper. Keep host utilities small and
direct, preserve the proxy's security defaults in tests, and never commit a red
tree.

Dependency changes require explicit approval before editing package lists or Go
modules. Propose the package and version, why it is needed, and its risk first.
