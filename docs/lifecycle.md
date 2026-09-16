# Session lifecycle

Run a harness launcher from a working directory that is mounted at the same
absolute path inside the Compose service. The shared launch code resolves the
current generation once, validates the working directory against the container's
bind mounts, and pins one immutable container ID for the session.

Interactive callers receive a TTY. Piped commands and editor wrappers keep
stdin/stdout stream-safe. Arguments after the launcher are forwarded to the
harness, and session PID bookkeeping is removed on normal exit or signals.

Each launcher prepends a built-in permission flag (see the harness guides).
Set `<HARNESS>_LAUNCH_FLAGS`, for example `CLAUDE_LAUNCH_FLAGS`, in the host
environment or `config/.env` to replace those flags; an empty value clears
them. The override is read at launch, so it affects new sessions only and never
a running one. Override values are split on whitespace, so an individual flag
value cannot contain whitespace.

When `SSH_AUTH_SOCK` names a live agent socket, every launch also restores the
host-side relay that forwards it into the sandbox (see [Setup](setup.md)), so a
relay that died or lost its agent socket returns without a restart of the stack.

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
- `gc` removes non-current generations when they have no fresh host-side session heartbeats.

The controller can start and stop the optional host beeper and invokes a
configured notifier hook for lifecycle events. Notification setup is documented
with the user-facing examples when they are added.

When `config/mcpbridge.jsonc` contains an enabled server, `start` and `rebuild`
also start the optional host MCP gateway. An absent or empty configuration
stops a previously running gateway, and `stop` always stops it. Use
`mcpbridge-start` and `mcpbridge-stop` to apply configuration changes without a
container rebuild. See [Host MCP gateway](mcpbridge.md).

`start` and `build-image` use the full build cache by default. `rebuild` also
uses the cache, but invalidates the harness-install layers so unpinned CLIs are
refreshed. Use `--no-cache` with any of those three commands for a full rebuild.
Every successful image build also updates `harness-docker:latest` for direct
external `docker run` calls; managed generations remain pinned to versioned
image tags.

See [Generations and rebuilds](generations.md) for the current-pointer, session
pinning, retirement, and garbage-collection guarantees.

See [Updates](updates.md) for the default-branch eligibility and fast-forward
workflow.
