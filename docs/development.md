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

`make lint` checks shell sources. `make test` runs parameterized host suites for
launching, controller commands, configuration, image/Compose behavior,
generations, updates, proxy security, and both Go packages. The live smoke check
reports a skip when no generation is running; that is expected in an otherwise
green host-only run.

The test helpers exercise the same harness table and shared paths used in
production so one harness cannot silently drift. Coverage includes all five
launcher and editor-wrapper variants. Image and Compose changes must
also keep the render and smoke assertions green. Keep host utilities small and
direct, preserve security defaults in tests, and never commit a red tree.

The running-container smoke suite also finds Codex's `codex-path/rg` entry and
executes `--version`. This protects the image contract that the vendored path
resolves to Alpine's working system ripgrep rather than an incompatible bundled
binary.

Dependency changes require explicit approval before editing package lists or Go
modules. Propose the package and version, why it is needed, and its risk first.

For image or Compose work, render the Compose model and build the affected image
in addition to the host suite. Keep documentation links repository-relative and
update the owning page in the same commit as user-visible flags, environment
variables, tool names, behavior, or supported-harness changes.
