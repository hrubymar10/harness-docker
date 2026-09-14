# Session lifecycle

Run a harness launcher from a working directory that is mounted at the same
absolute path inside the Compose service. The shared launch code resolves the
current generation once, validates the working directory against the container's
bind mounts, and pins one immutable container ID for the session.

Interactive callers receive a TTY. Piped commands and editor wrappers keep
stdin/stdout stream-safe. Arguments after the launcher are forwarded to the
harness, and session PID bookkeeping is removed on normal exit or signals.

The launchers are `claude-docker`, `codex-docker`, `pi-docker`, and
`vibe-docker`, and `opencode-docker`. Matching `*-docker-vscode-wrapper` commands provide an executable
path for editor integrations.

## Controller

`harness-docker-ctrl` owns the shared Compose lifecycle:

- `start [--no-cache]` validates and bootstraps configuration, then starts the
  current generation or creates one when necessary;
- `stop` stops every generation, while `restart` deliberately stops all of them
  before starting fresh;
- `status` reports generation state and live session counts;
- `shell` opens the configured container shell at the mirrored working path;
- `exec <claude|codex|pi|vibe|opencode> [args...]` invokes a supported launcher;
- `rebuild [--no-cache]` refreshes harness installs on cached base layers,
  starts, health-checks, and switches to a replacement;
- `build-image [--no-cache]` builds without starting a generation; and
- `gc` removes retired generations only when they have no live session PIDs.

The controller can start and stop the optional host beeper and invokes a
configured notifier hook for lifecycle events. Notification setup is documented
with the user-facing examples when they are added.

`start` and `build-image` use the full build cache by default. `rebuild` also
uses the cache, but invalidates the harness-install layers so unpinned CLIs are
refreshed. Use `--no-cache` with any of those three commands for a full rebuild.

See [Generations and rebuilds](generations.md) for the current-pointer, session
pinning, retirement, and garbage-collection guarantees.

See [Updates](updates.md) for the default-branch eligibility and fast-forward
workflow.
